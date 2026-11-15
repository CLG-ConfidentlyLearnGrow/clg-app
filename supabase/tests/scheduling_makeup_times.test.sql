-- Summary: tests for cancel reasons and make-up times (Carla, 16 Nov 2026).
-- Runs after scheduling.test.sql and reuses its people: tutors T3 (...13,
-- Sam's tutor) and T4 (...14), parents P3 (...03, Sam Three's parent) and
-- P4 (...04, not Sam's parent), and the owner admin (...a0).
-- Checks: a reason is needed; the two times must be in the same week, on a
-- quarter hour and free; the right side picks; picking books a make-up
-- session; "neither" needs a reason; CLG hears at each step; others can't
-- see or answer; times that run out are marked and CLG is told.

select tests.claims(null); -- Signs out, so no one is signed in.
-- Keeps Sam's student id as sam.
select id as sam from public.students where full_name = 'Sam Three' \gset
-- Keeps next Monday's date as mon (so every time below is in the future and in one week).
select (date_trunc('week', (now() at time zone 'Australia/Adelaide'))::date + 7) as mon \gset

-- Three sessions next week for Sam with tutor T3, online, 1 hr each.
insert into public.sessions (student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at) values -- Adds three sessions:
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', -- (Sam with T3, online)
   ((:'mon'::date + 2) + time '10:15') at time zone 'Australia/Adelaide', ((:'mon'::date + 2) + time '11:15') at time zone 'Australia/Adelaide'), -- Wednesday 10:15am,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', -- (Sam with T3, online)
   ((:'mon'::date + 1) + time '09:00') at time zone 'Australia/Adelaide', ((:'mon'::date + 1) + time '10:00') at time zone 'Australia/Adelaide'), -- Tuesday 9am,
  (:'sam', '00000000-0000-0000-0000-000000000013', 'General Maths', 'school', 'online', -- (Sam with T3, online)
   ((:'mon'::date + 4) + time '08:00') at time zone 'Australia/Adelaide', ((:'mon'::date + 4) + time '09:00') at time zone 'Australia/Adelaide'); -- Friday 8am.
-- Keeps the Wednesday session's id as s_wed.
select id as s_wed from public.sessions where starts_at = ((:'mon'::date + 2) + time '10:15') at time zone 'Australia/Adelaide' \gset
-- Keeps the Tuesday session's id as s_tue.
select id as s_tue from public.sessions where starts_at = ((:'mon'::date + 1) + time '09:00') at time zone 'Australia/Adelaide' \gset
-- Keeps the Friday session's id as s_fri.
select id as s_fri from public.sessions where starts_at = ((:'mon'::date + 4) + time '08:00') at time zone 'Australia/Adelaide' \gset

-- ---------------------------------------------------------------------------
-- The tutor cancels Wednesday and offers two times; the family picks one
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.cancel_session(%L)$$, :'s_wed'), 'reason', 'plain cancel with no reason'); -- Checks: a plain cancel with no reason is refused.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, null, null, %L, '11:00', %L, '13:30')$$, :'s_wed', :'mon'::date + 3, :'mon'::date + 4), 'reason', 'no reason picked'); -- Checks: no reason picked is refused.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'other', '  ', %L, '11:00', %L, '13:30')$$, :'s_wed', :'mon'::date + 3, :'mon'::date + 4), 'say why', '"Other" with no words'); -- Checks: "Other" needs a few words.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'sick', null, %L, '11:00')$$, :'s_wed', :'mon'::date + 3), 'two other times', 'only one time given'); -- Checks: both times are needed (or the "no other time" box).
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'sick', null, %L, '11:00', %L, '11:00')$$, :'s_wed', :'mon'::date + 3, :'mon'::date + 3), 'different', 'the same time twice'); -- Checks: the two times must differ.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'sick', null, %L, '11:00', %L, '11:10')$$, :'s_wed', :'mon'::date + 3, :'mon'::date + 4), '15, 30 or 45', 'not on a quarter hour'); -- Checks: times start on a quarter hour.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'sick', null, %L, '11:00', %L, '13:30')$$, :'s_wed', :'mon'::date + 3, :'mon'::date + 8), 'same week', 'a time in the next week'); -- Checks: both times must be in the same week.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'sick', null, %L, '11:00', %L, '08:30')$$, :'s_wed', :'mon'::date + 3, :'mon'::date + 4), 'already a session', 'clashes with the Friday session'); -- Checks: a time that clashes with another session is refused.
select tests.eq((select count(*) from public.sessions where id = :'s_wed' and status = 'scheduled'), 1, 'refused cancels leave the session on'); -- Checks: nothing was cancelled by the refused tries.
-- The tutor cancels, sick, offering Thursday 11am or Friday 1:30pm; keeps the offer's id as offer_wed.
select public.cancel_session_with_times(:'s_wed', 'sick', null, :'mon'::date + 3, '11:00', :'mon'::date + 4, '13:30') as offer_wed \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.sessions where id = :'s_wed' and status = 'cancelled' -- Checks the session is cancelled with the reason:
  and cancelled_by_role = 'tutor' and cancel_reason_kind = 'sick' and cancel_reason = 'Sick or unwell'), 1, 'cancelled by the tutor, sick'); -- (by the tutor, sick).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_wed' -- Checks the offer waits for the family:
  and status = 'waiting' and answer_by = 'family' and offered_by_role = 'tutor'), 1, 'family picks after a tutor cancels'); -- (the family picks).
