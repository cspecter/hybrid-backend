// Mailgun Configuration
const MAILGUN_DOMAIN = Deno.env.get("MAILGUN_DOMAIN")!;
const MAILGUN_API_KEY = Deno.env.get("MAILGUN_API_KEY")!;
const MAILGUN_FROM_EMAIL = Deno.env.get("MAILGUN_FROM_EMAIL") || "info@gethybrid.co";
const MAILGUN_FROM_NAME = Deno.env.get("MAILGUN_FROM_NAME") || "Hybrid";

// Mailgun API base URL
const MAILGUN_API_BASE = "https://api.mailgun.net/v3";

export interface EmailOptions {
  to: string | string[];
  subject: string;
  text?: string;
  html?: string;
  from?: string;
  replyTo?: string;
  cc?: string[];
  bcc?: string[];
  tags?: string[];
}

/**
 * Send an email via Mailgun REST API
 */
export async function sendEmail(options: EmailOptions): Promise<{ success: boolean; messageId?: string; error?: string }> {
  try {
    const recipients = Array.isArray(options.to) ? options.to : [options.to];
    
    const formData = new FormData();
    formData.append("from", options.from || `${MAILGUN_FROM_NAME} <${MAILGUN_FROM_EMAIL}>`);
    formData.append("subject", options.subject);
    
    // Add recipients
    for (const recipient of recipients) {
      formData.append("to", recipient);
    }
    
    if (options.text) {
      formData.append("text", options.text);
    }
    
    if (options.html) {
      formData.append("html", options.html);
    }
    
    if (options.replyTo) {
      formData.append("h:Reply-To", options.replyTo);
    }
    
    if (options.cc) {
      for (const cc of options.cc) {
        formData.append("cc", cc);
      }
    }
    
    if (options.bcc) {
      for (const bcc of options.bcc) {
        formData.append("bcc", bcc);
      }
    }
    
    if (options.tags) {
      for (const tag of options.tags) {
        formData.append("o:tag", tag);
      }
    }
    
    const response = await fetch(`${MAILGUN_API_BASE}/${MAILGUN_DOMAIN}/messages`, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${btoa(`api:${MAILGUN_API_KEY}`)}`,
      },
      body: formData,
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      console.error("Mailgun error response:", errorText);
      return {
        success: false,
        error: `Mailgun API error: ${response.status} - ${errorText}`,
      };
    }
    
    const result = await response.json();
    console.log("Email sent successfully:", result);
    
    return {
      success: true,
      messageId: result.id,
    };
  } catch (error) {
    console.error("Error sending email:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

// ============================================================================
// EMAIL TEMPLATES
// ============================================================================

export interface BrandClaimEmailData {
  userId: string;
  userEmail: string;
  userName: string;
  brandName: string;
  message?: string;
}

export async function sendBrandClaimEmail(data: BrandClaimEmailData): Promise<{ success: boolean; error?: string }> {
  return await sendEmail({
    to: ["nadir@gethybrid.co", "raskin@gethybrid.co", "chad@gethybrid.co"],
    subject: `🆙 ${data.userName} is claiming ${data.brandName}`,
    text: `${data.userName} (id: ${data.userId}, email: ${data.userEmail}) would like to claim ${data.brandName}.${data.message ? `\n\nMessage: ${data.message}` : ""}`,
    tags: ["brand-claim"],
  });
}

export interface WelcomeEmailData {
  email: string;
  name: string;
}

export async function sendWelcomeEmail(data: WelcomeEmailData): Promise<{ success: boolean; error?: string }> {
  return await sendEmail({
    to: data.email,
    subject: "Welcome to Hybrid! 🌿",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #10B981;">Welcome to Hybrid, ${data.name}!</h1>
        <p>We're excited to have you join our community.</p>
        <p>Here's what you can do:</p>
        <ul>
          <li>🔍 Discover new products</li>
          <li>📝 Create and share lists</li>
          <li>🎁 Enter giveaways</li>
          <li>👥 Follow creators and brands</li>
        </ul>
        <p style="margin-top: 30px;">
          <a href="https://app.gethybrid.co" style="background-color: #10B981; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
            Get Started
          </a>
        </p>
        <p style="color: #666; font-size: 12px; margin-top: 40px;">
          If you have any questions, reply to this email or contact us at support@gethybrid.co
        </p>
      </div>
    `,
    text: `Welcome to Hybrid, ${data.name}! We're excited to have you join our community.`,
    tags: ["welcome"],
  });
}

