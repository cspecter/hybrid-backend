/**
 * Turning live data into an email.
 *
 * Every function here goes through systemPrompt(), so the hard rules ride on every
 * generation call rather than only the first one in a conversation. Every function
 * also runs the result through checkCopy() before it is allowed out.
 *
 * The footer — unsubscribe link, mailing address, 21+ line, why-you-got-this — is
 * assembled here, not by the model, so it cannot be paraphrased away.
 */

import { complete } from "./anthropic.ts";
import { checkCopy, mailingAddressReady, systemPrompt } from "./guardrails.ts";
import {
  PHYSICAL_MAILING_ADDRESS, SENDER_NAME, SEQUENCE_TOPICS, UNSUBSCRIBE_BASE_URL,
  type Segment,
} from "./config.ts";
import type { Contact } from "./db.ts";

export const unsubscribeUrl = (contact: Contact): string =>
  `${UNSUBSCRIBE_BASE_URL}?c=${encodeURIComponent(contact.public_id)}`;

/**
 * Appended verbatim. consent_basis is echoed back so the recipient can see on what
 * basis we think we may write to them — which is also the fastest way for them to
 * tell us we are wrong.
 */
export const footer = (contact: Contact): string => [
  "",
  "—",
  `You're receiving this because: ${contact.consent_basis}.`,
  `Unsubscribe: ${unsubscribeUrl(contact)}`,
  `${SENDER_NAME} · Hybrid`,
  PHYSICAL_MAILING_ADDRESS,
  "For adults 21+ only.",
].join("\n");

export type Composed = { subject: string; body: string };

export class NotComposable extends Error {}

/**
 * The model returns "Subject: ...\n\n<body>". Splitting here rather than making two
 * calls keeps the subject and the body written against the same facts.
 */
const splitSubject = (raw: string, fallback: string): Composed => {
  const m = raw.match(/^\s*subject:\s*(.+?)\s*\n+([\s\S]*)$/i);
  if (m) return { subject: m[1].trim().slice(0, 140), body: m[2].trim() };
  return { subject: fallback, body: raw.trim() };
};

/**
 * One regenerate on a guardrail hit, then give up and skip the contact. Retrying
 * forever on a model that keeps producing a health claim would be worse than
 * sending nothing.
 */
const generate = async (
  task: string,
  userContent: string,
  fallbackSubject: string,
): Promise<Composed> => {
  if (!mailingAddressReady()) {
    throw new NotComposable(
      "PHYSICAL_MAILING_ADDRESS in config.ts is still the placeholder — an email without a real postal address is not one we may send",
    );
  }

  for (let attempt = 0; attempt < 2; attempt++) {
    const raw = await complete(
      systemPrompt(task),
      [{
        role: "user",
        content: attempt === 0
          ? userContent
          : `${userContent}\n\nYour previous draft broke one of the hard rules. Rewrite it, stating only what the data above says.`,
      }],
    );
    const composed = splitSubject(raw, fallbackSubject);
    const check = checkCopy(`${composed.subject}\n${composed.body}`);
    if (check.ok) return composed;
    console.warn(`guardrail hit (${check.reason}: "${check.match}") — attempt ${attempt + 1}`);
  }
  throw new NotComposable("copy failed the guardrail check twice");
};

const WHO = (c: Contact) =>
  `Recipient: ${c.name ?? "(name unknown)"} <${c.email}>. Segment: ${c.segment}. ` +
  (c.profile_id
    ? "They already have a Hybrid account, so write to them as an existing user."
    : "They do NOT have a Hybrid account yet — they are a prospect. Point them at signing up; never imply they already have an account, numbers or a profile.");

// ─── Welcome ─────────────────────────────────────────────────────────────────

export const composeWelcome = async (contact: Contact): Promise<Composed> => {
  const task = `
Write the first email in Hybrid's onboarding sequence: a short welcome.

${WHO(contact)}

Hybrid is a cannabis discovery app. People save ("stash") products, group them into
stashlists, follow brands, creators and dispensaries, and find giveaways and deals.
It runs in New York and New Jersey and is 21+ only.

Keep it under 120 words. Say what Hybrid is, name one thing they can do first that
fits their segment, and say that a few short tips follow over the next couple of
weeks and they can stop them any time by replying.

Start your output with a line "Subject: ..." and then the body.`;

  return await generate(task, WHO(contact), "Welcome to Hybrid");
};

// ─── Getting-started sequence ────────────────────────────────────────────────

