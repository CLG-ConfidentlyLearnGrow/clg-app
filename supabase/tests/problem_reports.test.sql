-- Problem reports: anyone signed in can send one with screenshots, only the
-- owner and the reviewer list can see the queue, reporters see their own
-- reports without private notes, and the daily tidy-up removes old
-- screenshots and reports. Reuses access_rules.test.sql people: owner
-- (...a0), operations admin (...b0), tutor T1 (...11), parent (...01).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the problem reports database change again (checks it can run twice).
\ir ../migrations/20261113700100_problem_reports.sql

-- The two screenshot paths used below, in the parent's own folder.
\set shot1 '00000000-0000-0000-0000-000000000001/11111111-1111-1111-1111-111111111111.png'
-- (a second screenshot)
\set shot2 '00000000-0000-0000-0000-000000000001/22222222-2222-2222-2222-222222222222.jpg'
-- A path in the tutor's folder, which the parent must not use.
\set tutorshot '00000000-0000-0000-0000-000000000011/33333333-3333-3333-3333-333333333333.png'

-- ---------------------------------------------------------------------------
-- A parent uploads screenshots and sends a report.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001'); -- acting as the parent (one-step sign-in is enough)
set role authenticated; -- as a signed-in person
select tests.fails(format($$insert into storage.objects (bucket_id, name) values ('problem-screenshots', %L)$$, :'tutorshot'), 'parent uploads into someone else''s folder'); -- checks this is refused
insert into storage.objects (bucket_id, name) values ('problem-screenshots', :'shot1'), ('problem-screenshots', :'shot2'); -- uploads two screenshots into their own folder
select tests.fails($$select public.problem_report_submit('short', '', '', '', '[]')$$, 'report with too little detail'); -- checks a too-short report is refused
select tests.fails(format($$select public.problem_report_submit('The booking page froze after I pressed Book.', '', '', '', %L)$$, -- checks a screenshot from someone else's folder is refused
  jsonb_build_array(jsonb_build_object('path', :'tutorshot', 'type', 'image/png'))), 'report with someone else''s screenshot'); -- (the tutor's path)
select tests.fails(format($$select public.problem_report_submit('The booking page froze after I pressed Book.', '', '', '', %L)$$, -- checks a screenshot that never uploaded is refused
  jsonb_build_array(jsonb_build_object('path', '00000000-0000-0000-0000-000000000001/44444444-4444-4444-4444-444444444444.png', 'type', 'image/png'))), 'report with a missing screenshot'); -- (a path with no file)
select public.problem_report_submit( -- sends the report:
  'The booking page froze after I pressed Book.', -- what went wrong,
  'Book a Maths session for Thursday', -- what they were trying to do,
  '/schedule?as=parent', -- the page,
  'Safari on iPhone', -- the device,
  jsonb_build_array(jsonb_build_object('path', :'shot1', 'type', 'image/png'), jsonb_build_object('path', :'shot2', 'type', 'image/jpeg')) -- and both screenshots
) as report \gset
select tests.eq((select count(*) from public.problem_reports), 0, 'reporter can''t read the reports table'); -- checks the queue is hidden from them
select tests.eq((select count(*) from public.my_problem_reports()), 1, 'reporter sees their own report'); -- checks they see their own
select tests.eq((select screenshots from public.my_problem_reports()), 2, 'reporter sees both screenshots counted'); -- checks the count
select tests.eq((select count(*) from storage.objects where bucket_id = 'problem-screenshots'), 2, 'reporter can open their own screenshots'); -- checks they can open their own
delete from storage.objects where bucket_id = 'problem-screenshots'; -- tries to remove their attached screenshots (the rules quietly skip them; checked below)
select tests.fails(format($$select public.problem_report_update(%L, 'closed', 'normal', '', '', '')$$, :'report'), 'reporter changes the status'); -- checks reporters can't change the status
select tests.fails($$select public.problem_reviewer_add('00000000-0000-0000-0000-000000000001')$$, 'reporter adds themselves as a reviewer'); -- checks this is refused
reset role; -- back to the test user (access rules off)
select tests.eq((select count(*) from storage.objects where bucket_id = 'problem-screenshots'), 2, 'attached screenshots are still there'); -- checks the delete above removed nothing

-- ---------------------------------------------------------------------------
-- Who can see the queue.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.problem_reports), 1, 'owner sees the report'); -- checks the owner always sees reports
select tests.eq((select count(*) from public.problem_report_screenshots), 2, 'owner sees the screenshots'); -- checks the owner sees the screenshot records
select tests.eq((select count(*) from storage.objects where bucket_id = 'problem-screenshots'), 2, 'owner can open the screenshots'); -- checks the owner can open the files
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin (not on the list yet)
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.problem_reports), 0, 'admin not on the list sees nothing'); -- checks the list decides
select tests.eq((select count(*) from storage.objects where bucket_id = 'problem-screenshots'), 0, 'admin not on the list can''t open screenshots'); -- checks the files too
select tests.fails($$select public.problem_reviewer_add('00000000-0000-0000-0000-0000000000b0')$$, 'admin adds themselves to the list'); -- checks only the owner chooses
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.problem_reports), 0, 'tutor sees nothing'); -- checks tutors can't see the queue
select tests.eq((select count(*) from public.my_problem_reports()), 0, 'tutor has no reports of their own'); -- checks they don't see the parent's report
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- The owner chooses the reviewer list.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails($$select public.problem_reviewer_add('00000000-0000-0000-0000-000000000011')$$, 'owner adds a tutor who isn''t an admin'); -- checks only admins can review
select public.problem_reviewer_add('00000000-0000-0000-0000-0000000000b0'); -- adds the operations admin
select public.problem_reviewer_add('00000000-0000-0000-0000-0000000000b0'); -- adding twice is fine
select tests.eq((select count(*) from public.problem_reviewer_choices() where on_list), 1, 'one admin on the list'); -- checks the list
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin, now on the list
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.problem_reports), 1, 'reviewer sees the report'); -- checks they now see it
select tests.eq((select count(*) from storage.objects where bucket_id = 'problem-screenshots'), 2, 'reviewer can open the screenshots'); -- checks the files too
select tests.eq((select count(*) from public.problem_reviewer_choices()), 0, 'reviewer can''t read the admin choices'); -- checks only the owner gets the choices
select public.problem_report_update(:'report', 'checking', 'urgent', 'Thanks, we are looking into it.', 'Happens on iPhone only', ''); -- marks it as being checked, with a reply and a note
select public.problem_report_update(:'report', 'fixed', 'urgent', 'Thanks, we are looking into it.', 'Happens on iPhone only', 'Booking page freezes on Safari after pressing Book.'); -- marks it fixed
select tests.eq((select count(*) from public.problem_reports where closed_at is not null and reviewed_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'fixed reports get a closed time'); -- checks the closed time is stamped
select tests.fails(format($$select public.problem_report_update(%L, 'done', 'normal', '', '', '')$$, :'report'), 'unknown status'); -- checks odd statuses are refused
select tests.fails(format($$select public.problem_report_github_saved(%L, 'https://github.com/x/y/issues/1')$$, :'report'), 'reviewer records a GitHub issue'); -- checks only the owner sends to GitHub
select tests.fails(format($$select public.problem_report_delete(%L)$$, :'report'), 'reviewer deletes a report'); -- checks only the owner deletes
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- the same reviewer without two-step login
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.problem_reports), 0, 'reviewer without two-step login sees nothing'); -- checks two-step login is needed
reset role; -- back to the test user

