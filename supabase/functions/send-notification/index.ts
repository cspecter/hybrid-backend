/**
 * Send Notification
 * 
 * This Edge Function provides a simple API to send notifications.
 * It wraps the database `send_notification()` function for easier use
 * from the client apps.
 * 
 * Can be called for:
 * - Immediate notifications
 * - Scheduled notifications
 * - Batch notifications to multiple users
 */

import { supabaseAdmin, createSupabaseClient } from "../_shared/supabase.ts";
import { jsonResponse, errorResponse, handleCors } from "../_shared/cors.ts";

interface NotificationRequest {
  // Single notification
  recipientId?: string;
  recipientIds?: string[]; // For batch sending
  typeCode: string;
  actorId?: string;
  relatedType?: string;
  relatedId?: string;
  extraData?: Record<string, unknown>;
  
  // For scheduling
  scheduledFor?: string; // ISO timestamp
  idempotencyKey?: string;
}

Deno.serve(async (req: Request) => {
  // Handle CORS
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;
  
  try {
    // Get the current user
    const supabase = createSupabaseClient(req);
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    
    if (authError) {
      console.error("Auth error:", authError);
      return errorResponse("Authentication required", 401);
    }
    
    const body: NotificationRequest = await req.json();
    
    // Validate required fields
    if (!body.typeCode) {
      return errorResponse("typeCode is required", 400);
    }
    
    if (!body.recipientId && (!body.recipientIds || body.recipientIds.length === 0)) {
      return errorResponse("recipientId or recipientIds is required", 400);
    }
    
    const recipients = body.recipientIds || [body.recipientId!];
    const results: Array<{ recipientId: string; notificationId?: string; error?: string }> = [];
    
    // Use the current user as actor if not specified
    const actorId = body.actorId || user?.id;
    
    for (const recipientId of recipients) {
      try {
        if (body.scheduledFor) {
          // Schedule the notification
          const { data, error } = await supabaseAdmin.rpc("schedule_notification", {
            p_recipient_id: recipientId,
            p_type_code: body.typeCode,
            p_scheduled_for: body.scheduledFor,
            p_actor_id: actorId,
            p_related_type: body.relatedType,
            p_related_id: body.relatedId,
            p_extra_data: body.extraData || {},
            p_idempotency_key: body.idempotencyKey,
          });
          
          if (error) {
            results.push({ recipientId, error: error.message });
          } else {
            results.push({ recipientId, notificationId: data });
          }
        } else {
          // Send immediately
          const { data, error } = await supabaseAdmin.rpc("send_notification", {
            p_recipient_id: recipientId,
            p_type_code: body.typeCode,
            p_actor_id: actorId,
            p_related_type: body.relatedType,
            p_related_id: body.relatedId,
            p_extra_data: body.extraData || {},
          });
          
          if (error) {
            results.push({ recipientId, error: error.message });
          } else {
            results.push({ recipientId, notificationId: data });
          }
        }
      } catch (error) {
        results.push({ 
          recipientId, 
          error: error instanceof Error ? error.message : "Unknown error" 
        });
      }
    }
    
    const successCount = results.filter(r => !r.error).length;
    const failedCount = results.filter(r => r.error).length;
    
    return jsonResponse({
      success: failedCount === 0,
      sent: successCount,
      failed: failedCount,
      results: recipients.length > 1 ? results : undefined,
      notificationId: recipients.length === 1 ? results[0].notificationId : undefined,
    });
    
  } catch (error) {
    console.error("Error in send-notification:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});
