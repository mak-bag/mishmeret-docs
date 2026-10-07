-- TECHLEAD v1.0 · M1 · 06/10/2026 · two migrations, staging first, then production.
-- Design: ROUND-U §7 #3 (real count in onboarding), TECHLEAD-DECISIONS-05-10 (offer notice).

-- ── M1a · v1_shift_counts_view ─────────────────────────────────────────────────
-- Onboarding shows "N jobs in range" BEFORE the user has an account. A function for anon
-- would break the privilege floor (anon = 0 functions). A view is SELECT — the floor holds.
-- It exposes counts only (city_id, radius_km, n): no shift, no business, no person.
-- Owner-privileged (postgres) on purpose: anon sees 0 shift rows under RLS; the view
-- aggregates them. Same predicate as shifts_for_me (open, live, business open, both radii),
-- and computed at read time — so it can never show a job that already ended.
create or replace view public.shift_counts with (security_barrier = true) as
select c.id as city_id, r.km as radius_km,
       count(s.id)::int as n
from public.cities c
cross join (values (5),(10),(15),(20),(30),(40),(60)) as r(km)
left join public.shifts s
  on  s.ends_at > now()
  and s.cancelled_at is null
  and s.filled < s.slots
  and exists (select 1 from public.businesses b where b.id = s.business_id and b.closed_at is null)
  and extensions.ST_DWithin(s.location,
        extensions.ST_SetSRID(extensions.ST_MakePoint(c.lng, c.lat),4326)::extensions.geography,
        r.km * 1000)
  and (s.max_distance_km is null
       or extensions.ST_DWithin(s.location,
            extensions.ST_SetSRID(extensions.ST_MakePoint(c.lng, c.lat),4326)::extensions.geography,
            s.max_distance_km * 1000))
group by c.id, r.km;

revoke all on public.shift_counts from public, anon, authenticated;
grant select on public.shift_counts to anon, authenticated;
comment on view public.shift_counts is
  'Counts only, for onboarding before sign-up. Owner-privileged by design; never add a column that identifies a shift, business or person.';

-- ── M1b · v1_offer_notification ────────────────────────────────────────────────
-- A business offer created no notification: the worker simply did not know (founder, 05/10).
-- Trigger, like notify_opened: offer_shift itself is untouched. notifications_once
-- (user_id, kind, shift_id) keeps a re-offer from notifying twice.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind = any (array['new_shift','opened','rate_prompt','offered']));

create or replace function private.notify_offered()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  if new.status = 'offered' and new.initiated_by = 'business'
     and (tg_op = 'INSERT' or old.status is distinct from 'offered') then
    insert into public.notifications(user_id, kind, shift_id, business_id)
    select new.worker_id, 'offered', new.shift_id, s.business_id
      from public.shifts s where s.id = new.shift_id
    on conflict do nothing;
  end if;
  return new;
end $function$;
revoke all on function private.notify_offered() from public, anon, authenticated;

drop trigger if exists applications_notify_offered on public.applications;
create trigger applications_notify_offered
  after insert or update of status on public.applications
  for each row execute function private.notify_offered();

insert into public.terms(kind, code, lang, label) values
 ('ui','ui.notif_offered','he','{n} מציעים לך משמרת'),
 ('ui','ui.notif_offered','en','{n} offered you a shift'),
 ('ui','ui.empty_offer','he','יש לך הצעה שמחכה לתשובה'),
 ('ui','ui.empty_offer','en','You have an offer waiting for your answer')
on conflict do nothing;

-- ROLLBACK:
--   drop view public.shift_counts;
--   drop trigger applications_notify_offered on public.applications; drop function private.notify_offered();
--   delete from notifications where kind='offered';
--   alter table notifications drop constraint notifications_kind_check;
--   alter table notifications add constraint notifications_kind_check check (kind = any (array['new_shift','opened','rate_prompt']));
