-- IP website changes W1, W2, W8 and W11 (Africa MICE Dashboard IP website changes, 19 Nov 2026).
-- Legal wording lives in legal_documents so it can change after legal review without a code change.
-- Bodies use the token {owner}; the pages replace it with the owner entity from legal.config.json.

create table public.legal_documents (
  id            bigint generated always as identity primary key,
  doc_type      text not null check (doc_type in ('submission_licence', 'terms_of_access', 'data_notice')),
  version       integer not null check (version > 0),
  title         text not null,
  body          text not null,
  accept_label  text,
  review_status text not null default 'draft_for_review' check (review_status in ('draft_for_review', 'approved')),
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  created_by    text,
  unique (doc_type, version)
);
alter table public.legal_documents enable row level security;
comment on table public.legal_documents is
  'Versioned legal wording (submission licence, Terms of Access, data notice). No policies on purpose: read through legal_document(), published through admin_legal_publish().';

create table public.terms_acceptances (
  id          bigint generated always as identity primary key,
  user_id     uuid not null,
  email       text,
  org_name    text,
  country_id  integer references public.countries(id),
  doc_type    text not null default 'terms_of_access',
  version     integer not null,
  accepted_at timestamptz not null default now(),
  ip_hash     text,
  unique (user_id, doc_type, version)
);
alter table public.terms_acceptances enable row level security;
comment on table public.terms_acceptances is
  'One row per user per accepted Terms of Access version. No policies on purpose: written by terms_accept(), read by admin_terms_acceptances().';

insert into public.legal_documents (doc_type, version, title, body, accept_label, published_at, created_by) values
('submission_licence', 1, 'Submission licence',
 'By submitting this information, you confirm that you have the right to share it, and that it does not include anything confidential you are not permitted to disclose. You grant {owner} a non-exclusive, royalty-free, perpetual and worldwide licence to store, verify, edit, compile, display and share this information as part of the Africa MICE Dashboard and its related services. We may edit, flag as unverified, or decline any submission. You keep ownership of what you submit.',
 'I confirm I have the right to share this information and accept the submission licence above.', now(), 'migration'),
('terms_of_access', 1, 'Terms of Access',
 '1. The Africa MICE Dashboard, including its data compilation, structure, scoring and written content, belongs to {owner}. Your organisation receives a licence to use it for its own bid planning during its subscription.
2. You may not resell, redistribute or publish the data, or share your login outside your organisation.
3. You may not scrape, bulk-download or systematically copy the dashboard, or use it to build a competing product or dataset.
4. Scores, fit ratings and win-factor notes are confidential to your organisation.
5. Records marked unverified are provided as-is. Every record shows its source and the date it was last checked. Verify critical details with the event owner before committing resources.
6. We may correct, flag or remove records at any time.',
 'I accept the Terms of Access on behalf of my organisation.', now(), 'migration'),
('data_notice', 1, 'About this data',
 'Records come from public sources, partner submissions and our own research. Records we have not been able to re-check against a primary source are marked unverified and show the date they were last checked.',
 null, now(), 'migration');

