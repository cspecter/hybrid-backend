/**
 * Anthropic client. The key is read from the environment and never logged, never
 * returned in a response body, and never written to a table.
 */

import { MAX_TOKENS, MODEL } from "./config.ts";

const API_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";

export class MissingCredential extends Error {}

const apiKey = (): string => {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    throw new MissingCredential(
      "ANTHROPIC_API_KEY is not set as a function secret — see docs/OUTREACH-AGENT.md",
    );
  }
  return key;
};

export type Message = { role: "user" | "assistant"; content: string };

/**
 * One call. Returns the concatenated text blocks.
 *
 * Errors carry the status and Anthropic's own message, which never contains the
 * key — but the request headers do, so nothing about the request is ever logged.
 */
export const complete = async (
  system: string,
  messages: Message[],
  opts: { maxTokens?: number; temperature?: number } = {},
): Promise<string> => {
  const res = await fetch(API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey(),
      "anthropic-version": API_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: opts.maxTokens ?? MAX_TOKENS,
      temperature: opts.temperature ?? 0.6,
      system,
      messages,
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`Anthropic ${res.status}: ${detail.slice(0, 400)}`);
  }

  const body = await res.json();
  const text = (body?.content ?? [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text)
    .join("")
    .trim();

  if (!text) throw new Error("Anthropic returned no text");
  return text;
};

/**
 * A completion that must come back as JSON. Used for reply classification, where a
 * free-text answer would have to be parsed by guessing.
 *
 * The model is told to emit JSON and nothing else; this still strips a code fence
 * if one appears, because that failure is common enough that throwing on it would
 * escalate replies for a formatting reason rather than a real one.
 */
export const completeJson = async <T>(
  system: string,
  messages: Message[],
  opts: { maxTokens?: number } = {},
): Promise<T> => {
  const raw = await complete(system, messages, { ...opts, temperature: 0 });
  const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/, "").trim();
  try {
    return JSON.parse(cleaned) as T;
  } catch {
    throw new Error(`Expected JSON, got: ${cleaned.slice(0, 200)}`);
  }
};
