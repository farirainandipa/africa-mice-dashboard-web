-- Email the agency team when a new access request or problem report arrives.
-- The trigger posts only { kind, id } to the admin-notify edge function through
-- pg_net; the function reads the row with the service role and mails every
-- super admin and active staff member. pg_net sends after commit, and any
-- failure here is swallowed so the insert itself always succeeds.

create or replace function public.admin_notify_queue_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
  v_kind   text;
begin
  if tg_table_name = 'signup_requests' then
    if new.status is distinct from 'pending' then
      return new;
    end if;
    v_kind := 'signup';
  else
    v_kind := 'report';
  end if;

  select decrypted_secret into v_secret
    from vault.decrypted_secrets
   where name = 'contact_webhook_secret'
   limit 1;
  if v_secret is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://upzkvszgoqhoefkiwoep.supabase.co/functions/v1/admin-notify',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    body := jsonb_build_object('kind', v_kind, 'id', new.id),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new;
end;
$$;

revoke execute on function public.admin_notify_queue_event() from public, anon, authenticated;

create trigger signup_requests_notify
  after insert on public.signup_requests
  for each row execute function public.admin_notify_queue_event();

create trigger user_reports_notify
  after insert on public.user_reports
  for each row execute function public.admin_notify_queue_event();
