-- Let admins (allowlisted emails) insert, update and delete events.
-- Until now events had only a read policy, so admin edits, "Mark checked today"
-- and confirming a submission into Strategic Events were all blocked by RLS.
-- Bureau users stay read-nothing: they reach events only through their RPCs.
create policy events_admin_all on public.events
  for all to authenticated
  using (public.is_allowlisted())
  with check (public.is_allowlisted());
