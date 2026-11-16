-- Tutor applications: only the app's server can save an application (so the
-- public form's spam checks can't be skipped), spam limits work, only the
-- owner and Operations admins (with two-step login) see applications and
-- CVs, approving needs the interview and both referee checks, declining
-- needs a reason, and the daily tidy-up deletes old applications and
-- queues their CVs. Reuses access_rules.test.sql people: owner (...a0),
-- operations admin (...b0), tutor T1 (...11), parent (...01).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the tutor applications database change again (checks it can run twice).
\ir ../migrations/20261118300100_tutor_applications.sql

-- A complete, valid application, kept in a psql variable for reuse below.
\set app '{"first_name":"Sam","last_name":"Tutor","email":"Sam.Tutor@example.com","phone":"0400 000 000","state":"SA","suburb":"Norwood","teach_mode":"both","right_to_work":true,"subjects":"Mathematics Years 7 to 10, Chemistry Year 11","availability":"Weekdays after 3:30pm","weekly_hours":"6","qualifications":"Bachelor of Science (Chemistry), University of Adelaide","teacher_registration":"","experience":"Two years tutoring high school students at a learning centre.","wwcc_status":"held","wwcc_number":"1234567","wwcc_state":"SA","wwcc_expiry":"2029-06-30","rrhan_ec_status":"done","first_aid_status":"not_yet","referees":[{"name":"Pat Manager","relationship":"Supervisor at the learning centre","email":"pat@example.com","phone":"0400 111 111"},{"name":"Lee Coach","relationship":"Head coach, junior netball club","email":"","phone":"0400 222 222"}],"statement":"I love helping students see that maths makes sense and builds confidence.","helped_example":"A Year 9 student was stuck on fractions, so we used drawings until it clicked for her.","heard_from":"A friend","cv_path":"","declared_true":true,"declared_suitable":true,"privacy_version":"2026-11-draft"}'
-- A scrambled internet address for the spam limits (64 hex characters).
\set ip 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
-- A CV path, as the app would name it.
\set cv '11111111-2222-3333-4444-555555555555.pdf'

-- ---------------------------------------------------------------------------
-- Only the app's server can save an application.
-- ---------------------------------------------------------------------------
set role anon; -- as someone not signed in, using the public key
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, :'app', :'ip'), 'public key saves an application'); -- checks this is refused (spam checks can't be skipped)
select tests.fails($$select count(*) from public.tutor_applications$$, 'public key reads applications'); -- checks applications can't be read without signing in
reset role; -- back to the test user (access rules off)
select tests.claims('00000000-0000-0000-0000-000000000001'); -- acting as a parent
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, :'app', :'ip'), 'signed-in person saves an application directly'); -- checks this is refused too
select tests.fails(format($$insert into storage.objects (bucket_id, name) values ('tutor-applications', %L)$$, :'cv'), 'signed-in person uploads a CV'); -- checks only the server adds CVs
reset role; -- back to the test user

-- The server saves applications.
set role service_role; -- as the app's server
insert into storage.objects (bucket_id, name) values ('tutor-applications', :'cv'); -- the server uploads the CV
-- The server saves the first application with its CV, keeping its id as app1.
select public.tutor_application_submit(jsonb_set(:'app'::jsonb, '{cv_path}', to_jsonb(:'cv'::text)), :'ip') as app1 \gset
select tests.eq((select count(*) from public.tutor_applications where email = 'sam.tutor@example.com' and cv_path = :'cv'), 1, 'application saved with the email in lower case and the CV'); -- checks it saved
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, :'app', :'ip'), 'second open application from the same email'); -- checks one open application per email
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, jsonb_set(:'app'::jsonb, '{declared_suitable}', 'false'), :'ip'), 'declaration not ticked'); -- checks both declarations are needed
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, jsonb_set(jsonb_set(:'app'::jsonb, '{email}', '"one@example.com"'), '{referees}', '[]'), :'ip'), 'no referees'); -- checks two referees are needed
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, jsonb_set(jsonb_set(:'app'::jsonb, '{email}', '"two@example.com"'), '{referees,1,phone}', '""'), :'ip'), 'referee with no way to contact them'); -- checks each referee can be contacted
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, jsonb_set(jsonb_set(:'app'::jsonb, '{email}', '"three@example.com"'), '{state}', '"XX"'), :'ip'), 'unknown state'); -- checks the table's own checks
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, jsonb_set(jsonb_set(:'app'::jsonb, '{email}', '"four@example.com"'), '{cv_path}', '"99999999-2222-3333-4444-555555555555.pdf"'), :'ip'), 'CV that never uploaded'); -- checks the CV must be there
select public.tutor_application_submit(jsonb_set(:'app'::jsonb, '{email}', '"five@example.com"'), :'ip'); -- a second application from the same connection
select public.tutor_application_submit(jsonb_set(:'app'::jsonb, '{email}', '"six@example.com"'), :'ip'); -- a third
select tests.fails(format($$select public.tutor_application_submit(%L, %L)$$, jsonb_set(:'app'::jsonb, '{email}', '"seven@example.com"'), :'ip'), 'fourth application from one connection in a day'); -- checks the daily limit per connection
select public.tutor_application_submit(jsonb_set(:'app'::jsonb, '{email}', '"seven@example.com"'), repeat('b', 64)); -- a different connection is fine
reset role; -- back to the test user
select tests.eq((select count(*) from public.tutor_applications), 4, 'four applications saved'); -- checks the count