select tests.eq((select count(*) from public.session_notices where session_id = :'s_wed' and account_id = '00000000-0000-0000-0000-000000000003' -- Checks the parent is asked to pick:
  and title like '%pick a make-up time%' and body like '%Make-up times offered%'), 1, 'parent asked to pick'); -- (with the times listed).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks the owner admin hears about the cancel:
  and kind = 'staff_alert' and title = 'Session cancelled' and body like '%10:15am%' and body like '%Reason: Sick or unwell%' and body like '%Waiting for the family%'), 1, 'CLG told about the cancel'); -- (with the reason and who picks).

-- Who can see the offer.
select tests.claims('00000000-0000-0000-0000-000000000004'); -- Signs in as parent P4 (not Sam's parent).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_makeup_offers()), 0, 'other parent sees no offers'); -- Checks: another parent sees nothing.
select tests.eq((select count(*) from public.session_makeup_offers), 0, 'other parent reads no offer rows'); -- Checks: the table rule hides them too.
select tests.fails(format($$select public.answer_makeup_times(%L, 1)$$, :'offer_wed'), 'other parent picks'); -- Checks: another parent can't pick.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000014', 'aal2'); -- Signs in as tutor T4 (not Sam's tutor).
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_makeup_offers()), 0, 'other tutor sees no offers'); -- Checks: another tutor sees nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_makeup_offers() where id = :'offer_wed' and student_name = 'Sam'), 1, 'tutor sees it, first name only'); -- Checks: the tutor sees it with the first name only.
select tests.fails(format($$select public.answer_makeup_times(%L, 1)$$, :'offer_wed'), 'tutor picks their own offer'); -- Checks: the side that offered can't pick.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The parent picks Thursday 11am.
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.list_makeup_offers() where id = :'offer_wed' and student_name = 'Sam Three'), 1, 'parent sees it'); -- Checks: the parent sees it.
select tests.fails_with(format($$select public.answer_makeup_times(%L, 3)$$, :'offer_wed'), 'pick one', 'a choice not on offer'); -- Checks: only 1, 2 or 0 are allowed.
-- The parent picks the first time; keeps the make-up session's id as makeup_wed.
select public.answer_makeup_times(:'offer_wed', 1) as makeup_wed \gset
select tests.fails_with(format($$select public.answer_makeup_times(%L, 2)$$, :'offer_wed'), 'already been answered', 'picking twice'); -- Checks: picking twice is refused.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.eq((select count(*) from public.sessions where id = :'makeup_wed' and makeup_for = :'s_wed' and status = 'scheduled' -- Checks the make-up session is booked:
  and starts_at = ((:'mon'::date + 3) + time '11:00') at time zone 'Australia/Adelaide' -- on Thursday at 11am,
  and ends_at = ((:'mon'::date + 3) + time '12:00') at time zone 'Australia/Adelaide' and delivery = 'online'), 1, 'make-up session booked'); -- for the same length and place.
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_wed' and status = 'picked' and makeup_session_id = :'makeup_wed'), 1, 'offer marked picked'); -- Checks: the offer shows as picked.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000013' -- Checks the tutor is told:
  and session_id = :'makeup_wed' and title = 'Make-up session booked'), 1, 'tutor told about the make-up'); -- (make-up booked).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks CLG is told:
  and kind = 'staff_alert' and title = 'Make-up session booked' and body like '%10:15am%'), 1, 'CLG told about the make-up'); -- (make-up booked, for the Wednesday 10:15am session).

-- ---------------------------------------------------------------------------
-- The family cancels Tuesday; the tutor says neither time works
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.cancel_session_with_times(%L, 'away', null, %L, '11:00', %L, '15:00')$$, :'s_tue', :'mon'::date + 3, :'mon'::date + 5), 'already a session', 'clashes with the new make-up'); -- Checks: the make-up just booked counts as a clash.
-- The parent cancels for a school event, offering Thursday 3pm or Saturday 10am; keeps the offer's id as offer_tue.
select public.cancel_session_with_times(:'s_tue', 'school_event', 'Sports day', :'mon'::date + 3, '15:00', :'mon'::date + 5, '10:00') as offer_tue \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.sessions where id = :'s_tue' and cancelled_by_role = 'family' -- Checks the reason and note are saved:
  and cancel_reason = 'School or uni event: Sports day'), 1, 'family cancel with reason and note'); -- (in words).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_tue' and answer_by = 'tutor'), 1, 'tutor picks after a family cancels'); -- Checks: the tutor picks.

