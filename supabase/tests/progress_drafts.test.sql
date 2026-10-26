-- Draft curricula. Runs after progress.test.sql and reuses its helpers,
-- owner (...a0), tutor T1 (...11) and parent P1 (...01).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.curriculum_frameworks (id, code, name, version, source)
  values ('00000000-0000-0000-0000-00000000f0d1', 'DRAFT', 'Draft curriculum', '1', 'Test file');
select tests.fails($$select public.confirm_curriculum('00000000-0000-0000-0000-00000000f0d1')$$, 'cannot confirm an empty curriculum');
select tests.fails($$insert into public.curriculum_frameworks (code, name, version, confirmed_at) values ('SKIP', 'Skip the check', '1', now())$$, 'loading straight in as confirmed');
select tests.fails($$update public.curriculum_frameworks set confirmed_at = now() where code = 'DRAFT'$$, 'confirming without the confirm step');
insert into public.curriculum_skills (id, framework_id, subject, level_band, code, description) values
  ('00000000-0000-0000-0000-00000000cd01', '00000000-0000-0000-0000-00000000f0d1', 'Science', 'Year 5', 'D-1', 'Draft skill');
select tests.eq((select count(*) from public.curriculum_frameworks where id = '00000000-0000-0000-0000-00000000f0d1' and confirmed_at is null), 1, 'new curriculum starts as a draft');
select tests.eq((select skills from public.curriculum_summary('00000000-0000-0000-0000-00000000f0d1') where subject = 'Science' and level_band = 'Year 5'), 1, 'summary counts skills');
reset role;

-- Draft skills can't be used in a goal.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails($$insert into public.goal_skills (goal_id, skill_id) select id, '00000000-0000-0000-0000-00000000cd01' from public.learning_goals limit 1$$, 'draft skill in a goal');
select tests.fails($$select public.confirm_curriculum('00000000-0000-0000-0000-00000000f0d1')$$, 'tutor confirms curriculum');
select tests.fails($$select public.discard_curriculum('00000000-0000-0000-0000-00000000f0d1')$$, 'tutor discards curriculum');
reset role;

-- Admin can throw a draft away, but never a confirmed one.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select public.discard_curriculum('00000000-0000-0000-0000-00000000f001'))::int, 0, 'confirmed curriculum is kept');
select tests.eq((select public.discard_curriculum('00000000-0000-0000-0000-00000000f0d1'))::int, 1, 'draft discarded');
select tests.eq((select count(*) from public.curriculum_skills where framework_id = '00000000-0000-0000-0000-00000000f0d1'), 0, 'draft skills removed');
reset role;
select tests.claims(null);

\echo '  curriculum drafts: all checks passed'
