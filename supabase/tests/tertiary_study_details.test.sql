-- Study details for university and TAFE students: program,
-- unit code and link (family), and a course overview (admins only).
-- Reuses access_rules.test.sql helpers: admin (...b0), tutor T1 (...11),
-- parents P1 (...01) and P2 (...02), and family_setup's tests.fails_with.

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Uma Two',
  (current_date - interval '19 years')::date, 'SA', 'University or TAFE', 'Adelaide University',
  '[{"subject":"Water Engineering Hydraulics and Modelling","level":"University or TAFE"}]') as uma \gset
select id as unit from public.student_subjects where student_id = :'uma' \gset
reset role;

-- The parent fills in the course details.
select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
update public.students set program = 'Bachelor of Engineering (Civil)(Honours)'
  where id = :'uma';
update public.student_subjects set course_code = 'ENGC 3000', course_url = 'https://example.edu/engc3000'
  where id = :'unit';
select tests.eq((select count(*) from public.students where id = :'uma' and program like 'Bachelor%'), 1, 'parent saves the program');
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_code = 'ENGC 3000'), 1, 'parent saves the unit code');
select tests.fails(format($$update public.student_subjects set course_url = 'javascript:alert(1)' where id = %L$$, :'unit'), 'only web links');
select tests.fails(format($$update public.students set program = repeat('x', 301) where id = %L$$, :'uma'), 'program too long');
-- The overview is for admins to write.
select tests.fails(format($$update public.student_subjects set course_overview = 'mine' where id = %L$$, :'unit'), 'parent cannot write the overview directly');
select tests.fails_with(format($$select public.admin_set_course_overview(%L, 'mine')$$, :'unit'),
  'Only CLG admins', 'parent cannot use the overview function');
reset role;

-- Another parent and an unassigned tutor can't see or change them.
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.student_subjects where id = :'unit'), 0, 'another parent sees nothing');
update public.student_subjects set course_code = 'HACK' where id = :'unit';
reset role;
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_code = 'HACK'), 0, 'another parent changes nothing');
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.student_subjects where id = :'unit'), 0, 'unassigned tutor sees nothing');
select tests.fails_with(format($$select public.admin_set_course_overview(%L, 'x')$$, :'unit'),
  'Only CLG admins', 'tutor cannot write the overview');
reset role;

-- An admin writes the overview; blank clears it.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_set_course_overview(:'unit', '  Open channel flow, pipe networks and modelling.  ');
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_overview = 'Open channel flow, pipe networks and modelling.'), 1, 'admin writes the overview');
select tests.fails_with(format($$select public.admin_set_course_overview(%L, repeat('x', 4001))$$, :'unit'),
  'under 4,000', 'overview too long');
select public.admin_set_course_overview(:'unit', '');
select tests.eq((select count(*) from public.student_subjects where id = :'unit' and course_overview is null), 1, 'blank clears the overview');
reset role;

-- An admin without two-step login can't.
select tests.claims('00000000-0000-0000-0000-0000000000b0');
set role authenticated;
select tests.fails(format($$select public.admin_set_course_overview(%L, 'x')$$, :'unit'), 'admin without two-step login');
reset role;

delete from public.students where id = :'uma';

\echo '  tertiary study details: all checks passed'
