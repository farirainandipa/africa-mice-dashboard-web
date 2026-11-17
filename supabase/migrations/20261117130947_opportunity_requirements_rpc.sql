-- Admin write path for the Requirements editor. Admins have read-only RLS on
-- bid_opportunities, so this function updates the requirement columns and
-- next_action only, and rejects anything else. The rescore trigger on
-- bid_opportunities then refreshes match_scores for the opportunity.
create or replace function public.opportunity_set_requirements(p_id integer, patch jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  allowed text[] := array['delegates_min','delegates_max','plenary_seats_min','origin_mix','visa_sensitivity',
                          'host_type','requirements_source_url','requirements_verified_on','next_action'];
  bad text;
begin
  if not public.is_allowlisted() then raise exception 'admins only'; end if;
  select k into bad from jsonb_object_keys(coalesce(patch,'{}'::jsonb)) k where not k = any(allowed) limit 1;
  if bad is not null then raise exception 'field % cannot be edited here', bad; end if;
  if not exists (select 1 from public.bid_opportunities where id = p_id) then raise exception 'unknown opportunity %', p_id; end if;

  update public.bid_opportunities o set
    delegates_min            = case when patch ? 'delegates_min' then (patch->>'delegates_min')::integer else o.delegates_min end,
    delegates_max            = case when patch ? 'delegates_max' then (patch->>'delegates_max')::integer else o.delegates_max end,
    plenary_seats_min        = case when patch ? 'plenary_seats_min' then (patch->>'plenary_seats_min')::integer else o.plenary_seats_min end,
    origin_mix               = case when patch ? 'origin_mix' then patch->>'origin_mix' else o.origin_mix end,
    visa_sensitivity         = case when patch ? 'visa_sensitivity' then patch->>'visa_sensitivity' else o.visa_sensitivity end,
    host_type                = case when patch ? 'host_type' then patch->>'host_type' else o.host_type end,
    requirements_source_url  = case when patch ? 'requirements_source_url' then patch->>'requirements_source_url' else o.requirements_source_url end,
    requirements_verified_on = case when patch ? 'requirements_verified_on' then (patch->>'requirements_verified_on')::date else o.requirements_verified_on end,
    next_action              = case when patch ? 'next_action' then patch->>'next_action' else o.next_action end
  where o.id = p_id;
end $$;
revoke execute on function public.opportunity_set_requirements(integer, jsonb) from public, anon;
grant execute on function public.opportunity_set_requirements(integer, jsonb) to authenticated;
