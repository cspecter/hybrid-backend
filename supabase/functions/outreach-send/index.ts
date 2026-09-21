/**
 * outreach-send — the scheduler.
 *
 * One tick: take the contacts whose next_eligible_at has passed, work out what each
 * one is due (welcome, the next tip, a periodic update, or a profile nudge), build
 * it from live data, hand it to deliver(), and write back when they are next due.
 *
 * Runs on pg_cron every 15 minutes inside the sending window (see
 * 20260920000011_outreach_cron.sql). MAX_SENDS_PER_TICK spreads the daily
 * allowance across the day instead of firing it in one burst.
 */

import { errorResponse, handleCors, jsonResponse } from "../_shared/cors.ts";
import {
  DIGEST_INTERVAL_DAYS, DROP_LOOKAHEAD_DAYS, DROP_LOOKBACK_DAYS,
  GIVEAWAY_LOOKAHEAD_DAYS, GIVEAWAY_LOOKBACK_DAYS, MAX_ITEMS_PER_SECTION,
  MAX_SENDS_PER_TICK, MAX_SENDS_WITHOUT_ENGAGEMENT, MODE, NEW_LOCATION_DAYS,
  NUDGE_INTERVAL_DAYS, SEQUENCE_INTERVAL_DAYS, SEQUENCE_LENGTH, STATS_WINDOW_DAYS,
  TEST_RECIPIENTS,
} from "../_shared/outreach/config.ts";
import {
  composeDigest, composeNudge, composeTip, composeWelcome, NotComposable,
} from "../_shared/outreach/compose.ts";
import { deliver, preflight, remainingToday, tickBlocked } from "../_shared/outreach/dispatch.ts";
import {
  completenessFor, type Contact, digestFor, dueContacts, hasSomethingToSay,
  logMessage, updateContact,
} from "../_shared/outreach/db.ts";

const DAY_MS = 86_400_000;
const inDays = (n: number) => new Date(Date.now() + n * DAY_MS).toISOString();

const WINDOWS = {
  giveawayAhead: GIVEAWAY_LOOKAHEAD_DAYS,
  giveawayBack: GIVEAWAY_LOOKBACK_DAYS,
  dropAhead: DROP_LOOKAHEAD_DAYS,
  dropBack: DROP_LOOKBACK_DAYS,
  newLocationDays: NEW_LOCATION_DAYS,
  statsWindow: STATS_WINDOW_DAYS,
  maxItems: MAX_ITEMS_PER_SECTION,
};

type Step =
  | { kind: "welcome" }
  | { kind: "tip"; step: number }
  | { kind: "digest"; digest: Record<string, unknown> }
  | { kind: "nudge"; item: { field: string; label: string } }
  | { kind: "none"; reason: string }
  | { kind: "stop"; reason: string; status: string };

/**
 * What this contact is due, in priority order.
 *
 * A nudge is preferred over a digest when both are available: a profile with a
 * hole in it limits everything else the app can do for them, and the digest will
 * still be there in two weeks.
 */
