-- Bureau match view (fit-score matching).
-- Requirements on opportunities, per-country fit inputs with per-field trust,
-- admin-tunable weights, a scoring function, materialised scores, the bureau
-- Matches RPC and the agent hooks. Bid history stays admin only, so nothing
-- here exposes bid_wins to bureaux.

-- ---------------------------------------------------------------------------
-- 1. Requirements on opportunities (and events, stored for later scoring)
-- ---------------------------------------------------------------------------
alter table public.bid_opportunities
  add column if not exists delegates_min integer check (delegates_min >= 0),
  add column if not exists delegates_max integer check (delegates_max >= 0),
  add column if not exists plenary_seats_min integer check (plenary_seats_min >= 0),
  add column if not exists origin_mix text check (origin_mix in ('global','africa','regional')),
  add column if not exists visa_sensitivity text check (visa_sensitivity in ('high','medium','low')),
  add column if not exists host_type text check (host_type in ('bureau','university','association_member','government','any')),
  add column if not exists requirements_source_url text,
  add column if not exists requirements_verified_on date,
  add column if not exists next_action text;

alter table public.events
  add column if not exists delegates_min integer check (delegates_min >= 0),
  add column if not exists delegates_max integer check (delegates_max >= 0),
  add column if not exists plenary_seats_min integer check (plenary_seats_min >= 0),
  add column if not exists origin_mix text check (origin_mix in ('global','africa','regional')),
  add column if not exists visa_sensitivity text check (visa_sensitivity in ('high','medium','low')),
  add column if not exists host_type text check (host_type in ('bureau','university','association_member','government','any')),
  add column if not exists requirements_source_url text,
  add column if not exists requirements_verified_on date;

