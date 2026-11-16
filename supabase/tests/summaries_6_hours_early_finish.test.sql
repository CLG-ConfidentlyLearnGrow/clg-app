-- Summary: checks Carla's 16 Nov 2026 rules reached the database:
-- session notes are due 6 hours after a session (tutor reminded and admins
-- told at 6 hr, to-do count and "on time" measure at 6 hr), and a finish
-- up to 15 minutes early counts as on time. Reads each function's code,
-- since the rules are hours inside background jobs.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Acts as the database itself.
select tests.claims(null);
-- Runs both changes again: earlier tests re-run the older migrations they
-- edit, and this also checks they can run twice.
\ir ../migrations/20261118200400_summaries_due_6_hours.sql
\ir ../migrations/20261118200500_early_finish_15_minutes.sql
\ir ../migrations/20261118200400_summaries_due_6_hours.sql
\ir ../migrations/20261118200500_early_finish_15_minutes.sql

-- Note reminders: 6 hr, and no 24 or 48 hr left.
select tests.eq(case when strpos(pg_get_functiondef('private.queue_note_reminders()'::regprocedure), 'interval ''6 hours''') > 0 and strpos(pg_get_functiondef('private.queue_note_reminders()'::regprocedure), 'interval ''48 hours''') = 0 and strpos(pg_get_functiondef('private.queue_note_reminders()'::regprocedure), 'interval ''24 hours''') = 0 then 1::bigint else 0::bigint end, 1::bigint, 'note reminders at 6 hr'); -- checks the reminder job
-- Admin to-do count: notes 6 hr or more late.
select tests.eq(case when strpos(pg_get_functiondef('public.to_do_counts()'::regprocedure), 'd.hours_since_end >= 6') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'to-do count at 6 hr'); -- checks the admin count
-- The "on time" measure: within 6 hr.
select tests.eq(case when strpos(pg_get_functiondef('public.progress_measures(date, date)'::regprocedure), 'h.ends_at + interval ''6 hours''') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'on-time measure at 6 hr'); -- checks the measure

-- A finish up to 15 minutes early: the tutor can't record it, and Times to check ignores it.
select tests.eq(case when strpos(pg_get_functiondef('public.record_end_time(uuid, timestamptz, text)'::regprocedure), 'counts as finishing on time') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'up to 15 min early is on time'); -- checks the tutor's form rule
select tests.eq(case when strpos(pg_get_functiondef('public.list_times_to_check()'::regprocedure), 'interval ''15 minutes''') > 0 then 1::bigint else 0::bigint end, 1::bigint, 'times to check ignores small early finishes'); -- checks the admin list

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  summaries 6 hr and early finish: all checks passed'
