# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## Project overview

Africa MICE Dashboard: bid intelligence for African destinations, a product of
Farirai Nandipa MICE Consultancy. The site has two parts, deployed together on
Netlify.

1. **Landing page** (`/`): Vite + React 19 + TypeScript + Tailwind CSS v4
   single-page marketing site. The access form files a request in the admin
   signup queue through the public `request_access` RPC and falls back to a
   prefilled `mailto:` if that call fails. "Submit an event" (nav, footer, the event-owner card and the
   Contribute section) and the destination partner link go to the public
   pipeline forms.
2. **Africa MICE Bid Pipeline** (`/pipeline`, `/pipeline/submit.html`): a
   standalone static app in `public/pipeline/`, outside the React build. It
   talks directly to Supabase with `@supabase/supabase-js` loaded from a CDN.
   Sign-in is required (admins and convention-bureau logins). Two public
   pages need no login, namely `submit.html` (organisers submit movable
   conferences) and `partner.html` at `/pipeline/partner` (destination partners
   submit profile data, plus the email-verify and status views).

## Commands

```bash
npm install
npm run dev       # landing + pipeline at http://localhost:5173 (pipeline: /pipeline/index.html)
npm run build     # tsc -b && vite build -> dist/ (public/pipeline is copied as-is)
npm run preview   # serve the production build
```

No test suite or linter is configured. `npm run build` is the check: it must
pass before deploying.

## Structure

```
src/
  content.ts            ALL landing copy, stats, URLs and the contact email
  lib/mailto.ts         mailto: URL builder
  components/           Nav, Hero, Platform, Audience, HowItWorks, Contribute,
                        AccessForm, Footer, AfricaDots, Reveal, Button, ...
public/
  pipeline/index.html   Bid Pipeline app (HTML + CSS + JS in one file, ~125 KB)
  pipeline/submit.html  public event submission form
  pipeline/partner.html public destination-partner submission form
  pipeline/theme.css    shared tokens and primitives for all pipeline pages
  admin/index.html      system admin console at /admin (agency team only)
netlify.toml            build, /pipeline rewrite, security headers
supabase/README.md      where the database schema and migrations live
supabase/migrations/    pipeline migrations from the move onwards
```

- Landing copy lives only in `src/content.ts`; components read from it.
  `DASHBOARD_URL` is `/pipeline` (the "Sign in" buttons).
- The pipeline pages are plain HTML/JS. Edit them directly; there is no build
  step for them. They share `pipeline/theme.css`, which mirrors the landing
  tokens in `src/index.css` (navy, one teal accent, Manrope). Change colours in
  both places together. Link it as `/pipeline/theme.css`, since the rewritten
  paths have no trailing slash. Keep links relative (`submit.html`, `location.origin`) so the
  pages work on any domain.

## Database (Supabase)

- Project ref `upzkvszgoqhoefkiwoep` (eu-west-1), **shared** with the
  farirainandipa.co.zw website. Both sites read the same pipeline data.
- The dashboard now lives in this repo, so new pipeline migrations go in
  `supabase/migrations/` **here**, named `<version>_<name>.sql` with the version
  the project records in `supabase_migrations.schema_migrations` when applied.
  Never edit existing ones. Apply to the project, then run the Supabase security
  advisor.
- The older history (001 to 023, before the move) stays in the
  **farirainandipa-web** repo under `supabase/migrations/`. Read it there; do
  not add to it for dashboard changes.
- The anon (publishable) key is hard-coded in the pipeline pages. That is
  expected: it is public by design and everything is enforced by RLS. Never put
  the `service_role` key in this repo or any client code.

### Access model (keep it this way)

- RLS is enabled on every table.
- **Admins**: emails in `public.allowlist`. `public.is_allowlisted()` gates
  every pipeline table and all writes. The allowlist and `site_assets` tables
  have no policies on purpose (service role only).
- **Bureau logins**: `public.user_access` (role `bureau`, a `country_id` and a
  licence `tier`, one of free, explorer, bureau or bureau_plus). Bureaux never read
  pipeline tables directly; they get their own country only, through the
  `bureau_portal()` RPC and the `dp_bureau_own` /
  `dpf_bureau_own` policies. They edit their own country's descriptive and
  visa fields through `bureau_country()` / `bureau_update_country(patch)`
  (migration `20261110221713_bureau_country_edit`), which reject any other
  column; admins edit `countries` directly. Accounts are created by the
  `bureau-admin` edge function (admins only; source in
  `supabase/functions/bureau-admin/`). Every tier gets the same
  portal for now.
- **First sign-in** (migration `20261119043319_bureau_first_signin_security`).
  Create and reset give a temporary password (seven days) and set
  `user_access.must_change_password`. Until `complete_first_signin()` clears
  it, `bureau_country_id()` and `my_tier()` return null, so the bureau sees
  nothing. That RPC requires a session opened with an emailed code (JWT `amr`
  of `otp` or `magiclink`) and a password change after the temporary one
  (`password_changed_at`, set by a trigger on `auth.users`). Route any new
  bureau policy or RPC through `bureau_country_id()` so it honours the gate.
  Password rules live in `PW_RULES` in `pipeline/index.html` and should match
  the Supabase Auth password settings.
- **Bid history** (`bid_wins`, `series`, `history_sync_log` and the
  `bid_history*` / `bid_wins_teaser` RPCs) is admin only. Bureaux and
  anonymous visitors have no access (migration
  `20261117081600_bid_history_admin_only`). Do not reopen it without asking.
