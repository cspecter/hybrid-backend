/**
 * Who may call the outreach functions.
 *
 * Supabase's verify_jwt only checks that the bearer token is a *valid* JWT — and
 * the anon key is a valid JWT, published in the frontend bundle. Without this
 * guard, anyone who viewed source could trigger sends, poll the mailbox and import
 * arbitrary contacts into the outreach list. verify_jwt stays on; this is the
 * check that actually decides.
 *
 * Two callers are allowed:
 *   service_role   pg_cron, and anything run with the service key
 *   super admin    a signed-in super admin, so the admin dashboard can upload a
 *                  CSV and preview copy with the user's own session token
 *
 * The JWT's signature is not re-verified here: the platform gateway already did
 * that before the function ran, and a token that failed never reaches this code.
 * Only the claims are read.
 */

import { supabaseAdmin } from "../supabase.ts";
import { errorResponse } from "../cors.ts";

type Claims = { role?: string; sub?: string };

const decodeClaims = (token: string): Claims | null => {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const norm = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const json = atob(norm + "=".repeat((4 - (norm.length % 4)) % 4));
    return JSON.parse(json) as Claims;
  } catch {
    return null;
  }
};

export type Caller =
  | { kind: "service_role" }
  | { kind: "super_admin"; authId: string };

/**
 * Returns the caller, or a Response to return immediately.
 *
 * Refusals are deliberately vague — "Not authorised" and nothing about why — so a
 * caller probing with different tokens learns nothing from the difference.
 */
export const requireAdminCaller = async (
  req: Request,
): Promise<{ caller: Caller } | { refuse: Response }> => {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return { refuse: errorResponse("Not authorised", 401) };

  // New-format secret keys (sb_secret_...) are not JWTs, so an exact match against
  // the platform's own service key is the only way to recognise one.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (serviceKey && token === serviceKey) return { caller: { kind: "service_role" } };

  const claims = decodeClaims(token);
  if (!claims) return { refuse: errorResponse("Not authorised", 401) };
  if (claims.role === "service_role") return { caller: { kind: "service_role" } };

  // An anon token lands here and is refused: role is "anon", and it carries no sub
  // to look a super admin up by.
  if (claims.role !== "authenticated" || !claims.sub) {
    return { refuse: errorResponse("Not authorised", 403) };
  }

  const { data, error } = await supabaseAdmin
    .from("super_admins").select("auth_id").eq("auth_id", claims.sub).maybeSingle();
  if (error) {
    console.error("super admin lookup failed:", error.message);
    return { refuse: errorResponse("Not authorised", 403) };
  }
  if (!data) return { refuse: errorResponse("Not authorised", 403) };

  return { caller: { kind: "super_admin", authId: claims.sub } };
};
