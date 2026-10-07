-- TECHLEAD v1.0 · M2 · 06/10/2026 · migration: v1_adult_attestation · staging first, then production.
-- ROUND-U §0 #3 + the founder's brief §1: keep "over 18 = yes" + a timestamp, not a birth date.
-- Live-compatible with beta-5.1: result codes are unchanged (need_birth_date / minors_soon), so the
-- old client behaves exactly as before; the v1.0 client calls confirm_adult() from the onboarding box.
-- birth_date is NOT dropped here. That is M2b, after v1.0 is live and no client writes it.

alter table public.profile_contacts add column if not exists adult_confirmed_at timestamptz;

-- Backfill only from data we already hold (7 adults by birth date). Nothing new is collected.
update public.profile_contacts set adult_confirmed_at = now()
 where adult_confirmed_at is null and birth_date is not null
   and birth_date <= current_date - interval '18 years';

create or replace function private.is_adult(u uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select coalesce((select adult_confirmed_at is not null
                          or birth_date <= current_date - interval '18 years'
                     from public.profile_contacts where id = u), false);
$$;
revoke all on function private.is_adult(uuid) from public, anon, authenticated;

-- One tap in onboarding. A stated birth date under 18 is not overridden by a click.
create or replace function public.confirm_adult()
returns jsonb language plpgsql security definer set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return jsonb_build_object('result','unauthenticated'); end if;
  if exists (select 1 from public.profile_contacts
              where id = v_uid and birth_date > current_date - interval '18 years') then
    return jsonb_build_object('result','minors_soon');
  end if;
  update public.profile_contacts set adult_confirmed_at = coalesce(adult_confirmed_at, now())
   where id = v_uid;
  if not found then return jsonb_build_object('result','not_found'); end if;
  return jsonb_build_object('result','confirmed');
end $$;
revoke all on function public.confirm_adult() from public, anon;
grant execute on function public.confirm_adult() to authenticated;

-- send_details: same as S5, the age block now asks is_adult() (either source).
create or replace function public.send_details(p_shift uuid, p_start_when text default null::text, p_experience text default null::text)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare s record; v_uid uuid := auth.uid(); v_prev text;
        v_exp text := nullif(btrim(coalesce(p_experience,'')),'');
begin
  if v_uid is null then return jsonb_build_object('result','unauthenticated'); end if;
  if not exists (select 1 from public.profiles where id = v_uid and terms_version = private.terms_version()) then
    return jsonb_build_object('result','need_terms','current',private.terms_version());
  end if;
  if p_start_when is not null and p_start_when not in ('today','week','later') then
    return jsonb_build_object('result','bad_start');
  end if;
  if v_exp is not null and length(v_exp) > 80 then return jsonb_build_object('result','note_too_long'); end if;

  select sh.id, sh.ends_at, sh.cancelled_at, sh.adults_only, sh.business_id, sh.slots, sh.filled, b.closed_at
    into s from public.shifts sh join public.businesses b on b.id = sh.business_id
   where sh.id = p_shift;
  if not found then return jsonb_build_object('result','not_found'); end if;
  if s.closed_at is not null then return jsonb_build_object('result','business_closed'); end if;
  if s.cancelled_at is not null then return jsonb_build_object('result','cancelled_shift'); end if;
  if s.ends_at <= now() then return jsonb_build_object('result','past'); end if;
  if private.is_business_member(s.business_id) then return jsonb_build_object('result','own_business'); end if;

  select status into v_prev from public.applications where shift_id = p_shift and worker_id = v_uid;
  if s.filled >= s.slots and v_prev is distinct from 'applied' and v_prev is distinct from 'offered'
     and v_prev is distinct from 'confirmed' then
    return jsonb_build_object('result','full');
  end if;

  if not private.is_adult(v_uid) then
    if exists (select 1 from public.profile_contacts where id = v_uid and birth_date is not null) then
      return jsonb_build_object('result','minors_soon');
    end if;
    return jsonb_build_object('result','need_birth_date');
  end if;

  if v_prev in ('applied','offered','confirmed') then return jsonb_build_object('result','already_applied'); end if;
  if v_prev = 'declined' then return jsonb_build_object('result','declined_before'); end if;

  insert into public.applications(shift_id, worker_id, status, initiated_by, contact_shared_at, start_when, experience_note, opened_at)
  values (p_shift, v_uid, 'applied', 'worker', now(), p_start_when, v_exp, null)
  on conflict (shift_id, worker_id) do update
    set status = 'applied', initiated_by = 'worker', contact_shared_at = now(),
        start_when = excluded.start_when, experience_note = excluded.experience_note,
        opened_at = null, confirmed_at = null;
  return jsonb_build_object('result','details_sent');
end $function$;
revoke all on function public.send_details(uuid,text,text) from public, anon;
grant execute on function public.send_details(uuid,text,text) to authenticated;

-- offer_shift: the age block asks is_adult() instead of reading birth_date.
create or replace function public.offer_shift(p_shift uuid, p_worker uuid)
 returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v_ends timestamptz; v_cancelled timestamptz; v_closed timestamptz;
        v_slots int; v_open int; v_biz uuid; v_known boolean;
begin
  if auth.uid() is null then return 'unauthenticated'; end if;
  v_biz := private.shift_business(p_shift);
  if not private.is_business_member(v_biz) then return 'forbidden'; end if;

  select s.ends_at, s.cancelled_at, s.slots, b.closed_at
    into v_ends, v_cancelled, v_slots, v_closed
    from public.shifts s join public.businesses b on b.id = s.business_id
   where s.id = p_shift for update of s;
  if not found then return 'not_found'; end if;
  if v_closed is not null then return 'business_closed'; end if;
  if v_cancelled is not null then return 'cancelled_shift'; end if;
  if v_ends <= now() then return 'past'; end if;

  if exists (select 1 from public.business_members where business_id = v_biz and user_id = p_worker) then
    return 'own_business';
  end if;

  v_known := exists (
      select 1 from public.applications
       where shift_id = p_shift and worker_id = p_worker
         and status in ('applied','offered','confirmed'))
    or exists (
      select 1 from public.team_members where business_id = v_biz and worker_id = p_worker);
  if not v_known then return 'not_applicant'; end if;

  if not private.is_adult(p_worker) then return 'minors_soon'; end if;

  select count(*) into v_open from public.applications
   where shift_id = p_shift and status = 'offered' and worker_id <> p_worker;
  if v_open >= v_slots + 2 then return 'offer_limit'; end if;

  insert into public.applications (shift_id, worker_id, status, initiated_by)
  values (p_shift, p_worker, 'offered', 'business')
  on conflict (shift_id, worker_id) do update
    set status = case when public.applications.status = 'confirmed' then 'confirmed' else 'offered' end;
  return 'offered';
end $function$;
revoke all on function public.offer_shift(uuid,uuid) from public, anon;
grant execute on function public.offer_shift(uuid,uuid) to authenticated;

-- claim_shift is retired: no client calls it (beta-5.1 and app.html, grepped 06/10), it creates an
-- application without contact_shared_at (PRIVACY-REVIEW P8), and its 'instant' path confirms with no
-- human on the business side (the regulatory line). Revoke only — reversible.
revoke all on function public.claim_shift(uuid) from public, anon, authenticated;

-- ROLLBACK:
--   grant execute on function public.claim_shift(uuid) to authenticated;
--   re-create send_details / offer_shift from TECHLEAD-S5 / pre-M2 defs; drop function public.confirm_adult();
--   restore is_adult to the birth_date-only body; alter table profile_contacts drop column adult_confirmed_at;
