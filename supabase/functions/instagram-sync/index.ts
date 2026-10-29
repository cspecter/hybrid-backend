/**
 * Keep connected brands' posts and tokens fresh.
 *
 * Two things expire and neither is optional:
 *
 *   media_url. Instagram's CDN links die within hours, so a cached URL stops rendering even
 *   though the post still exists. That is why this runs on a schedule rather than once at
 *   connect time, and why permalink — which does not expire — is stored alongside.
 *
 *   The access token. A long-lived Instagram token lasts 60 days and can be refreshed while
 *   still valid. Miss that window and the brand has to authorise again, so refreshing starts
 *   at 10 days out rather than on the last day.
 *
 * A token that comes back invalid means the brand revoked access in Instagram's own settings.
 * That is an answer, not an error: the connection is marked needs_reauth and the posts are
 * dropped, because the permission they were shown under is gone.
 *
 * Stores are swept in the same pass, with one difference: a store's posts are stored as
 * shortcodes and embedded rather than cached as images, so the first of those two expiries
 * does not apply to them. Only stores on the graph source appear here at all -- a store
 * whose posts were pasted in by hand has no token and nothing to refresh.
 *
 * Called by pg_cron through instagram_sync_dispatch with the shared invoke token, the same
 * way the giveaway winner email is.
 */
import { supabaseAdmin } from "../_shared/supabase.ts";
import { shortcodeFromPermalink } from "../_shared/instagram.ts";

const MEDIA_COUNT = 6;
const REFRESH_WITHIN_DAYS = 10;
const INVOKE_TOKEN = Deno.env.get("GIVEAWAY_INVOKE_TOKEN") || "";

