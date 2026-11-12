-- Tutor checks, 2 Nov 2026: RRHAN-EC everywhere, expiry worked out from the
-- date done, and renewal reminders at 6 and 2 weeks. Runs after
-- tutor_checks.test.sql. Uses tutor T1 (...11) and owner admin (...a0).

select tests.claims(null); -- Signs out, so no one is signed in.

-- RRHAN-EC is needed in every state.
select tests.eq((select count(distinct state) from public.check_requirements -- Checks RRHAN-EC Fundamentals is needed in all 8 states:
  where kind = 'rrhan_ec_fundamentals' and basis = 'student_state'), 8, 'RRHAN-EC Fundamentals in all 8 states'); -- (counts the states that list it).
select tests.eq((select count(distinct state) from public.check_requirements -- Checks RRHAN-EC Masterclass is needed in all 8 states:
  where kind = 'rrhan_ec_masterclass' and basis = 'student_state'), 8, 'RRHAN-EC Masterclass in all 8 states'); -- (counts the states that list it).

-- Expiry from the date done, for training with a set life.
insert into public.tutor_checks (tutor_id, kind, completed_on) values -- Adds a first aid certificate for tutor T1:
  ('00000000-0000-0000-0000-000000000011', 'first_aid', current_date - 10) -- (done 10 days ago, no expiry)
-- and keeps its id as fa.
returning id as fa \gset
select tests.eq((select (expires_on = (current_date - 10 + interval '3 years')::date)::int from public.tutor_checks where id = :'fa'), 1, 'first aid: 3 years from the date done'); -- Checks: first aid: 3 years from the date done.
select tests.fails($$insert into public.tutor_checks (tutor_id, kind, reference, completed_on) values ('00000000-0000-0000-0000-000000000011', 'wwcc_sa', 'X1', current_date - 10)$$, 'a card needs its expiry date'); -- Checks this is refused: a card needs its expiry date.
select tests.fails($$insert into public.tutor_checks (tutor_id, kind) values ('00000000-0000-0000-0000-000000000011', 'first_aid')$$, 'no dates at all'); -- Checks this is refused: no dates at all.
delete from public.tutor_checks where id = :'fa'; -- Removes it.

-- A verified check expiring in 5 weeks: one reminder now, another at 2 weeks.
update public.tutor_profiles set active = true where account_id = '00000000-0000-0000-0000-000000000011'; -- Makes tutor T1 active.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values -- Adds a Queensland blue card for tutor T1:
  ('00000000-0000-0000-0000-000000000011', 'blue_card_qld', 'QLD-1', current_date + 35) -- expiring in 35 days,
-- and keeps its id as soon.
returning id as soon \gset
select tests.eq(private.queue_check_reminders(), 1, 'reminded at 6 weeks'); -- Checks: reminded at 6 weeks.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-000000000011' -- Checks the tutor gets a "time to renew" notice:
  and kind = 'check_renewal' and title like 'Time to renew%'), 1, 'tutor gets a notice'); -- (one notice).
select tests.eq(private.queue_check_reminders(), 0, 'not again until 2 weeks'); -- Checks: not again until 2 weeks.
update public.tutor_checks set expires_on = current_date + 13 where id = :'soon'; -- Moves the expiry to 13 days away.
select tests.eq(private.queue_check_reminders(), 1, 'reminded at 2 weeks'); -- Checks: reminded at 2 weeks.
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' -- Checks admins are told at 2 weeks:
  and kind = 'staff_alert' and title like 'Check expiring%'), 1, 'admins told at 2 weeks'); -- (one "check expiring" alert).
select tests.eq(private.queue_check_reminders(), 0, 'each reminder once'); -- Checks: each reminder once.

-- A renewed check stops reminders for the old one.
update public.tutor_checks set reminded_6w_at = null, reminded_2w_at = null where id = :'soon'; -- Clears the reminder marks.
insert into public.tutor_checks (tutor_id, kind, reference, expires_on) values -- Adds a renewed blue card:
  ('00000000-0000-0000-0000-000000000011', 'blue_card_qld', 'QLD-2', current_date + 1000) -- expiring in about three years,
-- and keeps its id as renewed.
returning id as renewed \gset
select tests.eq(private.queue_check_reminders(), 0, 'no reminder once renewed'); -- Checks: no reminder once renewed.
delete from public.tutor_checks where id in (:'soon', :'renewed'); -- Removes both test cards.

-- Prints that every check in this file passed.
\echo '  tutor check reminders: all checks passed'
