-- Summary: tests Reports for Operations admins and the owner's goals
-- (Carla, 20 Nov 2026, for Emma's role). Reuses access_rules.test.sql
-- people: owner (...a0), Operations admin (...b0), tutor T1 (...11).
-- Checks: Operations can open reports but never sees the money part, only
-- the owner can set or remove goals, goals must be for a real quarter or
-- financial year, and how a period is going can be seen by both admins.
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261123400600_reports_operations_goals.sql

-- Adds a saved quarterly report that has a money part, and keeps its id as rep.
insert into public.reports (kind, period_start, period_end, figures) -- the report:
values ('quarterly', '2025-01-01', '2025-03-31', '{"matching": {"matched": 3}, "money": {"income_cents": 500000}}') -- January to March 2025, with money
returning id as rep \gset

-- ---------------------------------------------------------------------------
-- Operations admin: sees reports without money, cannot change goals
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.report_list() where id = :'rep'), 1::bigint, 'Operations sees the report in the list'); -- Checks: it is listed.
select tests.eq((select count(*) from public.report_get(:'rep') where figures ? 'matching'), 1::bigint, 'Operations sees the figures without money'); -- Checks: matching figures are there.
select tests.eq((select count(*) from public.report_get(:'rep') where figures ? 'money'), 0::bigint, 'Operations never gets the money part'); -- Checks: no money part.
select tests.eq((select count(*) from public.report_get(:'rep') where not has_money), 1::bigint, 'the report says it has no money part for Operations'); -- Checks: has_money is false.
select tests.eq((select count(*) from public.reports where id = :'rep'), 0::bigint, 'Operations cannot read the saved report with its money directly'); -- Checks: the table itself stays owner only.
select tests.fails_with($$select public.report_set_goal('quarterly', '2025-01-01', 'matched', 5)$$, 'Only the owner', 'Operations cannot set a goal'); -- Checks this is refused: Operations setting a goal.
select tests.eq((select count(*) from (select public.report_goal_progress('quarterly', '2025-01-01') as p) x where p ? 'matching' and not p ? 'money'), 1::bigint, 'Operations sees how a quarter is going, without money'); -- Checks: progress works with no money part.
select tests.eq((select count(*) from (select public.report_goal_progress('quarterly', '2099-01-01') as p) x where p is null), 1::bigint, 'a quarter that has not started has nothing to show'); -- Checks: a future quarter gives nothing.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Owner: sees money, sets, changes and removes goals
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.report_get(:'rep') where figures ? 'money' and has_money), 1::bigint, 'the owner gets the money part'); -- Checks: the owner sees money.
-- Sets a goal of 5 matches for January to March 2025, and keeps its id as goal.
select public.report_set_goal('quarterly', '2025-01-01', 'matched', 5, 'Five matches') as goal \gset
select public.report_set_goal('quarterly', '2025-01-01', 'matched', 8); -- Changes the same goal to 8.
select tests.eq((select count(*) from public.report_goals where kind = 'quarterly' and period_start = '2025-01-01' and metric = 'matched'), 1::bigint, 'setting a goal again changes it, not adds another'); -- Checks: still one goal.
select tests.eq((select target::bigint from public.report_goals where id = :'goal'), 8::bigint, 'the goal has the new target'); -- Checks: the target is 8 now.
select tests.fails_with($$select public.report_set_goal('quarterly', '2025-02-01', 'matched', 5)$$, 'Choose a quarter', 'a quarter must start on the 1st of January, April, July or October'); -- Checks this is refused: a quarter starting 1 February.
select tests.fails_with($$select public.report_set_goal('yearly', '2025-01-01', 'matched', 5)$$, 'Choose a quarter', 'a financial year must start on 1 July'); -- Checks this is refused: a year starting 1 January.
select tests.fails_with($$select public.report_set_goal('yearly', '2025-07-01', 'income', 5)$$, 'Choose a quarter', 'goals cannot be set on money'); -- Checks this is refused: a money figure.
select tests.fails_with($$select public.report_set_goal('yearly', '2025-07-01', 'matched', -1)$$, 'target of 0 or more', 'a target cannot be below zero'); -- Checks this is refused: a target below zero.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The Operations admin can see the goal the owner set.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as the Operations admin again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.report_goals where id = :'goal'), 1::bigint, 'Operations sees the goals'); -- Checks: the goal is visible.
select tests.fails_with(format($$select public.report_remove_goal(%L)$$, :'goal'), 'Only the owner', 'Operations cannot remove a goal'); -- Checks this is refused: Operations removing it.
select tests.fails($$insert into public.report_goals (kind, period_start, metric, target) values ('yearly', '2025-07-01', 'matched', 1)$$, 'Operations cannot add a goal straight into the table'); -- Checks this is refused: writing to the table.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Tutors: no reports and no goals
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as tutor T1 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.report_list()), 0::bigint, 'a tutor sees no reports'); -- Checks: nothing listed.
select tests.eq((select count(*) from public.report_get(:'rep')), 0::bigint, 'a tutor cannot open a report'); -- Checks: nothing returned.
select tests.eq((select count(*) from public.report_goals), 0::bigint, 'a tutor sees no goals'); -- Checks: no goals visible.
select tests.fails_with($$select public.report_goal_progress('quarterly', '2025-01-01')$$, 'Only the owner and Operations', 'a tutor cannot see how a quarter is going'); -- Checks this is refused.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The owner removes the goal.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner again.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.report_remove_goal(:'goal'); -- Removes the goal.
select tests.eq((select count(*) from public.report_goals where id = :'goal'), 0::bigint, 'the owner can remove a goal'); -- Checks: it is gone.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Signs out and undoes everything this file did.
select tests.claims(null); -- Signs out, so no one is signed in.
rollback; -- Throws away every change made in this file.

-- Prints that every check in this file passed.
\echo '  reports for Operations and goals: all checks passed'
