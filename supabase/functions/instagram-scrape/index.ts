/**
 * Fetch a consenting account's recent posts and keep our own copy of the pictures.
 *
 * Why this exists when instagram-sync already does something similar: sync talks to the
 * Graph API with a token the account granted us, which needs App Review and does not exist
 * yet. This talks to a scraping provider instead, and it is the only route that reaches a
 * cannabis account at all -- Instagram age-restricts them, so a logged-out reader is shown
 * "You must be 21 years old or over to see this profile" rather than a post. Embedding is
 * fetched by the reader's browser and therefore loses to that; a fetch we make ourselves
 * chooses its own address and session, and does not.
 *
 * Three things this deliberately does not do:
 *
 *   It does not visit a subject that has not consented. The query below is the gate, and it
 *   reads the same table the rest of the feature reads.
 *
 *   It does not hold a credential. The provider token and whatever session the provider
 *   needs are read from Vault at call time and never logged. The account behind that session
 *   is bound by Meta's terms and can be suspended, so it should be a dedicated one.
 *
 *   It does not keep what consent no longer covers. Withdrawal deletes the rows through a
 *   trigger and queues the files here, and this drains that queue before anything else --
 *   including on runs where there is nothing to fetch.
 *
 * The provider is configuration, not code. Scrapers break when Meta rotates its internal
 * endpoints, and the actor worth paying for this month may not be the one worth paying for
 * next month, so the actor id and any extra input it wants live in Vault.
 */
import { supabaseAdmin } from "../_shared/supabase.ts";

const BUCKET = "instagram-posts";
const POST_LIMIT = 6;             // matches store_instagram_post_limit()
const PURGE_BATCH = 200;
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

type Subject = { subject_type: string; subject_id: number; username: string | null };

type ScrapedPost = {
  shortcode: string;
  permalink: string;
  caption: string | null;
  postedAt: string | null;
  imageUrl: string | null;
  width: number | null;
  height: number | null;
  isVideo: boolean;
};

/**
 * Delete copies that consent no longer covers.
 *
 * Runs first and runs unconditionally. A shop that withdrew yesterday should not have its
 * photographs sitting in our bucket because the provider is misconfigured today.
 */
async function drainPurgeQueue(): Promise<{ purged: number; failed: number }> {
  const { data: rows } = await supabaseAdmin
    .from("instagram_media_purge")
    .select("id, bucket, path")
    .is("purged_at", null)
    .limit(PURGE_BATCH);

  const queue = (rows ?? []) as Array<{ id: number; bucket: string; path: string }>;
  if (queue.length === 0) return { purged: 0, failed: 0 };

  let purged = 0, failed = 0;
  for (const bucket of new Set(queue.map((r) => r.bucket))) {
    const mine = queue.filter((r) => r.bucket === bucket);
    const { error } = await supabaseAdmin.storage.from(bucket).remove(mine.map((r) => r.path));
    if (error) {
      failed += mine.length;
      await supabaseAdmin.from("instagram_media_purge")
        .update({ last_error: error.message.slice(0, 300) })
        .in("id", mine.map((r) => r.id));
      console.error("instagram-scrape: purge failed", bucket, error.message);
      continue;
    }
    // Storage treats removing an absent object as success, which is what we want: the point
    // is that it is gone, not that we were the one to delete it.
    purged += mine.length;
    await supabaseAdmin.from("instagram_media_purge")
      .update({ purged_at: new Date().toISOString(), last_error: null })
      .in("id", mine.map((r) => r.id));
  }
  return { purged, failed };
}

/** Normalise whatever the provider returns into the handful of fields a page needs. */
function readPosts(items: Array<Record<string, unknown>>): ScrapedPost[] {
  const out: ScrapedPost[] = [];
  for (const it of items) {
    const shortcode = String(it.shortCode ?? it.shortcode ?? "");
    if (!/^[A-Za-z0-9_-]{5,40}$/.test(shortcode)) continue;
    const type = String(it.type ?? "");
    out.push({
      shortcode,
      permalink: String(it.url ?? `https://www.instagram.com/p/${shortcode}/`),
      caption: (it.caption as string) ?? null,
      postedAt: (it.timestamp as string) ?? null,
      // A video's displayUrl is its cover frame, which is the thing we want to show.
      imageUrl: (it.displayUrl as string) ?? (it.imageUrl as string) ?? null,
      width: Number(it.dimensionsWidth) || null,
      height: Number(it.dimensionsHeight) || null,
      isVideo: type === "Video" || it.isVideo === true,
    });
    if (out.length >= POST_LIMIT) break;
  }
  return out;
}

