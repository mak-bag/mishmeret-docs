-- TECHLEAD P1 · 01/10/2026 · migration name: profiles_read_least_privilege
-- Finding (impersonation, rollback): an unrelated signed-in user (622e99d0) reads ALL 13 profiles —
--   full_name, given/family name, home city, bio, preferences, notify radius, terms acceptance.
--   Policy was: profiles_read [SELECT] using (true).
-- Who legitimately reads another person's profile (app.html:1437 is the only direct read):
--   the person themself · a business the worker shared details with / was offered or confirmed
--   (private.may_see_worker) · the business's team · co-members of the same business.
-- STATUS: ‼ SUPERSEDED 01/10 by TECHLEAD-SEC-01-APPLY-NOW.sql — DO NOT APPLY THIS FILE.

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (
  id = (select auth.uid())
  or private.may_see_worker(id)
  or exists (select 1 from public.team_members t
              where t.worker_id = profiles.id and private.is_business_member(t.business_id))
  or exists (select 1 from public.business_members m
              where m.user_id = profiles.id and private.is_business_member(m.business_id))
);

-- ── Pass-proof (run by the Tech Lead after applying) ──
-- unrelated user 622e99d0 → 1 (self) · founder ba1722d5 → self + shared/team/co-members, < 13
-- · anon → 0 · harness: app.html:1437 still fills team names.
