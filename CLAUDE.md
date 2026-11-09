# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## Project overview

Africa MICE Dashboard: bid intelligence for African destinations, a product of
Farirai Nandipa MICE Consultancy. The site has two parts, deployed together on
Netlify.

1. **Landing page** (`/`): Vite + React 19 + TypeScript + Tailwind CSS v4
   single-page marketing site. No backend. The access form opens a prefilled
   `mailto:`. "Submit an event" (nav, footer, the event-owner card and the
   Contribute section) and the destination partner link go to the public
   pipeline forms.
2. **Africa MICE Bid Pipeline** (`/pipeline`, `/pipeline/submit.html`): a
   standalone static app in `public/pipeline/`, outside the React build. It
   talks directly to Supabase with `@supabase/supabase-js` loaded from a CDN.
   Sign-in is required (admins and convention-bureau logins). Three public
   pages need no login, namely `submit.html` (organisers submit movable
   conferences), `partner.html` at `/pipeline/partner` (destination partners
   submit profile data, plus the email-verify and status views) and
   `history.html` at `/pipeline/history` (bid-history teaser).

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
  pipeline/history.html public bid-history teaser
  pipeline/theme.css    shared tokens and primitives for all pipeline pages
netlify.toml            build, /pipeline rewrite, security headers
supabase/README.md      where the database schema and migrations live
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
- The canonical schema and migrations live in the **farirainandipa-web** repo
  under `supabase/migrations/` (001 to 023 so far). Add new migrations there with the
  next number, never edit existing ones, then apply to the project and run the
  Supabase security advisor.
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
  `bureau_portal()` / `bid_history()` RPCs and the `dp_bureau_own` /
  `dpf_bureau_own` policies. Accounts are created by the `bureau-admin` edge
  function (admins only).
- **Anonymous visitors** can only read `econ_sectors`, insert into
  `submissions` (status forced to `review`), insert into `contact_submissions`,
  and call the public-form RPCs `bid_wins_teaser`, `partner_form_options`,
  `profile_submit`, `profile_verify`, `profile_status`,
  `submission_upload_allowed`. Every other function has EXECUTE revoked from
  `anon` (migration 023). New SECURITY DEFINER functions must
  `revoke execute ... from public, anon` unless they are meant for public forms,
  and must set `search_path`.
- Never widen a policy to plain `authenticated`: bureau users are
  authenticated too.

### Edge functions used by the pipeline

- `dashboard` (`/functions/v1/dashboard/logo`): serves the logo image.
- `bureau-admin`: create bureau logins, reset passwords, set tier/active.
- `bids`: serves the separate Bid Workspace app from `site_assets`.

## Deployment (Netlify)

- `netlify.toml`: build `npm run build`, publish `dist`, Node 22.
- `/pipeline`, `/pipeline/history`, `/pipeline/partner` and `/pipeline/submit` are rewritten to
  their `.html` files **before** the SPA catch-all. Keep that order.
- This repo is the only source of the pipeline pages. farirainandipa-web no
  longer carries a copy (removed in its PR #18), so edit them here.
- farirainandipa.co.zw/pipeline/* 301-redirects here (path and query kept), so
  old links and the partner verification emails, which still point at the
  old domain, keep working.
- `/pipeline/*` is served with `X-Robots-Tag: noindex` and `no-cache`.
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
