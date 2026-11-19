-- Close the admin console gaps from the handover (task 5).
-- 1. Staff first sign-in: a staff login with a temporary password has no
--    console access until it confirms its email with a code and sets its own
--    password, as bureau logins already must. The bureau-admin function sets
--    the flag on create and reset.
-- 2. Readable audit entries for signup Reject, Spam and Reopen.
-- 3. Read throttling: bureau_portal() and bureau_matches() count each bureau
--    read against a new portal_read rule and return an error value over it.

-- ---------- 1. staff first sign-in ----------
alter table public.admin_staff
  add column if not exists must_change_password boolean not null default false,
  add column if not exists temp_password_issued_at timestamptz,
  add column if not exists password_changed_at timestamptz,
  add column if not exists first_signin_completed_at timestamptz;

-- Record password changes for staff as well as bureau logins.
create or replace function public.track_password_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update public.user_access set password_changed_at = now() where user_id = new.id;
    update public.admin_staff set password_changed_at = now() where email = lower(new.email);
  end if;
  return new;
end
$function$;

-- Staff who still owe their first sign-in get no admin level.
create or replace function public.admin_level()
returns text
language sql
stable security definer
set search_path to 'public'
as $function$
  select case
    when public.is_allowlisted() then 'super'
    when exists (
      select 1 from public.admin_staff s
      join auth.users u on lower(u.email) = s.email
      where u.id = auth.uid() and s.active and not s.must_change_password
        and u.email_confirmed_at is not null
        and (u.banned_until is null or u.banned_until < now())
    ) then 'staff'
  end
$function$;

-- What the console needs to show a signed-in staff member who has not
-- finished first sign-in. Returns null for anyone who is not active staff.
create or replace function public.staff_signin_state()
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'must_change_password', s.must_change_password,
    'expired', s.must_change_password
               and coalesce(s.temp_password_issued_at, s.added_at) < now() - interval '7 days')
  from public.admin_staff s
  join auth.users u on lower(u.email) = s.email
  where u.id = auth.uid() and s.active
$function$;

create or replace function public.staff_complete_first_signin()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s public.admin_staff%rowtype;
  issued timestamptz;
  otp_at timestamptz;
begin
  select st.* into s from public.admin_staff st
    join auth.users u on lower(u.email) = st.email
   where u.id = auth.uid() and st.active;
  if not found then
    raise exception 'No active staff login.' using errcode = '42501';
  end if;
  if not s.must_change_password then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  issued := coalesce(s.temp_password_issued_at, s.added_at);
  if issued < now() - interval '7 days' then
    raise exception 'The temporary password has expired. Ask a super admin for a new one.' using errcode = '42501';
  end if;

  select max(to_timestamp((e ->> 'timestamp')::double precision)) into otp_at
  from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) e
  where e ->> 'method' in ('otp', 'magiclink');
  if otp_at is null or otp_at < issued - interval '1 minute' then
    raise exception 'Confirm your email with the code we sent before continuing.' using errcode = '42501';
  end if;

  if s.password_changed_at is null or s.password_changed_at <= issued then
    raise exception 'Set a new password before continuing.' using errcode = '42501';
  end if;

  update public.admin_staff
     set must_change_password = false, first_signin_completed_at = now()
   where email = s.email;
  perform public.audit_write('staff.first_signin', 'admin_staff', s.email,
                             'First sign-in completed by staff member ' || s.email, null, null, s.email);
  return jsonb_build_object('ok', true);
end
$function$;

revoke execute on function public.staff_signin_state() from public, anon;
revoke execute on function public.staff_complete_first_signin() from public, anon;
grant execute on function public.staff_signin_state() to authenticated;
grant execute on function public.staff_complete_first_signin() to authenticated;

-- Show staff who have not finished first sign-in on the Team screen.
create or replace function public.admin_team()
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
                 'must_change_password', s.must_change_password,
                 'has_login', u.id is not null, 'last_sign_in_at', u.last_sign_in_at) order by s.email), '[]'::jsonb)
              from public.admin_staff s left join auth.users u on lower(u.email) = s.email));
end $function$;