select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.answer_makeup_times(%L, 1)$$, :'offer_tue'), 'family picks their own offer'); -- Checks: the family can't pick its own times.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal1'); -- Signs in as tutor T3 without two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.answer_makeup_times(%L, 1)$$, :'offer_tue'), 'tutor without two-step sign-in'); -- Checks: two-step sign-in is needed.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails_with(format($$select public.answer_makeup_times(%L, 0)$$, :'offer_tue'), 'why neither', '"neither" with no reason'); -- Checks: "neither" needs a reason.
select public.answer_makeup_times(:'offer_tue', 0, 'Teaching all day Thursday and Saturday'); -- The tutor says neither works, and why.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_tue' and status = 'declined' and answer_note like 'Teaching%'), 1, 'offer marked neither'); -- Checks: the offer shows neither works, with the reason.
select tests.eq((select count(*) from public.sessions where makeup_for = :'s_tue'), 0, 'no make-up booked'); -- Checks: no make-up session was booked.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000003' -- Checks the parent is told:
  and title = 'Make-up times not suitable'), 1, 'parent told neither works'); -- (neither works).
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks CLG is told:
  and title = 'Make-up times not suitable' and body like '%Teaching all day%'), 1, 'CLG told neither works'); -- (with the reason).

-- ---------------------------------------------------------------------------
-- No other time works: CLG is asked to sort it out
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000003'); -- Signs in as parent P3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
-- The parent cancels (away) and ticks that no other time works; keeps the offer's id as offer_fri.
select public.cancel_session_with_times(:'s_fri', 'away', null, p_no_times => true) as offer_fri \gset
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_fri' and status = 'none_offered' and option_1 is null), 1, 'no times offered'); -- Checks: saved with no times.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks CLG is asked to arrange it:
  and kind = 'staff_alert' and body like '%No other time works this week%'), 1, 'CLG asked to arrange a make-up'); -- (no times offered).
select tests.claims('00000000-0000-0000-0000-000000000013', 'aal2'); -- Signs in as tutor T3.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.answer_makeup_times(%L, 1)$$, :'offer_fri'), 'nothing to pick'); -- Checks: there's nothing to pick.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Times that run out
-- ---------------------------------------------------------------------------
select tests.claims(null); -- Signs out, so no one is signed in.
update public.session_makeup_offers set status = 'waiting', answered_at = null, answer_note = null, -- Sets the Tuesday offer back to waiting,
  option_1 = now() - interval '2 hours', option_2 = now() - interval '1 hour' where id = :'offer_tue'; -- with both times already passed.
select tests.eq((select count(*) from public.list_makeup_offers() where id = :'offer_tue'), 0, 'signed-out list is empty'); -- Checks: nothing shows when signed out.
select tests.eq(private.expire_makeup_offers(), 1, 'one offer ran out'); -- Checks: the job finds it.
select tests.eq((select count(*) from public.session_makeup_offers where id = :'offer_tue' and status = 'expired'), 1, 'marked as run out'); -- Checks: it's marked as run out.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks CLG is told:
  and title = 'Make-up time not picked' and body like '%9:00am%'), 1, 'CLG told nobody picked'); -- (nobody picked, for the Tuesday 9am session).
select tests.eq(private.expire_makeup_offers(), 0, 'only once'); -- Checks: it's handled only once.

-- The helper on its own: a time too soon is refused when offering.
select tests.eq((private.makeup_time_problem((select x from public.sessions x where x.id = :'s_wed'), now() + interval '1 hour', interval '2 hours') is not null)::int, 1, 'too soon is refused'); -- Checks: a time under 2 hr away is refused.

-- Signed-out visitors can't use any of it.
set role anon; -- Acts as someone who is not signed in.
select tests.fails(format($$select public.cancel_session_with_times(%L, 'sick')$$, :'s_fri'), 'anon cancels'); -- Checks: signed-out visitors can't cancel.
select tests.fails($$select * from public.session_makeup_offers$$, 'anon reads offers'); -- Checks: signed-out visitors can't read offers.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Leave the extra sessions out of the later tests.
delete from public.sessions where makeup_for in (:'s_wed', :'s_tue', :'s_fri'); -- Removes the make-up sessions.
delete from public.sessions where id in (:'s_wed', :'s_tue', :'s_fri'); -- Removes the test sessions (their offers go with them).

-- Prints that every check in this file passed.
\echo '  cancel reasons and make-up times: all checks passed'
