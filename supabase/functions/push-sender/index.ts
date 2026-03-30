/**
 * Push Sender
 * 
 * This Edge Function processes the push notification queue and sends
 * batches to OneSignal. It should be called via a cron job every 1-5 minutes.
 * 
 * The function:
 * 1. Creates a batch of pending push notifications (up to 2000)
 * 2. Sends them to OneSignal
 * 3. Updates the queue status
 */

import { supabaseAdmin } from "../_shared/supabase.ts";
import { sendPushNotification, PushNotificationPayload } from "../_shared/onesignal.ts";
import { jsonResponse, errorResponse, handleCors } from "../_shared/cors.ts";

// Maximum notifications to process per batch
const MAX_BATCH_SIZE = 2000;
// Maximum number of push notifications per user in a 5-minute window
const MAX_PER_USER_WINDOW = 9;

interface PushQueueItem {
  id: string;
  notification_id: string;
  push_token_id: string;
  payload: PushNotificationPayload & { data?: Record<string, unknown> };
  priority: number;
  status: string;
  batch_id: string | null;
  created_at: string;
  profile_id: string;
}

interface PushToken {
  id: string;
  profile_id: string;
  token: string;
  platform: string;
  is_active: boolean;
}

Deno.serve(async (req: Request) => {
  // Handle CORS
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;
  
  try {
    console.log("Starting push notification processing...");
    
    // Create a new batch
    const { data: batchId, error: batchError } = await supabaseAdmin
      .rpc("create_push_batch", { p_max_messages: MAX_BATCH_SIZE });
    
    if (batchError) {
      console.error("Error creating batch:", batchError);
      throw batchError;
    }
    
    if (!batchId) {
      console.log("No pending push notifications to send");
      return jsonResponse({
        success: true,
        message: "No pending notifications",
        sent: 0,
      });
    }
    
    console.log(`Created batch ${batchId}`);
    
    // Get all notifications in this batch with their tokens
    const { data: queueItems, error: queueError } = await supabaseAdmin
      .from("push_queue")
      .select(`
        id,
        notification_id,
        push_token_id,
        payload,
        priority,
        status,
        batch_id,
        created_at,
        push_tokens!inner (
          id,
          profile_id,
          token,
          platform,
          is_active
        )
      `)
      .eq("batch_id", batchId);
    
    if (queueError) {
      console.error("Error fetching queue items:", queueError);
      throw queueError;
    }
    
    if (!queueItems || queueItems.length === 0) {
      console.log("No queue items found for batch");
      return jsonResponse({
        success: true,
        message: "No queue items in batch",
        sent: 0,
      });
    }
    
    console.log(`Processing ${queueItems.length} push notifications`);
    
    // Track sends per user to avoid spam
    const userSendCounts: Record<string, number> = {};
    const successIds: string[] = [];
    const failedIds: string[] = [];
    const skippedIds: string[] = [];
    
    // Group notifications by user for efficient sending
    const notificationsByUser = new Map<string, Array<{ queueItem: typeof queueItems[0]; token: PushToken }>>();
    
    for (const item of queueItems) {
      const token = (item as unknown as { push_tokens: PushToken }).push_tokens;
      if (!token || !token.is_active) {
        skippedIds.push(item.id);
        continue;
      }
      
      const profileId = token.profile_id;
      if (!notificationsByUser.has(profileId)) {
        notificationsByUser.set(profileId, []);
      }
      notificationsByUser.get(profileId)!.push({ queueItem: item, token });
    }
    
    // Process each user's notifications
    for (const [profileId, items] of notificationsByUser) {
      const currentCount = userSendCounts[profileId] || 0;
      
      for (const { queueItem } of items) {
        // Check rate limit per user
        if (currentCount >= MAX_PER_USER_WINDOW) {
          console.log(`Skipping notification for user ${profileId} - rate limit reached`);
          skippedIds.push(queueItem.id);
          continue;
        }
        
        try {
          const payload = queueItem.payload as PushNotificationPayload;
          
          // Send to OneSignal using external_user_id (profile_id)
          const result = await sendPushNotification(
            {
              title: payload.title,
              body: payload.body,
              sound: payload.sound,
              badge: payload.badge,
              data: payload.data,
            },
            {
              externalUserIds: [profileId],
            },
            {
              name: `batch-${batchId}-${queueItem.id}`,
              appUrl: (payload.data?.action_url as string) || undefined,
            }
          );
          
          if (result.success) {
            successIds.push(queueItem.id);
            userSendCounts[profileId] = (userSendCounts[profileId] || 0) + 1;
          } else {
            console.error(`Failed to send to ${profileId}:`, result.error);
            failedIds.push(queueItem.id);
          }
        } catch (error) {
          console.error(`Error sending to ${profileId}:`, error);
          failedIds.push(queueItem.id);
        }
      }
    }
    
    // Update queue item statuses
    if (successIds.length > 0) {
      const { error: updateSuccessError } = await supabaseAdmin
        .from("push_queue")
        .update({ status: "sent", sent_at: new Date().toISOString() })
        .in("id", successIds);
      
      if (updateSuccessError) {
        console.error("Error updating successful items:", updateSuccessError);
      }
    }
    
    if (failedIds.length > 0) {
      const { error: updateFailedError } = await supabaseAdmin
        .from("push_queue")
        .update({ 
          status: "failed",
          retry_count: supabaseAdmin.rpc("increment", { x: 1 }),
          retry_after: new Date(Date.now() + 5 * 60 * 1000).toISOString(), // Retry in 5 min
        })
        .in("id", failedIds);
      
      if (updateFailedError) {
        console.error("Error updating failed items:", updateFailedError);
      }
    }
    
    if (skippedIds.length > 0) {
      const { error: updateSkippedError } = await supabaseAdmin
        .from("push_queue")
        .update({ 
          status: "skipped",
          retry_after: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
        })
        .in("id", skippedIds);
      
      if (updateSkippedError) {
        console.error("Error updating skipped items:", updateSkippedError);
      }
    }
    
    // Update batch status
    const batchStatus = failedIds.length === queueItems.length 
      ? "failed" 
      : failedIds.length > 0 
        ? "partial" 
        : "sent";
    
    const { error: batchUpdateError } = await supabaseAdmin
      .from("push_batches")
      .update({
        status: batchStatus,
        sent_count: successIds.length,
        failed_count: failedIds.length,
        completed_at: new Date().toISOString(),
      })
      .eq("id", batchId);
    
    if (batchUpdateError) {
      console.error("Error updating batch:", batchUpdateError);
    }
    
    console.log(`Batch complete: ${successIds.length} sent, ${failedIds.length} failed, ${skippedIds.length} skipped`);
    
    return jsonResponse({
      success: true,
      batchId,
      sent: successIds.length,
      failed: failedIds.length,
      skipped: skippedIds.length,
    });
    
  } catch (error) {
    console.error("Error in push-sender:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});
