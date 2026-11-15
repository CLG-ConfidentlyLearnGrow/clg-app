-- Summary: tests that a make-up time is only booked once everyone has agreed (Carla, 16 Nov 2026).
-- Runs after scheduling.test.sql and reuses its people: tutor T3 (...13,
-- Sam's tutor), parents P3 (...03, Sam Three's parent) and P4 (...04, not
-- Sam's parent), and the owner admin (...a0, CLG front desk).
-- Checks: CLG staff can't pick for someone; when CLG offers the times, one
-- side picks and the other confirms before anything is booked; "doesn't
-- work" needs a reason and tells CLG; a pick not confirmed in time runs out.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps the Monday two weeks from now as mon (a quiet week, away from the other tests).
select (date_trunc('week', (now() at time zone 'Australia/Adelaide'))::date + 14) as mon \gset

-- Two sessions that week for Sam with tutor T3, online, 1 hr each.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) values -- Adds two sessions:
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', -- (Sam with T3, online)
   ((:'mon'::date + 1) + time '07:15') at time zone 'Australia/Adelaide', ((:'mon'::date + 1) + time '08:15') at time zone 'Australia/Adelaide'), -- Tuesday 7:15am,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', -- (Sam with T3, online)
   ((:'mon'::date + 2) + time '07:15') at time zone 'Australia/Adelaide', ((:'mon'::date + 2) + time '08:15') at time zone 'Australia/Adelaide'); -- Wednesday 7:15am.
-- Keeps the Tuesday session's id as s_a.
select id as s_a from public.sessions where starts_at = ((:'mon'::date + 1) + time '07:15') at time zone 'Australia/Adelaide' \gset
-- Keeps the Wednesday session's id as s_b.
select id as s_b from public.sessions where starts_at = ((:'mon'::date + 2) + time '07:15') at time zone 'Australia/Adelaide' \gset

-- ---------------------------------------------------------------------------
-- A tutor offering times themselves: one pick books it (no extra step)
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- The tutor cancels Tuesday, offering Thursday or Friday at 7:15am; keeps the offer's id as offer_a.
select public.cancel_session_with_times(:'s_a', 'away', null, :'mon'::date + 3, '07:15', :'mon'::date + 4, '07:15') as offer_a \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_a' and not needs_both), 1, 'tutor''s own offer needs only the family'); -- Checks: the tutor's own times count as their agreement.

-- CLG staff can't pick on the family's behalf.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.answer_makeup_times(%L, 1)$$, :'offer_a'), 'CLG picks for the family'); -- Checks: CLG staff can't pick for someone.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- The parent picks Thursday; keeps the make-up session's id as makeup_a.
select public.answer_makeup_times(:'offer_a', 1) as makeup_a \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.sessions where id = :'makeup_a' and makeup_for = :'s_a'), 1, 'booked straight away'); -- Checks: both sides agreed, so it's booked.

-- ---------------------------------------------------------------------------
-- CLG cancels and offers times: the tutor picks, the family confirms
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- CLG cancels Wednesday for the family (phone call), offering Thursday or Friday at 9:30am; keeps the offer's id as offer_b.
select public.cancel_session_with_times(:'s_b', 'family', null, :'mon'::date + 3, '09:30', :'mon'::date + 4, '09:30', false, 'family') as offer_b \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_b' and needs_both and answer_by = 'tutor'), 1, 'CLG''s offer needs both sides'); -- Checks: both sides must agree, the tutor picks first.

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.confirm_makeup_time(%L, true)$$, :'offer_b'), 'confirm before anything is picked'); -- Checks: nothing to confirm yet.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.answer_makeup_times(:'offer_b', 2); -- The tutor picks Friday 9:30am.
select tests.fails(format($$select public.confirm_makeup_time(%L, true)$$, :'offer_b'), 'the picker confirms their own pick'); -- Checks: the side that picked can't also confirm.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_b' and status = 'confirming' -- Checks it waits for the family:
  and picked_at = ((:'mon'::date + 4) + time '09:30') at time zone 'Australia/Adelaide'), 1, 'waiting for the family to confirm'); -- (Friday 9:30am picked).
select tests.eq((select count(*) from public.sessions where makeup_for = :'s_b'), 0, 'not booked before the family confirms'); -- Checks: nothing is booked yet.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' -- Checks the parent is asked to confirm:
  and title = 'Please confirm a make-up time'), 1, 'parent asked to confirm'); -- (one notice).

select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as parent P4 (not Sam's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.confirm_makeup_time(%L, true)$$, :'offer_b'), 'another parent confirms'); -- Checks: another parent can't confirm.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner admin.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.confirm_makeup_time(%L, true)$$, :'offer_b'), 'CLG confirms for the family'); -- Checks: CLG staff can't confirm for the family.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.confirm_makeup_time(%L, false)$$, :'offer_b'), 'say why', '"doesn''t work" with no reason'); -- Checks: saying no needs a reason.
-- The parent confirms; keeps the make-up session's id as makeup_b.
select public.confirm_makeup_time(:'offer_b', true) as makeup_b \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.sessions where id = :'makeup_b' and makeup_for = :'s_b' -- Checks the make-up is booked once both agreed:
  and starts_at = ((:'mon'::date + 4) + time '09:30') at time zone 'Australia/Adelaide'), 1, 'booked once the family confirms'); -- (Friday 9:30am).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_b' and status = 'picked' and makeup_session_id = :'makeup_b'), 1, 'offer marked booked'); -- Checks: the offer shows as booked.

-- ---------------------------------------------------------------------------
-- Saying it doesn't work, and a pick that isn't confirmed in time
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
update public.session_makeup_offers set status = 'confirming', makeup_session_id = null where id = :'offer_b'; -- Sets the offer back to waiting for the family.
delete from public.sessions where id = :'makeup_b'; -- Removes the make-up booked above.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.confirm_makeup_time(:'offer_b', false, 'Swimming lessons on Fridays'); -- The parent says Friday doesn't work, and why.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_b' and status = 'declined' and answer_note like 'Swimming%'), 1, 'marked as not suitable'); -- Checks: the offer shows it doesn't work, with the reason.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks CLG is told:
  and title = 'Make-up time not suitable' and body like '%Swimming%'), 1, 'CLG told it doesn''t work'); -- (with the reason).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' -- Checks the tutor is told:
  and title = 'Make-up time not suitable'), 1, 'tutor told it doesn''t work'); -- (one notice).

update public.session_makeup_offers set status = 'confirming', picked_at = now() - interval '1 hour' where id = :'offer_b'; -- Sets it back, with the picked time already passed.
select tests.eq(private.expire_makeup_offers(), 1, 'a passed pick runs out'); -- Checks: the job finds it.
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_b' and status = 'expired'), 1, 'marked as run out'); -- Checks: it's marked as run out.

-- Leave the extra sessions out of the later tests.
delete from public.sessions where makeup_for in (:'s_a', :'s_b'); -- Removes the make-up sessions.
delete from public.sessions where id in (:'s_a', :'s_b'); -- Removes the test sessions (their offers go with them).

-- Prints that every check in this file passed.
\echo '  make-up times need everyone to agree: all checks passed'
