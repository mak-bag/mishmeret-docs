-- TECHLEAD S5 · 29/09/2026 · migration name: send_details_refuses_full_shift
-- QA-SUITE-S §2: send_details never checked capacity. A worker could hand phone +
-- avatar (contact_shared_at, may_see_worker) to a business with no free slot.
-- Fail-proof on the current code (impersonation, rollback, 29/09 20:15):
--   shift f995813d forced to filled=slots → {"result":"details_sent"}, contact_shared=1
-- STATUS: APPLIED 29/09 by the founder via the Supabase SQL Editor (the classifier blocked the agent).
--   NOT in supabase_migrations (SQL Editor doesn't register) — head is still 65. The nightly dump
--   carries the function body, so backup/restore are unaffected.
-- Pass-proof (impersonation, rollback): full → {"result":"full"}, 0 rows written ·
--   free → {"result":"details_sent"} · anon_fns=0 · anon on send_details=false · advisors: nothing new.
-- Same signature → create or replace keeps the ACL; re-revoked anyway (trap 2).

create or replace function public.send_details(p_shift uuid, p_start_when text default null::text, p_experience text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare s record; v_uid uuid := auth.uid(); v_birth date; v_prev text;
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
  -- Full is checked before birth date, so nobody is asked for data on a shift
  -- they cannot get. Someone already on it still hears already_applied.
  if s.filled >= s.slots and v_prev is distinct from 'applied' and v_prev is distinct from 'offered'
     and v_prev is distinct from 'confirmed' then
    return jsonb_build_object('result','full');
  end if;

  select birth_date into v_birth from public.profile_contacts where id = v_uid;
  if v_birth is null then return jsonb_build_object('result','need_birth_date'); end if;
  if v_birth > current_date - interval '18 years' then return jsonb_build_object('result','minors_soon'); end if;

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

-- ── Pass-proof, run after applying (must return full / 0 / details_sent) ──
-- begin;
-- create temp table _r(k text, v jsonb); grant all on _r to authenticated;
-- update public.shifts set filled = slots where id='f995813d-e5be-401f-b34f-eb414a62649e';
-- select set_config('request.jwt.claims','{"sub":"848426b8-653b-4ad0-8b28-aa430af4e953","role":"authenticated"}', true);
-- set local role authenticated;
-- insert into _r select 'full_shift', public.send_details('f995813d-e5be-401f-b34f-eb414a62649e','today',null);
-- reset role;
-- insert into _r select 'contact_shared', to_jsonb(count(*)) from applications
--   where shift_id='f995813d-e5be-401f-b34f-eb414a62649e' and worker_id='848426b8-653b-4ad0-8b28-aa430af4e953';
-- update public.shifts set filled = 0 where id='f995813d-e5be-401f-b34f-eb414a62649e';
-- set local role authenticated;
-- insert into _r select 'free_shift', public.send_details('f995813d-e5be-401f-b34f-eb414a62649e','today',null);
-- reset role;
-- select json_agg(json_build_object(k,v)) from _r;
-- rollback;
-- Then: anon_fns = 0 (§7) · get_advisors security.
