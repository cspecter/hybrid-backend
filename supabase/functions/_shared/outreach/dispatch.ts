/**
 * The gate every outbound message passes through.
 *
 * Nothing in this agent calls gmail.sendMail or gmail.draftMail directly. They go
 * through deliver(), which checks — in this order — the pause switch, the
 * suppression list, the test-recipients allowlist, the daily cap and the sending
 * window, and then logs whatever happened either way.
 */

import { draftMail, sendMail } from "./gmail.ts";
import {
  DAILY_SEND_CAP, MODE, SEND_TIMEZONE, SEND_WEEKDAYS_ONLY,
  SEND_WINDOW_END_HOUR, SEND_WINDOW_START_HOUR, SENDER_NAME, TEST_RECIPIENTS,
} from "./config.ts";
import { footer, unsubscribeUrl } from "./compose.ts";
import { type Contact, isPaused, isSuppressed, logMessage, sentToday } from "./db.ts";

export type DeliveryOutcome =
  | { ok: true; status: "sent" | "drafted"; gmailId: string; threadId: string }
  | { ok: false; status: "skipped" | "failed"; reason: string };

const allowlisted = (email: string): boolean =>
  TEST_RECIPIENTS.length === 0 ||
  TEST_RECIPIENTS.some((a) => a.trim().toLowerCase() === email.trim().toLowerCase());

/** Local hour in SEND_TIMEZONE, so the window means what it says wherever this runs. */
export const localNow = (): { hour: number; weekday: number } => {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: SEND_TIMEZONE, hour: "numeric", hour12: false, weekday: "short",
  });
  const parts = Object.fromEntries(fmt.formatToParts(new Date()).map((p) => [p.type, p.value]));
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return { hour: Number(parts.hour), weekday: days.indexOf(String(parts.weekday)) };
};

export const inSendWindow = (): boolean => {
  const { hour, weekday } = localNow();
  if (SEND_WEEKDAYS_ONLY && (weekday === 0 || weekday === 6)) return false;
  return hour >= SEND_WINDOW_START_HOUR && hour < SEND_WINDOW_END_HOUR;
};

/**
 * Reasons a whole tick should do nothing. Checked once per invocation rather than
 * per contact, because none of them can change mid-tick.
 */
export const tickBlocked = async (): Promise<string | null> => {
  if (await isPaused()) return "agent is paused";
  if (!inSendWindow()) return `outside the sending window (${SEND_WINDOW_START_HOUR}:00–${SEND_WINDOW_END_HOUR}:00 ${SEND_TIMEZONE})`;
  const today = await sentToday();
  if (today >= DAILY_SEND_CAP) return `daily cap reached (${today}/${DAILY_SEND_CAP})`;
  return null;
};

export const remainingToday = async (): Promise<number> =>
  Math.max(0, DAILY_SEND_CAP - (await sentToday()));

/**
 * The two per-contact refusals, checked before anything expensive happens.
 *
 * deliver() checks both again — this is not belt and braces for its own sake. A
 * model call costs money and a Gmail draft is a side effect, and neither should be
 * spent on someone we are not allowed to write to. The check inside deliver()
 * stays because a reply processed later in the same run can suppress an address
 * that passed preflight a few seconds earlier.
 */
export type Preflight = { ok: true } | { ok: false; reason: string };

export const preflight = async (contact: Contact): Promise<Preflight> => {
  if (await isSuppressed(contact.email)) return { ok: false, reason: "suppressed" };
  if (!allowlisted(contact.email)) return { ok: false, reason: "not in TEST_RECIPIENTS allowlist" };
  return { ok: true };
};

export type Delivery = {
  contact: Contact;
  subject: string;
  body: string;
  messageType: string;
  /** Set for a reply so Gmail threads it under the original. */
  threadId?: string;
  inReplyTo?: string;
  references?: string;
};

/**
 * Sends or drafts one message, and logs it whichever happens — including when it is
 * skipped, so the audit trail shows the contact was considered and why nothing
 * went out.
 */
export const deliver = async (d: Delivery): Promise<DeliveryOutcome> => {
  const { contact } = d;

  // Re-checked here rather than trusted from the batch: a reply handled earlier in
  // this same run may have just suppressed them.
  if (await isSuppressed(contact.email)) {
    await logMessage({
      contact_id: contact.id, email: contact.email, direction: "outbound",
      message_type: d.messageType, subject: d.subject, status: "skipped", mode: MODE,
      error: "suppressed",
    });
    return { ok: false, status: "skipped", reason: "suppressed" };
  }

  if (!allowlisted(contact.email)) {
    await logMessage({
      contact_id: contact.id, email: contact.email, direction: "outbound",
      message_type: d.messageType, subject: d.subject, status: "skipped", mode: MODE,
      error: "not in TEST_RECIPIENTS allowlist",
    });
    return { ok: false, status: "skipped", reason: "not in TEST_RECIPIENTS allowlist" };
  }

  const mail = {
    to: contact.email,
    fromName: SENDER_NAME,
    subject: d.subject,
    body: `${d.body.trim()}\n${footer(contact)}`,
    unsubscribeUrl: unsubscribeUrl(contact),
    threadId: d.threadId,
    inReplyTo: d.inReplyTo,
    references: d.references,
  };

  try {
    const res = MODE === "send" ? await sendMail(mail) : await draftMail(mail);
    await logMessage({
      contact_id: contact.id, email: contact.email, direction: "outbound",
      message_type: d.messageType, subject: d.subject, body: mail.body,
      gmail_message_id: res.id, gmail_thread_id: res.threadId || d.threadId || null,
      status: MODE === "send" ? "sent" : "drafted", mode: MODE,
    });
    return {
      ok: true,
      status: MODE === "send" ? "sent" : "drafted",
      gmailId: res.id,
      threadId: res.threadId || d.threadId || "",
    };
  } catch (e) {
    const reason = e instanceof Error ? e.message : String(e);
    await logMessage({
      contact_id: contact.id, email: contact.email, direction: "outbound",
      message_type: d.messageType, subject: d.subject, body: mail.body,
      status: "failed", mode: MODE, error: reason.slice(0, 500),
    });
    return { ok: false, status: "failed", reason };
  }
};
