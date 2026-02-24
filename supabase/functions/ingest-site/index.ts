/**
 * Supabase Edge Function: ingest-site
 *
 * Calls ingest_site() via a direct Postgres connection, bypassing PostgREST.
 *
 * Deploy:
 *   supabase functions deploy ingest-site --no-verify-jwt
 *
 * Call (curl):
 *   curl -X POST https://<project>.supabase.co/functions/v1/ingest-site \
 *     -H "Authorization: Bearer <service_role_key>" \
 *     -H "Content-Type: application/json" \
 *     -d @payloads/example_ingest_site.json
 */

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import postgres from "https://deno.land/x/postgresjs@v3.4.4/mod.js";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request): Promise<Response> => {
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

  if (
    typeof payload !== "object" ||
    payload === null ||
    !("researcher_id" in payload)
  ) {
    return json({ ok: false, error: "Missing required field: researcher_id" }, 400);
  }

  const dbUrl = Deno.env.get("SUPABASE_DB_URL");
  if (!dbUrl) {
    return json({ ok: false, error: "Server misconfiguration: missing SUPABASE_DB_URL" }, 500);
  }

  const sql = postgres(dbUrl, { max: 1 });

  try {
    const rows = await sql`SELECT ingest_site(${sql.json(payload)}) AS result`;
    const data = rows[0].result;
    const status = data?.ok === false ? 500 : 200;
    return json(data, status);
  } catch (err) {
    return json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
  } finally {
    await sql.end();
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