export interface CreatorApprovalEmailData {
  email: string;
  name: string;
}

export async function sendCreatorApprovalEmail(data: CreatorApprovalEmailData): Promise<{ success: boolean; error?: string }> {
  return await sendEmail({
    to: data.email,
    subject: "🌟 You're Now a Creator on Hybrid!",
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #10B981;">Congratulations, ${data.name}!</h1>
        <p>You've been approved as a Creator on Hybrid.</p>
        <p>As a Creator, you can now:</p>
        <ul>
          <li>✨ Get verified badges</li>
          <li>📊 Access analytics</li>
          <li>🎁 Host giveaways</li>
          <li>💼 Create deals</li>
        </ul>
        <p style="margin-top: 30px;">
          <a href="https://app.gethybrid.co/settings/creator" style="background-color: #10B981; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
            Explore Creator Tools
          </a>
        </p>
      </div>
    `,
    text: `Congratulations, ${data.name}! You've been approved as a Creator on Hybrid.`,
    tags: ["creator-approval"],
  });
}

export interface EmployeeAddedEmailData {
  email: string;
  name: string;
  locationName: string;
}

export async function sendEmployeeAddedEmail(data: EmployeeAddedEmailData): Promise<{ success: boolean; error?: string }> {
  return await sendEmail({
    to: data.email,
    subject: `🔖 You've been added to ${data.locationName}!`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #10B981;">Welcome to ${data.locationName}!</h1>
        <p>Hi ${data.name},</p>
        <p>You've been added as a budtender at ${data.locationName}.</p>
        <p>You can now:</p>
        <ul>
          <li>🏷️ Manage product listings</li>
          <li>📋 Update inventory</li>
          <li>👤 Represent your location on Hybrid</li>
        </ul>
        <p style="margin-top: 30px;">
          <a href="https://app.gethybrid.co" style="background-color: #10B981; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
            Open Hybrid
          </a>
        </p>
      </div>
    `,
    text: `Hi ${data.name}, you've been added as a budtender at ${data.locationName}.`,
    tags: ["employee-added"],
  });
}

export interface GiveawayWinnerEmailData {
  email: string;
  name: string;
  giveawayName: string;
  prizeName?: string;
}

export async function sendGiveawayWinnerEmail(data: GiveawayWinnerEmailData): Promise<{ success: boolean; error?: string }> {
  return await sendEmail({
    to: data.email,
    subject: `🎉 Congratulations! You won ${data.giveawayName}!`,
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #10B981;">🎊 You're a Winner!</h1>
        <p>Hi ${data.name},</p>
        <p>Congratulations! You've won the <strong>${data.giveawayName}</strong> giveaway${data.prizeName ? ` and will receive ${data.prizeName}` : ""}!</p>
        <p>Check your app for next steps and shipping information.</p>
        <p style="margin-top: 30px;">
          <a href="https://app.gethybrid.co" style="background-color: #10B981; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">
            View Prize Details
          </a>
        </p>
        <p style="color: #666; font-size: 12px; margin-top: 40px;">
          If you have any questions about your prize, reply to this email.
        </p>
      </div>
    `,
    text: `Congratulations ${data.name}! You've won the ${data.giveawayName} giveaway!`,
    tags: ["giveaway-winner"],
  });
}
