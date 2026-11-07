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
    if (authError || !user?.email) return reply({ error: "Could not verify account" }, 401);

    const { title, message, eventType } = await req.json();
    const safeTitle = String(title || "Crown account update").slice(0, 100);
    const safeMessage = String(message || "").slice(0, 500);
    if (!safeMessage) return reply({ error: "Message is required" }, 400);

    const apiKey = Deno.env.get("BREVO_API_KEY");
    const senderEmail = Deno.env.get("BREVO_SENDER_EMAIL");
    const senderName = Deno.env.get("BREVO_SENDER_NAME") || "Crown";
    if (!apiKey || !senderEmail) return reply({ error: "Email service is not configured yet" }, 503);

    const sent = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": apiKey, "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify({
        sender: { name: senderName, email: senderEmail },
        to: [{ email: user.email }],
        subject: safeTitle,
        textContent: safeMessage + "\\n\\nThis is an automated Crown account notification."
      })
    });
    if (!sent.ok) return reply({ error: "Email provider could not send the message" }, 502);
    return reply({ sent: true, eventType: String(eventType || "activity").slice(0, 30) });
  } catch {
    return reply({ error: "Unable to send notification" }, 400);
  }
});