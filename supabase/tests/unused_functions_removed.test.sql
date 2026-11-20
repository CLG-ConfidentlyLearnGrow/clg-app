-- Summary: checks the clean-up of unused database functions (Carla,
-- 20 Nov 2026): the five functions nothing used are gone, the change can be
-- run twice, and the functions the app does use are still there.
-- Some earlier test files run old migrations again, which can bring the old
-- functions back inside the test database, so this file runs the clean-up
-- itself first. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the clean-up once (it may already have run with the other migrations).
\ir ../migrations/20261122400100_remove_unused_functions.sql
-- Runs it a second time, to check it is safe to run more than once.
\ir ../migrations/20261122400100_remove_unused_functions.sql

-- ---------------------------------------------------------------------------
-- The five unused functions are gone.
-- ---------------------------------------------------------------------------
select tests.eq((to_regprocedure('public.list_matching(text, text, integer, integer)') is null)::int, 1, 'old Matching list removed'); -- Checks: the old Matching list is gone.
select tests.eq((to_regprocedure('public.matching_pipeline()') is null)::int, 1, 'old Matching stage counts removed'); -- Checks: the old Matching stage counts are gone.
select tests.eq((to_regprocedure('public.count_booking_sessions(uuid, uuid, smallint, date, date)') is null)::int, 1, 'old booking session counter removed'); -- Checks: the old booking session counter is gone.
select tests.eq((to_regprocedure('private.queue_monthly_summaries(date)') is null)::int, 1, 'monthly summary stand-in removed'); -- Checks: the empty monthly summary stand-in is gone.
select tests.eq((to_regprocedure('private.monthly_summary_text(uuid, date, date)') is null)::int, 1, 'monthly summary text writer removed'); -- Checks: the monthly summary text writer is gone.

-- ---------------------------------------------------------------------------
-- The functions the Matching page uses now are still there.
-- ---------------------------------------------------------------------------
select tests.eq((to_regproc('public.matching_queue') is not null)::int, 1, 'Matching queue kept'); -- Checks: the Matching queue is still there.
select tests.eq((to_regproc('public.matching_stage_counts') is not null)::int, 1, 'Matching stage counts kept'); -- Checks: the Matching stage counts are still there.

-- Undoes everything above.
rollback;

-- Prints that every check in this file passed.
\echo '  unused functions removed: all checks passed'
