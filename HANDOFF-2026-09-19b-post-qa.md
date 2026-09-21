# Handoff — 19 Sep 2026, round 2 — after the QA pass

Supersedes `HANDOFF-2026-09-19-employer-side.md` where the two differ.
Everything in round 1 still stands; this adds what the QA audit changed.

QA's T1–T10 write tests have **already been run by the tech lead** and all pass.
Do not run them again — the results are in the QA prompt at the bottom.

---

## PROMPT FOR THE DEVELOPER

```
Round 2. Read HANDOFF-2026-09-19-employer-side.md first if you have not — all of
it still applies. This is what the QA audit changed on top of it.

== ONE NEW BLOCKER, AND IT IS THE MOST IMPORTANT ITEM ==

The board (shifts_for_me) now correctly hides shifts that are full. But the board
is the worker's only screen — so the moment a worker is booked, the shift they
are booked onto disappears and they no longer know when or where they work. An
instant shift books immediately, so this is the normal path, not an edge case.

Use the new RPC:

  my_shifts()  -- no arguments
  returns rows: shift_id, app_status, initiated_by, applied_at, confirmed_at,
                biz_name, city, city_id, address, role_code, starts_at, ends_at,
                timezone, rate, currency, urgent, instant, transport, descr,
                cancelled_at

  Covers every application of the signed-in worker with status applied, offered,
  confirmed, cancelled or declined, for shifts ending in the last 30 days or
  later. `address` is the street address and is NULL unless app_status is
  'confirmed' — that is the only place the worker gets it.

Build "המשמרות שלי" as a worker section, driven entirely by this one call. Do not
rebuild it out of shifts_for_me, and do not ask for the DB filter to come back —
the filter is right, the missing screen was the bug.

A shift with cancelled_at set must read as cancelled, not silently vanish. The
worker was counting on that shift; tell them it is gone.

== NEW RESULT CODES SINCE ROUND 1 ==
claim_shift can now also return:
  declined_before — the employer already declined this worker for this shift
  too_far         — outside the distance cap the employer set
  no_city         — the worker has no city in their profile, so distance cannot
                    be computed
All three are already in terms as 'result.<code>' in he and en, along with
'result.last_owner'. If you have done item (ב) from round 1, they work for free.

== BEHAVIOUR THAT CHANGED UNDER YOU ==

1. release_application is now asymmetric. A worker may only pass 'withdrawn'. A
   business may only pass 'declined' or 'cancelled'. Anything else returns
   bad_status. Previously a worker could label their own withdrawal as
   'declined', which poisoned their own history. Check which buttons call it.

2. An employer's max_distance_km now actually blocks claiming, not just display.
   A worker outside it gets too_far even with a direct shift id.

3. A worker the employer declined cannot re-claim that shift. This is per-shift
   only — it never blocks that worker anywhere else.

4. approve_application and accept_offer now reject a shift that has ended or been
   cancelled, exactly like claim_shift. They can return past and cancelled_shift.

5. These writes now fail from the client, by design — delete any code doing them:
   - INSERT into businesses         (use create_business)
   - UPDATE/DELETE on profile_contacts (nothing may write phone or
     phone_verified any more; the WhatsApp verification feature will add an RPC)
   - UPDATE on profiles is column-limited to: full_name, bio, badges,
     home_city_id, search_radius_km, preferred_lang, terms_accepted_at
   - DELETE on reviews
   Your existing profiles.update for search_radius_km still works.

6. Business ownership is protected. Only an owner can add or remove members, and
   the last owner cannot be removed (returns a last_owner error).

== TWO UI CORRECTIONS ==

7. app.html:357 tells the employer "הכתובת מוצגת לעובד שאושר". That was never
   true — any signed-in user can read any business address, and we are keeping it
   that way, because a restaurant's address is public anyway and the worker has
   to walk through the door. Change the text so it stops promising privacy we do
   not provide. Say where the address is shown, not who it is hidden from.

8. profiles.badges is self-declared by the worker — health certificate, car,
   available nights. shift_applicants returns it next to the attendance figures,
   and side by side they read as if both were verified. They are not. Label the
   badges as self-declared in the applicant row. The attendance counts are the
   real signal; badges are the worker describing themselves.

== UNCHANGED FROM ROUND 1, STILL OUTSTANDING ==
create_business, post_shift, shift_applicants, the cancel button, the terms.ui
string lookup, the multi-business picker, and the unused `s` parameter in
applicantRow.

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
Your 19 Sep audit was accurate and useful. Findings F2, F7, F9, F10, F11, F12,
F14 and F17 are fixed; F5, F6, F8, F13 and F16 were decided rather than fixed,
with reasons below. Here is what to re-verify, and what to stop reporting.

== YOUR T1–T10 HAVE BEEN RUN ==
The tech lead executed them rather than spending a developer round trip. All ran
inside rolled-back blocks under `set local role authenticated`. Results:

  T1  claim=applied, self_approve=forbidden, accept_offer=bad_state,
      direct UPDATE=blocked (42501)
  T2  second business created; foreign approve=forbidden; foreign cancel=forbidden
  T3  slots=1 instant: first=confirmed, second=full, shifts row = 1/1
  T4  employer release → filled dropped to 0
  T5  re-claim after decline = declined_before (your F11, now closed);
      worker tagging own exit as 'declined' = bad_status (your F14, now closed)
  T6  review on an unconfirmed worker = blocked (42501)
  T7  double-blind: author sees 1, counterpart sees 0, after both submit both
      see 2, and reveal_after = ends_at + 14 days exactly
  T8  redirecting a written review to another worker = blocked (23514)
  T9  self-setting phone_verified = blocked (42501)
  T10 claiming outside the employer's cap = too_far

T7 closes your "could not test at all" gap. The reviews table is still empty —
that test created its data and rolled it back.

== WHAT CHANGED, TO RE-VERIFY INDEPENDENTLY ==
Migrations: privilege_floor_and_ownership_protection,
flow_guards_and_worker_my_shifts, claim_shift_declined_before_code.

1. Write grants: anon should now have SELECT only on all 12 tables, and
   `authenticated` should have no TRUNCATE, REFERENCES or TRIGGER anywhere. Read
   information_schema.role_table_grants and confirm. You were right that RLS was
   the only thing standing between anon and the data, and that TRUNCATE ignores
   RLS entirely — this was the most valuable finding in your report.
2. profile_contacts: no INSERT, UPDATE or DELETE for authenticated at all, and no
   contacts_update policy. Confirm there is no remaining path to phone_verified.
3. profiles: UPDATE is column-limited. Confirm the grant list, and that
   country_code and created_at are not in it.
4. business_members: members_insert and members_delete now go through
   private.is_business_owner, plus a before-delete trigger protecting the last
   owner. Try to find an ordering of operations that removes every owner.
5. reviews: a before-update trigger pins shift_id, worker_id, business_id,
   direction, author_id and reveal_after. reviews_update now has a real WITH
   CHECK. Confirm the trigger cannot be dodged, including via dispute_review.
6. my_shifts(): confirm `address` is NULL for every status except 'confirmed',
   and that it returns nothing for a worker with no applications.
7. claim_shift: confirm the distance check uses the worker's city centroid
   server-side and that no coordinate of the worker enters or leaves the API.

== DECIDED, NOT FIXED — STOP REPORTING THESE ==
- F5 businesses_read USING(true). A restaurant's address is public; the worker
  must physically go there. The UI text was the lie, and the developer is fixing
  the text. If we ever want the stronger version it needs a view, not a policy.
- F6 shifts_read USING(true). Enumerating shifts is fine — the board is public by
  design. The half of F6 that mattered, that max_distance_km did not bind, is
  fixed inside claim_shift.
- F8 badges are self-declared and stay writable. The developer is labelling them
  as self-declared. Attendance is the trust signal, not badges.
- F13/F16 profiles_read USING(true) and offer_shift accepting any uuid. Accepted
  for now: a marketplace has to show names, and there is no worker-search UI, so
  there is no way to obtain a stranger's uuid. This must be revisited before Web
  Push ships, because that is the day unsolicited offers become spam. Raise it
  again then, not before.
- F18 SECURITY DEFINER advisor warnings. The RPCs are the write API. Accepted.

== STILL OPEN FOR YOU ==
- The reviews table is genuinely empty in the live database. Once the developer
  ships, re-run the double-blind checks against real rows rather than a
  rolled-back fixture.
- F19/F20 are noted; F20 is a founder question and has been passed to him.

--- HANDOFF TO: <Tech Lead | Developer> ---
DONE:      what you checked, and how.
STATE:     what you found the system in. Confirm you wrote nothing.
NEXT:      what should happen next, in order.
FOR YOU:   the specific thing this colleague must do.
MUST KNOW: constraints or gotchas that would otherwise cost them an hour.
OPEN:      anything unresolved, including questions for the founder.
--- END HANDOFF ---
```
