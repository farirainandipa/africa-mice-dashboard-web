-- System admin console backend.
-- Adds staff roles, an access request queue, user reports, rate limiting,
-- an append-only audit log, a system log, user activity tracking and system
-- metrics. Every table is RLS-locked with no policies; all access goes through
-- the SECURITY DEFINER functions below, which check public.admin_level().
--
-- Levels: 'super' is an email in public.allowlist (unchanged). 'staff' is an
-- active row in public.admin_staff. Staff work the queues and read everything
-- in the console; only super admins change tiers, rules, settings and the team.

-- ---------------------------------------------------------------- roles ----
create table public.admin_staff (
  email      text primary key check (email = lower(btrim(email)) and email like '%_@_%'),
  full_name  text,
  role       text not null default 'reviewer' check (role in ('reviewer')),
  active     boolean not null default true,
  added_by   text,
  added_at   timestamptz not null default now()
);

create table public.admin_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  updated_by  text
);
insert into public.admin_settings (key, value, description) values
  ('log_retention_days',      '90',  'System log entries older than this are deleted nightly'),
  ('activity_retention_days', '180', 'User activity entries older than this are deleted nightly');

create or replace function public.admin_level() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.is_allowlisted() then 'super'
    when exists (
      select 1 from public.admin_staff s
      join auth.users u on lower(u.email) = s.email
      where u.id = auth.uid() and s.active
        and u.email_confirmed_at is not null
        and (u.banned_until is null or u.banned_until < now())
    ) then 'staff'
  end
$$;

create or replace function public.admin_guard(p_min text default 'staff') returns text
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_level();
begin
  if lv is null or (p_min = 'super' and lv <> 'super') then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  return lv;
end $$;

create or replace function public.admin_actor() returns text
language sql stable set search_path = public as $$
  select coalesce(auth.jwt() ->> 'email', auth.jwt() ->> 'role', session_user::text)
$$;

-- ------------------------------------------------------------ audit log ----
create table public.admin_audit_log (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  actor     text not null,
  actor_id  uuid,
  action    text not null,
  entity    text,
  entity_id text,
  summary   text,
  old_row   jsonb,
  new_row   jsonb,
  ip_hash   text
);
create index admin_audit_log_at_idx on public.admin_audit_log (at desc);
create index admin_audit_log_entity_idx on public.admin_audit_log (entity, entity_id);

create or replace function public.admin_audit_immutable() returns trigger
language plpgsql set search_path = public as $$
begin
  raise exception 'The audit log is append-only';
end $$;
create trigger admin_audit_no_change before update or delete on public.admin_audit_log
  for each row execute function public.admin_audit_immutable();
create trigger admin_audit_no_truncate before truncate on public.admin_audit_log
  for each statement execute function public.admin_audit_immutable();

-- Explicit entry, used by the functions below and by edge functions (which
-- pass the signed-in admin as p_actor because they write with the service role).
create or replace function public.audit_write(
  p_action text, p_entity text default null, p_entity_id text default null,
  p_summary text default null, p_old jsonb default null, p_new jsonb default null,
  p_actor text default null
) returns void
language sql security definer set search_path = public as $$
  insert into public.admin_audit_log (actor, actor_id, action, entity, entity_id, summary, old_row, new_row, ip_hash)
  values (coalesce(nullif(p_actor, ''), public.admin_actor()), auth.uid(), p_action, p_entity, p_entity_id,
          left(p_summary, 500), p_old, p_new, public.request_ip_hash())
$$;

-- Row-level trigger. TG_ARGV[0] is the primary key column.
create or replace function public.audit_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare o jsonb; n jsonb;
begin
  if tg_op <> 'INSERT' then o := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then n := to_jsonb(new); end if;
  -- Sign-in bookkeeping is not an admin change.
  if tg_op = 'UPDATE' and (o - 'last_seen_at' - 'updated_at') = (n - 'last_seen_at' - 'updated_at') then
    return new;
  end if;
  insert into public.admin_audit_log (actor, actor_id, action, entity, entity_id, old_row, new_row, ip_hash)
  values (public.admin_actor(), auth.uid(), tg_table_name || '.' || lower(tg_op), tg_table_name,
          coalesce(n, o) ->> tg_argv[0], o, n, public.request_ip_hash());
  return coalesce(new, old);
end $$;

-- ----------------------------------------------------------- system log ----
create table public.system_log (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  level   text not null default 'info' check (level in ('debug', 'info', 'warn', 'error')),
  source  text not null,
  event   text not null,
  message text,
  context jsonb,
  user_id uuid,
  ip_hash text
);
create index system_log_at_idx on public.system_log (at desc);
create index system_log_event_idx on public.system_log (event, at desc);