- **Matching** (migration `20261117130614_bureau_match_view`). Requirement
  columns on `bid_opportunities` (delegates, plenary seats, origin mix, visa
  sensitivity, host type, `next_action`) are edited by admins through
  `opportunity_set_requirements(p_id, patch)`. `destination_fit_inputs` holds
  one row per country with per-field trust in `meta`; `match_weights` holds the
  admin weights. `score_match()` is internal and `rescore_matches()` fills
  `match_scores`, run by triggers on requirements, sectors, fit inputs and
  weights, and nightly by pg_cron (`match_rescore_nightly`). Bureaux read their
  own country through `bureau_matches()`, which adds the top three other
  African scores per call (country names on Bureau Plus only) and never
  includes bid history. The agent writes fit inputs only through
  `fit_inputs_agent_upsert()`, which stores values as unverified and logs a
  differing value for a verified field in `fit_input_conflicts` instead.
  `countries_ready_for_scoring` lists countries with every weighted input set.
- **System admin console** (migration `20261119090334_admin_console`,
  page `public/admin/index.html`). `admin_level()` returns `super` for an
  allowlisted email and `staff` for an active row in `admin_staff`. Staff work
  the signup and report queues, suspend accounts, reset passwords and read
  every console screen; only super admins change tiers, rate limit rules,
  settings and the team. Staff have no access to pipeline tables, which stay
  gated by `is_allowlisted()`. The console tables (`signup_requests`,
  `user_reports`, `user_activity`, `system_log`, `admin_audit_log`,
  `rate_limit_rules`, `rate_limit_counters`, `admin_staff`, `admin_settings`,
  `metrics_daily`) have no policies on purpose and are reached only through
  the `admin_*` RPCs. `admin_audit_log` is append-only (triggers reject update,
  delete and truncate) and is fed by `audit_row()` triggers on `user_access`,
  `allowlist` and the console tables. `rate_limit_hit(rule, subject)` counts a
  hit and returns false over the limit; callers must return an error value
  and not raise, or the count rolls back. Signed-in users call
  `report_submit`, `my_reports`, `track_activity` and `client_log`.
  `admin_maintenance()` runs nightly by pg_cron (`admin_maintenance_nightly`)
  to snapshot metrics and prune old logs.
- **Anonymous visitors** can only read `econ_sectors`, insert into
  `submissions` (status forced to `review`), insert into `contact_submissions`,
  and call the public-form RPCs `partner_form_options`,
  `profile_submit`, `profile_verify`, `profile_status`,
  `submission_upload_allowed`, `request_access`. Every other function has EXECUTE revoked from
  `anon` (migration 023). New SECURITY DEFINER functions must
  `revoke execute ... from public, anon` unless they are meant for public forms,
  and must set `search_path`.
- Never widen a policy to plain `authenticated`: bureau users are
  authenticated too.

### Weekly bid scan

- A Claude cloud routine, "Africa MICE Dashboard Weekly Scan" (Mondays 08:00
  Africa/Johannesburg), maintains `bid_opportunities`, `events` and
  `country_matches` through the Supabase MCP. Its prompt lives in the routine
  (claude.ai/code/routines), not in this repo.
- Step 1a of that prompt, run straight after auto-close, rescans closed bids
  and bid history for calls that have reopened. It reads
  `public.reopen_scan_queue(15)` (migration
  `20261110213927_reopened_bids_scan`), which lists closed opportunities,
  lapsed or set-aside events (fixed-venue ones excluded) and `series` whose
  next host window is near, skipping anything already tracked by an open or
  watchlist row with the same `series_key`. Every recheck is logged in
  `public.reopen_checks`, so each week covers the items checked longest ago.
  Both are admin only. Step 10 of the prompt is separate: it captures recently
  closed calls that new searches turn up.
- When editing the prompt, re-read the live routine first and keep the step
  numbers, since later steps refer to earlier ones by number.

### Edge functions used by the pipeline

- `dashboard` (`/functions/v1/dashboard/logo`): serves the logo image.
- `bureau-admin`: create bureau logins (also when approving a signup request),
  reset passwords, set tier/active, and create or reset staff logins. Callers
  are checked with `admin_level()`, rate limited and written to the audit log.
- `bids`: serves the separate Bid Workspace app from `site_assets`.

## Deployment (Netlify)

- `netlify.toml`: build `npm run build`, publish `dist`, Node 22.
- `/pipeline`, `/pipeline/partner` and `/pipeline/submit` are rewritten to
  their `.html` files, and `/admin` to `admin/index.html`, **before** the
  SPA catch-all. Keep that order.
- This repo is the only source of the pipeline pages. farirainandipa-web no
  longer carries a copy (removed in its PR #18), so edit them here.
- farirainandipa.co.zw/pipeline/* 301-redirects here (path and query kept), so
  old links and the partner verification emails, which still point at the
  old domain, keep working.
- `/pipeline/*` and `/admin/*` are served with `X-Robots-Tag: noindex` and `no-cache`.
- No build-time environment variables are needed.
- When the site's domain changes, add it to Supabase Auth URL configuration
  (Site URL / Redirect URLs) so sign-in and password flows work.

## Copy style

British English. No exclamation marks, no emojis, no hype.

These two rules apply to **all text you generate**, including page copy,
titles and meta tags, aria labels, code comments, README and docs, commit
messages, PR descriptions, emails and chat replies.

- **No em dashes** (U+2014, also written `&mdash;` or `\u2014`). Use a comma,
  a full stop, a semicolon or parentheses, or rephrase. En dashes only in
  number ranges.
- **No colon before a list.** Do not introduce a run of items with a colon in
  a sentence. Rephrase so the list follows naturally ("three pages, namely a,
  b and c", or "Three pages need no login. They are a, b and c."). A colon is
  fine after a label or term being defined (`bids`: serves the app) and in
  times, ratios and URLs.

Before finishing, grep changed files for U+2014 and fix any hits.
