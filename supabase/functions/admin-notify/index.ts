// Emails the agency team when a new access request or problem report arrives.
// Called by the admin_notify_queue_event() trigger (migration
// admin_notifications) through pg_net with only { kind, id }. The function
// reads the row itself with the service role, so the request carries no
// personal data. Recipients are every super admin (allowlist) and every
// active staff member. Deployed with verify_jwt = false and protected by the
// x-webhook-secret header (the same WEBHOOK_SECRET as
// send-enquiry-notification). Mail goes out over the project's SMTP secrets.
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const ADMIN_URL = Deno.env.get("ADMIN_CONSOLE_URL") ?? "https://africamicedashboard.com/admin";

const REPORT_KINDS: Record<string, string> = {
  data_issue: "Incorrect or outdated data",
  support: "Help using the dashboard",
  bug: "Something is not working",
  abuse: "Misuse or a security concern",
};

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

function esc(v: unknown): string {
  return String(v ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// Plain text and a simple HTML table from the same label and value rows.
function render(intro: string, rows: [string, unknown][], note: string, linkText: string) {
  const shown = rows.filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== "");
  const text = [intro, "", ...shown.map(([k, v]) => `${k}: ${v}`), "", note, "", `${linkText}: ${ADMIN_URL}`]
    .filter((l, i, a) => !(l === "" && a[i - 1] === ""))
    .join("\n");
  const html = `<div style="font-family:Arial,sans-serif;color:#1f2937;max-width:600px">
  <p>${esc(intro)}</p>
  <table style="border-collapse:collapse;width:100%">${shown.map(([k, v]) =>
    `<tr><td style="padding:6px 12px 6px 0;font-weight:bold;vertical-align:top;width:130px">${esc(k)}</td><td style="padding:6px 0;white-space:pre-wrap">${esc(v)}</td></tr>`).join("")}</table>
  ${note ? `<p style="color:#6b7280">${esc(note)}</p>` : ""}
  <p><a href="${esc(ADMIN_URL)}">${esc(linkText)}</a></p>
</div>`;
  return { text, html };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const expected = Deno.env.get("WEBHOOK_SECRET");
  if (!expected || req.headers.get("x-webhook-secret") !== expected) return json({ error: "Unauthorized" }, 401);

  let body: { kind?: string; id?: number };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const kind = body.kind, id = Number(body.id);
  if ((kind !== "signup" && kind !== "report") || !Number.isFinite(id)) return json({ error: "Expected kind and id" }, 400);

  const svc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Recipients: super admins and active staff, without duplicates.
  const [{ data: supers }, { data: staff }] = await Promise.all([
    svc.from("allowlist").select("email"),
    svc.from("admin_staff").select("email").eq("active", true),
  ]);
  const to = [...new Set([...(supers ?? []), ...(staff ?? [])]
    .map((r: { email: string }) => String(r.email || "").trim().toLowerCase()).filter(Boolean))];
  if (!to.length) return json({ ok: false, error: "No recipients" }, 200);

  let subject: string, mail: { text: string; html: string };
  let replyTo: string | undefined;
  if (kind === "signup") {
    const { data: r } = await svc.from("signup_requests").select("*").eq("id", id).maybeSingle();
    if (!r) return json({ ok: false, error: "Request not found" }, 404);
    if (r.status !== "pending") return json({ ok: true, skipped: "not pending" });
    replyTo = r.email;
    subject = `New access request: ${r.org_name || r.contact_name || r.email}${r.country_name ? ` (${r.country_name})` : ""}`;
    mail = render(
      "Someone has asked for access to the Africa MICE Dashboard.",
      [["Name", r.contact_name], ["Organisation", r.org_name], ["Type", r.org_type], ["Country", r.country_name],
        ["Email", r.email], ["Message", r.message]],
      r.existing_account ? "This email address already has a login." : "",
      "Review it under Signups in the admin console",
    );
  } else {
    const { data: r } = await svc.from("user_reports").select("*").eq("id", id).maybeSingle();
    if (!r) return json({ ok: false, error: "Report not found" }, 404);
    const kindLabel = REPORT_KINDS[r.kind] ?? r.kind;
    replyTo = r.reporter_email || undefined;
    subject = `${r.kind === "abuse" ? "Security report" : "New report"}: ${r.title}`;
    mail = render(
      "A signed-in user has filed a report from the dashboard.",
      [["Type", kindLabel], ["Summary", r.title], ["About", r.subject_label], ["Details", r.body],
        ["From", r.reporter_email], ["Page", r.page_url]],
      "",
      "Open it under Reports in the admin console",
    );
  }

  const username = Deno.env.get("SMTP_USERNAME"), password = Deno.env.get("SMTP_PASSWORD");
  if (!username || !password) return json({ ok: false, error: "SMTP not configured" }, 500);
  const client = new SMTPClient({
    connection: {
      hostname: Deno.env.get("SMTP_HOSTNAME") ?? "smtp.gmail.com",
      port: Number(Deno.env.get("SMTP_PORT") ?? "465"),
      tls: true,
      auth: { username, password },
    },
  });
  try {
    await client.send({
      from: Deno.env.get("NOTIFY_FROM") ?? username,
      to,
      replyTo,
      subject: subject.slice(0, 200),
      content: mail.text,
      html: mail.html,
    });
  } catch (err) {
    console.error("admin-notify send failed:", err);
    try { await client.close(); } catch { /* ignore */ }
    return json({ ok: false, error: "Send failed" }, 500);
  }
  try { await client.close(); } catch { /* ignore */ }
  return json({ ok: true, sent_to: to.length });
});
