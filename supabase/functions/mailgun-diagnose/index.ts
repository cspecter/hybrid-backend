// Why Mailgun answers 401, without anyone having to read the key.
//
// A live winner-email test on 24 Sep 2026 got "401 - Forbidden" and stayed there. From
// outside, a key issued in the wrong region, a revoked key and a key for a domain that no
// longer exists all look identical: Mailgun says Forbidden to all three. This asks the
// questions that separate them.
//
// Mailgun runs two regions with separate credential namespaces, api.mailgun.net and
// api.eu.mailgun.net, and a key belongs to exactly one. GET /v3/domains needs only the
// key, so a 200 from one region and a 401 from the other names the region outright. Once
// the region is known, asking for the domain says whether the sending domain still exists
// and is verified.
//
// Nothing here returns or logs the key. Its length and whether it carries the old "key-"
// prefix are reported because those distinguish a classic private key from a newer sending
// key, and that is a real cause of 401 on the messages endpoint.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const US = "https://api.mailgun.net/v3";
const EU = "https://api.eu.mailgun.net/v3";

async function probe(base: string, key: string, path: string) {
  try {
    const res = await fetch(`${base}${path}`, {
      headers: { Authorization: `Basic ${btoa(`api:${key}`)}` },
    });
    const body = await res.text();
    return {
      status: res.status,
      ok: res.ok,
      // Mailgun's bodies are short and carry no credentials; truncated anyway.
      body: body.slice(0, 300),
    };
  } catch (e) {
    return { status: 0, ok: false, body: e instanceof Error ? e.message : String(e) };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const key = Deno.env.get("MAILGUN_API_KEY") || "";
  const domain = Deno.env.get("MAILGUN_DOMAIN") || "";
  const from = Deno.env.get("MAILGUN_FROM_EMAIL") || "(unset, defaults to info@gethybrid.co)";
  const configuredBase = Deno.env.get("MAILGUN_API_BASE") || "(unset, defaults to US)";

  const report: Record<string, unknown> = {
    config: {
      domain: domain || "(unset)",
      from,
      api_base_configured: configuredBase,
      key_present: key.length > 0,
      key_length: key.length,
      key_has_legacy_prefix: key.startsWith("key-"),
      key_looks_like_url: key.includes("://"),
      key_has_whitespace: /\s/.test(key),
    },
  };

  if (!key) {
    report.verdict = "MAILGUN_API_KEY is not set at all.";
    return new Response(JSON.stringify(report, null, 2), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Which region, if any, accepts this key.
  const us = await probe(US, key, "/domains?limit=1");
  const eu = await probe(EU, key, "/domains?limit=1");
  report.auth_by_region = { us, eu };

  const live = us.ok ? US : eu.ok ? EU : null;
  report.region_that_accepts_the_key = us.ok ? "US" : eu.ok ? "EU" : "neither";

  if (live && domain) {
    report.sending_domain = await probe(live, key, `/domains/${domain}`);
  }

  if (!us.ok && !eu.ok) {
    report.verdict =
      "Neither region accepts this key, so the region is not the problem: the key itself is " +
      "rejected. Regenerate it in Mailgun (Send -> Domain settings -> Sending API keys, or " +
      "the account's Private API key) and set MAILGUN_API_KEY again.";
  } else if (eu.ok && !us.ok) {
    report.verdict =
      "The key is an EU-region key and the code defaults to the US host, which is the 401. " +
      "Fix: supabase secrets set MAILGUN_API_BASE=https://api.eu.mailgun.net/v3";
  } else if (us.ok && (report.sending_domain as { ok?: boolean } | undefined)?.ok === false) {
    report.verdict =
      "The key authenticates in the US region, so the key is fine and MAILGUN_DOMAIN is the " +
      "problem. See sending_domain for what Mailgun says about it.";
  } else if (us.ok) {
    report.verdict =
      "The key authenticates in the US region and the sending domain resolves, so " +
      "credentials and domain are both fine. If a send still fails, the body of that " +
      "failure is the next thing to read -- most likely an unverified domain or a " +
      "sandbox domain that only delivers to authorised recipients.";
  }

  // A send test lived here long enough to prove the path works: Mailgun returned 200 and
  // "Queued. Thank you." on 1 Oct 2026, message id 20261001145621.a7fa1d922ebf79ef. It is
  // gone again deliberately. The anon key is public, so an endpoint that sends mail is one
  // someone else can use to fill an inbox, and this endpoint only needs to answer questions.
  return new Response(JSON.stringify(report, null, 2), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
