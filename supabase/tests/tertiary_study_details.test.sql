-- Study details for university and TAFE students: program,
-- unit code and link (family), and a course overview (admins only).
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02), and family_setup's tests.fails_with.

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Uma Two', -- Adds a test university student, Uma, to parent P2's family:
  (current_date - interval '19 years')::date, 'SA', 'University or TAFE', 'Adelaide University', -- aged 19, at Adelaide University,
  -- with one unit, and keeps her id as uma.
  '[{"subject":"Water Engineering Hydraulics and Modelling","level":"University or TAFE"}]') as uma \gset
-- Keeps her unit's id as unit.
select id as unit from public.student_subjects where student_id = :'uma' \gset
reset role; -- Goes back to the all-powerful test user (access rules off).

-- The parent fills in the course details.
select tests.claims('00000000-0000-0000-0000-000000000002'); -- Signs in as test account ...02.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
update public.students set program = 'Bachelor of Engineering (Civil)(Honours)' -- Sets her degree:
  where id = :'uma'; -- (for Uma).
update public.student_subjects set course_code = 'ENGC 3000', course_url = 'https://example.edu/engc3000' -- Sets the unit's code and course link:
  where id = :'unit'; -- (for her unit).
select tests.eq((select count(*) from public.students where id = :'uma' and program like 'Bachelor%'), 1, 'parent saves the program'); -- Checks: parent saves the program.
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_code = 'ENGC 3000'), 1, 'parent saves the unit code'); -- Checks: parent saves the unit code.
select tests.fails(format($$update public.student_subjects set course_url = 'javascript:alert(1)' where id = %L$$, :'unit'), 'only web links'); -- Checks this is refused: only web links.
select tests.fails(format($$update public.students set program = repeat('x', 301) where id = %L$$, :'uma'), 'program too long'); -- Checks this is refused: program too long.
-- The overview is for admins to write.
select tests.fails(format($$update public.student_subjects set course_overview = 'mine' where id = %L$$, :'unit'), 'parent cannot write the overview directly'); -- Checks this is refused: parent cannot write the overview directly.
select tests.fails_with(format($$select public.admin_set_course_overview(%L, 'mine')$$, :'unit'), -- Checks a parent can't write the unit overview:
  'Only CLG admins', 'parent cannot use the overview function'); -- (the message says only CLG admins can).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Another parent and an unassigned tutor can't see or change them.
select tests.claims('00000000-0000-0000-0000-000000000001'); -- Signs in as test account ...01.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_subjects where id = :'unit'), 0, 'another parent sees nothing'); -- Checks: another parent sees nothing.
update public.student_subjects set course_code = 'HACK' where id = :'unit'; -- Tries to change the unit code.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_code = 'HACK'), 0, 'another parent changes nothing'); -- Checks: another parent changes nothing.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- Signs in as test account ...11 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_subjects where id = :'unit'), 0, 'unassigned tutor sees nothing'); -- Checks: unassigned tutor sees nothing.
select tests.fails_with(format($$select public.admin_set_course_overview(%L, 'x')$$, :'unit'), -- Checks a tutor can't write the overview:
  'Only CLG admins', 'tutor cannot write the overview'); -- (the message says only CLG admins can).
reset role; -- Goes back to the all-powerful test user (access rules off).

-- An admin writes the overview; blank clears it.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- Signs in as test account ...b0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select public.admin_set_course_overview(:'unit', '  Open channel flow, pipe networks and modelling.  '); -- Writes an overview (with extra spaces to be trimmed).
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_overview = 'Open channel flow, pipe networks and modelling.'), 1, 'admin writes the overview'); -- Checks: admin writes the overview.
select tests.fails_with(format($$select public.admin_set_course_overview(%L, repeat('x', 4001))$$, :'unit'), -- Checks an overview that's too long is refused:
  'under 4,000', 'overview too long'); -- (the message mentions the 4,000 letter limit).
select public.admin_set_course_overview(:'unit', ''); -- Clears the overview.
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_overview is null), 1, 'blank clears the overview'); -- Checks: blank clears the overview.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- An admin without two-step login can't.
select tests.claims('00000000-0000-0000-0000-0000000000b0'); -- Signs in as test account ...b0.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails(format($$select public.admin_set_course_overview(%L, 'x')$$, :'unit'), 'admin without two-step login'); -- Checks this is refused: admin without two-step login.
reset role; -- Goes back to the all-powerful test user (access rules off).

delete from public.students where id = :'uma'; -- Removes Uma again.

-- Prints that every check in this file passed.
\echo '  tertiary study details: all checks passed'
