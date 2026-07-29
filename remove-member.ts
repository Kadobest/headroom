// remove-member.ts
//
// This file does NOT go into your website. It runs on Supabase's
// servers, same as approve-assistant.ts. To use it: open your
// Supabase project → Edge Functions → Create a new function →
// name it exactly "remove-member" → paste this whole file's
// contents into the editor → Deploy.
//
// Why this needs to be here instead of the app deleting the
// profile row directly: deleting only the profile row leaves the
// underlying login (in auth.users) behind, which is why re-approving
// the same email later fails with "email already in use." This
// function deletes the actual login too, which frees the email up
// again — while leaving every project, client, artist, and track
// they added completely untouched, since none of that work data is
// linked to their account.
//
// Only a logged-in Owner can successfully call this function, and
// an Owner can never remove themselves this way.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "Not signed in." }), { status: 401, headers: corsHeaders });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (!callerProfile || callerProfile.role !== "owner") {
      return new Response(JSON.stringify({ error: "Only the owner can remove team members." }), { status: 403, headers: corsHeaders });
    }

    const { user_id } = await req.json();
    if (!user_id) {
      return new Response(JSON.stringify({ error: "Missing user_id." }), { status: 400, headers: corsHeaders });
    }
    if (user_id === user.id) {
      return new Response(JSON.stringify({ error: "You can't remove your own account this way." }), { status: 400, headers: corsHeaders });
    }

    // Deleting the auth user cascades to delete their profiles row too
    // (profiles.id references auth.users.id with ON DELETE CASCADE).
    const { error: deleteErr } = await admin.auth.admin.deleteUser(user_id);
    if (deleteErr) {
      return new Response(JSON.stringify({ error: deleteErr.message }), { status: 400, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
});
