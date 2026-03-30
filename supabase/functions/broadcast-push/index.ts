import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createSupabaseClient, supabaseAdmin } from "../_shared/supabase.ts";
import { sendPushToSegment } from "../_shared/onesignal.ts";
import { jsonResponse, errorResponse, handleCors } from "../_shared/cors.ts";

interface BroadcastPayload {
  title: string;
  body: string;
}

serve(async (req: Request) => {
  // Handle CORS
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    // 1. Authenticate User
    const supabase = createSupabaseClient(req);
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
      return errorResponse("Unauthorized", 401);
    }

    // 2. Check Super Admin Status
    // We check the 'super_admins' table for the user's ID
    const { count, error: adminError } = await supabaseAdmin
      .from("super_admins")
      .select("*", { count: "exact", head: true })
      .eq("auth_id", user.id);

    if (adminError) {
        console.error("Error checking super admin status:", adminError);
        return errorResponse("Server error checking permissions", 500);
    }

    if (!count || count === 0) {
      return errorResponse("Forbidden: Super Admin access required", 403);
    }

    // 3. Parse Payload
    const { title, body } = await req.json() as BroadcastPayload;

    if (!title || !body) {
      return errorResponse("Missing title or body", 400);
    }

    // 4. Send Broadcast
    const result = await sendPushToSegment(
      "Subscribed Users", // Standard OneSignal segment for "All Users"
      title,
      body
    );

    if (!result.success) {
      return errorResponse(`OneSignal Error: ${result.error}`, 500);
    }

    return jsonResponse({
      success: true,
      messageId: result.messageId,
      message: "Broadcast sent successfully"
    });

  } catch (error) {
    console.error("Error in broadcast-push:", error);
    return errorResponse(
      error instanceof Error ? error.message : "Unknown error occurred"
    );
  }
});
