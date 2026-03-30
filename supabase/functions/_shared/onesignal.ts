// OneSignal Configuration
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID")!;
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

// OneSignal API base URL
const ONESIGNAL_API_BASE = "https://onesignal.com/api/v1";

export interface PushNotificationPayload {
  title: string;
  body: string;
  sound?: string;
  badge?: number;
  data?: Record<string, unknown>;
}

export interface PushTarget {
  externalUserIds?: string[];  // OneSignal external user IDs (profile IDs)
  playerIds?: string[];        // OneSignal player IDs (subscription IDs)
  segments?: string[];         // OneSignal segments
}

interface OneSignalNotification {
  app_id: string;
  contents: { en: string };
  headings: { en: string };
  include_aliases?: { external_id: string[] };
  include_subscription_ids?: string[];
  included_segments?: string[];
  target_channel?: string;
  name?: string;
  app_url?: string;
  ios_sound?: string;
  android_sound?: string;
  ios_badgeType?: string;
  ios_badgeCount?: number;
  data?: Record<string, unknown>;
  ttl?: number;
}

/**
 * Send push notification via OneSignal REST API
 */
export async function sendPushNotification(
  payload: PushNotificationPayload,
  target: PushTarget,
  options?: {
    name?: string;
    appUrl?: string;
    ttl?: number;
  }
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  try {
    const notification: OneSignalNotification = {
      app_id: ONESIGNAL_APP_ID,
      contents: { en: payload.body },
      headings: { en: payload.title },
    };
    
    // Set targeting using new API format
    if (target.externalUserIds && target.externalUserIds.length > 0) {
      // Use the new include_aliases format for external user IDs
      notification.include_aliases = { external_id: target.externalUserIds };
      notification.target_channel = "push";
    } else if (target.playerIds && target.playerIds.length > 0) {
      // Use include_subscription_ids for player IDs (new name)
      notification.include_subscription_ids = target.playerIds;
    } else if (target.segments && target.segments.length > 0) {
      notification.included_segments = target.segments;
    } else {
      // Fallback: send to all subscribed users
      notification.included_segments = ["Subscribed Users"];
    }
    
    // Optional settings
    if (options?.name) {
      notification.name = options.name;
    }
    
    if (options?.appUrl) {
      notification.app_url = options.appUrl;
    } else {
      notification.app_url = "hybridlink://co.gethybrid.hybridapp/home";
    }
    
    if (payload.sound) {
      notification.ios_sound = payload.sound;
      notification.android_sound = payload.sound;
    }
    
    if (payload.badge !== undefined) {
      notification.ios_badgeType = "SetTo";
      notification.ios_badgeCount = payload.badge;
    }
    
    if (payload.data) {
      notification.data = payload.data;
    }
    
    if (options?.ttl) {
      notification.ttl = options.ttl;
    }
    
    console.log("Sending push notification:", JSON.stringify(notification, null, 2));
    
    const response = await fetch(`${ONESIGNAL_API_BASE}/notifications`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify(notification),
    });
    
    const result = await response.json();
    
    if (!response.ok) {
      console.error("OneSignal error response:", result);
      return {
        success: false,
        error: result.errors?.[0] || `OneSignal API error: ${response.status}`,
      };
    }
    
    console.log("OneSignal response:", result);
    
    return {
      success: true,
      messageId: result.id,
    };
  } catch (error) {
    console.error("Error sending push notification:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Send batch push notifications (up to 2000 per request)
 */
export async function sendBatchPushNotifications(
  notifications: Array<{
    payload: PushNotificationPayload;
    externalUserId: string;
  }>
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  if (notifications.length === 0) {
    return { success: true };
  }
  
  if (notifications.length > 2000) {
    throw new Error("OneSignal limit is 2000 notifications per batch");
  }
  
  // Group by same payload to minimize API calls
  const payloadGroups = new Map<string, string[]>();
  
  for (const n of notifications) {
    const key = JSON.stringify(n.payload);
    const existing = payloadGroups.get(key) || [];
    existing.push(n.externalUserId);
    payloadGroups.set(key, existing);
  }
  
  let lastMessageId: string | undefined;
  let hasErrors = false;
  
  for (const [payloadJson, userIds] of payloadGroups) {
    const payload = JSON.parse(payloadJson) as PushNotificationPayload;
    
    const result = await sendPushNotification(payload, {
      externalUserIds: userIds,
    });
    
    if (!result.success) {
      console.error(`Failed to send batch to ${userIds.length} users:`, result.error);
      hasErrors = true;
    } else {
      lastMessageId = result.messageId;
    }
  }
  
  return { 
    success: !hasErrors, 
    messageId: lastMessageId,
    error: hasErrors ? "Some notifications failed to send" : undefined,
  };
}

/**
 * Send push notification to a single user by their profile ID
 */
export async function sendPushToUser(
  profileId: string,
  title: string,
  body: string,
  data?: Record<string, unknown>,
  options?: {
    sound?: string;
    badge?: number;
    appUrl?: string;
  }
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  return await sendPushNotification(
    {
      title,
      body,
      sound: options?.sound,
      badge: options?.badge,
      data,
    },
    {
      externalUserIds: [profileId],
    },
    {
      appUrl: options?.appUrl,
    }
  );
}

/**
 * Send push notification to multiple users by their profile IDs
 */
export async function sendPushToUsers(
  profileIds: string[],
  title: string,
  body: string,
  data?: Record<string, unknown>,
  options?: {
    sound?: string;
    badge?: number;
    appUrl?: string;
  }
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  if (profileIds.length === 0) {
    return { success: true };
  }
  
  return await sendPushNotification(
    {
      title,
      body,
      sound: options?.sound,
      badge: options?.badge,
      data,
    },
    {
      externalUserIds: profileIds,
    },
    {
      appUrl: options?.appUrl,
    }
  );
}

/**
 * Send push notification to a segment
 */
export async function sendPushToSegment(
  segment: string,
  title: string,
  body: string,
  data?: Record<string, unknown>,
  options?: {
    sound?: string;
    appUrl?: string;
  }
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  return await sendPushNotification(
    {
      title,
      body,
      sound: options?.sound,
      data,
    },
    {
      segments: [segment],
    },
    {
      appUrl: options?.appUrl,
    }
  );
}