-- ---------------------------------------------------------------------------
-- Who can see applications and CVs.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.tutor_applications), 4, 'owner sees applications'); -- checks the owner sees them
select tests.eq((select count(*) from storage.objects where bucket_id = 'tutor-applications'), 1, 'owner can open the CV'); -- checks the owner can open CVs
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.tutor_applications), 4, 'operations admin sees applications'); -- checks Operations admins see them
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal1'); -- the same admin without two-step login
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.tutor_applications), 0, 'admin without two-step login sees nothing'); -- checks two-step login is needed
select tests.fails(format($$select public.tutor_application_save(%L, '{"status":"shortlisted"}')$$, :'app1'), 'admin without two-step login reviews'); -- checks they can't review
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000007c1', 'aal2'); -- acting as the support admin added in staff_levels.test.sql
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.tutor_applications), 0, 'support admin sees nothing'); -- checks only the owner and Operations see applications
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.tutor_applications), 0, 'tutor sees nothing'); -- checks tutors can't see applications
select tests.eq((select count(*) from storage.objects where bucket_id = 'tutor-applications'), 0, 'tutor can''t open CVs'); -- checks tutors can't open CVs
select tests.fails(format($$select public.tutor_application_approve(%L)$$, :'app1'), 'tutor approves an application'); -- checks tutors can't approve
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-000000000001'); -- acting as a parent
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.tutor_applications), 0, 'parent sees nothing'); -- checks parents can't see applications
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- Screening, approving and declining.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.tutor_application_save(%L, '{"status":"approved"}')$$, :'app1'), 'save used to approve'); -- checks approving has its own step
select public.tutor_application_save(:'app1', '{"status":"shortlisted","interview_on":"2026-11-20","interview_notes":"Clear explanations; good answers on boundaries."}'); -- shortlists and records the interview
select tests.fails(format($$select public.tutor_application_approve(%L)$$, :'app1'), 'approve before referee checks'); -- checks both referees are needed
select public.tutor_application_save(:'app1', '{"status":"shortlisted","interview_on":"2026-11-20","referee_1_checked_on":"2026-11-21","referee_2_checked_on":"2026-11-22","wwcc_verified_on":"2026-11-22"}'); -- records both referee checks
select tests.eq((select length(public.tutor_application_approve(:'app1'))), length('sam.tutor@example.com'), 'approve gives back the email'); -- approves it
select public.tutor_application_invited(:'app1'); -- notes the invite went
select tests.eq((select count(*) from public.tutor_applications where id = :'app1' and status = 'approved' and invited_at is not null and decided_by = '00000000-0000-0000-0000-0000000000b0'), 1, 'approved with who and when'); -- checks the approval saved
select tests.fails(format($$select public.tutor_application_decline(%L, 'other', '')$$, :'app1'), 'decline an approved application'); -- checks approved ones can't be declined
select public.tutor_application_save(:'app1', '{"status":"new","interview_on":"2026-11-20","referee_1_checked_on":"2026-11-21","referee_2_checked_on":"2026-11-22","admin_notes":"Starts in January."}'); -- tries to reopen it while adding a note
select tests.eq((select count(*) from public.tutor_applications where id = :'app1' and status = 'approved' and decided_at is not null and admin_notes = 'Starts in January.'), 1, 'approved application stays approved, note saved'); -- checks decided ones stay decided
-- Keeps the id of the application from five@example.com as app5.
select id as app5 from public.tutor_applications where email = 'five@example.com' \gset
select tests.fails(format($$select public.tutor_application_decline(%L, '', '')$$, :'app5'), 'decline with no reason'); -- checks a reason is needed
select tests.fails(format($$select public.tutor_application_decline(%L, 'too_young', '')$$, :'app5'), 'decline with a reason not on the list'); -- checks only listed reasons
select public.tutor_application_decline(:'app5', 'not_needed', 'Lots of maths tutors already.'); -- declines it
select tests.fails(format($$select public.tutor_application_approve(%L)$$, :'app5'), 'approve a declined application'); -- checks closed ones can't be approved
-- Keeps the id of the application from six@example.com as app6.
select id as app6 from public.tutor_applications where email = 'six@example.com' \gset
select public.tutor_application_save(:'app6', '{"status":"withdrawn"}'); -- marks one withdrawn
select tests.eq((select count(*) from public.tutor_applications where id = :'app6' and decided_at is not null), 1, 'withdrawn gets a decided time'); -- checks it's stamped
reset role; -- back to the test user

