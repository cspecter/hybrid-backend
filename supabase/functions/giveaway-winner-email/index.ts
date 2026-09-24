/**
 * Giveaway winner email.
 *
 * The client has been calling POST /functions/v1/giveaway-winner-email since the
 * draw button was built. The function never existed — not in this repo, not deployed
 * — so every call was a 404 that lib/giveaways.js caught, logged to the console and
 * swallowed. A winner got an in-app notification and nothing else, and the admin who
 * drew the giveaway was told the email had failed in a line nobody reads.
 *
 * This is that function. The request shape and the response shape are the ones the
 * client already expects; nothing on the frontend had to change to make it work.
 *
 * TWO CALLERS, TWO KINDS OF PROOF:
 *   • a super admin pressing Pick Winner, identified by their own JWT
 *   • pg_cron, via giveaway_winner_email_dispatch, identified by a shared token that
 *     exists only in Vault and in this function's environment
 * Anything else is refused. The anon key is not a caller: it resolves to no user, so
 * it fails the super-admin check like any other stranger.
 *
 * WHAT IT WILL MOSTLY DO, HONESTLY: answer no_email. Sign-in is phone OTP and nothing
 * in the product asks for an email address, so exactly one profile out of 2,485 has
 * one. That is not this function's problem to solve, but it is the reason nobody
 * should read "winner emails are wired up" as "winners get emailed".
 */

import { supabaseAdmin } from "../_shared/supabase.ts";
import { sendGiveawayWinnerEmail } from "../_shared/mailgun.ts";
import { jsonResponse, handleCors } from "../_shared/cors.ts";

const INVOKE_TOKEN = Deno.env.get("GIVEAWAY_INVOKE_TOKEN") || "";

// Length-independent compare. The token is a 32-byte random value so a timing leak is
// not a realistic attack, but a constant-time compare costs nothing and means the
// question never has to be argued.
const tokenMatches = (given: string): boolean => {
  if (!INVOKE_TOKEN || !given || given.length !== INVOKE_TOKEN.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ INVOKE_TOKEN.charCodeAt(i);
  return diff === 0;
};

const isSuperAdmin = async (jwt: string): Promise<boolean> => {
  const { data, error } = await supabaseAdmin.auth.getUser(jwt);
  if (error || !data?.user?.id) return false;
  const { data: row } = await supabaseAdmin
    .from("super_admins")
    .select("auth_id")
    .eq("auth_id", data.user.id)
    .maybeSingle();
  return !!row;
};

Deno.serve(async (req: Request) => {
  const preflight = handleCors(req);
  if (preflight) return preflight;

  try {
    const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
    if (!bearer) return jsonResponse({ ok: false, error: "Missing authorization" }, 401);

    const authorized = tokenMatches(bearer) || await isSuperAdmin(bearer);
    if (!authorized) return jsonResponse({ ok: false, error: "Not authorized" }, 403);

    const body = await req.json().catch(() => null);
    const giveawayId = Number(body?.giveaway_id);
    const winnerProfileId = Number(body?.winner_profile_id);
    if (!giveawayId || !winnerProfileId) {
      return jsonResponse({ ok: false, error: "giveaway_id and winner_profile_id are required" }, 400);
    }

    const { data: giveaway, error: gErr } = await supabaseAdmin
      .from("giveaways")
      .select("id,name,product_id")
      .eq("id", giveawayId)
      .maybeSingle();
    if (gErr) return jsonResponse({ ok: false, error: gErr.message }, 500);
    if (!giveaway) return jsonResponse({ ok: false, error: "Giveaway not found" }, 404);

    // The claim is checked rather than trusted: a caller with a valid token still
    // cannot use this to mail an arbitrary person about a giveaway they did not win.
    const { data: entry } = await supabaseAdmin
      .from("giveaway_entries")
      .select("id,won")
      .eq("giveaway_id", giveawayId)
      .eq("profile_id", winnerProfileId)
      .eq("won", true)
      .maybeSingle();
    if (!entry) {
      return jsonResponse({ ok: false, error: "That profile is not a winner of this giveaway", reason: "not_a_winner" }, 409);
    }

    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("id,display_name,username,email,contact_email")
      .eq("id", winnerProfileId)
      .maybeSingle();
    if (!profile) return jsonResponse({ ok: false, error: "Winner profile not found" }, 404);

    const email = (profile.email || profile.contact_email || "").trim();
    if (!email) {
      // Not an error the admin needs to act on, and not a failure of the draw. The
      // client distinguishes this from a real failure by `reason`.
      return jsonResponse({
        ok: false,
        reason: "no_email",
        error: "This winner has no email address on file — tell them in the app instead.",
      }, 200);
    }

    // The prize name, when the giveaway is tied to a product. Absent is fine; the
    // template drops the clause rather than printing "undefined".
    let prizeName: string | undefined;
    if (giveaway.product_id) {
      const { data: product } = await supabaseAdmin
        .from("products").select("name").eq("id", giveaway.product_id).maybeSingle();
      prizeName = product?.name || undefined;
    }

    const result = await sendGiveawayWinnerEmail({
      email,
      name: (profile.display_name || profile.username || "there").trim(),
      giveawayName: giveaway.name || "a Hybrid giveaway",
      prizeName,
    });

    if (!result.success) {
      return jsonResponse({ ok: false, error: result.error || "Mailgun rejected the message" }, 502);
    }

    return jsonResponse({ ok: true, provider: "mailgun", fulfillment: "emailed", id: entry.id });
  } catch (e) {
    return jsonResponse({ ok: false, error: (e as Error)?.message || "Unhandled error" }, 500);
  }
});
