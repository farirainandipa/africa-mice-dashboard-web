-- First sign-in security for bureau logins.
--
-- A bureau login created or reset by the bureau-admin edge function starts
-- with must_change_password = true and a temporary password that expires after
-- seven days. Until the first sign-in is completed the account sees nothing:
-- bureau_country_id() and my_tier(), which every bureau RPC and policy goes
-- through, return null. complete_first_signin() clears the flag only when the
-- current session was opened with an emailed one-time code (or magic link)
-- issued after the temporary password, and the password has been changed since.

alter table public.user_access
  add column if not exists must_change_password boolean not null default false,
  add column if not exists temp_password_issued_at timestamptz,
  add column if not exists password_changed_at timestamptz,
  add column if not exists first_signin_completed_at timestamptz;

comment on column public.user_access.must_change_password is
  'True from account creation or an admin reset until the user verifies their email with a code and sets their own password.';

-- True when the caller is an active bureau login that has finished first sign-in.
create or replace function public.bureau_signin_ok()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_access
    where user_id = auth.uid() and role = 'bureau' and active and not must_change_password)
$$;
revoke execute on function public.bureau_signin_ok() from public, anon;
grant execute on function public.bureau_signin_ok() to authenticated;

create or replace function public.bureau_country_id()
returns integer
language sql stable security definer
set search_path = public
as $$
  select country_id from public.user_access
  where user_id = auth.uid() and role = 'bureau' and active and not must_change_password
  limit 1
$$;

create or replace function public.my_tier()
returns text
language sql stable security definer
set search_path = public
as $$
  select case when public.is_allowlisted() then 'admin'
              else (select tier from public.user_access
                    where user_id = auth.uid() and role = 'bureau' and active and not must_change_password
                    limit 1) end
$$;

-- my_access also reports whether first sign-in is still pending.
create or replace function public.my_access()
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select case
    when public.is_allowlisted() then jsonb_build_object('role','admin','tier','admin')
    when exists(select 1 from public.user_access where user_id = auth.uid() and role = 'bureau' and active)
      then (select jsonb_build_object(
              'role','bureau','country_id',ua.country_id,'country',c.name,'iso2',c.iso2,
              'org_name',ua.org_name,'tier',ua.tier,
              'must_change_password', ua.must_change_password,
              'temp_password_expired', ua.must_change_password
                 and coalesce(ua.temp_password_issued_at, ua.created_at) < now() - interval '7 days')
            from public.user_access ua join public.countries c on c.id = ua.country_id
            where ua.user_id = auth.uid() limit 1)
    else jsonb_build_object('role','none') end
$$;

-- The two destination-profile policies read user_access directly; route them
-- through bureau_country_id() so they honour the first sign-in gate too.
drop policy if exists dp_bureau_own on public.destination_profiles;
create policy dp_bureau_own on public.destination_profiles
  for select to authenticated
  using (country_id = (select public.bureau_country_id()));

drop policy if exists dpf_bureau_own on public.destination_profile_fields;
create policy dpf_bureau_own on public.destination_profile_fields
  for select to authenticated
  using (country_id = (select public.bureau_country_id()));

-- Record when a user's password changes (by the user or by an admin reset).
create or replace function public.track_password_change()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update public.user_access set password_changed_at = now() where user_id = new.id;
  end if;
  return new;
end
$$;
revoke execute on function public.track_password_change() from public, anon, authenticated;

drop trigger if exists on_auth_password_change on auth.users;
create trigger on_auth_password_change
  after update of encrypted_password on auth.users
  for each row execute function public.track_password_change();

-- Called by the pipeline once the user has verified the emailed code and set a
-- new password. Checks both on the server.
create or replace function public.complete_first_signin()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  ua public.user_access%rowtype;
  issued timestamptz;
  otp_at timestamptz;
begin
  select * into ua from public.user_access
  where user_id = auth.uid() and role = 'bureau' and active;
  if not found then
    raise exception 'No active bureau login.' using errcode = '42501';
  end if;
  if not ua.must_change_password then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  issued := coalesce(ua.temp_password_issued_at, ua.created_at);
  if issued < now() - interval '7 days' then
    raise exception 'The temporary password has expired. Ask for a new one.' using errcode = '42501';
  end if;

  select max(to_timestamp((e ->> 'timestamp')::double precision)) into otp_at
  from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) e
  where e ->> 'method' in ('otp', 'magiclink');
  if otp_at is null or otp_at < issued - interval '1 minute' then
    raise exception 'Confirm your email with the code we sent before continuing.' using errcode = '42501';
  end if;

  if ua.password_changed_at is null or ua.password_changed_at <= issued then
    raise exception 'Set a new password before continuing.' using errcode = '42501';
  end if;

  update public.user_access
     set must_change_password = false, first_signin_completed_at = now()
   where user_id = ua.user_id;
  return jsonb_build_object('ok', true);
end
$$;
revoke execute on function public.complete_first_signin() from public, anon;
grant execute on function public.complete_first_signin() to authenticated;

-- Used by the bureau-admin edge function (service role) to end every session
-- of a login after a password reset or when it is disabled.
create or replace function public.revoke_user_sessions(p_user_id uuid)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare n integer;
begin
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics n = row_count;
  return n;
end
$$;
revoke execute on function public.revoke_user_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_user_sessions(uuid) to service_role;
