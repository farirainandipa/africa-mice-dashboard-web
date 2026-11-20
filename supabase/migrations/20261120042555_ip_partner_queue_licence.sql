-- IP website change W1: the partner review queue shows which submission licence version each submission accepted.
-- Rewrites profile_review_queue() with two extra keys; the rest of the definition is unchanged.
do $$
declare d text := pg_get_functiondef('public.profile_review_queue()'::regprocedure);
        k text := $k$'reviewer_note', s.reviewer_note,$k$;
begin
  if position(k in d) = 0 then raise exception 'profile_review_queue has changed; update this migration'; end if;
  execute replace(d, k, k || $k$ 'licence_version', s.licence_version, 'licence_accepted_at', s.licence_accepted_at,$k$);
end $$;