const decide = async (c: Contact): Promise<Step> => {
  if (c.sends_since_engagement >= MAX_SENDS_WITHOUT_ENGAGEMENT) {
    return {
      kind: "stop",
      status: "no_engagement",
      reason: `${c.sends_since_engagement} sends with no reply`,
    };
  }

  if (c.stage === "welcome") return { kind: "welcome" };

  if (c.stage === "sequence") {
    if (c.sequence_step < SEQUENCE_LENGTH) return { kind: "tip", step: c.sequence_step };
    // Falls through to updates on the next pass; stage is advanced below.
  }

  const completeness = await completenessFor(c);
  const nudgeDue = !c.last_nudge_field ||
    !c.last_sent_at ||
    Date.now() - new Date(c.last_sent_at).getTime() >= NUDGE_INTERVAL_DAYS * DAY_MS;

  if (completeness && completeness.complete === false && nudgeDue) {
    const top = completeness.top as { field: string; label: string } | null;
    // Never the same item twice in a row: if they ignored it, a second identical
    // email is nagging rather than helping, so move to the next one down.
    const list = (completeness.missing ?? []) as Array<{ field: string; label: string }>;
    const pick = top && top.field !== c.last_nudge_field
      ? top
      : list.find((m) => m.field !== c.last_nudge_field) ?? null;
    if (pick) return { kind: "nudge", item: pick };
  }

  const digestDue = !c.last_digest_at ||
    Date.now() - new Date(c.last_digest_at).getTime() >= DIGEST_INTERVAL_DAYS * DAY_MS;
  if (!digestDue) return { kind: "none", reason: "digest not due yet" };

  if (!c.profile_id) {
    // A prospect has no account to report on. They keep the welcome and the
    // sequence and then hear nothing, rather than getting a hollow digest.
    return { kind: "none", reason: "prospect: no linked account, nothing to report" };
  }

  const digest = await digestFor(c, WINDOWS);
  if (!hasSomethingToSay(c.segment, digest)) {
    return { kind: "none", reason: "no live content for this segment right now" };
  }
  return { kind: "digest", digest: digest! };
};

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    // ?dry=1 composes for the contacts that are due and returns the copy without
    // creating a Gmail draft and without advancing anybody's cadence. It is how you
    // read what each segment's email actually says before letting it out, and it
    // needs no Gmail credentials — only ANTHROPIC_API_KEY.
    const dry = new URL(req.url).searchParams.get("dry") === "1";

    const blocked = dry ? null : await tickBlocked();
    if (blocked) {
      console.log(`outreach-send: skipping tick — ${blocked}`);
      return jsonResponse({ ok: true, skipped: blocked, mode: MODE });
    }

    const budget = dry ? MAX_SENDS_PER_TICK : Math.min(MAX_SENDS_PER_TICK, await remainingToday());
    // Over-fetch: most candidates resolve to "nothing to say" and cost no budget,
    // so a batch the size of the budget would usually deliver almost nothing.
    const candidates = await dueContacts(budget * 4);

    const summary = {
      mode: dry ? "dry-run (nothing delivered, no state changed)" : MODE,
      allowlist_active: TEST_RECIPIENTS.length > 0,
      considered: candidates.length,
      budget,
      sent: 0, drafted: 0, skipped: 0, failed: 0, stopped: 0, nothing_to_say: 0,
      detail: [] as Array<Record<string, unknown>>,
    };

    for (const contact of candidates) {
      if (summary.sent + summary.drafted >= budget) break;

      const step = await decide(contact);

      if (step.kind === "stop") {
        await updateContact(contact.id, {
          status: step.status,
          next_eligible_at: "infinity",
        });
        summary.stopped++;
        summary.detail.push({ email: contact.email, outcome: "stopped", reason: step.reason });
        continue;
      }

      if (step.kind === "none") {
        // Advance the clock anyway. Without this the same contact is reconsidered
        // every tick for the rest of the day and starves everyone behind them.
        await updateContact(contact.id, {
          stage: "updates",
          next_eligible_at: inDays(DIGEST_INTERVAL_DAYS),
        });
        summary.nothing_to_say++;
        summary.detail.push({ email: contact.email, outcome: "nothing to say", reason: step.reason });
        continue;
      }

      // Before spending a model call: are we allowed to write to this person at
      // all? Suppression first, then the test-recipients allowlist.
      const pre = await preflight(contact);
      if (!pre.ok) {
        if (!dry) {
          await logMessage({
            contact_id: contact.id, email: contact.email, direction: "outbound",
            message_type: step.kind, status: "skipped", mode: MODE, error: pre.reason,
          });
          // Not a send, so the cadence does not advance — but do not reconsider
          // them on every tick for the rest of the day either.
          await updateContact(contact.id, { next_eligible_at: inDays(1) });
        }
        summary.skipped++;
        summary.detail.push({ email: contact.email, outcome: "skipped", reason: pre.reason });
        continue;
      }

      let composed;
      try {
        composed = step.kind === "welcome" ? await composeWelcome(contact)
          : step.kind === "tip" ? await composeTip(contact, step.step)
          : step.kind === "digest" ? await composeDigest(contact, step.digest)
          : await composeNudge(contact, step.item);
      } catch (e) {
        const reason = e instanceof Error ? e.message : String(e);
        // A guardrail failure or a missing mailing address is not this contact's
        // fault: leave them due and try again next tick rather than burning them.
        summary.failed++;
        summary.detail.push({
          email: contact.email,
          outcome: e instanceof NotComposable ? "not composable" : "compose failed",
          reason,
        });
        continue;
      }

      if (dry) {
        summary.drafted++;
        summary.detail.push({
          email: contact.email, segment: contact.segment, outcome: "dry-run",
          type: step.kind, subject: composed.subject, body: composed.body,
        });
        continue;
      }

      const messageType = step.kind === "tip" ? `tip_${step.step + 1}`
        : step.kind === "nudge" ? `nudge_${step.item.field}`
        : step.kind;

      const outcome = await deliver({
        contact,
        subject: composed.subject,
        body: composed.body,
        messageType,
        threadId: contact.gmail_thread_id ?? undefined,
      });

      if (!outcome.ok) {
        if (outcome.status === "skipped") {
          summary.skipped++;
          // A skip is not a send, so the cadence must not advance — but neither
          // should this contact be reconsidered on every tick today.
          await updateContact(contact.id, { next_eligible_at: inDays(1) });
        } else {
          summary.failed++;
        }
        summary.detail.push({ email: contact.email, outcome: outcome.status, reason: outcome.reason });
        continue;
      }

      if (outcome.status === "sent") summary.sent++; else summary.drafted++;

      const patch: Record<string, unknown> = {
        sends_count: contact.sends_count + 1,
        sends_since_engagement: contact.sends_since_engagement + 1,
        last_sent_at: new Date().toISOString(),
        // First message in a thread sets it, so replies land back on this contact.
        gmail_thread_id: contact.gmail_thread_id ?? outcome.threadId ?? null,
      };

      if (step.kind === "welcome") {
        patch.stage = "sequence";
        patch.sequence_step = 0;
        patch.next_eligible_at = inDays(SEQUENCE_INTERVAL_DAYS);
      } else if (step.kind === "tip") {
        const next = step.step + 1;
        patch.sequence_step = next;
        patch.stage = next >= SEQUENCE_LENGTH ? "updates" : "sequence";
        patch.next_eligible_at = inDays(
          next >= SEQUENCE_LENGTH ? DIGEST_INTERVAL_DAYS : SEQUENCE_INTERVAL_DAYS,
        );
      } else if (step.kind === "nudge") {
        patch.stage = "updates";
        patch.last_nudge_field = step.item.field;
        patch.next_eligible_at = inDays(NUDGE_INTERVAL_DAYS);
      } else {
        patch.stage = "updates";
        patch.last_digest_at = new Date().toISOString();
        patch.next_eligible_at = inDays(DIGEST_INTERVAL_DAYS);
      }

      await updateContact(contact.id, patch);
      summary.detail.push({
        email: contact.email, outcome: outcome.status, type: messageType, subject: composed.subject,
      });
    }

    console.log(
      `outreach-send: ${summary.sent} sent, ${summary.drafted} drafted, ` +
      `${summary.skipped} skipped, ${summary.nothing_to_say} nothing-to-say, ` +
      `${summary.failed} failed, ${summary.stopped} stopped`,
    );
    return jsonResponse({ ok: true, ...summary });
  } catch (e) {
    console.error("outreach-send failed:", e instanceof Error ? e.message : e);
    return errorResponse(e instanceof Error ? e.message : "Unknown error");
  }
});
