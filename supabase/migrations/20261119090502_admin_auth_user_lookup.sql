-- Lets the bureau-admin edge function find the login behind a staff email.
-- Service role only.
create or replace function public.admin_auth_user_id(p_email text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from auth.users where lower(email) = lower(btrim(p_email)) limit 1
$$;
revoke execute on function public.admin_auth_user_id(text) from public, anon, authenticated;
grant execute on function public.admin_auth_user_id(text) to service_role;
