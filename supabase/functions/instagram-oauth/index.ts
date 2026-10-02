/**
 * The Instagram authorise callback.
 *
 * A brand admin is sent to Instagram by instagram_connect_begin, approves read access to its
 * own account, and Instagram sends the browser here with a code. The code is exchanged for a
 * token on this side and the token stays on this side: it is a credential for somebody else's
 * account, the browser never needs it, and a token that reaches a client is a token in a
 * logfile sooner or later.
 *
 * What the state parameter is for: without it, anyone could call this endpoint with their own
 * code and have their Instagram attached to a brand they do not manage. The state is created
 * only after can_admin_profile passes, is single use, and carries which brand it was issued
 * for, so the brand is decided before the user ever leaves for Instagram.
 *
 * Scope is instagram_business_basic — the account's own profile and its own media, read only.
 * Nothing here can post, read messages, or see another account.
 */
import { supabaseAdmin } from "../_shared/supabase.ts";

const STATE_TTL_MINUTES = 15;
const MEDIA_COUNT = 6;   // the page shows three; a couple spare covers a deleted post

const html = (title: string, body: string, appUrl: string) => `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title><style>
body{font:16px -apple-system,system-ui,sans-serif;background:#111;color:#eee;
display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center}
.card{max-width:340px}h1{font-size:19px;margin:0 0 10px}p{color:#aaa;line-height:1.5;margin:0 0 20px}
a{display:inline-block;background:#f5af19;color:#000;text-decoration:none;padding:13px 22px;
border-radius:13px;font-weight:700}</style></head>
<body><div class="card"><h1>${title}</h1><p>${body}</p>
<a href="${appUrl}">Back to Hybrid</a></div></body></html>`;

