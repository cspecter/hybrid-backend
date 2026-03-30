/**
 * Cron Notifications
 * 
 * This Edge Function processes scheduled notifications.
 * It should be called via a cron job every 5 minutes.
 * 
 * The function calls the database function `process_scheduled_notifications()`
 * which handles all the notification scheduling logic.
 */

import { supabaseAdmin } from "../_shared/supabase.ts";
import { jsonResponse, errorResponse, handleCors } from "../_shared/cors.ts";

Deno.serve(async (req: Request) => {
  // Handle CORS
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;
  
  try {
    console.log("Starting scheduled notifications processing...");
    
    // Process scheduled notifications
    const { data: processedCount, error: processError } = await supabaseAdmin
      .rpc("process_scheduled_notifications");
    
    if (processError) {
      console.error("Error processing scheduled notifications:", processError);
      throw processError;
    }
    
    console.log(`Processed ${processedCount} scheduled notifications`);
    
    // Also clean up old expired notifications (older than 30 days)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const { error: cleanupError, count: deletedCount } = await supabaseAdmin
      .from("notifications")
      .delete({ count: "exact" })
      .lt("expires_at", thirtyDaysAgo.toISOString())
      .not("expires_at", "is", null);
    
    if (cleanupError) {
      console.warn("Error cleaning up expired notifications:", cleanupError);
      // Don't throw - this is a non-critical operation
    } else {
      console.log(`Cleaned up ${deletedCount} expired notifications`);
    }
    
    // Clean up old sent scheduled notifications (older than 7 days)
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    
    const { error: scheduledCleanupError, count: scheduledDeletedCount } = await supabaseAdmin
      .from("scheduled_notifications")
      .delete({ count: "exact" })
      .eq("status", "sent")
      .lt("sent_at", sevenDaysAgo.toISOString());
    
    if (scheduledCleanupError) {
      console.warn("Error cleaning up sent scheduled notifications:", scheduledCleanupError);
    } else {
      console.log(`Cleaned up ${scheduledDeletedCount} sent scheduled notifications`);
    }
    
    // Clean up old notification aggregates (older than 7 days with no activity)
    const { error: aggregateCleanupError, count: aggregateDeletedCount } = await supabaseAdmin
      .from("notification_aggregates")
      .delete({ count: "exact" })
      .lt("last_updated_at", sevenDaysAgo.toISOString());
    
    if (aggregateCleanupError) {
      console.warn("Error cleaning up old aggregates:", aggregateCleanupError);
    } else {
      console.log(`Cleaned up ${aggregateDeletedCount} old notification aggregates`);
    }
    
    return jsonResponse({
      success: true,
      processed: processedCount,
      cleanup: {
        expiredNotifications: deletedCount || 0,
        sentScheduled: scheduledDeletedCount || 0,
        oldAggregates: aggregateDeletedCount || 0,
      },
    });
    
  } catch (error) {
    console.error("Error in cron-notifications:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});
