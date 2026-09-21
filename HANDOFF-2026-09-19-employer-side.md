# Handoff — 19 Sep 2026 — Employer side moves to RPCs

Two standalone prompts. Paste each into a fresh session for that colleague.
Neither needs any history from the tech lead's session.

---

## PROMPT FOR THE DEVELOPER

```
The tech lead changed the database today. Some of what app.html does now will
fail, on purpose. Read all of this before you touch the file.

== WHY THIS CHANGED ==
A worker could open the browser console and PATCH their own application row to
status 'confirmed' — booking themselves onto a shift with no employer approval.
This was proved against the real database, not guessed. Two-sided approval is the
rule that keeps us a leads company rather than a staffing agency, so it is now
enforced by the database and no longer by convention.

Three grants were withdrawn. These will now fail from the client, always:
  - UPDATE or DELETE on `applications`
  - UPDATE or DELETE on `shifts`
If you find code doing any of those, it is dead code. Delete it, do not repair it.
Every state change goes through an RPC.

== WHAT IS NEW IN THE DATABASE ==

1) create_business(p_name text, p_city_id int, p_address text default '')
   returns jsonb: { "result": <code>, "id": <uuid|null> }
   Creates the business AND the owner membership row in one transaction.
   Copies country, timezone, city name and the city centroid coordinates
   server-side. You pass three fields and nothing else.
   result: created | unauthenticated | name_required | city_not_found

2) post_shift(
     p_business uuid, p_role_code text,
     p_starts timestamptz, p_ends timestamptz,
     p_rate numeric, p_slots int default 1,
     p_instant bool default false, p_urgent bool default false,
     p_transport bool default false, p_descr text default '',
     p_max_distance_km int default null, p_exp_code text default 'none')
   returns jsonb: { "result": <code>, "id": <uuid|null> }
   Copies biz_name, city, city_id, lat, lng, country, currency, timezone and
   kosher_code from the business record. Do NOT send any of those.
   result: posted | unauthenticated | forbidden | not_found | biz_incomplete
         | bad_role | bad_experience | bad_time | past | bad_rate | bad_slots
         | bad_distance

3) cancel_shift(p_shift uuid)
   returns jsonb: { "result": <code>, "released": <int> }
   Marks shifts.cancelled_at and releases every active application to
   'cancelled'. `released` is how many workers were let go — show it.
   Shifts are never deleted; history and reviews must survive.
   result: cancelled | unauthenticated | forbidden | not_found | already_cancelled

4) shift_applicants(p_shift uuid)
   returns rows: worker_id, full_name, home_city_id, badges, status,
   initiated_by, applied_at, phone, phone_verified, attended_yes, attended_no,
   attended_disputed, shifts_done, is_regular
   This replaces your manual profiles + profile_contacts fetch for applicants.
   `phone` is NULL until that application is 'confirmed'. That is deliberate.
   attended_* is the cross-employer show-up record and excludes this shift's own
   review, so the double-blind rule is not broken.

5) shifts.cancelled_at timestamptz — null means live.

6) terms now allows kind='ui'. Result strings live there as
   'result.<code>' plus 'result.biz.confirmed', in he and en.

== CHANGED BEHAVIOUR YOU MUST ACCOUNT FOR ==

- shifts_for_me and shifts_near_city no longer return shifts that are cancelled
  or already full. If you filter for either on the client, remove it.
- claim_shift can now return 'cancelled_shift'.
- profile_contacts only exposes a phone once the application is 'confirmed'.
  Previously it leaked at 'applied', which let an employer post a fake shift and
  harvest phone numbers.
- team_members insert now requires that the worker has at least one confirmed
  application with that business. You cannot add a stranger to your regulars.

== WHAT TO CHANGE IN app.html ==

1. onCreateBiz (~line 702): replace the two inserts with one
   sb.rpc('create_business', { p_name, p_city_id, p_address }).
   Delete the business_members insert. The old two-step could leave a business
   with no owner — invisible and undeletable — if the second call failed.

2. onCreateShift (~line 732): replace the shifts.insert with
   sb.rpc('post_shift', {...}). Remove business_id denormalisation: no biz_name,
   city, city_id, lat, lng or created_by in the payload. Keep your existing
   local-time to ISO conversion and the past-midnight handling — that part is
   correct.

3. loadBiz (~line 216): fetch applicants with
   sb.rpc('shift_applicants', { p_shift }) per open shift, instead of the .in()
   query over applications plus the profiles/profile_contacts join. Keep the
   profiles fetch only for the team list.

4. Applicants UI: when phone is NULL, do not render an empty field. Render the
   reason — a short line meaning "the phone number is revealed once you approve".
   Put that string in terms as kind='ui', code='ui.phone_after_approve', he+en,
   and read it from there.

5. Add a cancel button on an employer's own shift, calling cancel_shift, behind a
   confirmation step. Say how many workers will be released before they confirm.

6. Replace the hardcoded RESULT and BIZ_RESULT objects with a lookup built from
   terms where kind='ui' and code like 'result.%', in the user's preferred_lang
   with 'he' as fallback. Load it once at boot alongside the other term lists.

7. Show the attendance figures on each applicant: attended_yes / attended_no, and
   shifts_done. Stars come later and matter less. A disputed no-show
   (attended_disputed) must never be displayed as a plain no-show.

8. loadBiz takes mem[0] and assumes one business per user. Multiple is now
   legitimately possible. If the user has more than one, show a picker; if one,
   skip it silently.

== WHAT MUST NEVER APPEAR IN THE UI ==
- A worker's coordinates, anywhere, in any request or response.
- A phone number for an application that is not 'confirmed'.
- A raw English result code or Postgres error string.
- Any newly added Hebrew string written into the .js. New strings go in terms.
  You are not required to retro-migrate the Hebrew already in the file.
- An automatic assignment, a skill level, a certification, or employment terms.

== HOW TO VERIFY BEFORE YOU REPORT DONE ==
Serve over local HTTP, not file://. Then, as a real signed-in user:
  a. Open a business, post a shift, see it on a worker's board.
  b. Apply as the worker. Confirm the employer screen shows the applicant with
     NO phone number.
  c. Approve. Confirm the phone appears only now.
  d. Cancel a shift with a confirmed worker. Confirm the worker's board and
     "my shifts" both reflect it, and that the shift row still exists in the
     database with cancelled_at set — not deleted.
  e. Check the database after each step. Do not report success from the UI alone.
Delete any test rows you create and say in your handoff what you left behind.

--- HANDOFF TO: <Tech Lead | QA> ---
DONE:      what was completed, and how it was verified.
STATE:     the state of the database, repo and app the receiver will find,
           including any test data you left behind.
NEXT:      what should happen next, in order.
FOR YOU:   the specific thing this colleague must do.
MUST KNOW: constraints or gotchas that would otherwise cost them an hour.
OPEN:      anything unresolved, including questions for the founder.
--- END HANDOFF ---
```

