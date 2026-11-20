-- Summary: checks Carla's 20 Nov 2026 changes reached the database:
--   * a missing session summary: the tutor is still reminded at 6 hr, and
--     admins are told (and the to-do count counts it) at 12 hr;
--   * extra session requests say "significant date", not "event".
-- Reads each function's code, since these are hours and words inside
-- functions, and runs each file twice to check it is safe to run again.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Acts as the database itself.
select tests.claims(null);
-- Puts back the 16 Nov 2026 hours first (earlier tests re-run the older
-- migrations, which bring back 24 and 48 hr), as on the live database.
\ir ../migrations/20261118200400_summaries_due_6_hours.sql
-- Runs both files again (twice), to check they can run more than once.
\ir ../migrations/20261123400100_significant_dates_wording.sql
\ir ../migrations/20261123400200_summaries_admins_12_hours.sql
\ir ../migrations/20261123400100_significant_dates_wording.sql
\ir ../migrations/20261123400200_summaries_admins_12_hours.sql

-- Keeps the reminder job's code, split into the tutor's part and the admins' part.
select pg_get_functiondef('private.queue_note_reminders()'::regprocedure) as reminders \gset
-- The tutor's part (before the admins' notice kind) still reminds at 6 hr.
select tests.eq(case when strpos(split_part(:'reminders', '''note_overdue''', 1), 'interval ''6 hours''') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'tutor still reminded at 6 hr'); -- checks the tutor's reminder
-- The admins' part tells admins at 12 hr, not 6 hr.
select tests.eq(case when strpos(split_part(:'reminders', '''note_overdue''', 2), 'interval ''12 hours''') > 0 and strpos(split_part(:'reminders', '''note_overdue''', 2), 'interval ''6 hours''') = 0 then 1::bigint else 0::bigint end, 1::bigint, 'admins told at 12 hr'); -- checks the admins' notice
-- The admin to-do count: notes 12 hr or more late.
select tests.eq(case when strpos(pg_get_functiondef('public.to_do_counts()'::regprocedure), 'd.hours_since_end >= 12') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'to-do count at 12 hr'); -- checks the admin count
-- The "on time" measure still means within 6 hr.
select tests.eq(case when strpos(pg_get_functiondef('public.progress_measures(date, date)'::regprocedure), 'h.ends_at + interval ''6 hours''') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'on-time measure still 6 hr'); -- checks the measure

-- The request's error and notices say "significant date", with no "event" left.
select tests.eq(case when strpos(pg_get_functiondef('public.make_session_request(uuid, text, text, date, text, text, text)'::regprocedure), 'significant date') > 0 and strpos(pg_get_functiondef('public.make_session_request(uuid, text, text, date, text, text, text)'::regprocedure), 'event''') = 0 and strpos(pg_get_functiondef('public.make_session_request(uuid, text, text, date, text, text, text)'::regprocedure), 'test or event') = 0 then 1::bigint else 0::bigint end, 1::bigint, 'request says significant date'); -- checks the request
-- The one-off offer's error and note say "significant date".
select tests.eq(case when strpos(pg_get_functiondef('public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text)'::regprocedure), 'before the significant date') > 0 and strpos(pg_get_functiondef('public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text)'::regprocedure), 'an event') = 0 then 1::bigint else 0::bigint end, 1::bigint, 'one-off offer says significant date'); -- checks the offer

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  summaries admins 12 hr and significant dates: all checks passed'
