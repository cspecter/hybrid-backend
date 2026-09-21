/**
 * Gmail API, via an OAuth refresh token for one mailbox.
 *
 * The client id, client secret and refresh token are read from the environment.
 * None of the three, and no access token derived from them, is ever logged,
 * returned in a response, or written to a table. Errors deliberately report only
 * the HTTP status and Google's message.
 *
 * See docs/OUTREACH-AGENT.md for how to mint the refresh token.
 */

import { MissingCredential } from "./anthropic.ts";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const API = "https://gmail.googleapis.com/gmail/v1/users/me";

const env = (name: string): string => {
  const v = Deno.env.get(name);
  if (!v) {
    throw new MissingCredential(`${name} is not set as a function secret — see docs/OUTREACH-AGENT.md`);
  }
  return v;
};

// Access tokens last an hour; a cron tick is far shorter than that, so one
// exchange per invocation is enough and nothing is cached across invocations.
let cachedToken: { token: string; expiresAt: number } | null = null;

export const accessToken = async (): Promise<string> => {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.token;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("GMAIL_CLIENT_ID"),
      client_secret: env("GMAIL_CLIENT_SECRET"),
      refresh_token: env("GMAIL_REFRESH_TOKEN"),
      grant_type: "refresh_token",
    }),
  });

  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    // Google echoes error/error_description only; the credentials are not in it.
    throw new Error(
      `Gmail token exchange failed (${res.status}): ${detail.error ?? "unknown"} ${detail.error_description ?? ""}`,
    );
  }

  const body = await res.json();
  cachedToken = {
    token: body.access_token,
    expiresAt: Date.now() + (body.expires_in ?? 3600) * 1000,
  };
  return cachedToken.token;
};

const call = async (path: string, init: RequestInit = {}): Promise<any> => {
  const token = await accessToken();
  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`Gmail ${init.method ?? "GET"} ${path} -> ${res.status}: ${detail.slice(0, 300)}`);
  }
  if (res.status === 204) return null;
  return await res.json();
};

// ─── Encoding ────────────────────────────────────────────────────────────────