---

## PROMPT FOR QA

```
The tech lead applied three migrations on 19 Sep 2026 and claims a privilege
escalation is now closed. Your job is to disprove that claim, read-only.

Migrations: lock_application_transitions_and_contact_privacy,
employer_rpcs_and_shift_cancellation, terms_ui_kind_and_result_strings.

== THE BUG THAT WAS CLOSED ==
Policy apps_update on `applications` had a USING clause of
(worker_id = auth.uid() OR is_business_member(...)) and no WITH CHECK, so
Postgres reused USING as the check. A worker could UPDATE their own application
row to status 'confirmed' with no employer approval, and the sync trigger duly
incremented shifts.filled. The fix drops apps_update and apps_delete and revokes
UPDATE and DELETE on both `applications` and `shifts` from `authenticated`.

== PROVE OR DISPROVE, READ-ONLY ==
Remember: without `set local role authenticated` you run as postgres and bypass
RLS entirely, and every test will appear to pass while testing nothing.

1. Confirm there is now NO path for `authenticated` to change an application's
   status except through the RPCs. Read table grants (information_schema
   .role_table_grants), column grants, and pg_policies. Look for anything that
   restores write access by another route.
2. Read the body of every new function: create_business, post_shift,
   cancel_shift, shift_applicants. All four are SECURITY DEFINER and therefore
   bypass RLS. For each, find an argument choice that makes it act on a business
   or shift the caller does not belong to. shift_applicants is the one to press
   hardest — it returns phone numbers.
3. Verify shift_applicants cannot return a phone for an application that is not
   'confirmed', including when the same worker has a confirmed application on a
   DIFFERENT shift of the same business.
4. Verify the attendance counts in shift_applicants exclude the current shift's
   own review. If they do not, the double-blind review rule is broken: an
   employer could infer the worker's unrevealed review of them.
5. Verify the new team_members insert policy actually requires a prior confirmed
   application, and cannot be satisfied by a cancelled or withdrawn one.
6. Confirm shifts_for_me and shifts_near_city exclude cancelled and full shifts,
   and still return no worker coordinates in any column.
7. Run get_advisors for security and performance. The SECURITY DEFINER warnings
   on our RPCs are accepted by design — say so rather than re-reporting them,
   and flag only anything new.

Anything needing a write, hand to the developer as exact SQL with the expected
result and cleanup, as usual.

--- HANDOFF TO: <Tech Lead | Developer> ---
DONE:      what you checked, and how.
STATE:     what you found the system in. Confirm you wrote nothing.
NEXT:      what should happen next, in order.
FOR YOU:   the specific thing this colleague must do.
MUST KNOW: constraints or gotchas that would otherwise cost them an hour.
OPEN:      anything unresolved, including questions for the founder.
--- END HANDOFF ---
```
