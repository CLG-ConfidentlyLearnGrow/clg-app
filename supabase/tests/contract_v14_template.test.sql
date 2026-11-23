-- Summary: tests that the casual tutor contract v1.4 wording is loaded as a
-- draft template (Carla, 22 Nov 2026), and that running the file again
-- never overwrites the owner's own edits. Everything is undone at the end.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
begin; -- Starts a change that is undone at the end, so nothing is left behind.

-- 1. The draft holds the v1.4 wording.
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual' and status = 'draft' and body like '%| 1.4 %22 November 2026%' and body like '%# 7 Leave, ending employment and disputes%'), 1, 'the casual tutor draft holds the v1.4 wording'); -- Checks: loaded.
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual' and status = 'draft' and (body like '%<u>%' or body like '%(draft)%' or body like '%<table>%')), 0, 'no Word leftovers (underline tags, logo table, "(draft)")'); -- Checks: clean.
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual' and status = 'published' and body like '%| 1.4 %'), 0, 'nothing is published by the file'); -- Checks: the owner still publishes.

-- 2. The gaps: with the app's own values, only the gaps an admin types are left.
select tests.eq((select count(*) from public.employment_contract_templates t, private.contract_fill(t.body, '{"tutor_name": "Test Tutor", "tutor_email": "t@example.com"}'::jsonb) f where t.contract_type = 'tutor_casual' and t.status = 'draft' and f.missing = array['Start date', 'Miscellaneous Award level', 'School tutoring rate', 'School tutoring rate from']), 1, 'only the start date, school award level and school rate need typing'); -- Checks: the required gaps.

-- 3. Running it again changes nothing.
\ir ../migrations/20261124711200_casual_contract_v14_template.sql
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual' and body like '%| 1.4 %'), 1, 'running it again adds no second copy'); -- Checks: still only one v1.4.

-- 4. An owner's own draft is never overwritten.
update public.employment_contract_templates set body = 'The owner''s own edits' where contract_type = 'tutor_casual' and status = 'draft'; -- The owner edits the draft.
\ir ../migrations/20261124711200_casual_contract_v14_template.sql
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual' and status = 'draft' and body = 'The owner''s own edits'), 1, 'an edited draft is left as it is'); -- Checks: not overwritten.

-- 5. A starter draft is replaced.
update public.employment_contract_templates set body = 'Starter. The owner pastes the final wording here before publishing.' where contract_type = 'tutor_casual' and status = 'draft'; -- Puts the starter wording back.
\ir ../migrations/20261124711200_casual_contract_v14_template.sql
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual' and status = 'draft' and body like '%| 1.4 %'), 1, 'a starter draft gets the v1.4 wording'); -- Checks: replaced.

rollback; -- Undoes everything this test changed.
\echo '  contract v1.4 template: all checks passed'
