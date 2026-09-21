/**
 * outreach-unsubscribe — the link in the footer, and the target of the
 * List-Unsubscribe header.
 *
 * Public: no JWT, because the person clicking it is reading email, not signed in.
 * Deploy with --no-verify-jwt.
 *
 *   GET  ?c=<contact public_id>   human click. Writes the suppression and shows a
 *                                 confirmation page.
 *   POST ?c=<contact public_id>   one-click, sent by Gmail and Outlook on behalf of
 *                                 the reader. Same write, 200 with no body.
 *
 * GET performing a write is a deliberate departure from the usual rule: the one-click
 * headers and every mail client's link handling assume a plain GET works, and an
 * unsubscribe that needs a confirming click is an unsubscribe that fails.
 *
 * The identifier is the contact's public_id (a random uuid), not the address, so the
 * URL cannot be used to unsubscribe somebody else or to test whether an address is
 * on the list.
 */

import { corsHeaders } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabase.ts";

/**
 * Plain text, not HTML, and deliberately so.
 *
 * The Supabase Edge gateway serves every function response as `text/plain` with
 * `X-Content-Type-Options: nosniff` and `Content-Security-Policy: default-src
 * \'none\'; sandbox`, whatever content-type the function sets — it will not host a
 * rendered web page on a supabase.co URL. Verified against this function: the
 * response carried `content-type: text/plain` with `text/html; charset=utf-8` set
 * in code. An HTML page here would be shown to the reader as its own source.
 *
 * So the confirmation is written to be read as text. If you want a branded page,
 * the change is to redirect here to a route on the Hybrid domain — see the
 * decisions section of docs/OUTREACH-AGENT.md.
 */
const page = (title: string, message: string, status = 200): Response =>
  new Response(`${title}\n\n${message}\n\n— Hybrid\n`, {
    status,
    headers: { ...corsHeaders, "content-type": "text/plain; charset=utf-8" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const publicId = url.searchParams.get("c");
  const oneClick = req.method === "POST";

  if (!publicId) {
    return oneClick
      ? new Response("missing c", { status: 400, headers: corsHeaders })
      : page("Link incomplete", "This unsubscribe link is missing its code. Reply to the email with the word STOP and we will take you off the list.", 400);
  }

  try {
    const { data: contact } = await supabaseAdmin
      .from("outreach_contacts")
      .select("id,email")
      .eq("public_id", publicId)
      .maybeSingle();

    if (!contact) {
      // Not an error worth showing as one: an old link for a contact that has since
      // been removed has already achieved what the reader wanted.
      return oneClick
        ? new Response("ok", { status: 200, headers: corsHeaders })
        : page("You're unsubscribed", "This address will not receive any more onboarding email from Hybrid.");
    }

    // The insert trigger sets the contact's status and stops the cadence, so this
    // one write is the whole unsubscribe. Idempotent: clicking twice is fine.
    const { error } = await supabaseAdmin.from("outreach_suppressions").upsert(
      {
        email: contact.email,
        reason: "unsubscribed",
        source: oneClick ? "one-click header" : "footer link",
        contact_id: contact.id,
      },
      { onConflict: "email", ignoreDuplicates: true },
    );
    if (error) throw new Error(error.message);

    console.log(`unsubscribed contact ${contact.id} via ${oneClick ? "one-click" : "link"}`);

    return oneClick
      ? new Response("ok", { status: 200, headers: corsHeaders })
      : page("You're unsubscribed", "You won't receive any more onboarding email from Hybrid. Nothing else about your account changes.");
  } catch (e) {
    console.error("unsubscribe failed:", e instanceof Error ? e.message : e);
    return oneClick
      ? new Response("error", { status: 500, headers: corsHeaders })
      : page("Something went wrong", "We could not record that just now. Reply to the email with the word STOP and we will take you off the list by hand.", 500);
  }
});