const b64url = (bytes: Uint8Array): string => {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

const b64urlDecode = (s: string): string => {
  const norm = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = norm + "=".repeat((4 - (norm.length % 4)) % 4);
  const bin = atob(pad);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
};

/** RFC 2047 for any header that is not pure ASCII — a name with an accent in it. */
const encodeHeader = (value: string): string => {
  // deno-lint-ignore no-control-regex
  if (/^[\x00-\x7F]*$/.test(value)) return value;
  return `=?UTF-8?B?${b64url(new TextEncoder().encode(value)).replace(/-/g, "+").replace(/_/g, "/")}?=`;
};

export type OutgoingMail = {
  to: string;
  fromName: string;
  subject: string;
  /** Plain text. The agent does not send HTML. */
  body: string;
  unsubscribeUrl: string;
  unsubscribeMailto?: string;
  /** Set for a reply so Gmail threads it. */
  threadId?: string;
  inReplyTo?: string;
  references?: string;
};

/**
 * Builds an RFC 2822 message.
 *
 * List-Unsubscribe plus List-Unsubscribe-Post is what makes the one-click header
 * work in Gmail and Outlook: the URL must accept an unauthenticated POST, which
 * outreach-unsubscribe does.
 */
export const buildRaw = (mail: OutgoingMail): string => {
  const headers = [
    `From: ${encodeHeader(mail.fromName)} <me>`,
    `To: ${mail.to}`,
    `Subject: ${encodeHeader(mail.subject)}`,
    "MIME-Version: 1.0",
    'Content-Type: text/plain; charset="UTF-8"',
    "Content-Transfer-Encoding: 8bit",
    `List-Unsubscribe: <${mail.unsubscribeUrl}>${mail.unsubscribeMailto ? `, <mailto:${mail.unsubscribeMailto}>` : ""}`,
    "List-Unsubscribe-Post: List-Unsubscribe=One-Click",
  ];
  if (mail.inReplyTo) headers.push(`In-Reply-To: ${mail.inReplyTo}`);
  if (mail.references) headers.push(`References: ${mail.references}`);

  // "From: Name <me>" is rewritten by Gmail to the mailbox's own address, which is
  // what keeps the sending identity honest — the agent cannot spoof a From.
  return b64url(new TextEncoder().encode(`${headers.join("\r\n")}\r\n\r\n${mail.body}`));
};

export type SendResult = { id: string; threadId: string };

export const sendMail = async (mail: OutgoingMail): Promise<SendResult> => {
  const res = await call("/messages/send", {
    method: "POST",
    body: JSON.stringify({ raw: buildRaw(mail), ...(mail.threadId ? { threadId: mail.threadId } : {}) }),
  });
  return { id: res.id, threadId: res.threadId };
};

export const draftMail = async (mail: OutgoingMail): Promise<SendResult> => {
  const res = await call("/drafts", {
    method: "POST",
    body: JSON.stringify({
      message: { raw: buildRaw(mail), ...(mail.threadId ? { threadId: mail.threadId } : {}) },
    }),
  });
  return { id: res.message?.id ?? res.id, threadId: res.message?.threadId ?? "" };
};

// ─── Labels ──────────────────────────────────────────────────────────────────

let labelCache: Record<string, string> | null = null;

export const ensureLabel = async (name: string): Promise<string> => {
  if (!labelCache) {
    const res = await call("/labels");
    labelCache = {};
    for (const l of res.labels ?? []) labelCache[l.name] = l.id;
  }
  if (labelCache[name]) return labelCache[name];

  const created = await call("/labels", {
    method: "POST",
    body: JSON.stringify({
      name,
      labelListVisibility: "labelShow",
      messageListVisibility: "show",
    }),
  });
  labelCache[name] = created.id;
  return created.id;
};

export const labelThread = async (threadId: string, labelName: string): Promise<void> => {
  const id = await ensureLabel(labelName);
  await call(`/threads/${threadId}/modify`, {
    method: "POST",
    body: JSON.stringify({ addLabelIds: [id] }),
  });
};

// ─── Reading replies ─────────────────────────────────────────────────────────

export type InboundMessage = {
  id: string;
  threadId: string;
  from: string;
  fromEmail: string;
  subject: string;
  body: string;
  messageIdHeader: string;
  references: string;
  internalDate: number;
};

const headerValue = (headers: Array<{ name: string; value: string }>, name: string): string =>
  headers.find((h) => h.name.toLowerCase() === name.toLowerCase())?.value ?? "";

/** Depth-first for the first text/plain part; falls back to stripping the HTML. */
const extractBody = (payload: any): string => {
  if (!payload) return "";
  if (payload.mimeType === "text/plain" && payload.body?.data) return b64urlDecode(payload.body.data);
  for (const part of payload.parts ?? []) {
    const found = extractBody(part);
    if (found) return found;
  }
  if (payload.mimeType === "text/html" && payload.body?.data) {
    return b64urlDecode(payload.body.data).replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  }
  return "";
};

export const parseAddress = (from: string): string => {
  const m = from.match(/<([^>]+)>/);
  return (m ? m[1] : from).trim().toLowerCase();
};

/**
 * Replies the agent has not seen. Restricted to the inbox and to unread messages
 * in threads — the caller filters again against outreach_messages by Gmail id, so
 * a message that arrives twice is still only answered once.
 */
export const listReplies = async (lookbackHours: number, max: number): Promise<InboundMessage[]> => {
  const after = Math.floor((Date.now() - lookbackHours * 3600_000) / 1000);
  const q = encodeURIComponent(`in:inbox -from:me after:${after}`);
  const list = await call(`/messages?q=${q}&maxResults=${max}`);
  const out: InboundMessage[] = [];

  for (const stub of list.messages ?? []) {
    const full = await call(`/messages/${stub.id}?format=full`);
    const headers = full.payload?.headers ?? [];
    const from = headerValue(headers, "From");
    out.push({
      id: full.id,
      threadId: full.threadId,
      from,
      fromEmail: parseAddress(from),
      subject: headerValue(headers, "Subject"),
      body: extractBody(full.payload).slice(0, 8000),
      messageIdHeader: headerValue(headers, "Message-ID"),
      references: headerValue(headers, "References"),
      internalDate: Number(full.internalDate ?? 0),
    });
  }
  return out;
};
