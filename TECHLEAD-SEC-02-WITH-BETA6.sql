-- TECHLEAD SEC-02 · 01/10/2026 · apply ONLY in the same window as the beta-6 deploy.
-- ‼ 03/10 SPLIT: my_businesses() was applied ALONE as migration `sec02a_my_businesses`
--   (QA found the beta-6 client calling it while it did not exist). Verified: founder 1 row + phone,
--   stranger 0, anon no execute. What remains for the window is ONLY the column revoke + grant below
--   (SEC-02b). The create function block further down is now a harmless no-op re-create.
-- WHY NOT NOW: the live site is beta-5. Its loadBiz() selects `phone` from businesses
--   directly; after this revoke the business screen breaks for every owner until beta-6 is up.
-- Finding (SECURITY-REVIEW-2026-10-01 #1, reproduced by the Tech Lead 01/10):
--   businesses_read = using (true) + full table grant → a stranger (622e99d0) reads all 6 rows
--   and 4 phone numbers. biz_number / verify_evidence are empty today; they won't be after P6.
-- Checked: no RLS policy (any schema) and no INVOKER function references the hidden columns.
--   Client reads: app.html:1329 (granted columns only) and :1401 loadBiz → replaced by my_businesses().
-- Pass-proof (rollback, 01/10): stranger → 42501 on phone · stranger/worker board columns → 6 rows ·
--   founder my_businesses → 1 row, phone present · stranger/worker my_businesses → 0.

revoke select on table public.businesses from authenticated, anon;
grant select (
  id, name, kind, country_code, currency, timezone,
  city, city_id, address, location, lat, lng, located_at,
  kosher_code, closed_at, created_at,
  verified_at, verify_level,
  cover_path, logo_path
) on table public.businesses to authenticated;
-- deliberately NOT granted: phone, biz_number, verify_evidence, verify_requested_at, verified_by, created_by

create or replace function public.my_businesses()
returns table (id uuid, name text, kind text, phone text, city text, city_id integer,
  address text, closed_at timestamptz, lat double precision, lng double precision, located_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select b.id, b.name, b.kind, b.phone, b.city, b.city_id, b.address, b.closed_at, b.lat, b.lng, b.located_at
  from public.businesses b join public.business_members m on m.business_id = b.id
  where m.user_id = (select auth.uid()) order by b.name;
$$;
revoke all on function public.my_businesses() from public, anon;
grant execute on function public.my_businesses() to authenticated;

-- ROLLBACK:
--   grant select on table public.businesses to authenticated;
--   drop function public.my_businesses();
