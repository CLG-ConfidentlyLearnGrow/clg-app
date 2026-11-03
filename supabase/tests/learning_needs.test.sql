-- Learning needs: the family writes them; only people linked to the
-- student can read them. Reuses access_rules.test.sql helpers: admin
-- (...b0), tutor T1 (...11), parents P1 (...01) and P2 (...02).

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2');
set role authenticated;
select public.admin_add_child('00000000-0000-0000-0000-000000000002', 'Nia Two',
  (current_date - interval '10 years')::date, 'SA', 'Year 5', 'Hill PS', '[]') as nia \gset
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
update public.students set learning_needs = 'Dyslexia; prefers short tasks' where id = :'nia';
select tests.eq((select count(*) from public.students where id = :'nia' and learning_needs like 'Dyslexia%'), 1, 'parent writes learning needs');
select tests.fails(format($$update public.students set learning_needs = repeat('x', 2001) where id = %L$$, :'nia'), 'too long');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'nia'), 0, 'another parent cannot see them');
update public.students set learning_needs = 'changed' where id = :'nia';
reset role;
select tests.eq((select count(*) from public.students where id = :'nia' and learning_needs = 'changed'), 0, 'another parent cannot change them');

select tests.claims('00000000-0000-0000-0000-000000000011');
set role authenticated;
select tests.eq((select count(*) from public.students where id = :'nia'), 0, 'an unassigned tutor cannot see them');
reset role;

delete from public.students where id = :'nia';

\echo '  learning needs: all checks passed'