-- ---------- 2. readable signup decision audit entries ----------
create or replace function public.admin_signup_decide(p_id bigint, p_decision text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  perform public.audit_write(
    case p_decision when 'rejected' then 'signup.reject' when 'spam' then 'signup.spam' else 'signup.reopen' end,
    'signup_requests', p_id::text,
    case p_decision when 'rejected' then 'Rejected' when 'spam' then 'Marked as spam' else 'Reopened' end
      || ' the access request from ' || r.email
      || coalesce(' (' || left(nullif(btrim(p_note), ''), 200) || ')', ''),
    null, null, public.admin_actor());
  return jsonb_build_object('ok', true, 'status', p_decision);
end $function$;

-- ---------- 3. read throttling for the bureau portal ----------
insert into public.rate_limit_rules (key, description, max_hits, window_seconds, enabled)
values ('portal_read', 'Portal data loads by one bureau login', 120, 3600, true)
on conflict (key) do nothing;

create or replace function public.bureau_portal()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare cid int; res jsonb; t text;
begin
  cid := public.bureau_country_id();
  if cid is null then return jsonb_build_object('error','not_a_bureau'); end if;
  t := public.my_tier();
  if t is null then return jsonb_build_object('error','no_tier'); end if;
  -- Return an error value, never raise, so the counted hit is kept.
  if not public.rate_limit_hit('portal_read', auth.uid()::text) then
    return jsonb_build_object('error','rate_limited');
  end if;
  update public.user_access set last_seen_at = now() where user_id = auth.uid();
  res := public.portal_data(cid);
  return res || jsonb_build_object('tier', t, 'org', (select jsonb_build_object('org_name',org_name,'contact_name',contact_name,'email',email) from public.user_access where user_id=auth.uid()));
end $function$;

-- Now volatile, because a bureau read is counted against portal_read.
create or replace function public.bureau_matches(p_country_id integer default null, p_tier text default null)
returns jsonb
language plpgsql
volatile security definer
set search_path to 'public'
as $function$
declare cid int; t text; res jsonb;
begin
  if public.is_allowlisted() then
    cid := p_country_id; t := coalesce(p_tier, 'bureau_plus');
    if cid is null then raise exception 'country required'; end if;
  else
    cid := public.bureau_country_id(); t := public.my_tier();
    if cid is null then return jsonb_build_object('error','not_a_bureau'); end if;
    if not public.rate_limit_hit('portal_read', auth.uid()::text) then
      return jsonb_build_object('error','rate_limited');
    end if;
  end if;

  select coalesce(jsonb_agg(row_j order by (row_j->>'rank')::int), '[]'::jsonb) into res
  from (
    select jsonb_build_object(
      'rank', row_number() over (order by ms.score desc, o.submission_deadline nulls last, o.id),
      'id', o.id, 'title', o.title, 'issuing_body', o.issuing_body, 'status', o.list_status,
      'deadline', o.submission_deadline, 'host_year', o.host_year,
      'delegates_min', o.delegates_min, 'delegates_max', o.delegates_max,
      'host_type', o.host_type, 'next_action', o.next_action, 'source_url', o.primary_source_url,
      'score', ms.score, 'sub_scores', ms.sub_scores, 'reasons', to_jsonb(ms.reasons), 'gaps', to_jsonb(ms.gaps),
      'confidence', ms.confidence, 'scored_on', ms.scored_on,
      'competitors', (
        select coalesce(jsonb_agg(case when t = 'bureau_plus'
                   then jsonb_build_object('score', c2.score, 'name', c.name, 'iso2', c.iso2)
                   else jsonb_build_object('score', c2.score) end order by c2.score desc), '[]'::jsonb)
        from (select ms2.country_id, ms2.score from public.match_scores ms2
              join public.countries cc on cc.id = ms2.country_id and cc.type = 'country'
              where ms2.opportunity_id = o.id and ms2.country_id <> cid
              order by ms2.score desc, ms2.country_id limit 3) c2
        join public.countries c on c.id = c2.country_id)
    ) row_j
    from public.match_scores ms
    join public.bid_opportunities o on o.id = ms.opportunity_id
    where ms.country_id = cid and o.list_status in ('open','watchlist')
      and (o.submission_deadline is null or o.submission_deadline >= current_date)
  ) x;

  return jsonb_build_object('country_id', cid, 'tier', t, 'matches', res);
end $function$;
