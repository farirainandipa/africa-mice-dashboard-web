-- Let convention-bureau logins read and edit their own country's descriptive
-- data. Bureaux still have no direct access to public.countries; both
-- functions resolve the country from user_access, so a bureau can only ever
-- touch its own row, and only the columns listed here. Admin-only columns
-- (name, iso2, region, type, priority, afcfta_status, data_confidence) are
-- never writable this way. Admins keep editing through admin_update_countries.

create or replace function public.bureau_country()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name,
    'mice_summary', c.mice_summary, 'transport_summary', c.transport_summary,
    'security_summary', c.security_summary, 'bureau_name', c.bureau_name,
    'bureau_url', c.bureau_url, 'visa_regime', c.visa_regime,
    'visa_notes', c.visa_notes, 'visa_africa', c.visa_africa, 'evisa', c.evisa,
    'visa_on_arrival', c.visa_on_arrival, 'univisa', c.univisa,
    'visa_portal_url', c.visa_portal_url, 'visa_verified_on', c.visa_verified_on,
    'visa_events_note', c.visa_events_note, 'updated_at', c.updated_at)
  from public.countries c
  where c.id = public.bureau_country_id()
$$;

create or replace function public.bureau_update_country(patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cid int := public.bureau_country_id();
  allowed text[] := array['mice_summary','transport_summary','security_summary',
    'bureau_name','bureau_url','visa_regime','visa_notes','visa_africa','evisa',
    'visa_on_arrival','univisa','visa_portal_url','visa_verified_on','visa_events_note'];
  bad text;
begin
  if cid is null then
    raise exception 'Only an active bureau login can edit its country.' using errcode = '42501';
  end if;
  if patch is null or jsonb_typeof(patch) <> 'object' then
    raise exception 'Nothing to save.';
  end if;
  select k into bad from jsonb_object_keys(patch) k where k <> all (allowed) limit 1;
  if bad is not null then
    raise exception 'The field % cannot be edited from the bureau portal.', bad using errcode = '42501';
  end if;
  if patch ? 'bureau_url' and nullif(patch->>'bureau_url','') !~* '^https?://' then
    raise exception 'The bureau website must start with http:// or https://.';
  end if;
  if patch ? 'visa_portal_url' and nullif(patch->>'visa_portal_url','') !~* '^https?://' then
    raise exception 'The visa portal must start with http:// or https://.';
  end if;

  update public.countries c set
    mice_summary      = case when patch ? 'mice_summary'      then nullif(btrim(patch->>'mice_summary'),'')      else c.mice_summary end,
    transport_summary = case when patch ? 'transport_summary' then nullif(btrim(patch->>'transport_summary'),'') else c.transport_summary end,
    security_summary  = case when patch ? 'security_summary'  then nullif(btrim(patch->>'security_summary'),'')  else c.security_summary end,
    bureau_name       = case when patch ? 'bureau_name'       then nullif(btrim(patch->>'bureau_name'),'')       else c.bureau_name end,
    bureau_url        = case when patch ? 'bureau_url'        then nullif(btrim(patch->>'bureau_url'),'')        else c.bureau_url end,
    visa_regime       = case when patch ? 'visa_regime'       then nullif(btrim(patch->>'visa_regime'),'')       else c.visa_regime end,
    visa_notes        = case when patch ? 'visa_notes'        then nullif(btrim(patch->>'visa_notes'),'')        else c.visa_notes end,
    visa_africa       = case when patch ? 'visa_africa'       then nullif(patch->>'visa_africa','')::visa_africa_access else c.visa_africa end,
    evisa             = case when patch ? 'evisa'             then (patch->>'evisa')::boolean           else c.evisa end,
    visa_on_arrival   = case when patch ? 'visa_on_arrival'   then (patch->>'visa_on_arrival')::boolean else c.visa_on_arrival end,
    univisa           = case when patch ? 'univisa'           then (patch->>'univisa')::boolean         else c.univisa end,
    visa_portal_url   = case when patch ? 'visa_portal_url'   then nullif(btrim(patch->>'visa_portal_url'),'')   else c.visa_portal_url end,
    visa_verified_on  = case when patch ? 'visa_verified_on'  then nullif(patch->>'visa_verified_on','')::date  else c.visa_verified_on end,
    visa_events_note  = case when patch ? 'visa_events_note'  then nullif(btrim(patch->>'visa_events_note'),'')  else c.visa_events_note end,
    updated_at = now()
  where c.id = cid;

  return public.bureau_country();
end $$;

revoke execute on function public.bureau_country() from public, anon;
revoke execute on function public.bureau_update_country(jsonb) from public, anon;
grant execute on function public.bureau_country() to authenticated;
grant execute on function public.bureau_update_country(jsonb) to authenticated;