async function vault(name: string): Promise<string | null> {
  const { data } = await supabaseAdmin
    .from("decrypted_secrets").select("decrypted_secret").eq("name", name).maybeSingle();
  return (data as { decrypted_secret?: string } | null)?.decrypted_secret ?? null;
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const appUrl = Deno.env.get("SITE_URL") || "https://hybrid-raskin.vercel.app";
  const page = (t: string, b: string, status = 200) =>
    new Response(html(t, b, appUrl), { status, headers: { "Content-Type": "text/html; charset=utf-8" } });

  // Instagram sends the user back here having declined.
  const denied = url.searchParams.get("error");
  if (denied) {
    return page("Not connected",
      "Instagram access was not granted, so nothing was changed. You can try again any time from your brand profile.");
  }

  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) return page("Something went wrong", "That link was incomplete. Start again from your brand profile.", 400);

  // The state decides the brand, and it is spent on use.
  const { data: st } = await supabaseAdmin
    .from("instagram_oauth_state")
    .select("state, profile_id, created_by, created_at, used_at")
    .eq("state", state)
    .maybeSingle();

  if (!st) return page("That link has expired", "Start again from your brand profile.", 400);
  if (st.used_at) return page("That link was already used", "Start again from your brand profile.", 400);
  if (Date.now() - new Date(st.created_at as string).getTime() > STATE_TTL_MINUTES * 60_000) {
    return page("That link has expired", `Authorise links last ${STATE_TTL_MINUTES} minutes. Start again from your brand profile.`, 400);
  }
  await supabaseAdmin.from("instagram_oauth_state")
    .update({ used_at: new Date().toISOString() }).eq("state", state);

  const appId = await vault("instagram_app_id");
  const appSecret = await vault("instagram_app_secret");
  const redirect = await vault("instagram_redirect_uri");
  if (!appId || !appSecret || !redirect) {
    console.error("instagram-oauth: vault secrets missing (instagram_app_id / instagram_app_secret / instagram_redirect_uri)");
    return page("Not available yet", "Instagram connection is not switched on yet. Nothing was changed.", 503);
  }

  // Code -> short-lived token.
  const form = new FormData();
  form.append("client_id", appId);
  form.append("client_secret", appSecret);
  form.append("grant_type", "authorization_code");
  form.append("redirect_uri", redirect);
  form.append("code", code);

  const shortRes = await fetch("https://api.instagram.com/oauth/access_token", { method: "POST", body: form });
  const shortBody = await shortRes.text();
  if (!shortRes.ok) {
    console.error("instagram-oauth: code exchange failed", shortRes.status, shortBody.slice(0, 300));
    return page("Couldn't connect", "Instagram would not complete the connection. Nothing was changed — please try again.", 502);
  }
  const short = JSON.parse(shortBody) as { access_token?: string; user_id?: string | number };
  if (!short.access_token) return page("Couldn't connect", "Instagram did not return access. Nothing was changed.", 502);

  // Short-lived -> long-lived (60 days).
  const longRes = await fetch("https://graph.instagram.com/access_token?" + new URLSearchParams({
    grant_type: "ig_exchange_token", client_secret: appSecret, access_token: short.access_token,
  }));
  const longBody = await longRes.text();
  const long = longRes.ok
    ? JSON.parse(longBody) as { access_token?: string; expires_in?: number }
    : {};
  if (!longRes.ok) console.warn("instagram-oauth: long-lived exchange failed, using short-lived", longBody.slice(0, 200));

  const token = long.access_token || short.access_token;
  const expiresAt = new Date(Date.now() + (long.expires_in ?? 3600) * 1000).toISOString();

  // Who did we just connect?
  const meRes = await fetch("https://graph.instagram.com/me?" + new URLSearchParams({
    fields: "id,username,account_type", access_token: token,
  }));
  if (!meRes.ok) {
    console.error("instagram-oauth: /me failed", meRes.status, (await meRes.text()).slice(0, 200));
    return page("Couldn't connect", "Instagram would not say which account that was. Nothing was changed.", 502);
  }
  const me = await meRes.json() as { id: string; username?: string; account_type?: string };

  const { error: upErr } = await supabaseAdmin.from("brand_instagram").upsert({
    profile_id: st.profile_id,
    ig_user_id: me.id,
    username: me.username ?? null,
    account_type: me.account_type ?? null,
    access_token: token,
    token_expires_at: expiresAt,
    connected_by: st.created_by ?? null,
    status: "active",
    last_sync_error: null,
  }, { onConflict: "profile_id" });

  if (upErr) {
    console.error("instagram-oauth: could not store connection", upErr.message);
    return page("Couldn't connect", "The connection could not be saved. Please try again.", 500);
  }

  // Pull the first posts now, so the brand sees the result immediately rather than whenever
  // a scheduled sync next runs. A failure here is not a failed connection.
  try {
    const mediaRes = await fetch("https://graph.instagram.com/me/media?" + new URLSearchParams({
      fields: "id,media_type,media_url,thumbnail_url,permalink,caption,timestamp",
      limit: String(MEDIA_COUNT), access_token: token,
    }));
    if (mediaRes.ok) {
      const { data: items = [] } = await mediaRes.json() as { data?: Array<Record<string, string>> };
      const rows = items.map((m, i) => ({
        profile_id: st.profile_id,
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
        await supabaseAdmin.from("brand_instagram_media").upsert(rows, { onConflict: "profile_id,ig_media_id" });
      }
      await supabaseAdmin.from("brand_instagram")
        .update({ last_sync_at: new Date().toISOString() }).eq("profile_id", st.profile_id);
    } else {
      const body = (await mediaRes.text()).slice(0, 200);
      console.warn("instagram-oauth: first media pull failed", mediaRes.status, body);
      await supabaseAdmin.from("brand_instagram")
        .update({ last_sync_error: `first sync: ${mediaRes.status}` }).eq("profile_id", st.profile_id);
    }
  } catch (e) {
    console.warn("instagram-oauth: first media pull threw", e instanceof Error ? e.message : String(e));
  }

  return page("Instagram connected",
    `@${me.username ?? "your account"} is connected. Your latest posts will show on your brand page.`);
});
