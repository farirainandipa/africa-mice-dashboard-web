-- IP website changes W3, W4, W5 and W6.

-- ---------- W3: a blocked rate limit also lands in the admin audit log ----------
create or replace function public.rate_limit_hit(p_rule text, p_subject text)
returns boolean language plpgsql security definer set search_path = public as $$
declare r public.rate_limit_rules; w timestamptz; h integer;
begin
  select * into r from public.rate_limit_rules where key = p_rule and enabled;
  if not found then return true; end if;
  w := to_timestamp(floor(extract(epoch from now()) / r.window_seconds) * r.window_seconds);
  insert into public.rate_limit_counters (rule_key, subject, window_start, hits)
  values (p_rule, coalesce(nullif(p_subject, ''), 'unknown'), w, 1)
  on conflict (rule_key, subject, window_start)
  do update set hits = public.rate_limit_counters.hits + 1
  returning hits into h;
  if h > r.max_hits then
    if h = r.max_hits + 1 then
      insert into public.system_log (level, source, event, message, context, user_id, ip_hash)
      values ('warn', 'rate_limit', 'rate_limit.block', r.description,
              jsonb_build_object('rule', p_rule, 'subject', p_subject, 'max_hits', r.max_hits,
                                 'window_seconds', r.window_seconds),
              auth.uid(), public.request_ip_hash());
      perform public.audit_write('rate_limit.block', 'rate_limit_rules', p_rule,
        'Rate limit reached: ' || r.description || ' (' || coalesce(auth.jwt() ->> 'email', p_subject) || ')',
        null, jsonb_build_object('subject', p_subject, 'max_hits', r.max_hits, 'window_seconds', r.window_seconds),
        coalesce(auth.jwt() ->> 'email', 'system'));
    end if;
    return false;
  end if;
  return true;
end $$;

-- ---------- W4: host-fit method and points live in the database, not the browser ----------
create table public.host_fit_params (
  key        text primary key,
  value      numeric not null,
  note       text,
  updated_at timestamptz not null default now()
);
alter table public.host_fit_params enable row level security;
create policy hfp_admin_all on public.host_fit_params for all to authenticated
  using (public.is_allowlisted()) with check (public.is_allowlisted());
comment on table public.host_fit_params is 'Points and multipliers for the profile-based host-fit score and bid readiness. Admins only.';

insert into public.host_fit_params (key, value, note) values
  ('bureau_yes', 15, 'Convention bureau exists'), ('bureau_partial', 7, 'Bureau partial'),
  ('bids_yes', 15, 'Bids formally'), ('bids_informal', 6, 'Bids informally'),
  ('subvention_yes', 10, 'Subvention fund'), ('subvention_partial', 5, 'Subvention partial'),
  ('visa_max', 15, 'Visa ease at 5 of 5'), ('air_max', 15, 'Cap on international non-stops'),
  ('venue_max', 20, 'Plenary meets typical size'), ('venue_unknown_size', 12, 'Plenary recorded, delegate count unknown'),
  ('icca_top10', 10, 'ICCA 2024 Africa top 10'),
  ('open_open', 1, 'Winnability: open'), ('open_partly', 0.8, 'Winnability: partly open'),
  ('open_unknown', 0.6, 'Winnability: unknown'), ('open_rotation', 0.35, 'Winnability: rotation-bound'),
  ('open_fixed', 0, 'Winnability: fixed or closed'),
  ('advisory_amber', 0.5, 'Amber travel advisory'), ('advisory_red', 0, 'Red travel advisory'),
  ('readiness_seats_per_point', 150, 'Bid readiness: plenary seats per venue point');

create or replace function public.fit_band(p_score numeric, p_scale numeric)
returns text language sql immutable set search_path = public as $$
  select case when p_score is null then null
              when p_score >= 0.7 * p_scale then 'Strong fit'
              when p_score >= 0.4 * p_scale then 'Moderate fit'
              else 'Weak fit' end
$$;

