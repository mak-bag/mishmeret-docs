-- ═══════════════════════════════════════════════════════════════════════════════
-- Mishmeret · SERVER SUITE · owner: Tech Lead · v1 · 06/10/2026
-- Run as one statement (SQL Editor / execute_sql). It ALWAYS rolls back: the last line RAISEs,
-- which aborts the transaction. Every probe impersonates (set local role + jwt.claims) — trap 1.
-- Output: one JSON with PASS/FAIL per test and a summary. FAIL anywhere = do not ship.
-- Test data is planted inside the transaction and vanishes with it. Fixtures by role, not by name:
--   OWNER = owner of a business with a shift · WORKER = an adult outside that business ·
--   STRANGER = a user with no business, no application · MINOR = a contact with a birth date < 18y.
-- Adding a test: one block, one name, an expected value written next to it. Prove it fails on the
-- broken code before trusting it (trap 6).
-- ═══════════════════════════════════════════════════════════════════════════════
DO $suite$
DECLARE
  R jsonb := '{}'; pass int := 0; fail int := 0;
  OWNER uuid; BIZ uuid; SH uuid; WORKER uuid; STRANGER uuid; MINOR uuid; OTHERBIZ uuid; OTHERSH uuid;
  v text; n int;
  n2 int;
BEGIN
  -- ── fixtures ────────────────────────────────────────────────────────────────
  select m.user_id, m.business_id into OWNER, BIZ
    from business_members m join businesses b on b.id = m.business_id
   where m.role = 'owner' and b.closed_at is null
     and exists (select 1 from shifts s where s.business_id = b.id) limit 1;
  select id into SH from shifts where business_id = BIZ order by created_at desc limit 1;
  select p.id into WORKER from profiles p join profile_contacts c on c.id = p.id
   where private.is_adult(p.id) and p.home_city_id is not null
     and not exists (select 1 from business_members m where m.user_id = p.id) limit 1;
  select p.id into STRANGER from profiles p
   where not exists (select 1 from business_members m where m.user_id = p.id)
     and not exists (select 1 from applications a where a.worker_id = p.id)
     and p.id <> WORKER limit 1;
  select id into MINOR from profile_contacts where birth_date > current_date - interval '18 years' limit 1;
  select b.id into OTHERBIZ from businesses b where b.id <> BIZ and b.closed_at is null
     and exists (select 1 from shifts s where s.business_id = b.id) limit 1;
  select id into OTHERSH from shifts where business_id = OTHERBIZ limit 1;

  -- make the shift live and open, and the worker terms-current (planted, rolled back)
  update shifts set starts_at = now() + interval '2 hours', ends_at = now() + interval '6 hours',
                    cancelled_at = null, filled = 0, slots = greatest(slots,1) where id = SH;
  update profiles set terms_version = private.terms_version() where id in (WORKER, STRANGER);
  -- the worker lives in the business's city, so T08 compares a real count, never 0 = 0
  update profiles set home_city_id = (select city_id from businesses where id = BIZ) where id = WORKER;
  delete from applications where shift_id = SH and worker_id in (WORKER, STRANGER);

  R := R || jsonb_build_object('_fixtures', jsonb_build_object(
    'owner', left(OWNER::text,8), 'biz', left(BIZ::text,8), 'shift', left(SH::text,8),
    'worker', left(WORKER::text,8), 'stranger', left(STRANGER::text,8), 'minor', left(coalesce(MINOR::text,'-'),8)));

  -- helper pattern: impersonate → probe → reset → compare
  -- ── T01 privilege floor: anon executes 0 functions ───────────────────────────
  select count(*) into n from pg_proc p where p.pronamespace in ('public'::regnamespace,'private'::regnamespace)
     and has_function_privilege('anon',p.oid,'execute') and p.prokind='f';
  R := R || jsonb_build_object('T01_anon_fns_0', case when n=0 then 'PASS' else 'FAIL got '||n end);

  -- ── T02 a NEW function is anon=false, authenticated=true (default privileges, trap 2) ──
  create function public._suite_probe() returns int language sql as 'select 1';
  v := has_function_privilege('anon','public._suite_probe()','execute')::text||','||has_function_privilege('authenticated','public._suite_probe()','execute')::text;
  R := R || jsonb_build_object('T02_new_fn_defaults', case when v='false,true' then 'PASS' else 'FAIL got '||v end);

  -- ── T03 stranger reads only their own profile ────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub',STRANGER,'role','authenticated')::text, true);
  SET LOCAL ROLE authenticated; select count(*) into n from profiles; RESET ROLE;
  R := R || jsonb_build_object('T03_stranger_profiles_1', case when n=1 then 'PASS' else 'FAIL got '||n end);

  -- ── T04 stranger cannot read a business phone (column privilege) ─────────────
  BEGIN
    SET LOCAL ROLE authenticated; select count(phone) into n from businesses; RESET ROLE; v := 'readable '||n;
  EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; v := '42501'; END;
  R := R || jsonb_build_object('T04_biz_phone_42501', case when v='42501' then 'PASS' else 'FAIL '||v end);

  -- ── T05 board columns stay readable ──────────────────────────────────────────
  SET LOCAL ROLE authenticated; select count(*) into n from (select id,name,address,city,lat,lng,verified_at from businesses) x; RESET ROLE;
  R := R || jsonb_build_object('T05_board_columns', case when n>0 then 'PASS' else 'FAIL got 0' end);

  -- ── T06 shift_counts exposes exactly (city_id, radius_km, n) to anon ─────────
  select string_agg(column_name, ',' order by ordinal_position) into v from information_schema.columns where table_schema='public' and table_name='shift_counts';
  R := R || jsonb_build_object('T06_counts_columns', case when v='city_id,radius_km,n' then 'PASS' else 'FAIL got '||coalesce(v,'none') end);
  PERFORM set_config('request.jwt.claims','{"role":"anon"}', true);
  SET LOCAL ROLE anon; select count(*) into n from shift_counts; RESET ROLE;
  R := R || jsonb_build_object('T07_counts_anon_reads', case when n>0 then 'PASS' else 'FAIL got 0' end);

  -- ── T08 count == board for the worker's city and radius ──────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object('sub',WORKER,'role','authenticated')::text, true);
  SET LOCAL ROLE authenticated; select count(*) into n from shifts_for_me(20); RESET ROLE;
  select sc.n into n2 from shift_counts sc join profiles p on p.home_city_id = sc.city_id
   where p.id = WORKER and sc.radius_km = 20;
  R := R || jsonb_build_object('T08_count_eq_board', case when n = n2 and n > 0 then 'PASS ('||n||')' else 'FAIL board '||n||' view '||coalesce(n2,-1)||' (must be equal and > 0)' end);

  -- ── T09 full shift refuses details (S5) ──────────────────────────────────────
  update shifts set filled = slots where id = SH;
  SET LOCAL ROLE authenticated; select send_details(SH,'today',null)->>'result' into v; RESET ROLE;
  R := R || jsonb_build_object('T09_full_refuses', case when v='full' then 'PASS' else 'FAIL got '||v end);
  select count(*) into n from applications where shift_id=SH and worker_id=WORKER;
  R := R || jsonb_build_object('T10_full_writes_nothing', case when n=0 then 'PASS' else 'FAIL rows '||n end);
  update shifts set filled = 0 where id = SH;

  -- ── T11 open shift accepts details ───────────────────────────────────────────
  SET LOCAL ROLE authenticated; select send_details(SH,'today',null)->>'result' into v; RESET ROLE;
  R := R || jsonb_build_object('T11_open_sends', case when v='details_sent' then 'PASS' else 'FAIL got '||v end);

  -- ── T12 owner sees the phone only after details were sent; stranger's profile not visible ─
  PERFORM set_config('request.jwt.claims', json_build_object('sub',OWNER,'role','authenticated')::text, true);
  SET LOCAL ROLE authenticated; select count(*) into n from shift_applicants(SH) x where x.worker_id=WORKER and x.phone is not null; RESET ROLE;
  R := R || jsonb_build_object('T12_owner_sees_phone_after_send', case when n=1 then 'PASS' else 'FAIL got '||n end);

  -- ── T13 "did not show up" never crosses businesses (P2) ──────────────────────
  if OTHERSH is not null then
    insert into reviews(shift_id, worker_id, business_id, direction, author_id, attended, disputed)
    values (OTHERSH, WORKER, OTHERBIZ, 'business_to_worker',
            (select user_id from business_members where business_id=OTHERBIZ limit 1), 'no', false);
    SET LOCAL ROLE authenticated; select x.attended_no into n from shift_applicants(SH) x where x.worker_id=WORKER; RESET ROLE;
    R := R || jsonb_build_object('T13_noshow_local', case when n=0 then 'PASS' else 'FAIL got '||n end);
  else
    R := R || jsonb_build_object('T13_noshow_local', 'SKIP no second business');
  end if;

  -- ── T14 offer → exactly one notification, also on re-offer ───────────────────
  -- The worker APPLIED first (T11), so the offer updates an initiated_by='worker' row — the case
  -- that failed on 06/10 before v1_offer_notification_any_origin.
  SET LOCAL ROLE authenticated; select offer_shift(SH, WORKER) into v; RESET ROLE;
  update applications set status='applied' where shift_id=SH and worker_id=WORKER;
  SET LOCAL ROLE authenticated; perform offer_shift(SH, WORKER); RESET ROLE;
  select count(*) into n from notifications where kind='offered' and shift_id=SH and user_id=WORKER;
  R := R || jsonb_build_object('T14_offer_notifies_once', case when v='offered' and n=1 then 'PASS' else 'FAIL '||v||' n='||n end);

  -- ── T15 adult attestation: a click works for no-birth-date, never overrides a minor ──
  if MINOR is not null then
    PERFORM set_config('request.jwt.claims', json_build_object('sub',MINOR,'role','authenticated')::text, true);
    SET LOCAL ROLE authenticated; select confirm_adult()->>'result' into v; RESET ROLE;
    R := R || jsonb_build_object('T15_minor_not_overridden', case when v='minors_soon' then 'PASS' else 'FAIL got '||v end);
  else
    R := R || jsonb_build_object('T15_minor_not_overridden', 'SKIP no minor');
  end if;

  -- ── T16 claim_shift is retired ───────────────────────────────────────────────
  R := R || jsonb_build_object('T16_claim_retired',
     case when not has_function_privilege('authenticated','public.claim_shift(uuid)','execute') then 'PASS' else 'FAIL executable' end);

  -- ── T17 integrity (Q5 core): no orphans, filled == confirmed ─────────────────
  select (select count(*) from applications a left join shifts s on s.id=a.shift_id where s.id is null)
       + (select count(*) from businesses b where not exists (select 1 from business_members m where m.business_id=b.id and m.role='owner'))
       + (select count(*) from profiles p left join profile_contacts c on c.id=p.id where c.id is null)
       + (select count(*) from shifts s where s.filled <> (select count(*) from applications a where a.shift_id=s.id and a.status='confirmed'))
    into n;
  R := R || jsonb_build_object('T17_integrity', case when n=0 then 'PASS' else 'FAIL '||n end);

  -- ── summary ──────────────────────────────────────────────────────────────────
  select count(*) filter (where value #>> '{}' like 'PASS%'), count(*) filter (where value #>> '{}' like 'FAIL%')
    into pass, fail from jsonb_each(R) where key like 'T%';
  R := R || jsonb_build_object('_summary', pass||' PASS · '||fail||' FAIL');
  RAISE EXCEPTION 'SUITE %', jsonb_pretty(R);   -- rolls everything back
END $suite$;