-- Latest published version of a document. Public: the forms and the /legal page read it.
create or replace function public.legal_document(p_type text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('type', d.doc_type, 'version', d.version, 'title', d.title, 'body', d.body,
                            'accept_label', d.accept_label, 'published_at', d.published_at)
  from public.legal_documents d
  where d.doc_type = p_type and d.published_at is not null and d.published_at <= now()
  order by d.version desc limit 1
$$;
revoke execute on function public.legal_document(text) from public;
grant execute on function public.legal_document(text) to anon, authenticated;

create or replace function public.legal_current_version(p_type text)
returns integer language sql stable security definer set search_path = public as $$
  select max(version) from public.legal_documents
  where doc_type = p_type and published_at is not null and published_at <= now()
$$;
revoke execute on function public.legal_current_version(text) from public, anon, authenticated;

-- Super admins publish a new version. Bureaux are asked to accept a new Terms of Access version at their next sign-in.
create or replace function public.admin_legal_publish(p_type text, p_title text, p_body text, p_accept_label text default null,
                                                     p_review_status text default 'draft_for_review')
returns jsonb language plpgsql security definer set search_path = public as $$
declare lv text := public.admin_guard('super'); v int;
begin
  if coalesce(btrim(p_body), '') = '' or coalesce(btrim(p_title), '') = '' then raise exception 'Title and text are required'; end if;
  select coalesce(max(version), 0) + 1 into v from public.legal_documents where doc_type = p_type;
  insert into public.legal_documents (doc_type, version, title, body, accept_label, review_status, published_at, created_by)
  values (p_type, v, p_title, p_body, p_accept_label, p_review_status, now(), public.admin_actor());
  perform public.audit_write('legal.publish', 'legal_documents', p_type || ' v' || v, 'Published ' || p_type || ' version ' || v);
  return jsonb_build_object('ok', true, 'version', v);
end $$;
revoke execute on function public.admin_legal_publish(text, text, text, text, text) from public, anon;
grant execute on function public.admin_legal_publish(text, text, text, text, text) to authenticated;

create or replace function public.admin_legal_documents()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff');
begin
  return coalesce((select jsonb_agg(to_jsonb(d) order by d.doc_type, d.version desc) from public.legal_documents d), '[]'::jsonb);
end $$;
revoke execute on function public.admin_legal_documents() from public, anon;
grant execute on function public.admin_legal_documents() to authenticated;

-- ---------- W2: Terms of Access gate ----------
-- True when the signed-in user has accepted the current Terms of Access (or none is published).
create or replace function public.terms_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select public.legal_current_version('terms_of_access') is null
      or exists (select 1 from public.terms_acceptances t
                 where t.user_id = auth.uid() and t.doc_type = 'terms_of_access'
                   and t.version = public.legal_current_version('terms_of_access'))
$$;
revoke execute on function public.terms_ok() from public, anon;
grant execute on function public.terms_ok() to authenticated;

create or replace function public.terms_accept(p_version integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v int := public.legal_current_version('terms_of_access'); ua public.user_access;
begin
  select * into ua from public.user_access where user_id = auth.uid() and role = 'bureau' and active and not must_change_password;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_a_bureau'); end if;
  if v is null or p_version is distinct from v then return jsonb_build_object('ok', false, 'error', 'version_changed', 'version', v); end if;
  insert into public.terms_acceptances (user_id, email, org_name, country_id, doc_type, version, ip_hash)
  values (auth.uid(), ua.email, ua.org_name, ua.country_id, 'terms_of_access', v, public.request_ip_hash())
  on conflict (user_id, doc_type, version) do nothing;
  perform public.audit_write('terms.accept', 'terms_acceptances', auth.uid()::text,
                             coalesce(ua.org_name, ua.email) || ' accepted the Terms of Access version ' || v, null, null, ua.email);
  return jsonb_build_object('ok', true, 'version', v);
end $$;
revoke execute on function public.terms_accept(integer) from public, anon;
grant execute on function public.terms_accept(integer) to authenticated;

create or replace function public.admin_terms_acceptances()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lv text := public.admin_guard('staff'); v int := public.legal_current_version('terms_of_access');
begin
  return jsonb_build_object('current_version', v,
    'accounts', coalesce((select jsonb_agg(jsonb_build_object(
        'user_id', ua.user_id, 'email', ua.email, 'org_name', ua.org_name, 'country', c.name, 'active', ua.active,
        'accepted_version', (select max(t.version) from public.terms_acceptances t where t.user_id = ua.user_id and t.doc_type = 'terms_of_access'),
        'accepted_at', (select max(t.accepted_at) from public.terms_acceptances t where t.user_id = ua.user_id and t.doc_type = 'terms_of_access' and t.version = v))
        order by ua.org_name nulls last, ua.email)
      from public.user_access ua left join public.countries c on c.id = ua.country_id where ua.role = 'bureau'), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(to_jsonb(t) - 'ip_hash' order by t.accepted_at desc)
      from (select * from public.terms_acceptances order by accepted_at desc limit 500) t), '[]'::jsonb));
end $$;
revoke execute on function public.admin_terms_acceptances() from public, anon;
grant execute on function public.admin_terms_acceptances() to authenticated;

-- Every bureau read and write goes through these two, so a bureau sees nothing until the current terms are accepted.
create or replace function public.bureau_country_id()
returns integer language sql stable security definer set search_path = public as $$
  select country_id from public.user_access
  where user_id = auth.uid() and role = 'bureau' and active and not must_change_password and public.terms_ok()
  limit 1
$$;

create or replace function public.my_tier()
returns text language sql stable security definer set search_path = public as $$
  select case when public.is_allowlisted() then 'admin'
              else (select tier from public.user_access
                    where user_id = auth.uid() and role = 'bureau' and active and not must_change_password
                      and public.terms_ok()
                    limit 1) end
$$;

create or replace function public.my_access()
returns jsonb language sql stable security definer set search_path = public as $$
  select case
    when public.is_allowlisted() then jsonb_build_object('role','admin','tier','admin')
    when exists(select 1 from public.user_access where user_id = auth.uid() and role = 'bureau' and active)
      then (select jsonb_build_object(
              'role','bureau','country_id',ua.country_id,'country',c.name,'iso2',c.iso2,
              'org_name',ua.org_name,'tier',ua.tier,
              'must_change_password', ua.must_change_password,
              'temp_password_expired', ua.must_change_password
                 and coalesce(ua.temp_password_issued_at, ua.created_at) < now() - interval '7 days',
              'terms_required', not public.terms_ok(),
              'terms_version', public.legal_current_version('terms_of_access'))
            from public.user_access ua join public.countries c on c.id = ua.country_id
            where ua.user_id = auth.uid() limit 1)
    else jsonb_build_object('role','none') end
$$;

-- ---------- W1: submission licence on both public forms ----------
alter table public.submissions add column licence_version integer, add column licence_accepted_at timestamptz;
alter table public.profile_submissions add column licence_version integer, add column licence_accepted_at timestamptz;

create or replace function public.submission_licence_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.licence_version is null or new.licence_version is distinct from public.legal_current_version('submission_licence') then
    raise exception 'Please accept the current submission licence before submitting.' using errcode = 'check_violation';
  end if;
  new.licence_accepted_at := now();
  return new;
end $$;
revoke execute on function public.submission_licence_guard() from public, anon, authenticated;
create trigger submissions_licence before insert on public.submissions
  for each row execute function public.submission_licence_guard();
create trigger profile_submissions_licence before insert on public.profile_submissions
  for each row execute function public.submission_licence_guard();

-- profile_submit as before, now passing the accepted licence version (checked by the trigger above).
create or replace function public.profile_submit(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_email    text := lower(btrim(coalesce(payload ->> 'work_email', '')));
  v_type     text := payload ->> 'submitter_type';
  v_country  int  := (payload ->> 'country_id')::int;
  v_ip       text := public.request_ip_hash();
  v_sub      bigint;
  v_subm     bigint;
  v_token    text;
  v_secret   text;
  v_sent     boolean := false;
  v_free     boolean;
  v_domain   text;
  v_dom_ok   boolean;
  f          jsonb;
  n          int := 0;
begin
  delete from public.profile_submission_attempts where at < now() - interval '7 days';

  if coalesce(payload ->> 'website', '') <> '' then
    insert into public.profile_submission_attempts (email, ip_hash, outcome) values (v_email, v_ip, 'honeypot');
    return jsonb_build_object('ok', true);
  end if;

  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'A valid work email is required' using errcode = 'check_violation';
  end if;
  if coalesce(btrim(payload ->> 'full_name'), '') = '' or coalesce(btrim(payload ->> 'organisation'), '') = '' then
    raise exception 'Full name and organisation are required' using errcode = 'check_violation';
  end if;
  if v_type is null or v_type not in ('bureau','venue','ministry','association','airline') then
    raise exception 'Choose a submitter type' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.countries where id = v_country and type = 'country') then
    raise exception 'Choose the country covered' using errcode = 'check_violation';
  end if;
  if coalesce(jsonb_typeof(payload -> 'fields'), '') <> 'array' or jsonb_array_length(payload -> 'fields') = 0 then
    raise exception 'Add at least one data point' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(payload -> 'fields') > 40 then
    raise exception 'Too many data points in one submission' using errcode = 'check_violation';
  end if;
  if coalesce(payload ->> 'licence_version', '') !~ '^\d+$'
     or (payload ->> 'licence_version')::int is distinct from public.legal_current_version('submission_licence') then
    raise exception 'Please accept the current submission licence before submitting.' using errcode = 'check_violation';
  end if;

  if (select count(*) from public.profile_submission_attempts
       where email = v_email and at > now() - interval '24 hours' and outcome = 'submitted') >= 3 then
    insert into public.profile_submission_attempts (email, ip_hash, outcome) values (v_email, v_ip, 'rate_email');
    raise exception 'Daily limit reached for this email. Try again tomorrow.' using errcode = 'check_violation';
  end if;
  if (select count(*) from public.profile_submission_attempts
       where ip_hash = v_ip and at > now() - interval '1 hour') >= 10 then
    insert into public.profile_submission_attempts (email, ip_hash, outcome) values (v_email, v_ip, 'rate_ip');
    raise exception 'Too many attempts. Try again in an hour.' using errcode = 'check_violation';
  end if;

  v_domain := split_part(v_email, '@', 2);
  v_free   := exists (select 1 from public.freemail_domains where domain = v_domain);
  v_dom_ok := exists (select 1 from public.verified_submitter_domains d
                       where d.domain = v_domain and (d.country_id is null or d.country_id = v_country));

  select id into v_sub from public.profile_submitters
   where lower(work_email) = v_email and country_id = v_country and submitter_type = v_type;
  if v_sub is null then
    insert into public.profile_submitters (full_name, organisation, role, work_email, submitter_type, country_id, freemail_flag, domain_verified)
    values (btrim(payload ->> 'full_name'), btrim(payload ->> 'organisation'), nullif(btrim(payload ->> 'role'), ''),
            v_email, v_type, v_country, v_free, v_dom_ok)
    returning id into v_sub;
  else
    if exists (select 1 from public.profile_submitters where id = v_sub and status = 'blocked') then
      insert into public.profile_submission_attempts (email, ip_hash, outcome) values (v_email, v_ip, 'blocked');
      raise exception 'This submitter is blocked. Contact the pipeline team.' using errcode = 'check_violation';
    end if;
    update public.profile_submitters
       set full_name = btrim(payload ->> 'full_name'), organisation = btrim(payload ->> 'organisation'),
           role = nullif(btrim(payload ->> 'role'), ''), freemail_flag = v_free, domain_verified = v_dom_ok
     where id = v_sub;
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.profile_submissions (submitter_id, country_id, submitter_type, token_hash, token_expires_at, ip_hash, freemail_flag, licence_version)
  values (v_sub, v_country, v_type, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '48 hours', v_ip, v_free,
          (payload ->> 'licence_version')::int)
  returning id into v_subm;

  for f in select * from jsonb_array_elements(payload -> 'fields') loop
    if coalesce(f ->> 'value', '') = '' then continue; end if;
    if coalesce(f ->> 'as_of', '') !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'Each data point needs an as-of date (YYYY-MM-DD)' using errcode = 'check_violation';
    end if;
    insert into public.profile_submission_fields (submission_id, field_key, proposed_value, as_of_date, source_url, supporting_file)
    values (v_subm, f ->> 'key', f ->> 'value', (f ->> 'as_of')::date,
            nullif(btrim(f ->> 'source_url'), ''),
            case when coalesce(f ->> 'supporting_file', '') <> ''
                 then (select upload_key::text from public.profile_submissions where id = v_subm) || '/' || (f ->> 'key') || '/' || regexp_replace(f ->> 'supporting_file', '[^A-Za-z0-9._-]', '_', 'g')
            end);
    n := n + 1;
  end loop;
  if n = 0 then
    raise exception 'Add at least one data point' using errcode = 'check_violation';
  end if;

  insert into public.profile_submission_attempts (email, ip_hash, outcome) values (v_email, v_ip, 'submitted');

  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'submission_webhook_secret' limit 1;
  if v_secret is not null then
    perform net.http_post(
      url := 'https://upzkvszgoqhoefkiwoep.supabase.co/functions/v1/send-submission-verification',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
      body := jsonb_build_object('submission_id', v_subm, 'email', v_email,
                                 'name', btrim(payload ->> 'full_name'), 'token', v_token),
      timeout_milliseconds := 5000);
    v_sent := true;
  end if;

  return jsonb_build_object('ok', true, 'submission_id', v_subm,
                            'upload_key', (select upload_key from public.profile_submissions where id = v_subm),
                            'email_sent', v_sent);
end $function$;
