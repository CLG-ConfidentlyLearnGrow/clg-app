-- "Become a learner too": an existing account adds a student profile.
-- Reuses access_rules.test.sql helpers: tutor T1 (...11), parents P1 (...01)
-- and P2 (...02).

create or replace function tests.fails_with(p_sql text, p_words text, p_label text) returns void
language plpgsql as $f$
begin
  execute p_sql;
  raise exception 'Expected failure but it succeeded: %', p_label;
exception when others then
  if sqlerrm like 'Expected failure%' then raise; end if;
  if position(p_words in sqlerrm) = 0 then
    raise exception 'FAIL %: wrong error: %', p_label, sqlerrm;
  end if;
end;
$f$;

-- A tutor becomes a learner too.
select tests.claims('00000000-0000-0000-0000-000000000011');
set role authenticated;
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '15 years')::date, 'SA', 'Year 10', 'Hill HS')$$,
  'under 16', 'under 16 refused');
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Grade 4', 'Uni SA')$$,
  'year level', 'unknown year level refused');
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', ' ')$$,
  'school', 'no school refused');
select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', 'Open Uni',
  '[{"subject": "English", "level": null}]', 'Brush up essay writing') as tl \gset
select tests.eq((select count(*) from public.students where id = :'tl' and account_id = '00000000-0000-0000-0000-000000000011'), 1, 'tutor sees own student profile');
select tests.eq((select count(*) from public.student_subjects where student_id = :'tl'), 1, 'subject saved');
select tests.fails_with($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', 'Open Uni')$$,
  'already have a student profile', 'second profile refused');
reset role;
select tests.eq((select count(*) from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role in ('student', 'tutor')), 2, 'keeps tutor role and gains student role');

-- Other people can't see it, and nobody signed out can do this.
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'tl'), 0, 'a parent does not see it');
reset role;
select tests.claims(null);
set role anon;
select tests.fails($$select public.add_me_as_learner((current_date - interval '30 years')::date, 'SA', 'Year 12', 'Open Uni')$$, 'anon');
reset role;

-- Clean up so later test files see the original fixtures.
delete from public.students where id = :'tl';
delete from public.account_roles where account_id = '00000000-0000-0000-0000-000000000011' and role = 'student';

\echo '  become a learner: all checks passed'
