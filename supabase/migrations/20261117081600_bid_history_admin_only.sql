-- Bid history is for admins only. Convention-bureau logins (every tier) and
-- anonymous visitors lose all access to it; the public teaser page is removed.
-- The tables (bid_wins, series, history_sync_log) were already admin only
-- through is_allowlisted() policies, so this closes the RPCs that exposed them.
-- Free-tier bureaux, who used to see only the history teaser, now get the
-- normal portal.

-- 1. Bureau history RPCs: admins only. Admins work from the Bid History tab.
create or replace function public.bid_history()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_allowlisted() then raise exception 'Bid history is for admins only'; end if;
  raise exception 'admins use bid_history_preview(country_id, tier)';
end $$;

create or replace function public.bid_history_competitors(rivals text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_allowlisted() then raise exception 'Bid history is for admins only'; end if;
  return coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'series', s.name, 'series_key', b.series_key, 'year', b.edition_year, 'city', b.host_city, 'country', b.host_country_name,
      'iso2', b.host_iso2, 'region', b.host_region, 'sector', coalesce(b.sector, s.sector), 'status', b.award_status,
      'winning_bidder', b.winning_bidder, 'confidence', b.confidence, 'verified_on', b.verified_on, 'source_url', b.source_url))
      order by b.host_country_name, b.edition_year desc)
    from public.bid_wins b join public.series s on s.key = b.series_key
   where b.award_status <> 'cancelled'
     and (lower(b.host_country_name) = any (select lower(x) from unnest(rivals) x)
          or b.host_iso2 = any (select upper(x) from unnest(rivals) x))), '[]'::jsonb);
end $$;

revoke execute on function public.bid_history() from public, anon;
revoke execute on function public.bid_history_competitors(text[]) from public, anon;

-- 2. Public teaser: no longer callable by anyone through the API. It is still
--    used inside bid_history_preview(), which runs as the owner.
revoke execute on function public.bid_wins_teaser() from public, anon, authenticated;

-- 3. Free tier gets the normal portal instead of the history teaser.
create or replace function public.bureau_portal()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare cid int; res jsonb; t text;
begin
  cid := public.bureau_country_id();
  if cid is null then return jsonb_build_object('error','not_a_bureau'); end if;
  t := public.my_tier();
  if t is null then return jsonb_build_object('error','no_tier'); end if;
  update public.user_access set last_seen_at = now() where user_id = auth.uid();
  res := public.portal_data(cid);
  return res || jsonb_build_object('tier', t, 'org', (select jsonb_build_object('org_name',org_name,'contact_name',contact_name,'email',email) from public.user_access where user_id=auth.uid()));
end $$;
