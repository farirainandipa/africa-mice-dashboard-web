-- IP website change W11: correction and takedown requests from rights holders, filed in the user reports queue.
alter table public.user_reports drop constraint user_reports_kind_check;
alter table public.user_reports add constraint user_reports_kind_check
  check (kind = any (array['data_issue', 'support', 'bug', 'abuse', 'rights_request']));

insert into public.rate_limit_rules (key, description, max_hits, window_seconds, enabled)
values ('rights_request_ip', 'Correction and removal requests per network address', 5, 3600, true)
on conflict (key) do nothing;

-- Public: anyone can ask for a correction or removal. Rate limited by network address; a hidden field catches bots.
create or replace function public.rights_request_submit(payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_name   text := btrim(coalesce(payload ->> 'name', ''));
  v_org    text := btrim(coalesce(payload ->> 'organisation', ''));
  v_record text := btrim(coalesce(payload ->> 'record', ''));
  v_claim  text := btrim(coalesce(payload ->> 'claim', ''));
  v_kind   text := coalesce(payload ->> 'request_type', 'correction');
  v_email  text := lower(btrim(coalesce(payload ->> 'email', '')));
  v_id     bigint;
begin
  if coalesce(payload ->> 'website', '') <> '' then
    perform public.log_event('warn', 'rights', 'rights.honeypot', 'Rights request dropped (hidden field filled)', '{}'::jsonb);
    return jsonb_build_object('ok', true);
  end if;
  if v_name = '' or v_record = '' or v_claim = '' or v_kind not in ('correction', 'removal')
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' or length(v_email) > 254 then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if not public.rate_limit_hit('rights_request_ip', public.request_ip_hash()) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;
  insert into public.user_reports (kind, subject_type, subject_label, title, body, page_url, reporter_id, reporter_email, priority)
  values ('rights_request', 'record', left(v_record, 300),
          left((case v_kind when 'removal' then 'Removal request: ' else 'Correction request: ' end) || v_name
               || case when v_org <> '' then ', ' || v_org else '' end, 200),
          left('Name: ' || v_name || E'\nOrganisation: ' || coalesce(nullif(v_org, ''), 'not given')
               || E'\nContact: ' || v_email || coalesce(E'\nPhone: ' || nullif(btrim(payload ->> 'phone'), ''), '')
               || E'\nRecord: ' || v_record || E'\n\n' || v_claim, 4000),
          left(nullif(payload ->> 'page_url', ''), 500), auth.uid(), v_email,
          case v_kind when 'removal' then 'high' else 'normal' end)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;
revoke execute on function public.rights_request_submit(jsonb) from public;
grant execute on function public.rights_request_submit(jsonb) to anon, authenticated;
