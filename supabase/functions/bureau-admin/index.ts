// Admin-only management of logins for the pipeline portal.
// v2 (Nov 2026): every bureau login carries a licence tier
// (free / explorer / bureau / bureau_plus); set_tier changes it.
// v3 (Nov 2026): first sign-in security. Create and reset issue a temporary
// password that expires after seven days and set must_change_password, so the
// user must confirm their email with a one-time code and choose their own
// password before the portal shows anything (migration
// 20261119043319_bureau_first_signin_security). Reset and disable also end
// every open session of that login.
// v4 (Nov 2026): admin console (migration 20261119090334_admin_console).
// Callers are checked with admin_level(). Super admins (allowlist) keep every
// action. Staff may approve an access request (create with signup_request_id),
// reset a password and suspend or reinstate a login. Every action is rate
// limited per admin and written to the audit log with the admin's email.
// New actions create_staff and reset_staff_password manage staff logins.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "content-type": "application/json" } });
const TIERS = ["free", "explorer", "bureau", "bureau_plus"];
const TEMP_DAYS = 7;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

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
  // 1. caller must be a super admin (allowlist) or active staff
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const { data: level, error: lvErr } = await caller.rpc("admin_level");
  if (lvErr || (level !== "super" && level !== "staff")) return json({ error: "Admins only" }, 403);
  const { data: who } = await caller.auth.getUser();
  const actor = who?.user?.email ?? "unknown admin";
  const actorId = who?.user?.id ?? actor;
  const isSuper = level === "super";

  const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const { action } = body;
  const expiresAt = () => new Date(Date.now() + TEMP_DAYS * 86400_000).toISOString();
  const audit = (act: string, entity: string, id: string, summary: string) =>
    svc.rpc("audit_write", { p_action: act, p_entity: entity, p_entity_id: id, p_summary: summary, p_actor: actor });

  // 2. per-admin rate limit on account actions
  const { data: allowed } = await svc.rpc("rate_limit_hit", { p_rule: "admin_account_action", p_subject: actorId });
  if (allowed === false) return json({ error: "Too many account actions in the last hour. Try again later." }, 429);

  if (action === "create") {
    let email = String(body.email || "").trim().toLowerCase();
    const country_id = Number(body.country_id);
    const tier = String(body.tier || "");
    let org_name = body.org_name || null, contact_name = body.contact_name || null;
    // Approving an access request: the request supplies the email and names.
    let reqRow: any = null;
    if (body.signup_request_id != null) {
      const { data } = await svc.from("signup_requests").select("*").eq("id", body.signup_request_id).maybeSingle();
      if (!data) return json({ error: "Access request not found" }, 404);
      if (data.status === "approved") return json({ error: "This request already has a login" }, 400);
      reqRow = data;
      email = String(data.email).toLowerCase();
      org_name = org_name || data.org_name;
      contact_name = contact_name || data.contact_name;
    } else if (!isSuper) {
      return json({ error: "Staff can create a login only by approving an access request" }, 403);
    }
    if (!EMAIL_RE.test(email) || !country_id) return json({ error: "Email and country are required" }, 400);
    if (!TIERS.includes(tier)) return json({ error: "Choose a licence tier" }, 400);
    const { data: al } = await svc.from("allowlist").select("email").ilike("email", email).maybeSingle();
    const { data: st } = await svc.from("admin_staff").select("email").eq("email", email).maybeSingle();
    if (al || st) return json({ error: "That email is an admin account and cannot be a bureau login" }, 400);
    const pw = tempPassword();
    const { data: u, error } = await svc.auth.admin.createUser({ email, password: pw, email_confirm: true, user_metadata: { role: "bureau" } });
    if (error) return json({ error: error.message }, 400);
    const { error: insErr } = await svc.from("user_access").insert({
      user_id: u.user.id, email, role: "bureau", country_id, tier,
      org_name, contact_name, active: true,
      must_change_password: true, temp_password_issued_at: new Date().toISOString(),
    });
    if (insErr) { await svc.auth.admin.deleteUser(u.user.id); return json({ error: insErr.message }, 400); }
    if (reqRow) {
      await svc.from("signup_requests").update({
        status: "approved", reviewed_by: actor, reviewed_at: new Date().toISOString(),
        review_note: body.note ? String(body.note).slice(0, 1000) : null, tier, country_id, user_id: u.user.id,
      }).eq("id", reqRow.id);
    }
    await audit(reqRow ? "signup.approve" : "account.create", "user_access", u.user.id, `${email} created on tier ${tier}`);
    return json({ ok: true, user_id: u.user.id, email, tier, temp_password: pw, expires_at: expiresAt() });
  }

  if (action === "set_tier") {
    if (!isSuper) return json({ error: "Super admins only" }, 403);
    const tier = String(body.tier || "");
    if (!TIERS.includes(tier)) return json({ error: "Unknown tier" }, 400);
    const { data: ua } = await svc.from("user_access").select("user_id,role,email").eq("user_id", body.user_id).maybeSingle();
    if (!ua || ua.role !== "bureau") return json({ error: "Bureau account not found" }, 404);
    const { error } = await svc.from("user_access").update({ tier }).eq("user_id", ua.user_id);
    if (error) return json({ error: error.message }, 400);
    await audit("account.set_tier", "user_access", ua.user_id, `${ua.email} moved to tier ${tier}`);
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
    await audit("account.reset_password", "user_access", ua.user_id, `Temporary password issued for ${ua.email}`);
    return json({ ok: true, email: ua.email, temp_password: pw, expires_at: expiresAt() });
  }

  if (action === "set_active") {
    const { data: ua } = await svc.from("user_access").select("user_id,role,email").eq("user_id", body.user_id).maybeSingle();
    if (!ua || ua.role !== "bureau") return json({ error: "Bureau account not found" }, 404);
    const active = !!body.active;
    await svc.from("user_access").update({ active }).eq("user_id", ua.user_id);
    await svc.auth.admin.updateUserById(ua.user_id, { ban_duration: active ? "none" : "876000h" });
    if (!active) await svc.rpc("revoke_user_sessions", { p_user_id: ua.user_id });
    const reason = body.reason ? ` (${String(body.reason).slice(0, 300)})` : "";
    await audit(active ? "account.reinstate" : "account.suspend", "user_access", ua.user_id, `${ua.email} ${active ? "reinstated" : "suspended"}${reason}`);
    return json({ ok: true, active });
  }

  // Staff logins. The email must already be on the staff list (admin_staff_set).
  if (action === "create_staff" || action === "reset_staff_password") {
    if (!isSuper) return json({ error: "Super admins only" }, 403);
    const email = String(body.email || "").trim().toLowerCase();
    const { data: st } = await svc.from("admin_staff").select("email").eq("email", email).maybeSingle();
    if (!st) return json({ error: "Add this email to the staff list first" }, 400);
    const { data: ua } = await svc.from("user_access").select("user_id").ilike("email", email).maybeSingle();
    if (ua) return json({ error: "That email is a bureau login" }, 400);
    const pw = tempPassword();
    const { data: existing } = await svc.rpc("admin_auth_user_id", { p_email: email });
    if (action === "create_staff") {
      if (existing) return json({ error: "This staff member already has a login. Reset the password instead." }, 400);
      const { data: u, error } = await svc.auth.admin.createUser({ email, password: pw, email_confirm: true, user_metadata: { role: "staff" } });
      if (error) return json({ error: error.message }, 400);
      await audit("staff.create_login", "admin_staff", email, `Login created for staff member ${email}`);
      return json({ ok: true, user_id: u.user.id, email, temp_password: pw });
    }
    if (!existing) return json({ error: "This staff member has no login yet" }, 404);
    const { error } = await svc.auth.admin.updateUserById(existing, { password: pw });
    if (error) return json({ error: error.message }, 400);
    await svc.rpc("revoke_user_sessions", { p_user_id: existing });
    await audit("staff.reset_password", "admin_staff", email, `Temporary password issued for staff member ${email}`);
    return json({ ok: true, email, temp_password: pw });
  }

  return json({ error: "Unknown action" }, 400);
});