export const composeTip = async (contact: Contact, step: number): Promise<Composed> => {
  const topics = SEQUENCE_TOPICS[contact.segment as Segment];
  const topic = topics[Math.min(step, topics.length - 1)];

  const task = `
Write one email in Hybrid's short getting-started sequence. This is tip ${step + 1} of
${topics.length}.

${WHO(contact)}

The single subject of this email is: ${topic}

Cover that one thing and nothing else. Under 130 words. No recap of previous tips,
no "in our last email". Concrete and practical: what to tap, what happens next.

Do not state any statistic, count, date or result — this email carries no live data,
so any number you write would be invented.

Start your output with a line "Subject: ..." and then the body.`;

  return await generate(task, `Tip topic: ${topic}`, "A quick Hybrid tip");
};

// ─── Periodic update ─────────────────────────────────────────────────────────

const DIGEST_FRAMING: Record<Segment, string> = {
  consumer: `They are a consumer. The data below is what is live on Hybrid right now:
giveaways, dispensaries added recently, product drops, and the most-subscribed
stashlists. Report only what is present. "trending_lists" is ranked by total
subscribers, not by recent growth — do not call anything "trending fastest",
"rising" or "blowing up".`,

  creator: `They are a creator. The data below is their own account's numbers over the
window given. Report their numbers plainly. A "restash" is someone stashing a product
because of them — from one of their posts, one of their stashlists, or their profile.
Never compare them to anyone else, never project a trend from one window, and never
congratulate them on a number that is zero.`,

  brand: `They are a person who administers a brand profile on Hybrid — brands have no
login of their own. The data below is how that brand's products are doing: stashes,
appearances in stashlists, posts tagging them, and any giveaway they ran. Report the
giveaway numbers exactly as given; never estimate reach, value or ROI.`,

  dispensary: `They run one or more dispensary locations on Hybrid. The data below is
the state of their location pages: what is filled in, who their approved budtenders
are, any stashlists they feature, and any live deals. If pending_staff_requests is
above zero, that is somebody waiting on them and it is the most useful thing in the
email.`,
};

export const composeDigest = async (
  contact: Contact,
  digest: Record<string, unknown>,
): Promise<Composed> => {
  const task = `
Write a periodic update email from Hybrid.

${WHO(contact)}

${DIGEST_FRAMING[contact.segment as Segment]}

Rules for this email specifically:
- Use ONLY the JSON below. Every name, number and date must appear in it.
- If a section of the JSON is an empty array, that section does not exist. Do not
  mention it, do not apologise for it, do not say "no new X this time".
- Do not add a call to action that the data does not support.
- Under 200 words. Short paragraphs or a short list. No headers, no markdown.

Start your output with a line "Subject: ..." and then the body.`;

  return await generate(
    task,
    `Live Hybrid data for this recipient:\n\n${JSON.stringify(digest, null, 2)}`,
    "Your Hybrid update",
  );
};

// ─── Profile completion nudge ────────────────────────────────────────────────

export const composeNudge = async (
  contact: Contact,
  item: { field: string; label: string },
): Promise<Composed> => {
  const task = `
Write a very short email nudging someone to complete one part of their Hybrid profile.

${WHO(contact)}

The single missing item is: ${item.label}

Ask about that one item only. Do not list anything else that might be missing, and do
not imply their profile is bad. Say briefly what filling it in changes for them, and
where in the app to do it (Profile tab, then Edit Profile — for a shop's opening hours
or staff, that is the admin area for the location).

Under 90 words. No statistics.

Start your output with a line "Subject: ..." and then the body.`;

  return await generate(task, `Missing item: ${item.label} (${item.field})`, "One thing left on your Hybrid profile");
};

// ─── Reply answer ────────────────────────────────────────────────────────────

export const composeReplyAnswer = async (
  contact: Contact | null,
  question: string,
  knowledge: string,
): Promise<Composed> => {
  const task = `
Someone replied to a Hybrid onboarding email with a question about how the app works.
Answer it.

${contact ? WHO(contact) : "The sender is not a known contact — answer generally and claim nothing about their account."}

You may use ONLY the knowledge document below. It is the complete description of what
Hybrid does. If the answer is not in it — or if you are not sure — reply with exactly
the single word ESCALATE and nothing else. Do not guess, do not extrapolate from how
other apps work, and do not promise anything.

Never state a date, a price, a giveaway result, an account status, or a timeline.

Keep the answer under 120 words, plain and direct. No greeting beyond "Hi" and no
sign-off — the footer is added for you.

=== KNOWLEDGE DOCUMENT ===
${knowledge}
=== END KNOWLEDGE DOCUMENT ===

Start your output with a line "Subject: ..." and then the body.`;

  return await generate(task, `Their message:\n\n${question}`, "Re: your question");
};
