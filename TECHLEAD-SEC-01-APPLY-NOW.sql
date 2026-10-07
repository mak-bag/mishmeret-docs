-- TECHLEAD SEC-01 · 01/10/2026 · apply NOW (no client change needed)
-- STATUS: ✅ APPLIED 02/10 by the founder (SQL Editor; not in schema_migrations). Verified live, rollback probe:
--   stranger 1 · worker 1 · founder 2 (team names 2/2) · owner 8587 sees the founder (confirmed worker) ·
--   anon 0 · anon_fns 0 · a NEW function → anon=false, authenticated=true · advisors: nothing new.
-- Supersedes TECHLEAD-P1-PROFILES-RLS.sql — do NOT apply both.
-- Source: SECURITY-REVIEW-2026-10-01 §2 (may_see_profile — immune to future RLS on team_members,
--         the reviewer's robustness point, accepted) + §3 CORRECTED by the Tech Lead:
--   the review's `alter default privileges in schema public revoke execute ... from public, anon`
--   does NOT remove PUBLIC — Postgres can't revoke a global default per schema.
--   Measured in rollback: a new function still got `=X/postgres` and anon could execute it.
--   The global form below was measured: anon false in public AND private, authenticated true.
-- Pass-proof (applied in rollback, 01/10, vs a baseline run without it):
--   profiles visible: stranger 13→1 · worker 13→1 · founder 13→2 (= self + co-member; team names resolve)
--   my_shifts, shifts_for_me, min_radius_for_shifts, shift_details, biz_dashboard, shift_applicants: identical to baseline
--   anon_fns = 0

create or replace function private.may_see_profile(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user = (select auth.uid())
      or private.may_see_worker(p_user)
      or exists (select 1 from public.business_members bm
                 where bm.user_id = p_user and private.is_business_member(bm.business_id))
      or exists (select 1 from public.team_members tm
                 where tm.worker_id = p_user and private.is_business_member(tm.business_id));
$$;
revoke all on function private.may_see_profile(uuid) from public, anon;
grant execute on function private.may_see_profile(uuid) to authenticated;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using ( private.may_see_profile(id) );

-- Trap 2, closed for good: functions created from now on are NOT executable by PUBLIC/anon.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;

-- ROLLBACK:
--   drop policy profiles_read on public.profiles;
--   create policy profiles_read on public.profiles for select to authenticated using (true);
--   drop function private.may_see_profile(uuid);
--   alter default privileges grant execute on functions to public;
