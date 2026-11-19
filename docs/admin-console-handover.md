# Admin console handover

Status on 19 November 2026, written for the next agent to finish the setup.
Read `CLAUDE.md` first; its access model and copy style apply to everything
here.

## What exists

| Part | Where | State |
|---|---|---|
| Database | Migrations `20261119090334_admin_console` and `20261119090502_admin_auth_user_lookup` | Applied to project `upzkvszgoqhoefkiwoep` |
| Account function | Edge function `bureau-admin` | Version 4 deployed |
| Console page | `public/admin/index.html`, served at `/admin` | Merged to main (PRs 15 to 18) |
| Access form | `src/components/AccessForm.tsx` calls `request_access` | Merged to main |
| Portal hooks | `public/pipeline/index.html` ("Report a problem", `track_activity`, `client_log`) | Merged to main |

The console has nine screens. They are Overview, Signups, Accounts, Reports,
Activity, Logs, Audit log, Rate limits and Team. Each one reads and writes
through the `admin_*` RPCs, which check `admin_level()` (`super` for an
allowlisted email, `staff` for an active `admin_staff` row).

## What has been verified

- Every RPC was exercised in a rolled-back transaction as an anonymous
  visitor, a bureau user and a super admin. Non-admins were refused, the sixth
  access request from one network was blocked, and the audit log rejected an
  update.
- The Supabase security advisor showed no new warning types after the
  migration.
- `npm run build` passed.

## What has not been verified

Nothing has been used for real yet. On 19 November the tables
`signup_requests`, `user_reports`, `user_activity`, `system_log`,
`admin_audit_log` and `admin_staff` were all empty, and
`admin_maintenance_nightly` had not had its first run.

- The console screens were syntax-checked only. Nobody has clicked through
  them against live data.
- `bureau-admin` version 4 has not received a real call. The pipeline's
  existing Access tab (create login, set tier, reset password, suspend) now
  runs through it.
- The live access form has not been submitted end to end.

## Tasks, in order

### 1. Put version 4 of `bureau-admin` in the repo (do this first)

`supabase/functions/bureau-admin/index.ts` on main is still **version 3**. It
checks `my_access` and has no staff, audit or rate limit code. Deploying from
the repo would silently remove signup approval for staff, the audit entries
and the staff login actions.

Fetch the deployed source with the Supabase MCP (`get_edge_function`, slug
`bureau-admin`), confirm it is version 4 (it calls `admin_level`, `audit_write`
and `rate_limit_hit`, and handles `create_staff` and `reset_staff_password`),
and commit it over the repo copy unchanged. Do not redeploy.

### 2. Test the account function with a throwaway login

Signed in as a super admin, create a bureau login for a test address, set its
tier, reset its password, suspend it and reinstate it. Confirm each call
succeeds, the first sign-in flow from migration
`20261119043319_bureau_first_signin_security` still works, and each action
appears in the console's Audit log with the admin's email as the actor.
Delete the test login afterwards. If version 4 fails and cannot be fixed
quickly, redeploy version 3 from git history and say so.

### 3. Walk the signup flow

Submit the landing page access form, check the request appears under Signups,
approve it (country and tier), and sign in with the temporary password. Then
test Reject, Spam and Reopen on further requests, and confirm a sixth
request inside an hour from one network shows the rate limit message.

### 4. Click through the remaining screens

File a report from the portal's "Report a problem" menu item and update it in
Reports. Check Activity after a bureau sign-in, Logs, Rate limits (change a
rule and lift a block as super admin), and Team (add a staff member, create
their login, sign in as them, confirm super-only buttons are hidden and the
super-only RPCs refuse them). Fix what is broken in `public/admin/index.html`.

### 5. Close the known gaps

Ask Farirai before starting any of these; they are product decisions as much
as code.

- **Notifications.** No email is sent when a signup request or report
  arrives. The project already sends mail through edge functions
  (`send-enquiry-notification`, `send-submission-verification`).
- **Read throttling.** Rate limits cover the new write endpoints only. The
  portal's data reads (`bureau_portal`, `bureau_matches` and similar) are not
  limited, so scraping is not yet addressed. Those functions are `STABLE`, so
  they cannot call `rate_limit_hit` as they stand.
- **Staff first sign-in.** Staff get a temporary password but are not forced
  to change it, unlike bureau logins.
- **Super admin management.** Super admins are added by editing
  `public.allowlist` directly. There is no console screen for it, on purpose.
- **Export limit.** The `data_export` rule only takes effect if an export or
  download feature calls `track_activity('export')` and honours a refusal.
  The portal has no export feature today.
- **Auth settings.** The advisor reports leaked password protection as
  disabled. That is a Supabase Auth setting, not code.

### 6. Update the docs

When the tasks above are done, correct `CLAUDE.md` where it has drifted (the
`bureau-admin` entry should name `supabase/functions/` as the source) and
delete this file.

## Things that are easy to get wrong

- `rate_limit_hit` must be followed by a returned error value, never a raised
  exception, or the count rolls back with the transaction.
- `admin_audit_log` rejects update, delete and truncate, so test entries stay
  for good. Test destructive paths inside a transaction that ends in a raised
  exception, as the original tests did.
- The audit trigger on `user_access` records the actor as `service_role` for
  writes made by the edge function. The readable entry is the one the function
  writes itself through `audit_write` with `p_actor`.
- The console tables have no RLS policies on purpose. Do not add policies for
  `authenticated`; bureau users are authenticated too.
- The database is shared with farirainandipa.co.zw.
- Supabase asks the account owner to confirm migrations that contain
  destructive statements. The prompt times out after two minutes, so warn
  Farirai before applying one.