/** Ask the provider for this account's recent posts. */
async function fetchPosts(
  username: string, apifyToken: string, actor: string, extraInput: Record<string, unknown>,
): Promise<ScrapedPost[]> {
  const res = await fetch(
    `https://api.apify.com/v2/acts/${encodeURIComponent(actor)}/run-sync-get-dataset-items` +
    `?token=${encodeURIComponent(apifyToken)}&timeout=180`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        directUrls: [`https://www.instagram.com/${username}/`],
        resultsType: "posts",
        resultsLimit: POST_LIMIT,
        addParentData: false,
        // Session cookies, proxy configuration, and anything else the chosen actor wants.
        // Age-restricted accounts are unreachable without a logged-in session, so for a
        // dispensary this is not optional -- but it is the operator's to supply, not ours
        // to invent.
        ...extraInput,
      }),
    },
  );
  if (!res.ok) {
    throw new Error(`provider ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
  const items = await res.json() as Array<Record<string, unknown>>;
  return readPosts(Array.isArray(items) ? items : []);
}

/** Copy one picture into our bucket. Returns the stored path, or null if it could not be. */
async function storeImage(
  subjectType: string, subjectId: number, post: ScrapedPost,
): Promise<string | null> {
  if (!post.imageUrl) return null;
  const res = await fetch(post.imageUrl);
  if (!res.ok) {
    console.warn("instagram-scrape: image fetch failed", post.shortcode, res.status);
    return null;
  }
  const contentType = res.headers.get("content-type") || "image/jpeg";
  if (!/^image\/(jpeg|png|webp)$/.test(contentType)) {
    console.warn("instagram-scrape: unexpected content type", post.shortcode, contentType);
    return null;
  }
  const ext = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
  const path = `${subjectType}/${subjectId}/${post.shortcode}.${ext}`;

  const { error } = await supabaseAdmin.storage.from(BUCKET)
    .upload(path, new Uint8Array(await res.arrayBuffer()), { contentType, upsert: true });
  if (error) {
    console.error("instagram-scrape: upload failed", path, error.message);
    return null;
  }
  return path;
}

async function syncSubject(
  s: Subject, apifyToken: string, actor: string, extraInput: Record<string, unknown>,
): Promise<"synced" | "empty" | "failed"> {
  const key = { subject_type: s.subject_type, subject_id: s.subject_id };

  let posts: ScrapedPost[];
  try {
    posts = await fetchPosts(s.username as string, apifyToken, actor, extraInput);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await supabaseAdmin.from("instagram_consent")
      .update({ last_sync_error: msg.slice(0, 300) }).match(key);
    return "failed";
  }

  if (posts.length === 0) {
    // Most often this is the age gate with no session supplied, which is a configuration
    // answer rather than a transient failure, so it is worth saying so plainly.
    await supabaseAdmin.from("instagram_consent").update({
      last_sync_at: new Date().toISOString(),
      last_sync_error: "provider returned no posts — if this account is age-restricted, the provider needs a logged-in session",
    }).match(key);
    return "empty";
  }

  // What we already hold, so an unchanged post is not downloaded twice.
  const { data: existing } = await supabaseAdmin.from("instagram_consent_media")
    .select("shortcode, image_path").match(key);
  const held = new Map((existing ?? []).map((r) => [r.shortcode as string, r.image_path as string | null]));

  const rows = [];
  for (let i = 0; i < posts.length; i++) {
    const p = posts[i];
    const already = held.get(p.shortcode);
    const path = already ?? await storeImage(s.subject_type, s.subject_id, p);
    rows.push({
      ...key,
      shortcode: p.shortcode,
      permalink: p.permalink,
      caption: p.caption,
      posted_at: p.postedAt,
      rank: i + 1,
      source: "scrape",
      image_path: path,
      image_width: p.width,
      image_height: p.height,
      is_video: p.isVideo,
      synced_at: new Date().toISOString(),
    });
  }

  await supabaseAdmin.from("instagram_consent_media")
    .upsert(rows, { onConflict: "subject_type,subject_id,shortcode" });

  // Posts the shop has since deleted stop showing, and their copies are queued for removal
  // by the trigger on the way out.
  await supabaseAdmin.from("instagram_consent_media").delete().match(key)
    .not("shortcode", "in", `(${rows.map((r) => `"${r.shortcode}"`).join(",")})`);

  await supabaseAdmin.from("instagram_consent")
    .update({ last_sync_at: new Date().toISOString(), last_sync_error: null }).match(key);
  return "synced";
}

Deno.serve(async (req: Request) => {
  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!tokenMatches(bearer)) return json({ ok: false, error: "Not authorised" }, 401);

  // Deletions first, and regardless of whether anything else can run.
  const purge = await drainPurgeQueue();

  const apifyToken = await vault("instagram_scrape_token");
  if (!apifyToken) {
    return json({ ok: true, purge, scraped: null,
      note: "instagram_scrape_token is not in Vault; nothing was fetched" });
  }
  const actor = (await vault("instagram_scrape_actor")) || "apify~instagram-scraper";

  let extraInput: Record<string, unknown> = {};
  const extraRaw = await vault("instagram_scrape_input");
  if (extraRaw) {
    try {
      extraInput = JSON.parse(extraRaw) as Record<string, unknown>;
    } catch {
      // Never echo the value: it carries the session.
      console.error("instagram-scrape: instagram_scrape_input is not valid JSON; ignoring it");
    }
  }

  const { data: subjects } = await supabaseAdmin
    .from("instagram_consent")
    .select("subject_type, subject_id, username")
    .eq("source", "scrape")
    .eq("consent_status", "granted")
    .eq("status", "active");

  const out = { checked: 0, synced: 0, empty: 0, failed: 0, skipped: 0 };
  for (const s of (subjects ?? []) as Subject[]) {
    if (!s.username) { out.skipped++; continue; }
    out.checked++;
    const r = await syncSubject(s, apifyToken, actor, extraInput);
    out[r === "synced" ? "synced" : r === "empty" ? "empty" : "failed"]++;
  }

  return json({ ok: true, purge, scraped: out, actor });
});
