/**
 * Notify User
 * 
 * A convenience function that handles common notification patterns:
 * - Sends in-app notification via send_notification()
 * - Optionally sends push notification
 * - Optionally sends email
 * 
 * Use this for common flows like:
 * - Creator approval (notification + email)
 * - Employee added (notification + email)
 * - Giveaway winner (notification + email)
 */

import { supabaseAdmin } from "../_shared/supabase.ts";
import {
  sendCreatorApprovalEmail,
  sendEmployeeAddedEmail,
  sendGiveawayWinnerEmail,
} from "../_shared/mailgun.ts";
import { jsonResponse, errorResponse, handleCors } from "../_shared/cors.ts";

type NotifyAction =
  | "creator_approved"
  | "employee_added"
  | "employee_request"
  | "giveaway_winner"
  | "brand_notification";

interface NotifyRequest {
  action: NotifyAction;
  profileId: string; // The user to notify
  
  // For employee actions
  locationId?: string;
  locationName?: string;
  role?: string;
  
  // For giveaway winner
  giveawayId?: string;
  giveawayName?: string;
  prizeName?: string;
  
  // For brand notification
  brandUserId?: string;
  dispensaryName?: string;
  
  // Optional: skip certain channels
  skipEmail?: boolean;
  skipPush?: boolean;
  skipInApp?: boolean;
}

Deno.serve(async (req: Request) => {
  // Handle CORS
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;
  
  try {
    const body: NotifyRequest = await req.json();
    
    if (!body.action || !body.profileId) {
      return errorResponse("action and profileId are required", 400);
    }
    
    // Get the user's profile for email
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("id, email, display_name, username")
      .eq("id", body.profileId)
      .single();
    
    if (profileError || !profile) {
      return errorResponse("User not found", 404);
    }
    
    const userName = profile.display_name || profile.username || "User";
    const results: { inApp?: string; email?: boolean; error?: string } = {};
    
    switch (body.action) {
      case "creator_approved": {
        // Send in-app notification
        if (!body.skipInApp) {
          const { data, error } = await supabaseAdmin.rpc("send_notification", {
            p_recipient_id: body.profileId,
            p_type_code: "upgraded_to_creator",
          });
          if (error) {
            results.error = error.message;
          } else {
            results.inApp = data;
          }
        }
        
        // Send email
        if (!body.skipEmail && profile.email) {
          const emailResult = await sendCreatorApprovalEmail({
            email: profile.email,
            name: userName,
          });
          results.email = emailResult.success;
        }
        break;
      }
      
      case "employee_added": {
        if (!body.locationName) {
          return errorResponse("locationName is required for employee_added", 400);
        }
        
        // Send in-app notification
        if (!body.skipInApp) {
          const { data, error } = await supabaseAdmin.rpc("send_notification", {
            p_recipient_id: body.profileId,
            p_type_code: "employee_approved",
            p_related_type: "location",
            p_related_id: body.locationId,
            p_extra_data: {
              location_name: body.locationName,
              role: body.role || "budtender",
            },
          });
          if (error) {
            results.error = error.message;
          } else {
            results.inApp = data;
          }
        }
        
        // Send email
        if (!body.skipEmail && profile.email) {
          const emailResult = await sendEmployeeAddedEmail({
            email: profile.email,
            name: userName,
            locationName: body.locationName,
          });
          results.email = emailResult.success;
        }
        break;
      }
      
      case "employee_request": {
        if (!body.brandUserId || !body.dispensaryName) {
          return errorResponse("brandUserId and dispensaryName are required", 400);
        }
        
        // Send notification to the brand owner
        if (!body.skipInApp) {
          const { data, error } = await supabaseAdmin.rpc("send_notification", {
            p_recipient_id: body.brandUserId,
            p_type_code: "employee_request",
            p_actor_id: body.profileId,
            p_related_type: "location",
            p_related_id: body.locationId,
            p_extra_data: {
              location_name: body.dispensaryName,
            },
          });
          if (error) {
            results.error = error.message;
          } else {
            results.inApp = data;
          }
        }
        break;
      }
      
      case "giveaway_winner": {
        if (!body.giveawayId || !body.giveawayName) {
          return errorResponse("giveawayId and giveawayName are required", 400);
        }
        
        // Send in-app notification
        if (!body.skipInApp) {
          const { data, error } = await supabaseAdmin.rpc("send_notification", {
            p_recipient_id: body.profileId,
            p_type_code: "giveaway_won",
            p_related_type: "giveaway",
            p_related_id: body.giveawayId,
            p_extra_data: {
              giveaway_name: body.giveawayName,
              prize_name: body.prizeName,
            },
          });
          if (error) {
            results.error = error.message;
          } else {
            results.inApp = data;
          }
        }
        
        // Send email
        if (!body.skipEmail && profile.email) {
          const emailResult = await sendGiveawayWinnerEmail({
            email: profile.email,
            name: userName,
            giveawayName: body.giveawayName,
            prizeName: body.prizeName,
          });
          results.email = emailResult.success;
        }
        break;
      }
      
      case "brand_notification": {
        if (!body.brandUserId || !body.dispensaryName) {
          return errorResponse("brandUserId and dispensaryName are required", 400);
        }
        
        // Send notification to brand owner
        if (!body.skipInApp) {
          const { data, error } = await supabaseAdmin.rpc("send_notification", {
            p_recipient_id: body.brandUserId,
            p_type_code: "employee_request",
            p_actor_id: body.profileId,
            p_extra_data: {
              message: `A new employee is requesting to join your dispensary: ${body.dispensaryName}`,
            },
          });
          if (error) {
            results.error = error.message;
          } else {
            results.inApp = data;
          }
        }
        break;
      }
      
      default:
        return errorResponse(`Unknown action: ${body.action}`, 400);
    }
    
    return jsonResponse({
      success: !results.error,
      ...results,
    });
    
  } catch (error) {
    console.error("Error in notify-user:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});
