/**
 * Everything the agent reads and writes, in one place, over the service-role
 * client. The outreach tables have no grants to anon or authenticated, so this is
 * the only path to them.
 */

import { supabaseAdmin } from "../supabase.ts";
import type { Segment } from "./config.ts";

export type Contact = {
  id: number;
  public_id: string;
  email: string;
  name: string | null;
  segment: Segment;
  profile_id: number | null;
  consent_basis: string;
  source: string | null;
  status: string;
  stage: "welcome" | "sequence" | "updates";
  sequence_step: number;
  sends_count: number;
  sends_since_engagement: number;
  replies_count: number;
  last_sent_at: string | null;
  next_eligible_at: string;
  last_digest_at: string | null;
  last_nudge_field: string | null;
  gmail_thread_id: string | null;
};

export type LoggedMessage = {
  contact_id: number | null;
  email: string | null;
  direction: "outbound" | "inbound";
  message_type: string;
  subject?: string | null;
  body?: string | null;
  gmail_message_id?: string | null;
  gmail_thread_id?: string | null;
  status: "drafted" | "sent" | "received" | "failed" | "skipped";
  mode?: "draft" | "send" | null;
  classification?: string | null;
  needs_human?: boolean;
  error?: string | null;
};

export const isPaused = async (): Promise<boolean> => {
  const { data } = await supabaseAdmin
    .from("outreach_settings").select("is_paused").eq("id", 1).maybeSingle();
  return data?.is_paused === true;
};

/**
 * The one check that has no exceptions. Called immediately before every send and
 * every draft, not once at the top of a batch: a reply processed earlier in the
 * same run can add a suppression, and a contact selected before that must still
 * be stopped by it.
 */
export const isSuppressed = async (email: string): Promise<boolean> => {
  const { data } = await supabaseAdmin
    .from("outreach_suppressions").select("id").eq("email", email.trim().toLowerCase()).maybeSingle();
  return !!data;
};

export const suppress = async (
  email: string,
  reason: "unsubscribed" | "bounced" | "complained" | "manual",
  source: string,
  contactId?: number | null,
): Promise<void> => {
  await supabaseAdmin.from("outreach_suppressions").upsert(
    { email: email.trim().toLowerCase(), reason, source, contact_id: contactId ?? null },
    { onConflict: "email", ignoreDuplicates: true },
  );
};

export const logMessage = async (m: LoggedMessage): Promise<void> => {
  const { error } = await supabaseAdmin.from("outreach_messages").insert(m);
  // A duplicate inbound Gmail id is the poller seeing the same reply twice, which
  // is the unique index doing its job — not something to shout about.
  if (error && !String(error.message ?? "").includes("duplicate key")) {
    console.error("outreach_messages insert failed:", error.message);
  }
};

/** Outbound messages logged today, against DAILY_SEND_CAP. */
export const sentToday = async (): Promise<number> => {
  const startOfDay = new Date();
  startOfDay.setUTCHours(0, 0, 0, 0);
  const { count } = await supabaseAdmin
    .from("outreach_messages")
    .select("id", { count: "exact", head: true })
    .eq("direction", "outbound")
    .in("status", ["sent", "drafted"])
    .gte("created_at", startOfDay.toISOString());
  return count ?? 0;
};

/** Active contacts whose next_eligible_at has passed, oldest first. */
export const dueContacts = async (limit: number): Promise<Contact[]> => {
  const { data, error } = await supabaseAdmin
    .from("outreach_contacts")
    .select("*")
    .eq("status", "active")
    .lte("next_eligible_at", new Date().toISOString())
    .order("next_eligible_at", { ascending: true })
    .limit(limit);
  if (error) throw new Error(`dueContacts: ${error.message}`);
  return (data ?? []) as Contact[];
};

/**
 * Active contacts of one segment, regardless of whether they are due.
 *
 * Only for the dry-run preview. The scheduler must never use this: it would mail
 * people ahead of their cadence.
 */
export const activeContactsInSegment = async (segment: Segment, limit: number): Promise<Contact[]> => {
  const { data, error } = await supabaseAdmin
    .from("outreach_contacts")
    .select("*")
    .eq("status", "active")
    .eq("segment", segment)
    .order("id", { ascending: true })
    .limit(limit);
  if (error) throw new Error(`activeContactsInSegment: ${error.message}`);
  return (data ?? []) as Contact[];
};

export const contactByEmail = async (email: string): Promise<Contact | null> => {
  const { data } = await supabaseAdmin
    .from("outreach_contacts").select("*").eq("email", email.trim().toLowerCase()).maybeSingle();
  return (data as Contact) ?? null;
};

export const contactByPublicId = async (publicId: string): Promise<Contact | null> => {
  const { data } = await supabaseAdmin
    .from("outreach_contacts").select("*").eq("public_id", publicId).maybeSingle();
  return (data as Contact) ?? null;
};