const tokenMatches = (given: string): boolean => {
  if (!INVOKE_TOKEN || !given || given.length !== INVOKE_TOKEN.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ INVOKE_TOKEN.charCodeAt(i);
  return diff === 0;
};

async function vault(name: string): Promise<string | null> {
  const { data } = await supabaseAdmin
    .from("decrypted_secrets").select("decrypted_secret").eq("name", name).maybeSingle();
  return (data as { decrypted_secret?: string } | null)?.decrypted_secret ?? null;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!tokenMatches(bearer)) return json({ ok: false, error: "Not authorised" }, 401);

  const appSecret = await vault("instagram_app_secret");
  const { data: conns } = await supabaseAdmin
    .from("brand_instagram")
    .select("profile_id, access_token, token_expires_at, status")
    .eq("status", "active");

  const out = { checked: 0, synced: 0, refreshed: 0, revoked: 0, failed: 0 };
  const stores = { checked: 0, synced: 0, refreshed: 0, revoked: 0, failed: 0 };

  for (const c of (conns ?? []) as Array<{
    profile_id: number; access_token: string; token_expires_at: string | null; status: string;
  }>) {
    out.checked++;
    let token = c.access_token;

    // Refresh well before the deadline: a token refreshed late cannot be refreshed at all.
    const expiresIn = c.token_expires_at
      ? new Date(c.token_expires_at).getTime() - Date.now()
      : 0;
    if (expiresIn < REFRESH_WITHIN_DAYS * 86_400_000) {
      const r = await fetch("https://graph.instagram.com/refresh_access_token?" + new URLSearchParams({
        grant_type: "ig_refresh_token", access_token: token,
      }));
      if (r.ok) {
        const d = await r.json() as { access_token?: string; expires_in?: number };
        if (d.access_token) {
          token = d.access_token;
          await supabaseAdmin.from("brand_instagram").update({
            access_token: token,
            token_expires_at: new Date(Date.now() + (d.expires_in ?? 5_184_000) * 1000).toISOString(),
          }).eq("profile_id", c.profile_id);
          out.refreshed++;
        }
      } else {
        console.warn(`instagram-sync: refresh failed for profile ${c.profile_id}`, r.status);
      }
    }

    const mediaRes = await fetch("https://graph.instagram.com/me/media?" + new URLSearchParams({
      fields: "id,media_type,media_url,thumbnail_url,permalink,caption,timestamp",
      limit: String(MEDIA_COUNT), access_token: token,
    }));

    if (mediaRes.status === 401 || mediaRes.status === 403) {
      // The brand took access away in Instagram. The posts go with the permission.
      await supabaseAdmin.from("brand_instagram_media").delete().eq("profile_id", c.profile_id);
      await supabaseAdmin.from("brand_instagram").update({
        status: "needs_reauth",
        last_sync_error: `access revoked (${mediaRes.status})`,
      }).eq("profile_id", c.profile_id);
      out.revoked++;
      continue;
    }

    if (!mediaRes.ok) {
      await supabaseAdmin.from("brand_instagram").update({
        last_sync_error: `sync ${mediaRes.status}`,
      }).eq("profile_id", c.profile_id);
      out.failed++;
      continue;
    }

    const { data: items = [] } = await mediaRes.json() as { data?: Array<Record<string, string>> };
    const rows = items.map((m, i) => ({
      profile_id: c.profile_id,
      ig_media_id: m.id,
      media_type: m.media_type ?? null,
      permalink: m.permalink ?? null,
      caption: m.caption ?? null,
      media_url: m.media_url ?? null,
      thumbnail_url: m.thumbnail_url ?? null,
      posted_at: m.timestamp ?? null,
      rank: i + 1,
      synced_at: new Date().toISOString(),
    }));

    if (rows.length) {
      await supabaseAdmin.from("brand_instagram_media")
        .upsert(rows, { onConflict: "profile_id,ig_media_id" });
      // Posts the brand has since deleted should stop showing.
      await supabaseAdmin.from("brand_instagram_media")
        .delete()
        .eq("profile_id", c.profile_id)
        .not("ig_media_id", "in", `(${rows.map((r) => `"${r.ig_media_id}"`).join(",")})`);
    }

    await supabaseAdmin.from("brand_instagram").update({
      last_sync_at: new Date().toISOString(), last_sync_error: null,
    }).eq("profile_id", c.profile_id);
    out.synced++;
  }


  // ── Stores ────────────────────────────────────────────────────────────────
  const { data: storeConns } = await supabaseAdmin
    .from("store_instagram")
    .select("location_id, access_token, token_expires_at")
    .eq("source", "graph")
    .eq("status", "active")
    .eq("consent_status", "granted");

  for (const c of (storeConns ?? []) as Array<{
    location_id: number; access_token: string | null; token_expires_at: string | null;
  }>) {
    if (!c.access_token) continue;
    stores.checked++;
    let token = c.access_token;

    const expiresIn = c.token_expires_at
      ? new Date(c.token_expires_at).getTime() - Date.now()
      : 0;
    if (expiresIn < REFRESH_WITHIN_DAYS * 86_400_000) {
      const r = await fetch("https://graph.instagram.com/refresh_access_token?" + new URLSearchParams({
        grant_type: "ig_refresh_token", access_token: token,
      }));
      if (r.ok) {
        const d = await r.json() as { access_token?: string; expires_in?: number };
        if (d.access_token) {
          token = d.access_token;
          await supabaseAdmin.from("store_instagram").update({
            access_token: token,
            token_expires_at: new Date(Date.now() + (d.expires_in ?? 5_184_000) * 1000).toISOString(),
          }).eq("location_id", c.location_id);
          stores.refreshed++;
        }
      } else {
        console.warn(`instagram-sync: refresh failed for location ${c.location_id}`, r.status);
      }
    }

    // media_url is deliberately not requested: a store's photographs are never copied here.
    const mediaRes = await fetch("https://graph.instagram.com/me/media?" + new URLSearchParams({
      fields: "id,media_type,permalink,caption,timestamp",
      limit: String(MEDIA_COUNT), access_token: token,
    }));

    if (mediaRes.status === 401 || mediaRes.status === 403) {
      // Taking access away in Instagram is withdrawing consent, so it is recorded as that.
      // The trigger on store_instagram deletes the posts when the status flips.
      await supabaseAdmin.from("store_instagram").update({
        consent_status: "revoked",
        revoked_at: new Date().toISOString(),
        status: "needs_reauth",
        access_token: null,
        last_sync_error: `access revoked (${mediaRes.status})`,
      }).eq("location_id", c.location_id);
      stores.revoked++;
      continue;
    }

    if (!mediaRes.ok) {
      await supabaseAdmin.from("store_instagram").update({
        last_sync_error: `sync ${mediaRes.status}`,
      }).eq("location_id", c.location_id);
      stores.failed++;
      continue;
    }

    const { data: items = [] } = await mediaRes.json() as { data?: Array<Record<string, string>> };
    const rows = items
      .map((m) => ({ m, code: shortcodeFromPermalink(m.permalink) }))
      .filter((x): x is { m: Record<string, string>; code: string } => x.code !== null)
      .map(({ m, code }, i) => ({
        location_id: c.location_id,
        shortcode: code,
        permalink: m.permalink,
        caption: m.caption ?? null,
        posted_at: m.timestamp ?? null,
        rank: i + 1,
        source: "graph",
        synced_at: new Date().toISOString(),
      }));

    if (rows.length) {
      await supabaseAdmin.from("store_instagram_media")
        .upsert(rows, { onConflict: "location_id,shortcode" });
      await supabaseAdmin.from("store_instagram_media")
        .delete()
        .eq("location_id", c.location_id)
        .not("shortcode", "in", `(${rows.map((r) => `"${r.shortcode}"`).join(",")})`);
    }

    await supabaseAdmin.from("store_instagram").update({
      last_sync_at: new Date().toISOString(), last_sync_error: null,
    }).eq("location_id", c.location_id);
    stores.synced++;
  }

  if (!appSecret && out.checked + stores.checked > 0) {
    console.warn("instagram-sync: instagram_app_secret missing from Vault; tokens cannot be refreshed");
  }
  return json({ ok: true, ...out, stores });
});
