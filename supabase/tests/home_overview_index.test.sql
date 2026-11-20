-- Summary: checks the index added for the Home overview dashboards (Carla,
-- 20 Nov 2026): sessions can be found by start time, the database change can
-- run twice, and it changed no access rules on sessions.
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Counts the access rules on sessions before running the change again.
select count(*) as rules_before from pg_policies where schemaname = 'public' and tablename = 'sessions' \gset
-- (keeps the number as rules_before)
-- Runs the index change again (checks it can run twice).
\ir ../migrations/20261122610100_sessions_starts_at_index.sql

-- 1. The index exists, on sessions, by start time.
select tests.eq( -- checks
  (select count(*) from pg_indexes where schemaname = 'public' and tablename = 'sessions' and indexname = 'sessions_starts_at_idx' and indexdef like '%(starts_at)'), -- how many indexes on sessions have that name and are by start time
  1::bigint, -- exactly one
  'sessions can be found by start time' -- (what this check proves)
); -- end of the check

-- 2. No access rules on sessions were added or removed.
select tests.eq( -- checks
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'sessions'), -- the number of access rules now
  :'rules_before'::bigint, -- is the same as before
  'the index change leaves the sessions access rules alone' -- (what this check proves)
); -- end of the check

-- Undoes everything above.
rollback;