export const contactByThread = async (threadId: string): Promise<Contact | null> => {
  const { data } = await supabaseAdmin
    .from("outreach_messages")
    .select("contact_id")
    .eq("gmail_thread_id", threadId)
    .not("contact_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data?.contact_id) return null;
  const { data: c } = await supabaseAdmin
    .from("outreach_contacts").select("*").eq("id", data.contact_id).maybeSingle();
  return (c as Contact) ?? null;
};

export const updateContact = async (id: number, patch: Record<string, unknown>): Promise<void> => {
  const { error } = await supabaseAdmin.from("outreach_contacts").update(patch).eq("id", id);
  if (error) console.error(`updateContact ${id}: ${error.message}`);
};

/** Any inbound reply is engagement: it resets the no-engagement counter. */
export const recordEngagement = async (contact: Contact): Promise<void> => {
  await updateContact(contact.id, {
    replies_count: contact.replies_count + 1,
    sends_since_engagement: 0,
  });
};

export const knowledgeDocument = async (): Promise<string> => {
  const { data } = await supabaseAdmin
    .from("outreach_knowledge")
    .select("title,body,sort_order")
    .eq("is_active", true)
    .order("sort_order", { ascending: true });
  return (data ?? []).map((s) => `## ${s.title}\n\n${s.body.trim()}`).join("\n\n");
};

/** Digest payload for a linked contact. Returns null for a prospect. */
export const digestFor = async (
  contact: Contact,
  windows: {
    giveawayAhead: number; giveawayBack: number;
    dropAhead: number; dropBack: number;
    newLocationDays: number; statsWindow: number; maxItems: number;
  },
): Promise<Record<string, unknown> | null> => {
  if (!contact.profile_id) return null;
  const rpc = {
    consumer: ["outreach_digest_consumer", {
      p_profile_id: contact.profile_id,
      p_giveaway_ahead: windows.giveawayAhead,
      p_giveaway_back: windows.giveawayBack,
      p_drop_ahead: windows.dropAhead,
      p_drop_back: windows.dropBack,
      p_new_loc_days: windows.newLocationDays,
      p_max: windows.maxItems,
    }],
    creator: ["outreach_digest_creator", {
      p_profile_id: contact.profile_id, p_window_days: windows.statsWindow, p_max: windows.maxItems,
    }],
    brand: ["outreach_digest_brand", {
      p_profile_id: contact.profile_id, p_window_days: windows.statsWindow, p_max: windows.maxItems,
    }],
    dispensary: ["outreach_digest_dispensary", {
      p_profile_id: contact.profile_id, p_max: windows.maxItems,
    }],
  }[contact.segment] as [string, Record<string, unknown>];

  const { data, error } = await supabaseAdmin.rpc(rpc[0], rpc[1]);
  if (error) { console.error(`digest ${contact.segment}: ${error.message}`); return null; }
  return data as Record<string, unknown>;
};

export const completenessFor = async (contact: Contact): Promise<Record<string, unknown> | null> => {
  if (!contact.profile_id) return null;
  const { data, error } = await supabaseAdmin.rpc("outreach_profile_completeness", {
    p_profile_id: contact.profile_id,
    p_segment: contact.segment,
  });
  if (error) { console.error(`completeness: ${error.message}`); return null; }
  return data as Record<string, unknown>;
};

/**
 * Does a digest payload contain anything worth an email?
 *
 * A prospect has no payload and never passes this — prospects get the welcome and
 * the sequence, then nothing, because there is no account to report on.
 */
export const hasSomethingToSay = (segment: Segment, digest: Record<string, any> | null): boolean => {
  if (!digest) return false;
  const nonEmpty = (k: string) => Array.isArray(digest[k]) && digest[k].length > 0;

  if (segment === "consumer") {
    return nonEmpty("giveaways") || nonEmpty("new_dispensaries") ||
           nonEmpty("drops") || nonEmpty("trending_lists");
  }
  if (segment === "creator") {
    return (digest.followers_gained ?? 0) > 0 || (digest.restashes_window ?? 0) > 0 ||
           (digest.posts_window ?? 0) > 0 || nonEmpty("top_posts") || nonEmpty("activity");
  }
  if (segment === "brand") {
    return (digest.stashes_window ?? 0) > 0 || (digest.posts_tagging_window ?? 0) > 0 ||
           nonEmpty("top_products") || nonEmpty("giveaways") || nonEmpty("activity");
  }
  // A dispensary's page state is worth reporting even when quiet, but only when
  // there is something on it or something waiting for them.
  return nonEmpty("locations") &&
         ((digest.pending_staff_requests ?? 0) > 0 || (digest.staff_count ?? 0) > 0 ||
          nonEmpty("active_deals") || nonEmpty("featured_stashlists") || nonEmpty("activity"));
};
