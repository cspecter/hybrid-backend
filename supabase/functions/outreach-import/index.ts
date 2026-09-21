/**
 * outreach-import — load contacts from a CSV.
 *
 * POST the file as text/csv, or as multipart/form-data with a "file" field.
 * Requires the service-role key in the Authorization header: this writes the list
 * the agent will email, so it is not something an app user may call.
 *
 * Every row is validated. A row with no consent_basis is rejected outright — this
 * is cannabis marketing in NY and NJ and a contact who cannot say why they may be
 * emailed is not a contact. Rows are deduped against contacts already loaded and
 * against the suppression list, and the response reports every rejection with its
 * line number and reason.
 *
 * Add ?dry_run=1 to validate without writing.
 *
 * Columns (header row required, case-insensitive, order-free):
 *   email*         the address
 *   name           display name
 *   segment*       consumer | creator | brand | dispensary
 *   consent_basis* why we may email them, in words
 *   profile_id     numeric profiles.id, if they already have an account
 *   source         where the list came from
 *   notes          free text
 */

import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import { supabaseAdmin } from "../_shared/supabase.ts";
import { SEGMENTS } from "../_shared/outreach/config.ts";

/** RFC 4180 enough: quoted fields, doubled quotes inside them, embedded newlines. */
const parseCsv = (text: string): string[][] => {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else { quoted = false; }
      } else field += ch;
      continue;
    }
    if (ch === '"') { quoted = true; continue; }
    if (ch === ",") { row.push(field); field = ""; continue; }
    if (ch === "\r") continue;
    if (ch === "\n") { row.push(field); rows.push(row); row = []; field = ""; continue; }
    field += ch;
  }
  if (field.length > 0 || row.length > 0) { row.push(field); rows.push(row); }
  return rows.filter((r) => r.some((c) => c.trim() !== ""));
};

// Deliberately permissive on the local part and strict about the shape. The point
// is to catch a mangled column, not to adjudicate what an address may contain.
const EMAIL_RE = /^[^\s@,;]+@[^\s@,;.]+\.[^\s@,;]{2,}$/;

type Rejection = { line: number; email: string; reason: string };

