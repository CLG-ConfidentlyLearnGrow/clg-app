-- Study plans as an add-on. Runs after progress_roadmaps.test.sql and reuses
-- its people: owner ...a0, tutor T1 ...11 (teaches Cara One), parent P1
-- ...01 (Cara's parent), parent P2 ...02 (Vic and Cal's parent).

-- The migration is safe to run twice, and the roadmap migration is safe to
-- run again after it.
\ir ../migrations/20261102500100_study_plan_add_on.sql
\ir ../migrations/20261029500100_progress_roadmaps.sql

select tests.claims(null);
select id as cara from public.students where full_name = 'Cara One' \gset
select id as cal from public.students where full_name = 'Cal Two' \gset
select (now() at time zone 'Australia/Adelaide')::date as today \gset
select tests.eq((select count(*) from public.admin_profiles where account_id = '00000000-0000-0000-0000-0000000000a0' and level = 'owner'), 1, 'test owner is the owner');

-- ===========================================================================
-- Free (the starting point): everyone keeps study plans, nothing changes
-- ===========================================================================
select tests.eq((select count(*) from public.add_ons where code = 'study_plans' and mode = 'free'), 1, 'study plans start free');

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.add_ons where code in ('study_plans', 'term_reviews')), 2, 'families can see the add-ons');
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'cara') where has_it = true), 1, 'free: Cara has study plans');
insert into public.roadmap_targets (id, student_id, kind, title, due_on)
  values ('00000000-0000-0000-0000-0000000ad001', :'cara', 'assessment', 'Free plan test', :'today'::date + 14);
select tests.eq(public.plan_assessment_steps('00000000-0000-0000-0000-0000000ad001'), 6, 'free: parent plans study steps');
update public.add_ons set mode = 'off';
select tests.eq((select count(*) from public.add_ons where code = 'study_plans' and mode = 'free'), 1, 'parent cannot change the add-on');
select tests.fails(format($$insert into public.add_on_members (add_on, student_id) values ('study_plans', %L)$$, :'cara'), 'parent gives themselves the add-on');
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'cal')), 0, 'parent cannot look up another child');
reset role;

-- ===========================================================================
-- Only the owner switches it
-- ===========================================================================
select tests.claims(null);
update public.admin_profiles set level = 'operations' where account_id = '00000000-0000-0000-0000-0000000000a0';
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
update public.add_ons set mode = 'off' where code = 'study_plans';
select tests.eq((select count(*) from public.add_ons where code = 'study_plans' and mode = 'free'), 1, 'operations admin cannot switch it');
reset role;
select tests.claims(null);
update public.admin_profiles set level = 'owner' where account_id = '00000000-0000-0000-0000-0000000000a0';

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails($$update public.add_ons set mode = 'paid' where code = 'study_plans'$$, 'paid without a price');
update public.add_ons set mode = 'paid', price_cents = 2500, price_period = 'month' where code = 'study_plans';
select tests.eq((select count(*) from public.add_ons where code = 'study_plans' and mode = 'paid'), 1, 'owner makes study plans paid');
select tests.fails($$insert into public.add_ons (code, name) values ('games', 'Games')$$, 'add-ons are not added in the app');
reset role;
select tests.eq((select count(*) from public.audit_log where table_name = 'add_ons' and actor_id = '00000000-0000-0000-0000-0000000000a0'), 1, 'the switch is logged');

-- ===========================================================================
-- Paid, and Cara doesn't have it
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'cara') where has_it = false), 1, 'paid: Cara does not have it');
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title, due_on) values (%L, 'assessment', 'Paid test', %L)$$, :'cara', :'today'::date + 10), 'paid: parent adds an assessment');
select tests.fails(format($$insert into public.roadmap_steps (student_id, title) values (%L, 'Parent step')$$, :'cara'), 'paid: parent adds a step');
-- What was planned while it was free stays, and can still be ticked off.
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000ad001'), 6, 'paid: earlier plan still visible');
select public.tick_roadmap_step((select id from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000ad001' order by due_on limit 1));
select tests.eq((select count(*) from public.roadmap_steps where target_id = '00000000-0000-0000-0000-0000000ad001' and done_at is not null), 1, 'paid: parent still ticks steps off');
reset role;

-- The tutor's own steps are part of tutoring.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
insert into public.roadmap_steps (id, student_id, title) values ('00000000-0000-0000-0000-0000000ad101', :'cara', 'Tutor step without the add-on');
select tests.eq((select count(*) from public.roadmap_steps where id = '00000000-0000-0000-0000-0000000ad101'), 1, 'paid: tutor still adds steps');
select tests.fails(format($$insert into public.roadmap_targets (student_id, kind, title) values (%L, 'goal', 'Tutor goal')$$, :'cara'), 'paid: tutor adds a goal without the add-on');
reset role;

-- ===========================================================================
-- Paid, and the admin gives it to Cara
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into public.add_on_members (add_on, student_id, note) values ('study_plans', :'cara', 'Pays monthly');
select tests.eq((select count(*) from public.add_on_members where created_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'admin gives Cara study plans');
select tests.fails(format($$update public.add_on_members set student_id = %L$$, :'cal'), 'moving it to another student');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.add_on_members), 1, 'parent sees Cara has it');
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'cara') where has_it = true), 1, 'paid: Cara has it now');
insert into public.roadmap_targets (student_id, kind, title, due_on) values (:'cara', 'assessment', 'Paid plan test', :'today'::date + 10);
select tests.eq((select count(*) from public.roadmap_targets where title = 'Paid plan test'), 1, 'paid with add-on: parent adds an assessment');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000002');
set role authenticated;
select tests.eq((select count(*) from public.add_on_members), 0, 'other parent cannot see who has it');
reset role;

-- It stops on its end date.
select tests.claims(null);
update public.add_on_members set starts_on = :'today'::date - 30, ends_on = :'today'::date - 1 where student_id = :'cara';
select tests.claims('00000000-0000-0000-0000-000000000001');
set role authenticated;
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'cara') where has_it = false), 1, 'ended: Cara no longer has it');
reset role;

-- ===========================================================================
-- Off: nobody, and back to free for the tests after this
-- ===========================================================================
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
update public.add_on_members set ends_on = null where student_id = :'cara';
update public.add_ons set mode = 'off' where code = 'study_plans';
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'cara') where has_it = false), 1, 'off: nobody has it, even members');
update public.add_ons set mode = 'free' where code = 'study_plans';
delete from public.add_on_members;
reset role;
select tests.eq((select count(*) from public.add_on_members), 0, 'admin ends the add-on');
select tests.claims(null);
\echo '  study plans add-on: all checks passed'