create or replace function public.log_event(
  p_level text, p_source text, p_event text, p_message text default null, p_context jsonb default null
) returns void
language sql security definer set search_path = public as $$
  insert into public.system_log (level, source, event, message, context, user_id, ip_hash)
  values (case when p_level in ('debug', 'info', 'warn', 'error') then p_level else 'info' end,
          left(p_source, 60), left(p_event, 120), left(p_message, 2000), p_context, auth.uid(), public.request_ip_hash())
$$;

-- --------------------------------------------------------- rate limiting ----
create table public.rate_limit_rules (
  key            text primary key,
  description    text not null,
  max_hits       integer not null check (max_hits > 0),
  window_seconds integer not null check (window_seconds between 10 and 2592000),
  enabled        boolean not null default true,
  updated_at     timestamptz not null default now(),
  updated_by     text
);
insert into public.rate_limit_rules (key, description, max_hits, window_seconds) values
  ('access_request_ip',    'Access requests from one network address',          5,   3600),
  ('access_request_email', 'Access requests for one email address',             2,   86400),
  ('report_submit',        'Reports filed by one user',                         10,  3600),
  ('activity_track',       'Activity events recorded for one user',             300, 3600),
  ('data_export',          'Exports and downloads by one user',                 20,  86400),
  ('client_log',           'Browser error reports from one user',               30,  3600),
  ('admin_account_action', 'Account actions (create, reset, suspend) by one admin', 40, 3600);

create table public.rate_limit_counters (
  rule_key     text not null references public.rate_limit_rules (key) on delete cascade,
  subject      text not null,
  window_start timestamptz not null,
  hits         integer not null default 1,
  primary key (rule_key, subject, window_start)
);
create index rate_limit_counters_window_idx on public.rate_limit_counters (window_start);

-- Counts one hit and returns false when the subject is over the limit.
-- Callers must return an error value, not raise, or the count is rolled back.
create or replace function public.rate_limit_hit(p_rule text, p_subject text) returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.rate_limit_rules; w timestamptz; h integer;
begin
  select * into r from public.rate_limit_rules where key = p_rule and enabled;
  if not found then return true; end if;
  w := to_timestamp(floor(extract(epoch from now()) / r.window_seconds) * r.window_seconds);
  insert into public.rate_limit_counters (rule_key, subject, window_start, hits)
  values (p_rule, coalesce(nullif(p_subject, ''), 'unknown'), w, 1)
  on conflict (rule_key, subject, window_start)
  do update set hits = public.rate_limit_counters.hits + 1
  returning hits into h;
  if h > r.max_hits then
    if h = r.max_hits + 1 then
      insert into public.system_log (level, source, event, message, context, user_id, ip_hash)
      values ('warn', 'rate_limit', 'rate_limit.block', r.description,
              jsonb_build_object('rule', p_rule, 'subject', p_subject, 'max_hits', r.max_hits,
                                 'window_seconds', r.window_seconds),
              auth.uid(), public.request_ip_hash());
    end if;
    return false;
  end if;
  return true;
end $$;

-- ------------------------------------------------------- access requests ----
create table public.signup_requests (
  id               bigint generated always as identity primary key,
  created_at       timestamptz not null default now(),
  email            text not null,
  contact_name     text not null,
  org_name         text not null,
  org_type         text,
  country_name     text,
  message          text,
  status           text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'spam')),
  existing_account boolean not null default false,
  reviewed_by      text,
  reviewed_at      timestamptz,
  review_note      text,
  tier             text,
  country_id       integer references public.countries (id),
  user_id          uuid,
  ip_hash          text
);
create unique index signup_requests_one_pending on public.signup_requests (lower(email)) where status = 'pending';
create index signup_requests_status_idx on public.signup_requests (status, created_at desc);

