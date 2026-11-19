// Admin-only management of bureau (client) logins for the pipeline portal.
// v2 (Nov 2026): every bureau login carries a licence tier
// (free / explorer / bureau / bureau_plus); set_tier changes it.
// v3 (Nov 2026): first sign-in security. Create and reset issue a temporary
// password that expires after seven days and set must_change_password, so the
// user must confirm their email with a one-time code and choose their own
// password before the portal shows anything (migration
// 20261119043319_bureau_first_signin_security). Reset and disable also end
// every open session of that login.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "content-type": "application/json" } });
const TIERS = ["free", "explorer", "bureau", "bureau_plus"];
const TEMP_DAYS = 7;

// Uniform random pick from an alphabet (rejection sampling, no modulo bias).
function pick(alphabet: string): string {
  const limit = 256 - (256 % alphabet.length);
  while (true) {
    const [x] = crypto.getRandomValues(new Uint8Array(1));
    if (x < limit) return alphabet[x % alphabet.length];
  }
}

// 16 characters with at least one of each class, in random order. Ambiguous
// characters (0/O, 1/l/I) are left out so it can be read aloud or retyped.
function tempPassword(): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ", lower = "abcdefghijkmnpqrstuvwxyz", digit = "23456789", sym = "!@#$%*?-+=";
  const all = upper + lower + digit + sym;
  const chars = [pick(upper), pick(lower), pick(digit), pick(sym)];
  while (chars.length < 16) chars.push(pick(all));
  // Fisher-Yates shuffle; the bias of a 32-bit value mod 16 or less is negligible.
  for (let i = chars.length - 1; i > 0; i--) {
    const k = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [chars[i], chars[k]] = [chars[k], chars[i]];
  }
  return chars.join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  // 1. caller must be an allowlisted admin
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: acc, error: accErr } = await caller.rpc("my_access");
  if (accErr || acc?.role !== "admin") return json({ error: "Admins only" }, 403);

  const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const { action } = body;
  const expiresAt = () => new Date(Date.now() + TEMP_DAYS * 86400_000).toISOString();

  if (action === "create") {
    const email = String(body.email || "").trim().toLowerCase();
    const country_id = Number(body.country_id);
    const tier = String(body.tier || "");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !country_id) return json({ error: "Email and country are required" }, 400);
    if (!TIERS.includes(tier)) return json({ error: "Choose a licence tier" }, 400);
    const { data: al } = await svc.from("allowlist").select("email").ilike("email", email).maybeSingle();
    if (al) return json({ error: "That email is an admin account and cannot be a bureau login" }, 400);
    const pw = tempPassword();
    const { data: u, error } = await svc.auth.admin.createUser({ email, password: pw, email_confirm: true, user_metadata: { role: "bureau" } });
    if (error) return json({ error: error.message }, 400);
    const { error: insErr } = await svc.from("user_access").insert({
      user_id: u.user.id, email, role: "bureau", country_id, tier,
      org_name: body.org_name || null, contact_name: body.contact_name || null, active: true,
      must_change_password: true, temp_password_issued_at: new Date().toISOString(),
    });
    if (insErr) { await svc.auth.admin.deleteUser(u.user.id); return json({ error: insErr.message }, 400); }
    return json({ ok: true, user_id: u.user.id, email, tier, temp_password: pw, expires_at: expiresAt() });
  }

  if (action === "set_tier") {
    const tier = String(body.tier || "");
    if (!TIERS.includes(tier)) return json({ error: "Unknown tier" }, 400);
    const { data: ua } = await svc.from("user_access").select("user_id,role").eq("user_id", body.user_id).maybeSingle();
    if (!ua || ua.role !== "bureau") return json({ error: "Bureau account not found" }, 404);
    const { error } = await svc.from("user_access").update({ tier }).eq("user_id", ua.user_id);
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true, tier });
  }

  if (action === "reset_password") {
    const { data: ua } = await svc.from("user_access").select("user_id,email,role").eq("user_id", body.user_id).maybeSingle();
    if (!ua || ua.role !== "bureau") return json({ error: "Bureau account not found" }, 404);
    const pw = tempPassword();
    const { error } = await svc.auth.admin.updateUserById(ua.user_id, { password: pw });
    if (error) return json({ error: error.message }, 400);
    // Set after the password update, and clear the password_changed_at the
    // auth trigger has just written, so only the user's own change counts.
    const { error: upErr } = await svc.from("user_access")
      .update({ must_change_password: true, temp_password_issued_at: new Date().toISOString(), password_changed_at: null })
      .eq("user_id", ua.user_id);
    if (upErr) return json({ error: upErr.message }, 400);
    await svc.rpc("revoke_user_sessions", { p_user_id: ua.user_id });
    return json({ ok: true, email: ua.email, temp_password: pw, expires_at: expiresAt() });
  }

  if (action === "set_active") {
    const { data: ua } = await svc.from("user_access").select("user_id,role").eq("user_id", body.user_id).maybeSingle();
    if (!ua || ua.role !== "bureau") return json({ error: "Bureau account not found" }, 404);
    const active = !!body.active;
    await svc.from("user_access").update({ active }).eq("user_id", ua.user_id);
    await svc.auth.admin.updateUserById(ua.user_id, { ban_duration: active ? "none" : "876000h" });
    if (!active) await svc.rpc("revoke_user_sessions", { p_user_id: ua.user_id });
    return json({ ok: true, active });
  }

  return json({ error: "Unknown action" }, 400);
});
