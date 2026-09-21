/**
 * Outreach agent configuration.
 *
 * Every interval, cap, window and switch the agent obeys is in this file. Nothing
 * below is read from the database, so changing behaviour is an edit here and a
 * redeploy — deliberately, because these are the settings that decide whether real
 * mail goes to real people, and they should move through review.
 *
 * NO CREDENTIALS HERE. The Anthropic key, the Gmail OAuth client id and secret and
 * the Gmail refresh token are read from Deno.env inside gmail.ts and anthropic.ts,
 * and are set as Supabase function secrets. See docs/OUTREACH-AGENT.md.
 */

// ─── Mode ────────────────────────────────────────────────────────────────────

/**
 * "draft" writes every outbound message into the Gmail Drafts folder and logs it.
 * "send" actually sends. Replies are handled in the same mode: in draft mode the
 * agent drafts its answer and labels the thread, and never sends.
 */
export const MODE: "draft" | "send" = "draft";

/**
 * When non-empty, every send AND every draft is restricted to these addresses,
 * whatever MODE says. This is the safety catch for running the pipeline against
 * your own inbox first.
 *
 * >>> PLACEHOLDER — replace with your own address before the first run, and empty
 * >>> the array to let the agent reach real contacts. While it contains an address
 * >>> that nobody owns, the agent will skip every contact and log why.
 */
export const TEST_RECIPIENTS: string[] = ["REPLACE-ME@example.com"];

// ─── Model ───────────────────────────────────────────────────────────────────

/** The one place the model string lives. */
export const MODEL = "claude-sonnet-5";
export const MAX_TOKENS = 1500;

// ─── Sender identity ─────────────────────────────────────────────────────────

/**
 * Honest identity: an assistant, not a person. Do not put a human's name here.
 */
export const SENDER_NAME = "Hybrid Onboarding Assistant";

/**
 * CAN-SPAM requires a physical postal address in every commercial email.
 *
 * >>> PLACEHOLDER — replace with Hybrid's real mailing address. The agent will not
 * >>> send or draft anything while this still says PLACEHOLDER, because an email
 * >>> without a real address is not one we are allowed to send.
 */
export const PHYSICAL_MAILING_ADDRESS =
  "PLACEHOLDER — Hybrid, [street], [city], [state] [zip], USA";

/**
 * Where the unsubscribe link points. The outreach-unsubscribe function is public
 * (no JWT) and lives at <project>/functions/v1/outreach-unsubscribe.
 */
export const UNSUBSCRIBE_BASE_URL =
  `${Deno.env.get("SUPABASE_URL") ?? ""}/functions/v1/outreach-unsubscribe`;

// ─── Cadence ─────────────────────────────────────────────────────────────────

/** Days between the welcome and the first tip, and between tips after that. */
export const SEQUENCE_INTERVAL_DAYS = 3;

/** How many getting-started tips follow the welcome. */
export const SEQUENCE_LENGTH = 4;

/** Days between periodic updates once the sequence is finished. */
export const DIGEST_INTERVAL_DAYS = 14;

/** Minimum days between two profile-completion nudges to the same person. */
export const NUDGE_INTERVAL_DAYS = 7;

/**
 * Stop condition. After this many consecutive sends with no reply, the contact is
 * marked 'no_engagement' and nothing further is sent. Any inbound reply resets it.
 */
export const MAX_SENDS_WITHOUT_ENGAGEMENT = 6;

// ─── Throughput ──────────────────────────────────────────────────────────────

/**
 * Gmail's published limit is 500 recipients/day on a consumer account and 2,000 on
 * Workspace. This sits well under the lower of the two; raise it only after you
 * know which kind of mailbox this is.
 */
export const DAILY_SEND_CAP = 300;

/**
 * Sends per cron tick. With a 15-minute schedule inside the sending window this
 * spreads the daily allowance across the day instead of firing it in one burst.
 */
export const MAX_SENDS_PER_TICK = 8;

/** Local hours (SEND_TIMEZONE) between which the agent will send or draft. */
export const SEND_WINDOW_START_HOUR = 9;
export const SEND_WINDOW_END_HOUR = 18;
export const SEND_TIMEZONE = "America/New_York";

/** Skip Saturday and Sunday. */
export const SEND_WEEKDAYS_ONLY = true;

// ─── Content windows ─────────────────────────────────────────────────────────
//
// How far the digest builders look for something worth saying. A digest with no
// sections is not sent, so these decide how often a contact hears anything at all.

export const GIVEAWAY_LOOKAHEAD_DAYS = 30;
/** Recently finished giveaways still count: the result is news. */
export const GIVEAWAY_LOOKBACK_DAYS = 14;
export const DROP_LOOKAHEAD_DAYS = 30;
export const DROP_LOOKBACK_DAYS = 14;
export const NEW_LOCATION_DAYS = 90;
// No constant for trending stashlists: they are ranked by total subscribers,
// because nothing records when a subscription happened, so there is no window to
// set. See the note in outreach_digest_consumer.
/** Window for a creator's or brand's own numbers. */
export const STATS_WINDOW_DAYS = 30;
/** Most items of any one kind in a digest. */
export const MAX_ITEMS_PER_SECTION = 5;

// ─── Replies ─────────────────────────────────────────────────────────────────

/** How far back the reply poller looks on each pass. */
export const REPLY_POLL_LOOKBACK_HOURS = 48;
export const MAX_REPLIES_PER_TICK = 20;

/** Gmail labels. Created on first use if missing. */
export const GMAIL_LABEL_NEEDS_HUMAN = "Hybrid/Needs human";
export const GMAIL_LABEL_HANDLED = "Hybrid/Answered by agent";
export const GMAIL_LABEL_UNSUBSCRIBED = "Hybrid/Unsubscribed";

// ─── Segments ────────────────────────────────────────────────────────────────

export type Segment = "consumer" | "creator" | "brand" | "dispensary";
export const SEGMENTS: Segment[] = ["consumer", "creator", "brand", "dispensary"];

/**
 * The getting-started tips, per segment. The agent writes the prose; these are the
 * subjects it is writing about, in order. SEQUENCE_LENGTH entries each.
 */
export const SEQUENCE_TOPICS: Record<Segment, string[]> = {
  consumer: [
    "Stashing products, and what the Stash tab is for",
    "Building a stashlist and why other people subscribe to them",
    "Following brands and shops so the Home feed fills up",
    "Finding giveaways and deals in Explore, and the Near Me map",
  ],
  creator: [
    "Stashlists as your main format, and how to build one worth subscribing to",
    "Tagging products in a post so the stash is attributed to you",
    "Restashes: what they measure and why they matter more than followers",
    "Reading your own numbers on your profile",
  ],
  brand: [
    "Claiming your brand profile and who can administer it",
    "Getting your products tagged in posts",
    "Running a giveaway, and what the results tell you",
    "Where your products show up: stashes, stashlists and posts",
  ],
  dispensary: [
    "Your location page: address, hours, features",
    "Adding budtenders, and how they request to be added themselves",
    "Featuring stashlists on your page",
    "Running deals, redemption codes and your store's master code",
  ],
};