-- Public form endpoint. Always answers ok for a well-formed request so the
-- form cannot be used to find out which emails already have an account.
create or replace function public.request_access(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(btrim(coalesce(payload ->> 'email', '')));
  v_name  text := btrim(coalesce(payload ->> 'name', ''));
  v_org   text := btrim(coalesce(payload ->> 'organisation', ''));
  v_ip    text := public.request_ip_hash();
begin
  if coalesce(payload ->> 'website', '') <> '' then  -- hidden field, filled only by bots
    perform public.log_event('warn', 'signup', 'signup.honeypot', 'Access request dropped (hidden field filled)',
                             jsonb_build_object('email', left(v_email, 254)));
    return jsonb_build_object('ok', true);
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' or length(v_email) > 254
     or v_name = '' or v_org = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if not public.rate_limit_hit('access_request_ip', v_ip)
     or not public.rate_limit_hit('access_request_email', v_email) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  if exists (select 1 from public.signup_requests where lower(email) = v_email and status = 'pending') then
    return jsonb_build_object('ok', true);
  end if;
  insert into public.signup_requests (email, contact_name, org_name, org_type, country_name, message, existing_account, ip_hash)
  values (v_email, left(v_name, 200), left(v_org, 200), left(nullif(btrim(payload ->> 'org_type'), ''), 100),
          left(nullif(btrim(payload ->> 'country'), ''), 100), left(nullif(btrim(payload ->> 'message'), ''), 2000),
          exists (select 1 from public.user_access where lower(email) = v_email), v_ip);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------- user reports ----
create table public.user_reports (
  id                  bigint generated always as identity primary key,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  kind                text not null check (kind in ('data_issue', 'support', 'bug', 'abuse')),
  subject_type        text,
  subject_id          text,
  subject_label       text,
  title               text not null,
  body                text,
  page_url            text,
  reporter_id         uuid,
  reporter_email      text,
  reporter_country_id integer,
  status              text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'dismissed')),
  priority            text not null default 'normal' check (priority in ('low', 'normal', 'high')),
  assigned_to         text,
  resolution_note     text,
  resolved_at         timestamptz,
  resolved_by         text
);
create index user_reports_status_idx on public.user_reports (status, created_at desc);
create index user_reports_reporter_idx on public.user_reports (reporter_id);

create or replace function public.report_submit(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_acc   jsonb := public.my_access();
  v_kind  text := coalesce(payload ->> 'kind', '');
  v_title text := btrim(coalesce(payload ->> 'title', ''));
  v_id    bigint;
begin
  if v_uid is null or (coalesce(v_acc ->> 'role', 'none') = 'none' and public.admin_level() is null) then
    return jsonb_build_object('ok', false, 'error', 'not_authorised');
  end if;
  if v_kind not in ('data_issue', 'support', 'bug', 'abuse') or v_title = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if not public.rate_limit_hit('report_submit', v_uid::text) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  insert into public.user_reports (kind, subject_type, subject_id, subject_label, title, body, page_url,
                                   reporter_id, reporter_email, reporter_country_id)
  values (v_kind, left(payload ->> 'subject_type', 40), left(payload ->> 'subject_id', 80),
          left(payload ->> 'subject_label', 300), left(v_title, 200), left(payload ->> 'body', 4000),
          left(payload ->> 'page_url', 500), v_uid, auth.jwt() ->> 'email',
          nullif(v_acc ->> 'country_id', '')::integer)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.my_reports() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'created_at', r.created_at, 'kind', r.kind, 'title', r.title, 'subject_label', r.subject_label,
           'status', r.status, 'resolution_note', r.resolution_note, 'resolved_at', r.resolved_at)
         order by r.created_at desc), '[]'::jsonb)
  from public.user_reports r where r.reporter_id = auth.uid()
$$;

-- --------------------------------------------------------- user activity ----
create table public.user_activity (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  user_id uuid not null,
  email   text,
  event   text not null,
  detail  jsonb,
  ip_hash text
);
create index user_activity_user_idx on public.user_activity (user_id, at desc);
create index user_activity_at_idx on public.user_activity (at desc);

create or replace function public.track_activity(p_event text, p_detail jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or p_event not in ('signin', 'signout', 'view', 'search', 'export', 'download') then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if p_event in ('export', 'download') and not public.rate_limit_hit('data_export', v_uid::text) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  if not public.rate_limit_hit('activity_track', v_uid::text) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  insert into public.user_activity (user_id, email, event, detail, ip_hash)
  values (v_uid, auth.jwt() ->> 'email', p_event,
          case when p_detail is not null and pg_column_size(p_detail) <= 2000 then p_detail end,
          public.request_ip_hash());
  return jsonb_build_object('ok', true);
end $$;

-- Browser errors from signed-in users, shown in the console's log view.
create or replace function public.client_log(p_event text, p_message text default null, p_context jsonb default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return jsonb_build_object('ok', false); end if;
  if not public.rate_limit_hit('client_log', v_uid::text) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  perform public.log_event('error', 'browser', left(coalesce(p_event, 'client.error'), 120), p_message,
          case when p_context is not null and pg_column_size(p_context) <= 2000 then p_context end);
  return jsonb_build_object('ok', true);
end $$;

-- ------------------------------------------------------- metrics history ----
create table public.metrics_daily (
  day  date primary key,
  data jsonb not null
);

-- ------------------------------------------------------- audit triggers ----
create trigger audit_user_access after insert or update or delete on public.user_access
  for each row execute function public.audit_row('user_id');
create trigger audit_allowlist after insert or update or delete on public.allowlist
  for each row execute function public.audit_row('email');
create trigger audit_admin_staff after insert or update or delete on public.admin_staff
  for each row execute function public.audit_row('email');
create trigger audit_admin_settings after insert or update or delete on public.admin_settings
  for each row execute function public.audit_row('key');
create trigger audit_rate_limit_rules after insert or update or delete on public.rate_limit_rules
  for each row execute function public.audit_row('key');
create trigger audit_signup_requests after update or delete on public.signup_requests
  for each row execute function public.audit_row('id');
create trigger audit_user_reports after update or delete on public.user_reports
  for each row execute function public.audit_row('id');

-- =========================================================== admin RPCs ====

create or replace function public.admin_lookups() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return jsonb_build_object(
    'level', lv,
    'email', auth.jwt() ->> 'email',
    'tiers', jsonb_build_array('free', 'explorer', 'bureau', 'bureau_plus'),
    'countries', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb)
                  from public.countries));