-- A declined applicant can apply again.
set role service_role; -- as the app's server
select public.tutor_application_submit(jsonb_set(:'app'::jsonb, '{email}', '"five@example.com"'), repeat('c', 64)); -- applies again after being declined
reset role; -- back to the test user

-- Someone with no right to work can't be approved.
update public.tutor_applications set right_to_work = false, interview_on = current_date, referee_1_checked_on = current_date, referee_2_checked_on = current_date -- pretends a screened applicant said no to right to work
where email = 'seven@example.com'; -- (the seventh test applicant)
-- Keeps the id of the application from seven@example.com as app7.
select id as app7 from public.tutor_applications where email = 'seven@example.com' \gset
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.tutor_application_approve(%L)$$, :'app7'), 'approve without right to work'); -- checks this is refused
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- The daily tidy-up.
-- ---------------------------------------------------------------------------
select tests.fails($$set local role authenticated; select public.tutor_applications_tidy()$$, 'signed-in person runs the tidy-up'); -- checks only the server can run it
reset role; -- back to the test user (in case the line above changed it)
update public.tutor_applications set ip_hash = :'ip', created_at = now() - interval '40 days' where email = 'seven@example.com'; -- pretends one was sent 40 days ago
update public.tutor_applications set decided_at = now() - interval '13 months' where id = :'app5'; -- pretends the decline was 13 months ago
update public.tutor_applications set decided_at = now() - interval '6 years' where id = :'app1'; -- pretends the approval was 6 years ago
select public.tutor_applications_tidy(); -- runs the tidy-up
select tests.eq((select count(*) from public.tutor_applications where id = :'app5'), 0, 'declined application removed after 12 months'); -- checks it went
select tests.eq((select count(*) from public.tutor_applications where id = :'app1'), 1, 'approved application kept'); -- checks approved ones stay
select tests.eq((select count(*) from public.tutor_applications where email = 'seven@example.com' and ip_hash is null), 1, 'old scrambled address cleared'); -- checks the 30-day clearing
select tests.eq((select count(*) from public.tutor_application_file_removals), 0, 'no CV queued yet'); -- the approved one's CV stays
update public.tutor_applications set decided_at = now() - interval '8 years' where id = :'app1'; -- pretends the approval was 8 years ago
select public.tutor_applications_tidy(); -- runs the tidy-up again
select tests.eq((select count(*) from public.tutor_applications where id = :'app1'), 0, 'approved application removed after 7 years'); -- checks it went
select tests.eq((select count(*) from unnest(public.tutor_application_files_to_remove())), 1, 'its CV is queued for removal'); -- checks the CV is queued
select public.tutor_application_files_removed(array[:'cv']); -- the job reports it removed
select tests.eq((select count(*) from public.tutor_application_file_removals), 0, 'queue emptied'); -- checks the queue is clear
update public.tutor_applications set created_at = now() - interval '13 months' where id = :'app7'; -- pretends an undecided one was sent 13 months ago
select public.tutor_applications_tidy(); -- runs the tidy-up again
select tests.eq((select count(*) from public.tutor_applications where id = :'app7'), 0, 'never-decided application removed after 12 months'); -- checks it went

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  tutor applications: all checks passed'
