/**
 * Supabase Edge Function: ingest-site
 *
 * Accepts a POST request whose body is the ingest_site payload (JSON),
 * calls the ingest_site Postgres RPC, and returns the result.
 *
 * Deploy:
 *   supabase functions deploy ingest-site --no-verify-jwt
 *
 * Call (curl):
 *   curl -X POST https://<project>.supabase.co/functions/v1/ingest-site \
 *     -H "Authorization: Bearer <service_role_key>" \
 *     -H "Content-Type: application/json" \
 *     -d @payloads/example_ingest_site.json
 *
 * Environment variables (auto-provided by Supabase runtime):
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed" }, 405);
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: "Invalid JSON body" }, 400);
  }

  // Basic guard: researcher_id is required
  if (
    typeof payload !== "object" ||
    payload === null ||
    !("researcher_id" in payload)
  ) {
    return json({ ok: false, error: "Missing required field: researcher_id" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ ok: false, error: "Server misconfiguration: missing env vars" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase.rpc("ingest_site", { payload });

  if (error) {
    // Supabase client-level error (network, auth, etc.)
    return json({ ok: false, error: error.message, detail: error.details }, 500);
  }

  // The RPC itself returns { ok, site_id } or { ok: false, error, sqlstate }
  const status = data?.ok === false ? 500 : 200;
  return json(data, status);
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