const readBody = async (req: Request): Promise<string> => {
  const type = req.headers.get("content-type") ?? "";
  if (type.includes("multipart/form-data")) {
    const form = await req.formData();
    const file = form.get("file");
    if (file instanceof File) return await file.text();
    if (typeof file === "string") return file;
    throw new Error('multipart body has no "file" field');
  }
  return await req.text();
};

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("POST a CSV body", 405);

  try {
    const dryRun = new URL(req.url).searchParams.get("dry_run") === "1";
    const text = await readBody(req);
    const rows = parseCsv(text);
    if (rows.length < 2) return errorResponse("CSV has no data rows", 400);

    const header = rows[0].map((h) => h.trim().toLowerCase());
    const col = (name: string) => header.indexOf(name);
    const iEmail = col("email");
    const iSegment = col("segment");
    const iConsent = col("consent_basis");

    const missingColumns = [
      iEmail < 0 ? "email" : null,
      iSegment < 0 ? "segment" : null,
      iConsent < 0 ? "consent_basis" : null,
    ].filter(Boolean);
    if (missingColumns.length > 0) {
      return errorResponse(`CSV is missing required column(s): ${missingColumns.join(", ")}`, 400);
    }

    const iName = col("name");
    const iProfile = col("profile_id");
    const iSource = col("source");
    const iNotes = col("notes");

    const accepted: Array<Record<string, unknown>> = [];
    const rejected: Rejection[] = [];
    const seenInFile = new Set<string>();

    for (let r = 1; r < rows.length; r++) {
      const line = r + 1;
      const cells = rows[r];
      const get = (i: number) => (i >= 0 && i < cells.length ? cells[i].trim() : "");

      const email = get(iEmail).toLowerCase();
      const segment = get(iSegment).toLowerCase();
      const consent = get(iConsent);

      if (!email) { rejected.push({ line, email: "", reason: "no email" }); continue; }
      if (!EMAIL_RE.test(email)) { rejected.push({ line, email, reason: "email is not a valid address" }); continue; }
      if (!consent) { rejected.push({ line, email, reason: "no consent_basis — required, row rejected" }); continue; }
      if (!SEGMENTS.includes(segment as never)) {
        rejected.push({ line, email, reason: `segment must be one of ${SEGMENTS.join(", ")} (got "${segment || "empty"}")` });
        continue;
      }
      if (seenInFile.has(email)) { rejected.push({ line, email, reason: "duplicate within this file" }); continue; }

      let profileId: number | null = null;
      const rawProfile = get(iProfile);
      if (rawProfile) {
        const n = Number(rawProfile);
        if (!Number.isInteger(n) || n <= 0) {
          rejected.push({ line, email, reason: `profile_id "${rawProfile}" is not a positive integer` });
          continue;
        }
        profileId = n;
      }

      seenInFile.add(email);
      accepted.push({
        email, name: get(iName) || null, segment, consent_basis: consent,
        profile_id: profileId, source: get(iSource) || null, notes: get(iNotes) || null,
        _line: line,
      });
    }

    // ── Dedupe against what is already in the database ────────────────────────
    const emails = accepted.map((a) => a.email as string);
    const existing = new Set<string>();
    const suppressed = new Set<string>();
    const badProfiles = new Set<number>();

    for (let i = 0; i < emails.length; i += 500) {
      const chunk = emails.slice(i, i + 500);
      const [{ data: c }, { data: s }] = await Promise.all([
        supabaseAdmin.from("outreach_contacts").select("email").in("email", chunk),
        supabaseAdmin.from("outreach_suppressions").select("email").in("email", chunk),
      ]);
      for (const row of c ?? []) existing.add(row.email);
      for (const row of s ?? []) suppressed.add(row.email);
    }

    // A profile_id that does not exist would be a silently wrong link, and a
    // digest built against the wrong account is worse than no digest.
    const profileIds = [...new Set(accepted.map((a) => a.profile_id).filter(Boolean))] as number[];
    if (profileIds.length > 0) {
      const { data } = await supabaseAdmin.from("profiles").select("id").in("id", profileIds);
      const found = new Set((data ?? []).map((p) => p.id));
      for (const id of profileIds) if (!found.has(id)) badProfiles.add(id);
    }

    const toInsert: Array<Record<string, unknown>> = [];
    for (const row of accepted) {
      const email = row.email as string;
      const line = row._line as number;
      if (suppressed.has(email)) { rejected.push({ line, email, reason: "on the suppression list — never contact again" }); continue; }
      if (existing.has(email)) { rejected.push({ line, email, reason: "already a contact" }); continue; }
      if (row.profile_id && badProfiles.has(row.profile_id as number)) {
        rejected.push({ line, email, reason: `profile_id ${row.profile_id} does not exist` });
        continue;
      }
      const { _line, ...clean } = row;
      toInsert.push(clean);
    }

    let inserted = 0;
    if (!dryRun && toInsert.length > 0) {
      for (let i = 0; i < toInsert.length; i += 200) {
        const chunk = toInsert.slice(i, i + 200);
        const { error, count } = await supabaseAdmin
          .from("outreach_contacts").insert(chunk, { count: "exact" });
        if (error) return errorResponse(`insert failed at row ${i}: ${error.message}`, 500);
        inserted += count ?? chunk.length;
      }
    }

    return jsonResponse({
      ok: true,
      dry_run: dryRun,
      rows_in_file: rows.length - 1,
      accepted: toInsert.length,
      inserted,
      rejected: rejected.length,
      rejections: rejected.sort((a, b) => a.line - b.line),
    });
  } catch (e) {
    console.error("outreach-import failed:", e instanceof Error ? e.message : e);
    return errorResponse(e instanceof Error ? e.message : "Unknown error");
  }
});
