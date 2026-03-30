/**
 * Send Email
 * 
 * This Edge Function handles sending various transactional emails via Mailgun.
 * It supports multiple email types and can be called from the app or other functions.
 * 
 * Supported email types:
 * - brand_claim: When a user wants to claim a brand
 * - welcome: Welcome email for new users
 * - creator_approval: When a user is approved as a creator
 * - employee_added: When a user is added as an employee
 * - giveaway_winner: When a user wins a giveaway
 * - custom: Custom email with provided content
 */

import { supabaseAdmin, createSupabaseClient } from "../_shared/supabase.ts";
import {
  sendEmail,
  sendBrandClaimEmail,
  sendWelcomeEmail,
  sendCreatorApprovalEmail,
  sendEmployeeAddedEmail,
  sendGiveawayWinnerEmail,
} from "../_shared/mailgun.ts";
import { jsonResponse, errorResponse, handleCors } from "../_shared/cors.ts";

interface BrandClaimRequest {
  type: "brand_claim";
  userId: string;
  userEmail: string;
  userName: string;
  brandName: string;
  message?: string;
}

interface WelcomeRequest {
  type: "welcome";
  email: string;
  name: string;
}

interface CreatorApprovalRequest {
  type: "creator_approval";
  email: string;
  name: string;
}

interface EmployeeAddedRequest {
  type: "employee_added";
  email: string;
  name: string;
  locationName: string;
}

interface GiveawayWinnerRequest {
  type: "giveaway_winner";
  email: string;
  name: string;
  giveawayName: string;
  prizeName?: string;
}

interface CustomEmailRequest {
  type: "custom";
  to: string | string[];
  subject: string;
  text?: string;
  html?: string;
  from?: string;
  replyTo?: string;
  tags?: string[];
}

type EmailRequest =
  | BrandClaimRequest
  | WelcomeRequest
  | CreatorApprovalRequest
  | EmployeeAddedRequest
  | GiveawayWinnerRequest
  | CustomEmailRequest;

Deno.serve(async (req: Request) => {
  // Handle CORS
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;
  
  try {
    // Verify authorization for custom emails
    const authHeader = req.headers.get("Authorization");
    
    const body: EmailRequest = await req.json();
    
    if (!body.type) {
      return errorResponse("Missing email type", 400);
    }
    
    console.log(`Processing ${body.type} email request`);
    
    let result: { success: boolean; messageId?: string; error?: string };
    
    switch (body.type) {
      case "brand_claim": {
        const data = body as BrandClaimRequest;
        if (!data.userId || !data.userEmail || !data.userName || !data.brandName) {
          return errorResponse("Missing required fields for brand_claim", 400);
        }
        result = await sendBrandClaimEmail({
          userId: data.userId,
          userEmail: data.userEmail,
          userName: data.userName,
          brandName: data.brandName,
          message: data.message,
        });
        break;
      }
      
      case "welcome": {
        const data = body as WelcomeRequest;
        if (!data.email || !data.name) {
          return errorResponse("Missing required fields for welcome", 400);
        }
        result = await sendWelcomeEmail({
          email: data.email,
          name: data.name,
        });
        break;
      }
      
      case "creator_approval": {
        const data = body as CreatorApprovalRequest;
        if (!data.email || !data.name) {
          return errorResponse("Missing required fields for creator_approval", 400);
        }
        result = await sendCreatorApprovalEmail({
          email: data.email,
          name: data.name,
        });
        break;
      }
      
      case "employee_added": {
        const data = body as EmployeeAddedRequest;
        if (!data.email || !data.name || !data.locationName) {
          return errorResponse("Missing required fields for employee_added", 400);
        }
        result = await sendEmployeeAddedEmail({
          email: data.email,
          name: data.name,
          locationName: data.locationName,
        });
        break;
      }
      
      case "giveaway_winner": {
        const data = body as GiveawayWinnerRequest;
        if (!data.email || !data.name || !data.giveawayName) {
          return errorResponse("Missing required fields for giveaway_winner", 400);
        }
        result = await sendGiveawayWinnerEmail({
          email: data.email,
          name: data.name,
          giveawayName: data.giveawayName,
          prizeName: data.prizeName,
        });
        break;
      }
      
      case "custom": {
        // Custom emails require service role authentication
        if (!authHeader) {
          return errorResponse("Authorization required for custom emails", 401);
        }
        
        // Verify the request is from an admin
        const supabase = createSupabaseClient(req);
        const { data: { user }, error: authError } = await supabase.auth.getUser();
        
        if (authError || !user) {
          return errorResponse("Invalid authorization", 401);
        }
        
        // Check if user has admin role (optional - implement based on your needs)
        const { data: profile } = await supabaseAdmin
          .from("profiles")
          .select("role")
          .eq("id", user.id)
          .single();
        
        if (profile?.role !== "admin" && profile?.role !== "superadmin") {
          return errorResponse("Admin access required for custom emails", 403);
        }
        
        const data = body as CustomEmailRequest;
        if (!data.to || !data.subject || (!data.text && !data.html)) {
          return errorResponse("Missing required fields for custom email", 400);
        }
        
        result = await sendEmail({
          to: data.to,
          subject: data.subject,
          text: data.text,
          html: data.html,
          from: data.from,
          replyTo: data.replyTo,
          tags: data.tags,
        });
        break;
      }
      
      default:
        return errorResponse(`Unknown email type: ${(body as { type: string }).type}`, 400);
    }
    
    if (!result.success) {
      console.error(`Failed to send ${body.type} email:`, result.error);
      return errorResponse(result.error || "Failed to send email", 500);
    }
    
    console.log(`Successfully sent ${body.type} email`);
    
    return jsonResponse({
      success: true,
      messageId: result.messageId,
    });
    
  } catch (error) {
    console.error("Error in send-email:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});
