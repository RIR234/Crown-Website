import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://crown-website-livid.vercel.app",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return reply({ error: "Sign in required" }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user?.email) {
      console.warn("send-notification: user verification failed", { hasUser: !!user, authError: !!authError });
      return reply({ error: "Could not verify account. Please sign in again." }, 401);
    }

    const { title, message, eventType } = await req.json();
    const safeTitle = String(title || "Crown account update").slice(0, 100);
    const safeMessage = String(message || "").slice(0, 500);
    const safeEventType = String(eventType || "activity").slice(0, 30);
    if (!safeMessage) return reply({ error: "Message is required" }, 400);

    const apiKey = Deno.env.get("BREVO_API_KEY");
    const senderEmail = Deno.env.get("BREVO_SENDER_EMAIL");
    const senderName = Deno.env.get("BREVO_SENDER_NAME") || "Crown";
    if (!apiKey || !senderEmail) {
      console.error("send-notification: Brevo secrets missing", { hasApiKey: !!apiKey, hasSenderEmail: !!senderEmail });
      return reply({ error: "Email service is not configured. Check BREVO_API_KEY and BREVO_SENDER_EMAIL in Supabase Secrets." }, 503);
    }

    console.info("send-notification: sending to authenticated account", { eventType: safeEventType, subject: safeTitle });
    const sent = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": apiKey, "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({
        sender: { name: senderName, email: senderEmail },
        to: [{ email: user.email }],
        subject: safeTitle,
        textContent: safeMessage + "\n\nThis is an automated Crown account notification."
      })
    });

    const providerBody = await sent.json().catch(() => ({}));
    if (!sent.ok) {
      const providerMessage = String(providerBody?.message || providerBody?.code || "Brevo rejected the email").slice(0, 240);
      console.error("send-notification: Brevo rejected email", { status: sent.status, code: providerBody?.code || "unknown", message: providerMessage });
      return reply({ error: providerMessage, providerStatus: sent.status }, 502);
    }

    console.info("send-notification: Brevo accepted email", { status: sent.status, messageId: providerBody?.messageId || null, eventType: safeEventType });
    return reply({ sent: true, providerStatus: sent.status, messageId: providerBody?.messageId || null, eventType: safeEventType });
  } catch (error) {
    console.error("send-notification: unexpected error", { message: error instanceof Error ? error.message.slice(0, 240) : "Unknown error" });
    return reply({ error: "Unable to send notification. Check the Function logs for details." }, 400);
  }
});