end $$;

create or replace function public.admin_metrics() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return jsonb_build_object(
    'generated_at', now(),
    'accounts', (
      select jsonb_build_object(
        'total', count(*), 'active', count(*) filter (where active),
        'suspended', count(*) filter (where not active),
        'awaiting_first_signin', count(*) filter (where active and must_change_password),
        'by_tier', (select coalesce(jsonb_object_agg(t, n), '{}'::jsonb)
                    from (select coalesce(tier, 'none') t, count(*) n from public.user_access
                          where role = 'bureau' group by 1) x))
      from public.user_access where role = 'bureau'),
    'team', jsonb_build_object(
      'super', (select count(*) from public.allowlist),
      'staff', (select count(*) from public.admin_staff where active)),
    'signups', (
      select jsonb_build_object(
        'pending', count(*) filter (where status = 'pending'),
        'last_7d', count(*) filter (where created_at > now() - interval '7 days'),
        'oldest_pending_days', coalesce(extract(day from now() - min(created_at) filter (where status = 'pending')), 0))
      from public.signup_requests),
    'reports', (
      select jsonb_build_object(
        'open', count(*) filter (where status = 'open'),
        'in_progress', count(*) filter (where status = 'in_progress'),
        'resolved_7d', count(*) filter (where status in ('resolved', 'dismissed') and resolved_at > now() - interval '7 days'),
        'open_by_kind', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb)
                         from (select kind, count(*) n from public.user_reports
                               where status in ('open', 'in_progress') group by 1) x))
      from public.user_reports),
    'activity', jsonb_build_object(
      'active_24h', (select count(distinct user_id) from public.user_activity where at > now() - interval '1 day'),
      'active_7d',  (select count(distinct user_id) from public.user_activity where at > now() - interval '7 days'),
      'active_30d', (select count(distinct user_id) from public.user_activity where at > now() - interval '30 days'),
      'signins_7d', (select count(*) from public.user_activity where event = 'signin' and at > now() - interval '7 days'),
      'events_24h', (select count(*) from public.user_activity where at > now() - interval '1 day'),
      'signed_in_7d', (select count(*) from auth.users where last_sign_in_at > now() - interval '7 days')),
    'security', jsonb_build_object(
      'rate_limit_blocks_24h', (select count(*) from public.system_log where event = 'rate_limit.block' and at > now() - interval '1 day'),
      'errors_24h',   (select count(*) from public.system_log where level = 'error' and at > now() - interval '1 day'),
      'warnings_24h', (select count(*) from public.system_log where level = 'warn' and at > now() - interval '1 day'),
      'cron_failed_7d', (select count(*) from cron.job_run_details where status = 'failed' and start_time > now() - interval '7 days'),
      'http_failed_7d', (select count(*) from net._http_response
                         where created > now() - interval '7 days'
                           and (status_code >= 400 or error_msg is not null or timed_out)),
      'audit_entries_7d', (select count(*) from public.admin_audit_log where at > now() - interval '7 days')),
    'data', jsonb_build_object(
      'events', (select count(*) from public.events),
      'opportunities', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb)
                        from (select list_status::text s, count(*) n from public.bid_opportunities group by 1) x),
      'bid_wins', (select count(*) from public.bid_wins),
      'event_submissions_in_review', (select count(*) from public.submissions where status = 'review')),
    'system', jsonb_build_object(
      'db_size_bytes', pg_database_size(current_database()),
      'db_size', pg_size_pretty(pg_database_size(current_database())),
      'connections', (select count(*) from pg_stat_activity where datname = current_database()),
      'largest_tables', (
        select coalesce(jsonb_agg(jsonb_build_object('table', relname, 'size', pg_size_pretty(sz), 'rows', n_live_tup)
                                  order by sz desc), '[]'::jsonb)
        from (select relname, pg_total_relation_size(relid) sz, n_live_tup
              from pg_stat_user_tables where schemaname = 'public'
              order by pg_total_relation_size(relid) desc limit 8) t),
      'jobs', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'job', j.jobname, 'schedule', j.schedule, 'active', j.active, 'last_status', d.status,
                 'last_run', d.start_time, 'message', left(d.return_message, 200)) order by j.jobname), '[]'::jsonb)
        from cron.job j
        left join lateral (select status, start_time, return_message from cron.job_run_details r
                           where r.jobid = j.jobid order by r.start_time desc limit 1) d on true)),
    'trend', (select coalesce(jsonb_agg(jsonb_build_object('day', day) || data order by day), '[]'::jsonb)
              from (select day, data from public.metrics_daily order by day desc limit 30) m));