-- ---------------------------------------------------------------------------
-- 2. Destination fit inputs, one row per country, trust held per field in meta
--    meta = { "<field>": {"confidence":"verified|partial|unverified",
--                          "source_url":..., "verified_on":..., "added_by":...} }
-- ---------------------------------------------------------------------------
create table if not exists public.destination_fit_inputs (
  country_id integer primary key references public.countries(id) on delete cascade,
  bureau_exists text check (bureau_exists in ('yes','partial','no')),
  bids_formally text check (bids_formally in ('yes','informal','no')),
  subvention_fund text check (subvention_fund in ('yes','partial','no')),
  visa_ease smallint check (visa_ease between 1 and 5),
  intercontinental_nonstops smallint check (intercontinental_nonstops >= 0),
  largest_plenary_seats integer check (largest_plenary_seats >= 0),
  icca_meetings_2024 smallint check (icca_meetings_2024 >= 0),
  icca_africa_top10 boolean,
  profile_depth text check (profile_depth in ('full','base')),
  meta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.destination_fit_inputs enable row level security;
drop policy if exists dfi_admin_all on public.destination_fit_inputs;
create policy dfi_admin_all on public.destination_fit_inputs for all to authenticated
  using (public.is_allowlisted()) with check (public.is_allowlisted());

create table if not exists public.fit_input_conflicts (
  id bigint generated always as identity primary key,
  country_id integer not null references public.countries(id) on delete cascade,
  field text not null,
  current_value text,
  proposed_value text,
  proposed_source_url text,
  proposed_by text not null default 'agent',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution text
);
create index if not exists fit_input_conflicts_open on public.fit_input_conflicts (country_id) where resolved_at is null;
alter table public.fit_input_conflicts enable row level security;
drop policy if exists fic_admin_all on public.fit_input_conflicts;
create policy fic_admin_all on public.fit_input_conflicts for all to authenticated
  using (public.is_allowlisted()) with check (public.is_allowlisted());

-- Seed from destination_profiles (the imported Fit score inputs sheet) and
-- take each field's trust from destination_profile_fields. Field numbers
-- differ between full (21 field) and base (12 field) profiles.
with fmap(field, full_no, base_no) as (values
  ('bureau_exists',1,1), ('bids_formally',2,2), ('subvention_fund',6,3),
  ('visa_ease',9,4), ('intercontinental_nonstops',10,5),
  ('largest_plenary_seats',12,6), ('icca_meetings_2024',17,8), ('icca_africa_top10',17,8)
), m as (
  select dp.country_id,
    jsonb_object_agg(fm.field, jsonb_strip_nulls(jsonb_build_object(
      'confidence', coalesce(lower(f.confidence),'unverified'),
      'source_url', f.source_url,
      'verified_on', f.verified_on,
      'added_by', 'seed'))) meta
  from public.destination_profiles dp
  cross join fmap fm
  left join public.destination_profile_fields f
    on f.country_id = dp.country_id
   and f.field_no = case when dp.profile_depth = 'full' then fm.full_no else fm.base_no end
  group by dp.country_id
)
insert into public.destination_fit_inputs (country_id, bureau_exists, bids_formally, subvention_fund,
  visa_ease, intercontinental_nonstops, largest_plenary_seats, icca_meetings_2024, icca_africa_top10,
  profile_depth, meta)
select dp.country_id,
  case when dp.bureau_exists ~* '^yes' then 'yes' when dp.bureau_exists ~* '^partial' then 'partial'
       when dp.bureau_exists ~* '^no' then 'no' end,
  case when dp.bids_formally ~* '^yes' then 'yes' when dp.bids_formally ~* '^informal' then 'informal'
       when dp.bids_formally ~* '^no' then 'no' end,
  case when dp.subvention_fund ~* '^yes' then 'yes'
       when dp.subvention_fund ~* '^partial' or dp.subvention_fund ~* 'in-kind' then 'partial'
       when dp.subvention_fund ~* '^(no|proposed)' then 'no' end,
  dp.visa_ease, dp.intl_nonstops, dp.largest_plenary, dp.icca_2024_meetings, dp.icca_2024_top10,
  case when dp.profile_depth in ('full','base') then dp.profile_depth end,
  coalesce(m.meta,'{}'::jsonb)
from public.destination_profiles dp
left join m on m.country_id = dp.country_id
on conflict (country_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Weights (admin only)
-- ---------------------------------------------------------------------------
create table if not exists public.match_weights (
  input text primary key check (input in ('venue','air','visa','bidding_capability','sector_alignment')),
  weight numeric not null check (weight >= 0 and weight <= 100),
  updated_at timestamptz not null default now()
);
insert into public.match_weights (input, weight) values
  ('venue',30), ('air',20), ('visa',15), ('bidding_capability',20), ('sector_alignment',15)
on conflict (input) do nothing;
alter table public.match_weights enable row level security;
drop policy if exists mw_admin_all on public.match_weights;
create policy mw_admin_all on public.match_weights for all to authenticated
  using (public.is_allowlisted()) with check (public.is_allowlisted());

create table if not exists public.match_scores (
  opportunity_id integer not null references public.bid_opportunities(id) on delete cascade,
  country_id integer not null references public.countries(id) on delete cascade,
  score smallint not null,
  sub_scores jsonb not null,
  reasons text[] not null default '{}',
  gaps text[] not null default '{}',
  confidence text not null check (confidence in ('verified','partial','unverified')),
  scored_on timestamptz not null default now(),
  primary key (opportunity_id, country_id)
);
create index if not exists match_scores_country on public.match_scores (country_id, score desc);
alter table public.match_scores enable row level security;
drop policy if exists ms_admin_read on public.match_scores;
create policy ms_admin_read on public.match_scores for select to authenticated using (public.is_allowlisted());
drop policy if exists ms_bureau_own on public.match_scores;
create policy ms_bureau_own on public.match_scores for select to authenticated
  using (country_id = public.bureau_country_id());

-- ---------------------------------------------------------------------------
-- Scoring. Internal: callable only by the definer functions below.
-- A null requirement leaves its input out of the weighted average (neutral).
-- Confidence is the weakest trust among the fit inputs that fed a sub-score,
-- and the plenary figure always counts, so an unverified plenary never yields
-- a verified score.
-- ---------------------------------------------------------------------------
create or replace function public.score_match(p_opportunity_id integer, p_country_id integer, p_weights jsonb default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  o public.bid_opportunities%rowtype;
  f public.destination_fit_inputs%rowtype;
  w jsonb;
  need int; s numeric; ns int;
  subs jsonb := '{}'::jsonb;
  reasons text[] := '{}'; gaps text[] := '{}';
  confs text[] := '{}';
  total numeric := 0; wsum numeric := 0;
  k text; v numeric; wt numeric;
  sens text; rank_hit int;
  conf_of text;
begin
  select * into o from public.bid_opportunities where id = p_opportunity_id;
  if not found then return null; end if;
  select * into f from public.destination_fit_inputs where country_id = p_country_id;
  if not found then return null; end if;
  w := coalesce(p_weights, (select jsonb_object_agg(input, weight) from public.match_weights));

  -- Venue
  need := coalesce(o.plenary_seats_min, o.delegates_max);
  confs := confs || coalesce(f.meta->'largest_plenary_seats'->>'confidence','unverified');
  if f.largest_plenary_seats is null then
    confs := confs || 'unverified'::text;
  end if;
  if need is not null and need > 0 then
    if f.largest_plenary_seats is null then
      s := 50; gaps := gaps || 'venue capacity not verified'::text;
    elsif f.largest_plenary_seats >= need then
      s := 100; reasons := reasons || format('Plenary of %s seats covers %s needed', to_char(f.largest_plenary_seats,'FM999,999'), to_char(need,'FM999,999'));
    else
      s := greatest(0, least(100, (f.largest_plenary_seats - need/2.0) / (need/2.0) * 100));
      gaps := gaps || format('Largest plenary %s seats, %s needed', to_char(f.largest_plenary_seats,'FM999,999'), to_char(need,'FM999,999'));
    end if;
    subs := subs || jsonb_build_object('venue', round(s));
  end if;

  -- Air
  if o.origin_mix is not null then
    if o.origin_mix = 'regional' then
      s := 100;
    else
      ns := f.intercontinental_nonstops;
      confs := confs || coalesce(f.meta->'intercontinental_nonstops'->>'confidence','unverified');
      if ns is null then
        s := 50; gaps := gaps || 'air access not verified'::text;
      elsif o.origin_mix = 'global' then
        s := least(ns, 15) / 15.0 * 100;
      else -- africa: intercontinental links matter less
        s := 50 + least(ns, 15) / 15.0 * 50;
      end if;
      if ns is not null and ns >= 10 then reasons := reasons || format('%s intercontinental non-stops', ns);
      elsif ns is not null and o.origin_mix = 'global' and ns < 5 then gaps := gaps || format('Only %s intercontinental non-stops', ns); end if;
    end if;
    subs := subs || jsonb_build_object('air', round(s));
  end if;

  -- Visa (sensitivity defaults to medium; ease is always a country property)
  sens := coalesce(o.visa_sensitivity, 'medium');
  confs := confs || coalesce(f.meta->'visa_ease'->>'confidence','unverified');
  if f.visa_ease is null then
    s := 50; gaps := gaps || 'visa ease not verified'::text;
  else
    s := f.visa_ease * 20;
    s := case sens when 'high' then s when 'medium' then 50 + s/2 else 75 + s/4 end;
    if f.visa_ease >= 4 then reasons := reasons || 'Easy visa access for delegates'::text;
    elsif f.visa_ease <= 2 and sens <> 'low' then gaps := gaps || 'Visa access is a hurdle for delegates'::text; end if;
  end if;
  subs := subs || jsonb_build_object('visa', round(s));

  -- Bidding capability
  s := case f.bureau_exists when 'yes' then 40 when 'partial' then 20 else 0 end
     + case f.bids_formally when 'yes' then 30 when 'informal' then 15 else 0 end
     + case f.subvention_fund when 'yes' then 30 when 'partial' then 15 else 0 end;
  foreach k in array array['bureau_exists','bids_formally','subvention_fund'] loop
    confs := confs || coalesce(f.meta->k->>'confidence','unverified');
  end loop;
  if f.bureau_exists = 'yes' and f.bids_formally = 'yes' then reasons := reasons || 'Bureau bids formally'::text; end if;
  if f.subvention_fund = 'yes' then reasons := reasons || 'Subvention fund available'::text;
  elsif coalesce(f.subvention_fund,'no') = 'no' then gaps := gaps || 'No bid subvention fund'::text; end if;
  if coalesce(f.bureau_exists,'no') = 'no' then gaps := gaps || 'No convention bureau'::text; end if;
  subs := subs || jsonb_build_object('bidding_capability', round(s));

  -- Sector alignment
  if exists (select 1 from public.opportunity_sectors where opportunity_id = o.id) then
    select min(r.rn) into rank_hit
    from (select cs.econ_sector_id, row_number() over (order by cs.priority_rank, cs.id) rn
          from public.country_sectors cs where cs.country_id = p_country_id) r
    join public.opportunity_sectors os on os.econ_sector_id = r.econ_sector_id and os.opportunity_id = o.id;
    if rank_hit is null then s := 20;
    elsif rank_hit <= 5 then s := 100;
      reasons := reasons || (select format('%s is a top national priority', es.name)
        from (select cs.econ_sector_id, row_number() over (order by cs.priority_rank, cs.id) rn
              from public.country_sectors cs where cs.country_id = p_country_id) r
        join public.opportunity_sectors os on os.econ_sector_id = r.econ_sector_id and os.opportunity_id = o.id
        join public.econ_sectors es on es.id = r.econ_sector_id order by r.rn limit 1);
    else s := 60; end if;
    subs := subs || jsonb_build_object('sector_alignment', round(s));
  end if;

  -- Host type
  if o.host_type in ('university','association_member') then gaps := gaps || 'needs a local lead'::text; end if;

  for k, v in select key, value::numeric from jsonb_each_text(subs) loop
    wt := coalesce((w->>k)::numeric, 0);
    total := total + wt * v; wsum := wsum + wt;
  end loop;

  conf_of := case when 'unverified' = any(confs) then 'unverified'
                  when 'partial' = any(confs) then 'partial' else 'verified' end;

  return jsonb_build_object(
    'score', case when wsum > 0 then round(total / wsum) else 0 end,
    'sub_scores', subs, 'reasons', to_jsonb(reasons), 'gaps', to_jsonb(gaps), 'confidence', conf_of);
end $$;
revoke execute on function public.score_match(integer, integer, jsonb) from public, anon, authenticated;

-- Materialise scores for open and watchlist opportunities.
create or replace function public.rescore_matches(p_opportunity_id integer default null, p_country_id integer default null)
returns integer
language plpgsql security definer set search_path = public
as $$
declare n int;
begin
  delete from public.match_scores ms
  where (p_opportunity_id is null or ms.opportunity_id = p_opportunity_id)
    and (p_country_id is null or ms.country_id = p_country_id);

  insert into public.match_scores (opportunity_id, country_id, score, sub_scores, reasons, gaps, confidence, scored_on)
  select o.id, f.country_id, (r->>'score')::smallint, r->'sub_scores',
         array(select jsonb_array_elements_text(r->'reasons')),
         array(select jsonb_array_elements_text(r->'gaps')),
         r->>'confidence', now()
  from public.bid_opportunities o
  cross join public.destination_fit_inputs f
  cross join lateral (select public.score_match(o.id, f.country_id) r) x
  where o.list_status in ('open','watchlist')
    and (p_opportunity_id is null or o.id = p_opportunity_id)
    and (p_country_id is null or f.country_id = p_country_id)
    and r is not null;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.rescore_matches(integer, integer) from public, anon, authenticated;

-- Rescore triggers
create or replace function public.trg_rescore_opportunity()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_table_name = 'opportunity_sectors' then
    perform public.rescore_matches(coalesce(new.opportunity_id, old.opportunity_id), null);
    if tg_op = 'UPDATE' and new.opportunity_id is distinct from old.opportunity_id then
      perform public.rescore_matches(old.opportunity_id, null);
    end if;
  else
    perform public.rescore_matches(coalesce(new.id, old.id), null);
  end if;
  return null;
end $$;
revoke execute on function public.trg_rescore_opportunity() from public, anon, authenticated;

create or replace function public.trg_rescore_country()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.rescore_matches(null, coalesce(new.country_id, old.country_id));
  return null;
end $$;
revoke execute on function public.trg_rescore_country() from public, anon, authenticated;

create or replace function public.trg_rescore_all()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.rescore_matches(null, null);
  return null;
end $$;
revoke execute on function public.trg_rescore_all() from public, anon, authenticated;

drop trigger if exists rescore_on_opportunity on public.bid_opportunities;
create trigger rescore_on_opportunity
  after insert or update of list_status, delegates_min, delegates_max, plenary_seats_min, origin_mix, visa_sensitivity, host_type
  on public.bid_opportunities for each row execute function public.trg_rescore_opportunity();

drop trigger if exists rescore_on_opportunity_sectors on public.opportunity_sectors;
create trigger rescore_on_opportunity_sectors
  after insert or update or delete on public.opportunity_sectors
  for each row execute function public.trg_rescore_opportunity();

drop trigger if exists rescore_on_fit_inputs on public.destination_fit_inputs;
create trigger rescore_on_fit_inputs
  after insert or update or delete on public.destination_fit_inputs
  for each row execute function public.trg_rescore_country();

drop trigger if exists rescore_on_country_sectors on public.country_sectors;
create trigger rescore_on_country_sectors
  after insert or update or delete on public.country_sectors
  for each row execute function public.trg_rescore_country();

drop trigger if exists rescore_on_weights on public.match_weights;
create trigger rescore_on_weights
  after insert or update or delete on public.match_weights
  for each statement execute function public.trg_rescore_all();

-- Nightly rescore, which also drops opportunities that closed during the day.
select cron.unschedule('match_rescore_nightly') where exists (select 1 from cron.job where jobname = 'match_rescore_nightly');
select cron.schedule('match_rescore_nightly', '30 2 * * *', 'select public.rescore_matches()');

-- ---------------------------------------------------------------------------
-- 4. Bureau Matches RPC. Bureaux get their own country only; admins may pass
--    a country and tier to preview. Competitor names only on Bureau Plus.
--    Bid history (bid_wins) is not included: it stays admin only.
-- ---------------------------------------------------------------------------
create or replace function public.bureau_matches(p_country_id integer default null, p_tier text default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare cid int; t text; res jsonb;
begin
  if public.is_allowlisted() then
    cid := p_country_id; t := coalesce(p_tier, 'bureau_plus');
    if cid is null then raise exception 'country required'; end if;
  else
    cid := public.bureau_country_id(); t := public.my_tier();
    if cid is null then return jsonb_build_object('error','not_a_bureau'); end if;
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
end $$;
revoke execute on function public.bureau_matches(integer, text) from public, anon;
grant execute on function public.bureau_matches(integer, text) to authenticated;

-- Admin live preview for the Weights panel: scores one country with trial
-- weights, without saving.
create or replace function public.match_preview(p_country_id integer, p_weights jsonb default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_allowlisted() then raise exception 'admins only'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', o.id, 'title', o.title, 'deadline', o.submission_deadline,
             'status', o.list_status) || public.score_match(o.id, p_country_id, p_weights)
           order by (public.score_match(o.id, p_country_id, p_weights)->>'score')::int desc, o.submission_deadline nulls last)
    from public.bid_opportunities o
    where o.list_status in ('open','watchlist')
      and (o.submission_deadline is null or o.submission_deadline >= current_date)
      and exists (select 1 from public.destination_fit_inputs f where f.country_id = p_country_id)), '[]'::jsonb);
end $$;
revoke execute on function public.match_preview(integer, jsonb) from public, anon;
grant execute on function public.match_preview(integer, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Agent hooks
-- ---------------------------------------------------------------------------
-- Upsert fit inputs after a destination run. Values land as unverified with
-- added_by 'agent'. A verified value is never overwritten: a differing value
-- is logged in fit_input_conflicts instead. Cannot touch weights, delete rows
-- or set verified. Callable by admins and the service role.
create or replace function public.fit_inputs_agent_upsert(p_country_id integer, p_values jsonb, p_sources jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  allowed text[] := array['bureau_exists','bids_formally','subvention_fund','visa_ease','intercontinental_nonstops',
                          'largest_plenary_seats','icca_meetings_2024','icca_africa_top10','profile_depth'];
  k text; newv text; curv text; curconf text;
  cur jsonb; updated text[] := '{}'; conflicts text[] := '{}'; skipped text[] := '{}';
begin
  if not (public.is_allowlisted() or coalesce(auth.role(),'') = 'service_role') then
    raise exception 'not permitted';
  end if;
  if not exists (select 1 from public.countries where id = p_country_id) then raise exception 'unknown country %', p_country_id; end if;

  insert into public.destination_fit_inputs (country_id) values (p_country_id) on conflict do nothing;
  select to_jsonb(f) into cur from public.destination_fit_inputs f where country_id = p_country_id for update;

  for k, newv in select key, value from jsonb_each_text(coalesce(p_values,'{}'::jsonb)) loop
    if not k = any(allowed) then skipped := skipped || k; continue; end if;
    curv := cur->>k;
    curconf := cur->'meta'->k->>'confidence';
    if curv is not distinct from newv then continue; end if;
    if curconf = 'verified' then
      insert into public.fit_input_conflicts (country_id, field, current_value, proposed_value, proposed_source_url)
      values (p_country_id, k, curv, newv, p_sources->>k);
      conflicts := conflicts || k;
      continue;
    end if;
    execute format('update public.destination_fit_inputs set %I = $1::%s, meta = jsonb_set(meta, array[%L], $2, true), updated_at = now() where country_id = $3',
                   k,
                   case when k in ('visa_ease','intercontinental_nonstops','icca_meetings_2024') then 'smallint'
                        when k = 'largest_plenary_seats' then 'integer'
                        when k = 'icca_africa_top10' then 'boolean' else 'text' end,
                   k)
      using newv,
            jsonb_strip_nulls(jsonb_build_object('confidence','unverified','added_by','agent',
              'source_url', p_sources->>k, 'verified_on', current_date)),
            p_country_id;
    updated := updated || k;
  end loop;

  return jsonb_build_object('updated', to_jsonb(updated), 'conflicts', to_jsonb(conflicts), 'ignored', to_jsonb(skipped));
end $$;
revoke execute on function public.fit_inputs_agent_upsert(integer, jsonb, jsonb) from public, anon;
grant execute on function public.fit_inputs_agent_upsert(integer, jsonb, jsonb) to authenticated, service_role;

-- Countries with every weighted input filled. Admin only through RLS on the
-- underlying table (security_invoker).
create or replace view public.countries_ready_for_scoring with (security_invoker = true) as
select c.id as country_id, c.name, c.iso2, f.profile_depth, f.updated_at
from public.destination_fit_inputs f
join public.countries c on c.id = f.country_id
where f.largest_plenary_seats is not null
  and f.intercontinental_nonstops is not null
  and f.visa_ease is not null
  and f.bureau_exists is not null and f.bids_formally is not null and f.subvention_fund is not null
  and exists (select 1 from public.country_sectors cs where cs.country_id = f.country_id);
revoke all on public.countries_ready_for_scoring from anon;

-- ---------------------------------------------------------------------------
-- Backfill requirements that the opportunity text itself states. Delegate
-- counts are not in the source text, so they stay null (venue then scores
-- neutral) until an admin fills them in.
-- ---------------------------------------------------------------------------
update public.bid_opportunities set origin_mix = 'global', visa_sensitivity = 'high', host_type = 'any',
  requirements_source_url = primary_source_url where id in (13, 25, 32, 45) and origin_mix is null;
update public.bid_opportunities set origin_mix = 'global', visa_sensitivity = 'high', host_type = 'government',
  requirements_source_url = primary_source_url where id = 33 and origin_mix is null;
update public.bid_opportunities set origin_mix = 'global', visa_sensitivity = 'high', host_type = 'university',
  requirements_source_url = primary_source_url where id = 46 and origin_mix is null;
update public.bid_opportunities set origin_mix = 'global', visa_sensitivity = 'high', host_type = 'association_member',
  requirements_source_url = primary_source_url where id = 47 and origin_mix is null;
update public.bid_opportunities set host_type = 'university',
  requirements_source_url = primary_source_url where id = 48 and host_type is null;
update public.bid_opportunities set origin_mix = 'africa', host_type = 'any',
  requirements_source_url = primary_source_url where id = 49 and origin_mix is null;

select public.rescore_matches();