-- The reporter sees the reply but never the private notes.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- acting as the parent
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.my_problem_reports() where status = 'fixed' and reply like 'Thanks%'), 1, 'reporter sees the status and reply'); -- checks the reply shows
reset role; -- back to the test user
select tests.eq((select count(*) from pg_proc p, unnest(p.proargnames) a where p.proname = 'my_problem_reports' and a in ('reviewer_notes', 'fix_summary')), 0, 'reporter list has no private columns'); -- checks the notes never reach reporters

-- The owner records a GitHub issue, and a bad address is refused.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.problem_report_github_saved(%L, 'https://example.com/issues/1')$$, :'report'), 'non-GitHub issue address'); -- checks odd addresses are refused
select public.problem_report_github_saved(:'report', 'https://github.com/CLG-ConfidentlyLearnGrow/clg-app/issues/1'); -- records the issue
select public.problem_reviewer_remove('00000000-0000-0000-0000-0000000000b0'); -- takes the operations admin off the list
reset role; -- back to the test user
select tests.eq((select count(*) from public.problem_reports where github_issue_url is not null), 1, 'GitHub issue recorded'); -- checks it saved
select tests.eq((select count(*) from public.problem_reviewers), 0, 'reviewer removed'); -- checks the list is empty again

-- ---------------------------------------------------------------------------
-- Too many reports in a day.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select public.problem_report_submit('Report number ' || n || ' about the app.', '', '', '', '[]') from generate_series(1, 10) n; -- sends 10 reports
select tests.fails($$select public.problem_report_submit('Report number 11 about the app.', '', '', '', '[]')$$, 'eleventh report in a day'); -- checks the 11th is refused
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- The daily tidy-up.
-- ---------------------------------------------------------------------------
select tests.fails($$set local role authenticated; select public.problem_reports_tidy()$$, 'signed-in person runs the tidy-up'); -- checks only the server can run it
reset role; -- back to the test user (in case the line above changed it)
update public.problem_reports set closed_at = now() - interval '100 days' where id = :'report'; -- pretends the report was fixed 100 days ago
select public.problem_reports_tidy(); -- runs the tidy-up
select tests.eq((select count(*) from public.problem_report_screenshots), 0, 'old screenshots removed'); -- checks the screenshot records went
select tests.eq((select count(*) from public.problem_reports where id = :'report'), 1, 'report kept for 2 years'); -- checks the report itself stays
select tests.eq((select count(*) from public.problem_screenshot_removals), 2, 'files queued for removal'); -- checks both files are queued
select tests.eq((select count(*) from unnest(public.problem_screenshots_to_remove())), 2, 'job gets the queued files'); -- checks the job's list
select public.problem_screenshots_removed(array[:'shot1', :'shot2']); -- the job reports them removed
select tests.eq((select count(*) from public.problem_screenshot_removals), 0, 'queue emptied'); -- checks the queue is clear
update public.problem_reports set closed_at = now() - interval '3 years' where id = :'report'; -- pretends it was fixed 3 years ago
select public.problem_reports_tidy(); -- runs the tidy-up again
select tests.eq((select count(*) from public.problem_reports where id = :'report'), 0, 'report removed after 2 years'); -- checks the report went

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  problem reports: all checks passed'