end $$;

-- Combined log view: application log, scheduled jobs and failed outbound calls.
-- Filter keys: source, level, q, hours, limit.
create or replace function public.admin_logs(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  lv      text := public.admin_guard('staff');
  v_src   text := nullif(p_filter ->> 'source', '');
  v_level text := nullif(p_filter ->> 'level', '');
  v_q     text := nullif(btrim(p_filter ->> 'q'), '');
  v_since timestamptz := now() - make_interval(hours => least(coalesce((p_filter ->> 'hours')::integer, 168), 2400));
  v_limit integer := least(coalesce((p_filter ->> 'limit')::integer, 200), 500);
begin
  return (
    select coalesce(jsonb_agg(to_jsonb(l) order by l.at desc), '[]'::jsonb) from (
      select * from (
        select s.at, s.level, s.source, s.event, s.message, s.context,
               (select u.email from auth.users u where u.id = s.user_id) as user_email
        from public.system_log s
        union all
        select d.start_time, case d.status when 'failed' then 'error' else 'info' end, 'cron',
               'cron.' || coalesce(j.jobname, d.jobid::text), left(d.return_message, 500),
               jsonb_build_object('status', d.status,
                                  'seconds', round(extract(epoch from d.end_time - d.start_time)::numeric, 1)),
               null
        from cron.job_run_details d left join cron.job j on j.jobid = d.jobid
        union all
        select h.created, 'error', 'http', 'http.failed',
               coalesce(h.error_msg, 'HTTP ' || h.status_code), jsonb_build_object('status_code', h.status_code,
               'timed_out', h.timed_out), null
        from net._http_response h
        where h.status_code >= 400 or h.error_msg is not null or h.timed_out
      ) a
      where a.at >= v_since
        and (v_src is null or a.source = v_src)
        and (v_level is null or a.level = v_level)
        and (v_q is null or a.event ilike '%' || v_q || '%' or a.message ilike '%' || v_q || '%'
             or a.user_email ilike '%' || v_q || '%')
      order by a.at desc limit v_limit
    ) l);
end $$;

-- Audit trail: this console's log plus the partner-profile review audit.
-- Filter keys: entity, actor, q, days, limit.
create or replace function public.admin_audit(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  lv       text := public.admin_guard('staff');
  v_entity text := nullif(p_filter ->> 'entity', '');
  v_actor  text := nullif(btrim(p_filter ->> 'actor'), '');
  v_q      text := nullif(btrim(p_filter ->> 'q'), '');
  v_since  timestamptz := now() - make_interval(days => least(coalesce((p_filter ->> 'days')::integer, 30), 3650));
  v_limit  integer := least(coalesce((p_filter ->> 'limit')::integer, 200), 500);
begin
  return (
    select coalesce(jsonb_agg(to_jsonb(l) order by l.at desc), '[]'::jsonb) from (
      select * from (
        select a.at, a.actor, a.action, a.entity, a.entity_id, a.summary, a.old_row, a.new_row
        from public.admin_audit_log a
        union all
        select p.at, p.actor, 'profile.' || p.action, p.table_name, p.row_id, null, p.old_row, p.new_row
        from public.profile_review_audit p
      ) x
      where x.at >= v_since
        and (v_entity is null or x.entity = v_entity)
        and (v_actor is null or x.actor ilike '%' || v_actor || '%')
        and (v_q is null or x.action ilike '%' || v_q || '%' or x.entity_id ilike '%' || v_q || '%'
             or x.summary ilike '%' || v_q || '%')
      order by x.at desc limit v_limit
    ) l);
end $$;

-- ------------------------------------------------------------- signups ----
create or replace function public.admin_signups(p_status text default 'pending') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (select s.id, s.created_at, s.email, s.contact_name, s.org_name, s.org_type, s.country_name, s.message,
                 s.status, s.existing_account, s.reviewed_by, s.reviewed_at, s.review_note, s.tier, s.country_id,
                 (select count(*) from public.signup_requests o where o.ip_hash = s.ip_hash and o.id <> s.id
                    and o.created_at > s.created_at - interval '7 days') as same_network_7d
          from public.signup_requests s
          where p_status is null or p_status = 'all' or s.status = p_status
          order by s.created_at desc limit 500) x);
end $$;

-- Reject, mark as spam or reopen. Approval creates a login, so it goes through
-- the bureau-admin edge function, which then marks the request approved.
create or replace function public.admin_signup_decide(p_id bigint, p_decision text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('staff'); r public.signup_requests;
begin
  if p_decision not in ('rejected', 'spam', 'pending') then
    raise exception 'Decision must be rejected, spam or pending';
  end if;
  select * into r from public.signup_requests where id = p_id for update;
  if not found then raise exception 'Request not found'; end if;
  if r.status = 'approved' then raise exception 'This request already has a login'; end if;
  update public.signup_requests
     set status = p_decision,
         reviewed_by = case when p_decision = 'pending' then null else public.admin_actor() end,
         reviewed_at = case when p_decision = 'pending' then null else now() end,
         review_note = left(nullif(btrim(p_note), ''), 1000)
   where id = p_id;
  return jsonb_build_object('ok', true, 'status', p_decision);
end $$;

-- ------------------------------------------------------------- reports ----
create or replace function public.admin_reports(p_filter jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  lv       text := public.admin_guard('staff');
  v_status text := nullif(p_filter ->> 'status', '');
  v_kind   text := nullif(p_filter ->> 'kind', '');
begin
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (select r.*, c.name as reporter_country
          from public.user_reports r left join public.countries c on c.id = r.reporter_country_id
          where (v_kind is null or r.kind = v_kind)
            and (case coalesce(v_status, 'active')
                   when 'all' then true
                   when 'active' then r.status in ('open', 'in_progress')
                   else r.status = v_status end)
          order by r.created_at desc limit 500) x);
end $$;

-- Patch keys: status, priority, assigned_to, resolution_note.
create or replace function public.admin_report_update(p_id bigint, patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('staff'); r public.user_reports; v_status text;
begin
  select * into r from public.user_reports where id = p_id for update;
  if not found then raise exception 'Report not found'; end if;
  v_status := coalesce(patch ->> 'status', r.status);
  update public.user_reports
     set status = v_status,
         priority = coalesce(patch ->> 'priority', priority),
         assigned_to = case when patch ? 'assigned_to' then nullif(btrim(patch ->> 'assigned_to'), '') else assigned_to end,
         resolution_note = case when patch ? 'resolution_note' then left(nullif(btrim(patch ->> 'resolution_note'), ''), 2000)
                                else resolution_note end,
         resolved_at = case when v_status in ('resolved', 'dismissed') then coalesce(resolved_at, now()) else null end,
         resolved_by = case when v_status in ('resolved', 'dismissed') then coalesce(resolved_by, public.admin_actor()) else null end,
         updated_at = now()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- ------------------------------------------------------------ accounts ----
create or replace function public.admin_users() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (select ua.user_id, ua.email, ua.org_name, ua.contact_name, ua.country_id, c.name as country, ua.tier,
                 ua.active, ua.must_change_password,
                 (ua.must_change_password
                    and coalesce(ua.temp_password_issued_at, ua.created_at) < now() - interval '7 days') as temp_password_expired,
                 ua.created_at, ua.first_signin_completed_at, u.last_sign_in_at,
                 (select max(a.at) from public.user_activity a where a.user_id = ua.user_id) as last_active_at,
                 (select count(*) from public.user_activity a
                   where a.user_id = ua.user_id and a.at > now() - interval '30 days') as activity_30d,
                 (select count(*) from public.user_reports r
                   where r.reporter_id = ua.user_id and r.status in ('open', 'in_progress')) as open_reports
          from public.user_access ua
          left join public.countries c on c.id = ua.country_id
          left join auth.users u on u.id = ua.user_id
          where ua.role = 'bureau') x);
end $$;

-- Patch keys: org_name, contact_name, country_id, tier. Super admins only.
-- Suspend, reinstate and password reset go through the bureau-admin edge
-- function because they also change the sign-in itself.
create or replace function public.admin_user_update(p_user_id uuid, patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super');
begin
  if patch ? 'tier' and (patch ->> 'tier') not in ('free', 'explorer', 'bureau', 'bureau_plus') then
    raise exception 'Unknown tier';
  end if;
  update public.user_access
     set org_name = case when patch ? 'org_name' then left(nullif(btrim(patch ->> 'org_name'), ''), 200) else org_name end,
         contact_name = case when patch ? 'contact_name' then left(nullif(btrim(patch ->> 'contact_name'), ''), 200) else contact_name end,
         country_id = case when patch ? 'country_id' then (patch ->> 'country_id')::integer else country_id end,
         tier = case when patch ? 'tier' then patch ->> 'tier' else tier end
   where user_id = p_user_id and role = 'bureau';
  if not found then raise exception 'Account not found'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_user_activity(p_user_id uuid default null, p_limit integer default 200)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return jsonb_build_object(
    'by_user', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.events_30d desc), '[]'::jsonb)
      from (select a.user_id, max(a.email) as email, max(ua.org_name) as org_name, max(c.name) as country,
                   count(*) as events_30d,
                   count(*) filter (where a.event = 'signin') as signins_30d,
                   count(*) filter (where a.event = 'view') as views_30d,
                   count(*) filter (where a.event in ('export', 'download')) as exports_30d,
                   count(distinct a.ip_hash) as networks_30d,
                   max(a.at) as last_active_at
            from public.user_activity a
            left join public.user_access ua on ua.user_id = a.user_id
            left join public.countries c on c.id = ua.country_id
            where a.at > now() - interval '30 days'
            group by a.user_id) x),
    'recent', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.at desc), '[]'::jsonb)
      from (select a.at, a.user_id, a.email, a.event, a.detail
            from public.user_activity a
            where p_user_id is null or a.user_id = p_user_id
            order by a.at desc limit least(coalesce(p_limit, 200), 500)) x));