create or replace function public.host_fit(p_country_id integer, p_attendance integer, p_openness text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.destination_profiles; w jsonb; parts jsonb; raw numeric; mult numeric; adv numeric; ok text; venue numeric; sc numeric;
begin
  select * into p from public.destination_profiles where country_id = p_country_id;
  if not found then return null; end if;
  select jsonb_object_agg(key, value) into w from public.host_fit_params;
  venue := case when p.largest_plenary is null then 0
                when p_attendance is null then (w->>'venue_unknown_size')::numeric
                when p.largest_plenary >= p_attendance then (w->>'venue_max')::numeric
                else round((w->>'venue_max')::numeric * p.largest_plenary / p_attendance) end;
  parts := jsonb_build_array(
    jsonb_build_array('Bureau', case when p.bureau_exists ~* '^yes' then (w->>'bureau_yes')::numeric
                                     when p.bureau_exists ~* 'partial' then (w->>'bureau_partial')::numeric else 0 end, (w->>'bureau_yes')::numeric),
    jsonb_build_array('Bids formally', case when p.bids_formally ~* '^yes' then (w->>'bids_yes')::numeric
                                            when p.bids_formally ~* 'informal' then (w->>'bids_informal')::numeric else 0 end, (w->>'bids_yes')::numeric),
    jsonb_build_array('Subvention fund', case when p.subvention_fund ~* '^yes' then (w->>'subvention_yes')::numeric
                                              when p.subvention_fund ~* 'partial' then (w->>'subvention_partial')::numeric else 0 end, (w->>'subvention_yes')::numeric),
    jsonb_build_array('Visa ease', round(coalesce(p.visa_ease, 0) / 5.0 * (w->>'visa_max')::numeric), (w->>'visa_max')::numeric),
    jsonb_build_array('Air access', least((w->>'air_max')::numeric, coalesce(p.intl_nonstops, 0)), (w->>'air_max')::numeric),
    jsonb_build_array('Venue vs size', venue, (w->>'venue_max')::numeric),
    jsonb_build_array('ICCA 2024 top 10', case when p.icca_2024_top10 then (w->>'icca_top10')::numeric else 0 end, (w->>'icca_top10')::numeric));
  select sum((x->>1)::numeric) into raw from jsonb_array_elements(parts) x;
  ok := coalesce(p_openness, 'unknown');
  mult := coalesce((w->>('open_' || ok))::numeric, (w->>'open_unknown')::numeric);
  adv := case p.advisory_level when 'red' then (w->>'advisory_red')::numeric when 'amber' then (w->>'advisory_amber')::numeric else 1 end;
  sc := round(raw * mult * adv) / 20.0;
  return jsonb_build_object('score', sc, 'band', public.fit_band(sc, 5), 'parts', parts, 'mult', mult, 'adv', adv, 'open_key', ok);
end $$;
revoke execute on function public.host_fit(integer, integer, text) from public, anon, authenticated;

create or replace function public.destination_readiness(p_country_id integer)
returns integer language plpgsql stable security definer set search_path = public as $$
declare f jsonb; p public.destination_profiles; w jsonb; raw numeric;
begin
  select * into p from public.destination_profiles where country_id = p_country_id;
  if not found then return null; end if;
  select jsonb_object_agg(key, value) into w from public.host_fit_params;
  f := public.host_fit(p_country_id, null, 'open');
  select sum((x->>1)::numeric) into raw from jsonb_array_elements(f->'parts') x where x->>0 <> 'Venue vs size';
  raw := raw + case when p.largest_plenary is null then 0
                    else least((w->>'venue_max')::numeric, round(p.largest_plenary / (w->>'readiness_seats_per_point')::numeric)) end;
  return round(raw * (f->>'adv')::numeric);
end $$;
revoke execute on function public.destination_readiness(integer) from public, anon, authenticated;

-- Admin screens: scores and breakdowns for the priority destinations, computed here.
create or replace function public.admin_fit_scores()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_allowlisted() then raise exception 'admins only' using errcode = '42501'; end if;
  return jsonb_build_object(
    'events', coalesce((select jsonb_object_agg(e.id, (
        select coalesce(jsonb_agg(jsonb_build_object('country_id', c.id) || f.j order by (f.j->>'score')::numeric desc), '[]'::jsonb)
        from public.countries c cross join lateral (select public.host_fit(c.id, e.typical_attendance, e.openness_2027_29) j) f
        where c.priority and f.j is not null)) from public.events e), '{}'::jsonb),
    'opportunities', coalesce((select jsonb_object_agg(o.id, (
        select coalesce(jsonb_agg(jsonb_build_object('country_id', c.id) || f.j order by (f.j->>'score')::numeric desc), '[]'::jsonb)
        from public.countries c cross join lateral (select public.host_fit(c.id, null,
               case when o.list_status::text = 'closed' or (o.submission_deadline < current_date) then 'fixed' else 'open' end) j) f
        where c.priority and f.j is not null)) from public.bid_opportunities o), '{}'::jsonb),
    'readiness', coalesce((select jsonb_object_agg(dp.country_id, public.destination_readiness(dp.country_id)) from public.destination_profiles dp), '{}'::jsonb));
end $$;
revoke execute on function public.admin_fit_scores() from public, anon;
grant execute on function public.admin_fit_scores() to authenticated;

-- ---------- W5: every record names its source ----------
alter table public.bid_opportunities add column source_name text;
alter table public.events add column source_name text;
update public.bid_opportunities set source_name = regexp_replace(primary_source_url, '^https?://(www\.)?([^/:?#]+).*$', '\2')
 where source_name is null and coalesce(primary_source_url, '') <> '';
update public.events set source_name = regexp_replace(source_url, '^https?://(www\.)?([^/:?#]+).*$', '\2')
 where source_name is null and coalesce(source_url, '') <> '';

-- tg_argv[0] is the link column. A missing name is filled from the link's host, so the weekly scan keeps working.
-- A row saved before this rule without a link may still be updated (the nightly jobs touch it) but not cleared of one.
create or replace function public.record_source_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare n jsonb := to_jsonb(new); u text := nullif(btrim(n ->> tg_argv[0]), '');
begin
  if u is null then
    if tg_op = 'UPDATE' and nullif(btrim(to_jsonb(old) ->> tg_argv[0]), '') is null then return new; end if;
    raise exception 'Every record needs a source link.' using errcode = 'check_violation';
  end if;
  if nullif(btrim(n ->> 'source_name'), '') is null then
    new := jsonb_populate_record(new, jsonb_build_object('source_name', regexp_replace(u, '^https?://(www\.)?([^/:?#]+).*$', '\2')));
  end if;
  return new;
end $$;
revoke execute on function public.record_source_guard() from public, anon, authenticated;
create trigger bid_opportunities_source before insert or update on public.bid_opportunities
  for each row execute function public.record_source_guard('primary_source_url');
create trigger events_source before insert or update on public.events
  for each row execute function public.record_source_guard('source_url');

-- ---------- W6: 14-word quote cap and the Draft to Reviewed gate ----------
create or replace function public.longest_quote_words(t text)
returns integer language sql immutable set search_path = public as $$
  select coalesce(max(array_length(regexp_split_to_array(btrim(m[1]), '\s+'), 1)), 0)
  from regexp_matches(coalesce(t, ''), '["“]([^"“”]+)["”]', 'g') m
$$;

alter table public.bid_wins add column reviewed_by text, add column reviewed_at timestamptz;

create or replace function public.bid_wins_review_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.win_factors_status = 'reviewed' then
    if public.longest_quote_words(new.win_factors) > 14 then
      raise exception 'Win factors quote more than 14 words in a row. Shorten the quote before marking it reviewed.' using errcode = 'check_violation';
    end if;
    if tg_op = 'INSERT' or old.win_factors_status is distinct from 'reviewed' or old.win_factors is distinct from new.win_factors then
      new.reviewed_by := public.admin_actor(); new.reviewed_at := now();
    end if;
  else
    new.reviewed_by := null; new.reviewed_at := null;
  end if;
  return new;
end $$;
revoke execute on function public.bid_wins_review_guard() from public, anon, authenticated;
create trigger bid_wins_review before insert or update on public.bid_wins
  for each row execute function public.bid_wins_review_guard();

alter table public.destination_profiles
  add column text_status text not null default 'draft' check (text_status in ('draft', 'reviewed')),
  add column reviewed_by text, add column reviewed_at timestamptz;
comment on column public.destination_profiles.text_status is
  'Review state of the written fields (bureau_detail, venue_detail, visa_detail, fcdo_summary). Bureaux see them only when reviewed.';

create or replace function public.destination_profiles_review_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare changed boolean;
begin
  changed := tg_op = 'INSERT' or (old.bureau_detail, old.venue_detail, old.visa_detail, old.fcdo_summary)
             is distinct from (new.bureau_detail, new.venue_detail, new.visa_detail, new.fcdo_summary);
  -- Edited text goes back to Draft unless this same update is the review.
  if tg_op = 'UPDATE' and changed and old.text_status = 'reviewed' and new.text_status = 'reviewed' then
    new.text_status := 'draft';
  end if;
  if new.text_status = 'reviewed' then
    if greatest(public.longest_quote_words(new.bureau_detail), public.longest_quote_words(new.venue_detail),
                public.longest_quote_words(new.visa_detail), public.longest_quote_words(new.fcdo_summary)) > 14 then
      raise exception 'The profile text quotes more than 14 words in a row. Shorten the quote before marking it reviewed.' using errcode = 'check_violation';
    end if;
    if tg_op = 'INSERT' or old.text_status is distinct from 'reviewed' then
      new.reviewed_by := public.admin_actor(); new.reviewed_at := now();
    end if;
  else
    new.reviewed_by := null; new.reviewed_at := null;
  end if;
  return new;
end $$;
revoke execute on function public.destination_profiles_review_guard() from public, anon, authenticated;
create trigger destination_profiles_review before insert or update on public.destination_profiles
  for each row execute function public.destination_profiles_review_guard();

-- Bureaux read their own profile row directly only once its text is reviewed (structured values come through portal_data).
drop policy dp_bureau_own on public.destination_profiles;
create policy dp_bureau_own on public.destination_profiles for select to authenticated
  using (country_id = (select public.bureau_country_id()) and text_status = 'reviewed');

-- Admin action: mark a profile's text reviewed (the trigger runs the quote check and stamps the reviewer).
create or replace function public.profile_text_review(p_country_id integer, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_allowlisted() then raise exception 'admins only' using errcode = '42501'; end if;
  if p_status not in ('draft', 'reviewed') then raise exception 'invalid status'; end if;
  update public.destination_profiles set text_status = p_status, updated_at = now() where country_id = p_country_id;
  return (select jsonb_build_object('ok', true, 'text_status', text_status, 'reviewed_by', reviewed_by, 'reviewed_at', reviewed_at)
          from public.destination_profiles where country_id = p_country_id);
end $$;
revoke execute on function public.profile_text_review(integer, text) from public, anon;
grant execute on function public.profile_text_review(integer, text) to authenticated;

-- ---------- bureau payloads: server-side host fit, source names, reviewed text only ----------
create or replace function public.portal_data(cid integer)
returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare res jsonb;
begin
  with m as (
    select vm.* from public.v_sector_matches vm
    where vm.country_id = cid
      and not exists (select 1 from public.bid_alignments d where d.country_id=cid and d.status='dismissed'
                      and ((vm.kind='opportunity' and d.opportunity_id=vm.item_id) or (vm.kind='event' and d.event_id=vm.item_id))
                      and (d.econ_sector_id is null or d.econ_sector_id = vm.econ_sector_id))
  ), a as (
    select ba.*, case when ba.opportunity_id is not null then 'opportunity' else 'event' end kind,
           coalesce(ba.opportunity_id, ba.event_id) item_id
    from public.bid_alignments ba where ba.country_id=cid and ba.status='confirmed' and ba.share_with_bureau
  ), items as (
    select kind, item_id from m union select kind, item_id from a
  ), scored as (
    select i.kind, i.item_id,
      coalesce((select jsonb_agg(distinct s.name) from m join public.econ_sectors s on s.id=m.econ_sector_id where m.kind=i.kind and m.item_id=i.item_id),'[]'::jsonb) as sectors,
      coalesce((select jsonb_agg(jsonb_build_object('sector',s.name,'policy',p.title,'policy_short',p.short_name,'rationale',a.rationale,'strength',a.strength))
                from a left join public.econ_sectors s on s.id=a.econ_sector_id left join public.policy_frameworks p on p.id=a.policy_id
                where a.kind=i.kind and a.item_id=i.item_id),'[]'::jsonb) as alignments,
      coalesce((select jsonb_agg(distinct coalesce(p.short_name,p.title)) from m join public.policy_frameworks p on p.id=m.policy_id where m.kind=i.kind and m.item_id=i.item_id),'[]'::jsonb) as policies,
      coalesce((select sum(6 - m.priority_rank + case when m.is_primary then 1 else 0 end) from m where m.kind=i.kind and m.item_id=i.item_id),0)
       + coalesce((select sum(a.strength*2) from a where a.kind=i.kind and a.item_id=i.item_id),0) as fit
    from items i
  )
  select jsonb_build_object(
    'country', (select jsonb_build_object('id',c.id,'name',c.name,'iso2',c.iso2,'region',c.region,'afcfta_status',c.afcfta_status,
        'mice_summary',c.mice_summary,'bureau_name',c.bureau_name,'transport_summary',c.transport_summary,
        'visa_regime',c.visa_regime,'visa_notes',c.visa_notes,'visa_africa',c.visa_africa,'evisa',c.evisa,'visa_on_arrival',c.visa_on_arrival,
        'univisa',c.univisa,'visa_portal_url',c.visa_portal_url,'visa_verified_on',c.visa_verified_on,'visa_events_note',c.visa_events_note)
      from public.countries c where c.id=cid),
    'profile', (select case when dp.text_status = 'reviewed' then to_jsonb(dp)
                            else to_jsonb(dp) - 'bureau_detail' - 'venue_detail' - 'visa_detail' - 'fcdo_summary' end
                       - 'updated_at' - 'reviewed_by'
                from public.destination_profiles dp where dp.country_id=cid),
    'policies', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'short_name',p.short_name,'level',p.level,'sector',s.name,
        'period_start',p.period_start,'period_end',p.period_end,'issuing_body',p.issuing_body,'status',p.status,'summary',p.summary,
        'source_url',p.source_url,'document_path',p.document_path,'parent_id',p.parent_id) order by p.level, p.period_end desc nulls last)
      from public.policy_frameworks p left join public.econ_sectors s on s.id=p.econ_sector_id where p.country_id=cid),'[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('sector',s.name,'code',s.code,'rank',cs.priority_rank,'policy',p.title,'policy_short',p.short_name,
        'reference',cs.policy_reference,'target',cs.target,'mice_angle',cs.mice_angle,
        'n_items',(select count(distinct (m.kind, m.item_id)) from m where m.econ_sector_id=cs.econ_sector_id)) order by cs.priority_rank, s.sort)
      from public.country_sectors cs join public.econ_sectors s on s.id=cs.econ_sector_id left join public.policy_frameworks p on p.id=cs.policy_id where cs.country_id=cid),'[]'::jsonb),
    'bids', coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'title',o.title,'issuing_body',o.issuing_body,'event_type',o.event_type,'bid_type',o.bid_type,
        'eligibility',o.eligibility,'submission_deadline',o.submission_deadline,'required_documents',o.required_documents,'source_url',o.primary_source_url,
        'source_name',o.source_name,
        'summary',o.summary,'host_year',o.host_year,'status',o.list_status,'sectors',sc.sectors,'policies',sc.policies,'alignments',sc.alignments,'fit',sc.fit,
        'confidence',o.confidence,'verified_on',o.verified_on,'source_tier',o.source_tier,'edition_label',o.edition_label,'host_selection',o.host_selection)
        order by sc.fit desc, o.submission_deadline nulls last)
      from scored sc join public.bid_opportunities o on o.id=sc.item_id
      where sc.kind='opportunity' and o.list_status in ('open','watchlist') and (o.submission_deadline is null or o.submission_deadline >= current_date)),'[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.event_name,'organiser',e.organiser,'scope',e.scope,'edition_year',e.edition_year,
        'attendance',e.typical_attendance,'rotation',e.rotation_pattern,'host_requirements',e.host_requirements,'bid_deadline',e.bid_deadline,
        'next_edition',e.next_available_edition,'status',e.bid_status,'source_url',e.source_url,'source_name',e.source_name,
        'sectors',sc.sectors,'policies',sc.policies,'alignments',sc.alignments,'fit',sc.fit,
        'host_fit',hf.score, 'host_fit_band', public.fit_band(hf.score, 5),
        'confidence',e.confidence,'verified_on',e.verified_on,'source_tier',e.source_tier,'edition_label',e.edition_label,
        'host_selection',e.host_selection,'decision_body',e.decision_body,'lead_time',e.lead_time,
        'openness_2027_29',e.openness_2027_29,'openness_note',e.openness_note,'fixed_venue',e.fixed_venue)
        order by sc.fit desc)
      from scored sc join public.events e on e.id=sc.item_id
      cross join lateral (select coalesce((public.host_fit(cid, e.typical_attendance, e.openness_2027_29) ->> 'score')::numeric,
                                          (select cm.total_score from public.country_matches cm where cm.event_id=e.id and cm.country_id=cid limit 1)) score) hf
      where sc.kind='event' and e.bid_status not in ('lost','not_pursued','awarded')),'[]'::jsonb)
  ) into res;
  return res;
end $function$;

create or replace function public.bureau_matches(p_country_id integer default null, p_tier text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
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
      'source_name', o.source_name, 'verified_on', o.verified_on, 'confidence_record', o.confidence,
      'score', ms.score, 'band', public.fit_band(ms.score, 100),
      'sub_scores', ms.sub_scores, 'reasons', to_jsonb(ms.reasons), 'gaps', to_jsonb(ms.gaps),
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

revoke execute on function public.fit_band(numeric, numeric) from public, anon, authenticated;
revoke execute on function public.longest_quote_words(text) from public, anon, authenticated;