end $$;

-- ---------------------------------------------------------------- team ----
create or replace function public.admin_team() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('super');
begin
  return jsonb_build_object(
    'super', (select coalesce(jsonb_agg(jsonb_build_object(
                 'email', a.email, 'added_at', a.added_at,
                 'has_login', u.id is not null, 'last_sign_in_at', u.last_sign_in_at) order by a.email), '[]'::jsonb)
              from public.allowlist a left join auth.users u on lower(u.email) = lower(a.email)),
    'staff', (select coalesce(jsonb_agg(jsonb_build_object(
                 'email', s.email, 'full_name', s.full_name, 'role', s.role, 'active', s.active,
                 'added_by', s.added_by, 'added_at', s.added_at,
                 'has_login', u.id is not null, 'last_sign_in_at', u.last_sign_in_at) order by s.email), '[]'::jsonb)
              from public.admin_staff s left join auth.users u on lower(u.email) = s.email));
end $$;

create or replace function public.admin_staff_set(p_email text, p_full_name text default null, p_active boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super'); v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' then raise exception 'Enter a valid email'; end if;
  if exists (select 1 from public.allowlist where lower(email) = v_email) then
    raise exception 'That email is already a super admin';
  end if;
  if exists (select 1 from public.user_access where lower(email) = v_email) then
    raise exception 'That email is a bureau login and cannot also be staff';
  end if;
  insert into public.admin_staff (email, full_name, active, added_by)
  values (v_email, left(nullif(btrim(p_full_name), ''), 200), coalesce(p_active, true), public.admin_actor())
  on conflict (email) do update
    set full_name = coalesce(excluded.full_name, public.admin_staff.full_name), active = excluded.active;
  return jsonb_build_object('ok', true, 'email', v_email);
end $$;

create or replace function public.admin_staff_remove(p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super');
begin
  delete from public.admin_staff where email = lower(btrim(p_email));
  return jsonb_build_object('ok', found);
end $$;

-- --------------------------------------------------- rate limit control ----
create or replace function public.admin_rate_limits() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return jsonb_build_object(
    'rules', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'key', r.key, 'description', r.description, 'max_hits', r.max_hits,
               'window_seconds', r.window_seconds, 'enabled', r.enabled, 'updated_at', r.updated_at,
               'updated_by', r.updated_by,
               'blocks_24h', (select count(*) from public.system_log l
                               where l.event = 'rate_limit.block' and l.context ->> 'rule' = r.key
                                 and l.at > now() - interval '1 day'),
               'hits_now', (select coalesce(sum(c.hits), 0) from public.rate_limit_counters c
                             where c.rule_key = r.key
                               and c.window_start > now() - make_interval(secs => r.window_seconds)))
             order by r.key), '[]'::jsonb)
      from public.rate_limit_rules r),
    'blocked_now', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'rule', c.rule_key, 'subject', c.subject, 'hits', c.hits, 'max_hits', r.max_hits,
               'until', c.window_start + make_interval(secs => r.window_seconds),
               'label', coalesce((select u.email from auth.users u where u.id::text = c.subject),
                                 case when c.subject like '%@%' then c.subject else 'network ' || left(c.subject, 10) end))
             order by c.window_start desc), '[]'::jsonb)
      from public.rate_limit_counters c join public.rate_limit_rules r on r.key = c.rule_key
      where c.hits > r.max_hits and c.window_start + make_interval(secs => r.window_seconds) > now()),
    'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'value', value, 'description', description)
                                           order by key), '[]'::jsonb) from public.admin_settings));
end $$;

-- Patch keys: max_hits, window_seconds, enabled.
create or replace function public.admin_rate_limit_set(p_key text, patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super');
begin
  update public.rate_limit_rules
     set max_hits = coalesce((patch ->> 'max_hits')::integer, max_hits),
         window_seconds = coalesce((patch ->> 'window_seconds')::integer, window_seconds),
         enabled = coalesce((patch ->> 'enabled')::boolean, enabled),
         updated_at = now(), updated_by = public.admin_actor()
   where key = p_key;
  if not found then raise exception 'Rule not found'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Lifts a current block (for example a colleague who tripped a limit).
create or replace function public.admin_rate_limit_clear(p_rule text, p_subject text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super'); n integer;
begin
  delete from public.rate_limit_counters where rule_key = p_rule and subject = p_subject;
  get diagnostics n = row_count;
  perform public.audit_write('rate_limit.clear', 'rate_limit_counters', p_rule, 'Cleared block for ' || p_subject);
  return jsonb_build_object('ok', true, 'cleared', n);
end $$;

create or replace function public.admin_setting_set(p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super');
begin
  if p_key in ('log_retention_days', 'activity_retention_days')
     and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric not between 7 and 3650) then
    raise exception 'Retention must be between 7 and 3650 days';
  end if;
  update public.admin_settings set value = p_value, updated_at = now(), updated_by = public.admin_actor()
   where key = p_key;
  if not found then raise exception 'Setting not found'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------- nightly housekeeping ----
create or replace function public.admin_maintenance() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_log integer := coalesce((select (value #>> '{}')::integer from public.admin_settings where key = 'log_retention_days'), 90);
  v_act integer := coalesce((select (value #>> '{}')::integer from public.admin_settings where key = 'activity_retention_days'), 180);
begin
  insert into public.metrics_daily (day, data)
  values (current_date, jsonb_build_object(
    'accounts_active', (select count(*) from public.user_access where role = 'bureau' and active),
    'active_users',    (select count(distinct user_id) from public.user_activity where at > now() - interval '1 day'),
    'activity_events', (select count(*) from public.user_activity where at > now() - interval '1 day'),
    'signups_pending', (select count(*) from public.signup_requests where status = 'pending'),
    'reports_open',    (select count(*) from public.user_reports where status in ('open', 'in_progress')),
    'errors',          (select count(*) from public.system_log where level = 'error' and at > now() - interval '1 day'),
    'rate_limit_blocks', (select count(*) from public.system_log where event = 'rate_limit.block' and at > now() - interval '1 day'),
    'db_size_bytes',   pg_database_size(current_database())))
  on conflict (day) do update set data = excluded.data;

  delete from public.rate_limit_counters where window_start < now() - interval '31 days';
  delete from public.system_log where at < now() - make_interval(days => v_log);
  delete from public.user_activity where at < now() - make_interval(days => v_act);
end $$;

select cron.schedule('admin_maintenance_nightly', '45 2 * * *', 'select public.admin_maintenance()');

-- ------------------------------------------------------------ privileges ----
alter table public.admin_staff          enable row level security;
alter table public.admin_settings       enable row level security;
alter table public.admin_audit_log      enable row level security;
alter table public.system_log           enable row level security;
alter table public.rate_limit_rules     enable row level security;
alter table public.rate_limit_counters  enable row level security;
alter table public.signup_requests      enable row level security;
alter table public.user_reports         enable row level security;
alter table public.user_activity        enable row level security;
alter table public.metrics_daily        enable row level security;

revoke all on public.admin_staff, public.admin_settings, public.admin_audit_log, public.system_log,
  public.rate_limit_rules, public.rate_limit_counters, public.signup_requests, public.user_reports,
  public.user_activity, public.metrics_daily from anon, authenticated;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'admin_level', 'admin_guard', 'admin_actor', 'admin_audit_immutable', 'audit_write', 'audit_row', 'log_event',
      'rate_limit_hit', 'request_access', 'report_submit', 'my_reports', 'track_activity', 'client_log',
      'admin_lookups', 'admin_metrics', 'admin_logs', 'admin_audit', 'admin_signups', 'admin_signup_decide',
      'admin_reports', 'admin_report_update', 'admin_users', 'admin_user_update', 'admin_user_activity',
      'admin_team', 'admin_staff_set', 'admin_staff_remove', 'admin_rate_limits', 'admin_rate_limit_set',
      'admin_rate_limit_clear', 'admin_setting_set', 'admin_maintenance')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('audit_write', 'log_event', 'rate_limit_hit') then
      execute format('grant execute on function %s to service_role', f.sig);
    elsif f.proname = 'request_access' then
      execute format('grant execute on function %s to anon, authenticated, service_role', f.sig);
    elsif f.proname not in ('admin_audit_immutable', 'audit_row', 'admin_maintenance', 'admin_guard', 'admin_actor') then
      execute format('grant execute on function %s to authenticated, service_role', f.sig);
    end if;
  end loop;
end $$;
