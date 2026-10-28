-- Materials library. Runs after access_rules.test.sql and reuses its people:
-- owner ...a0 (admin), tutor T1 ...11 (teaches General Maths Years 3 to 6 and
-- tutors Cara One, Year 5), tutor T2 ...12 (General Maths Years 1 to 12,
-- Science Years 1 to 6), parent P1 ...01 (Cara's parent).
-- Cleans up after itself so later tests see the same data as before.

select id as cara from public.students where full_name = 'Cara One' \gset

-- A small confirmed curriculum to tag with, plus one draft curriculum.
insert into public.curriculum_frameworks (id, code, name, version, confirmed_at) values
  ('00000000-0000-0000-0000-00000000f601', 'MATT', 'Materials test', '1', now()),
  ('00000000-0000-0000-0000-00000000f602', 'MATD', 'Materials draft', '1', null);
insert into public.curriculum_skills (id, framework_id, subject, level_band, code, description) values
  ('00000000-0000-0000-0000-00000000c601', '00000000-0000-0000-0000-00000000f601', 'Mathematics', 'Year 5', 'MT5-1', 'Compare fractions'),
  ('00000000-0000-0000-0000-00000000c602', '00000000-0000-0000-0000-00000000f601', 'Mathematics', 'Year 9', 'MT9-1', 'Solve linear equations'),
  ('00000000-0000-0000-0000-00000000c603', '00000000-0000-0000-0000-00000000f601', 'English', 'Year 5', 'ET5-1', 'Persuasive writing'),
  ('00000000-0000-0000-0000-00000000c604', '00000000-0000-0000-0000-00000000f601', 'Mathematics', 'Years 3 and 4', 'MT34-1', 'Times tables'),
  ('00000000-0000-0000-0000-00000000c605', '00000000-0000-0000-0000-00000000f602', 'Mathematics', 'Year 5', 'MD5-1', 'Draft skill');

-- Reading curriculum levels.
select tests.eq((private.level_band_ranks('Year 5'))[1], 6, 'Year 5 is rank 6');
select tests.eq((private.level_band_ranks('Year 11 (Stage 1)'))[2], 12, 'Stage 1 note ignored');
select tests.eq((private.level_band_ranks('Years 3 and 4'))[2], 5, 'two-year band');
select tests.eq((private.level_band_ranks('Foundation'))[1], 1, 'Foundation');
select tests.eq((private.level_band_ranks('Unit 3') is null)::int, 0, 'number read from unit');
select tests.eq((private.level_band_ranks('Adults') is null)::int, 1, 'unknown level');

-- ===========================================================================
-- Only admins add and tag materials
-- ===========================================================================

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.fails($$insert into public.materials (title, subject, from_level, to_level, file_path, file_type, file_bytes) values ('Mine', 'General Maths', 'Year 5', 'Year 5', 'view/00000000-0000-0000-0000-000000000001.pdf', 'application/pdf', 100)$$, 'tutor adds a material');
select tests.fails($$insert into storage.objects (bucket_id, name) values ('materials', 'view/x.pdf')$$, 'tutor uploads a file');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1');
set role authenticated;
select tests.fails($$insert into public.materials (title, subject, from_level, to_level, file_path, file_type, file_bytes) values ('No 2-step', 'General Maths', 'Year 5', 'Year 5', 'view/00000000-0000-0000-0000-000000000001.pdf', 'application/pdf', 100)$$, 'admin without two-step login');
reset role;

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
insert into storage.objects (bucket_id, name) values ('materials', 'view/00000000-0000-0000-0000-00000000e601.pdf');
insert into public.materials (id, title, kind, subject, from_level, to_level, file_path, file_type, file_bytes) values
  ('00000000-0000-0000-0000-00000000e601', 'Fraction walls', 'worksheet', 'General Maths', 'Year 4', 'Year 6', 'view/00000000-0000-0000-0000-00000000e601.pdf', 'application/pdf', 1000),
  ('00000000-0000-0000-0000-00000000e602', 'Equations starter', 'worksheet', 'General Maths', 'Year 8', 'Year 10', 'view/00000000-0000-0000-0000-00000000e602.pdf', 'application/pdf', 1000),
  ('00000000-0000-0000-0000-00000000e603', 'Persuasive essay plan', 'lesson_plan', 'English', 'Year 5', 'Year 6', 'view/00000000-0000-0000-0000-00000000e603.pdf', 'application/pdf', 1000),
  ('00000000-0000-0000-0000-00000000e604', 'Study timetable', 'reference', 'General Maths', 'Year 5', 'Year 5', 'view/00000000-0000-0000-0000-00000000e604.png', 'image/png', 1000);
select tests.eq((select count(*) from public.materials where created_by = '00000000-0000-0000-0000-0000000000a0' and status = 'draft'), 4, 'drafts stamped with admin');
select tests.fails($$insert into public.materials (title, subject, from_level, to_level, file_path, file_type, file_bytes) values ('Backwards', 'General Maths', 'Year 9', 'Year 4', 'view/00000000-0000-0000-0000-000000000001.pdf', 'application/pdf', 100)$$, 'year range backwards');
select tests.fails($$insert into public.materials (title, subject, from_level, to_level, file_path, file_type, file_bytes) values ('Bad path', 'General Maths', 'Year 4', 'Year 4', '../secret.pdf', 'application/pdf', 100)$$, 'odd file path');
select tests.fails($$insert into public.materials (title, subject, from_level, to_level, file_path, file_type, file_bytes) values ('Too big', 'General Maths', 'Year 4', 'Year 4', 'view/00000000-0000-0000-0000-000000000001.pdf', 'application/pdf', 5000000)$$, 'file over 4 MB');

-- The skill picker lists matching skills in confirmed curricula only.
select tests.eq((select count(*) from public.skills_for_material('General Maths', 'Year 4', 'Year 6')), 2, 'maths skills for Years 4 to 6 (fractions, times tables)');
select tests.eq((select count(*) from public.skills_for_material('General Maths', 'Year 4', 'Year 6', 'fraction')), 1, 'search words');
select tests.eq((select count(*) from public.skills_for_material('English', 'Year 5', 'Year 5')), 1, 'English skills');

-- Publishing needs skills (or a reason).
select tests.fails($$update public.materials set status = 'published' where id = '00000000-0000-0000-0000-00000000e601'$$, 'publish without skills');
insert into public.material_skills (material_id, skill_id) values
  ('00000000-0000-0000-0000-00000000e601', '00000000-0000-0000-0000-00000000c601'),
  ('00000000-0000-0000-0000-00000000e602', '00000000-0000-0000-0000-00000000c602'),
  ('00000000-0000-0000-0000-00000000e603', '00000000-0000-0000-0000-00000000c603');
select tests.fails($$insert into public.material_skills (material_id, skill_id) values ('00000000-0000-0000-0000-00000000e601', '00000000-0000-0000-0000-00000000c605')$$, 'tag with a draft curriculum skill');
update public.materials set status = 'published' where id in (
  '00000000-0000-0000-0000-00000000e601', '00000000-0000-0000-0000-00000000e602', '00000000-0000-0000-0000-00000000e603');
select tests.eq((select count(*) from public.materials where status = 'published' and published_at is not null), 3, 'published with date');
update public.materials set status = 'published', no_skills_reason = 'Study skills: no curriculum' where id = '00000000-0000-0000-0000-00000000e604';
select tests.eq((select count(*) from public.materials where status = 'published'), 4, 'published with a reason instead of skills');
select tests.fails($$delete from public.material_skills where material_id = '00000000-0000-0000-0000-00000000e601'$$, 'remove the last skill of a published material');
select tests.fails($$update public.materials set status = 'draft' where id = '00000000-0000-0000-0000-00000000e601'$$, 'published back to draft');
update public.materials set created_by = '00000000-0000-0000-0000-000000000011' where id = '00000000-0000-0000-0000-00000000e601';
select tests.eq((select count(*) from public.materials where id = '00000000-0000-0000-0000-00000000e601' and created_by = '00000000-0000-0000-0000-0000000000a0'), 1, 'creator kept');
delete from public.materials where id = '00000000-0000-0000-0000-00000000e602';
select tests.eq((select count(*) from public.materials where id = '00000000-0000-0000-0000-00000000e602'), 1, 'published material cannot be deleted');
reset role;

-- Parent and student logins: no skill picker.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.fails($$select * from public.skills_for_material('General Maths', 'Year 4', 'Year 6')$$, 'parent uses skill picker');
reset role;

-- ===========================================================================
-- Who sees what
-- ===========================================================================

-- T1 teaches General Maths Years 3 to 6: fractions and the study timetable,
-- not equations (Years 8 to 10) or English.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.materials), 2, 'T1 sees maths for the years they teach');
select tests.eq((select count(*) from public.material_skills), 1, 'T1 sees the tags of those');
select tests.eq((select count(*) from storage.objects where bucket_id = 'materials'), 0, 'tutor cannot read files directly');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1');
set role authenticated;
select tests.eq((select count(*) from public.materials), 0, 'no materials without two-step login');
reset role;

-- T2 teaches General Maths Years 1 to 12.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.materials), 3, 'T2 sees all three maths materials');
reset role;

select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.materials), 0, 'parent sees none');
select tests.fails($$select * from public.open_material('00000000-0000-0000-0000-00000000e601')$$, 'parent opens a material');
reset role;

select tests.claims(null);
set role anon;
select tests.fails($$select * from public.materials$$, 'anon');
reset role;

-- A draft is hidden from tutors; a retired one too.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
update public.materials set status = 'retired' where id = '00000000-0000-0000-0000-00000000e604';
reset role;
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.materials), 1, 'retired material hidden');

-- ===========================================================================
-- Opening: logged, limited, stamped with the tutor's details
-- ===========================================================================

select tests.eq((select count(*) from public.open_material('00000000-0000-0000-0000-00000000e601') where title = 'Fraction walls'), 1, 'T1 opens fractions');
select tests.fails($$select * from public.open_material('00000000-0000-0000-0000-00000000e602')$$, 'T1 opens equations (not their years)');
select tests.fails($$select * from public.open_material('00000000-0000-0000-0000-00000000e603')$$, 'T1 opens English (not their subject)');
select tests.eq((select count(*) from public.material_opens), 0, 'tutor cannot read the open log');
select tests.fails($$insert into public.material_opens (material_id, account_id) values ('00000000-0000-0000-0000-00000000e601', '00000000-0000-0000-0000-000000000011')$$, 'tutor writes the open log');
select tests.fails($$select * from public.material_open_summary(7)$$, 'tutor reads the summary');
reset role;
select tests.eq((select count(*) from public.material_opens where account_id = '00000000-0000-0000-0000-000000000011'), 1, 'open logged');

-- Daily limit: 30 different materials in 24 hours. Opening the same one
-- again doesn't count.
insert into public.material_opens (material_id, account_id, opened_at)
  select '00000000-0000-0000-0000-00000000e601', '00000000-0000-0000-0000-000000000011', now() from generate_series(1, 5);
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.open_material('00000000-0000-0000-0000-00000000e601')), 1, 'same material again is fine');
reset role;
-- Make T1 look like they opened 30 other materials today.
insert into public.materials (id, title, subject, from_level, to_level, file_path, file_type, file_bytes, status, no_skills_reason)
  select ('00000000-0000-0000-0000-0000000e' || lpad(g::text, 4, '0'))::uuid, 'Bulk ' || g, 'General Maths', 'Year 5', 'Year 5',
         'view/' || ('00000000-0000-0000-0000-0000000e' || lpad(g::text, 4, '0')) || '.pdf', 'application/pdf', 10, 'published', 'test'
  from generate_series(1, 31) g;
insert into public.material_opens (material_id, account_id)
  select ('00000000-0000-0000-0000-0000000e' || lpad(g::text, 4, '0'))::uuid, '00000000-0000-0000-0000-000000000011'
  from generate_series(1, 29) g;
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
-- Fractions + 29 bulk = 30 different, so a new one is refused.
select tests.fails($$select * from public.open_material('00000000-0000-0000-0000-0000000e0031')$$, 'more than 30 different materials in a day');
select tests.eq((select count(*) from public.open_material('00000000-0000-0000-0000-0000000e0001')), 1, 'one already opened today still opens');
reset role;
-- Opens from yesterday don't count.
update public.material_opens set opened_at = now() - interval '25 hours' where account_id = '00000000-0000-0000-0000-000000000011';
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.open_material('00000000-0000-0000-0000-0000000e0031')), 1, 'limit resets after 24 hours');
reset role;

-- Admins see who opened what, and have no limit.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.material_opens), 38, 'admin reads the open log');
select tests.eq((select different_materials from public.material_open_summary(7) where account_id = '00000000-0000-0000-0000-000000000011'), 31, 'summary counts different materials');
select tests.eq((select count(*) from public.open_material('00000000-0000-0000-0000-00000000e603')), 1, 'admin opens any material');
reset role;

-- Old opens are cleared after 2 years.
update public.material_opens set opened_at = now() - interval '3 years' where material_id = '00000000-0000-0000-0000-0000000e0002';
select tests.eq(private.clear_old_material_opens(), 1, 'old opens cleared');

-- ===========================================================================
-- Suggestions from a student's goals
-- ===========================================================================

insert into public.learning_goals (id, student_id, subject, title)
  values ('00000000-0000-0000-0000-00000000a601', :'cara', 'General Maths', 'Compare fractions confidently');
insert into public.goal_skills (goal_id, skill_id) values
  ('00000000-0000-0000-0000-00000000a601', '00000000-0000-0000-0000-00000000c601');
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.materials_for_my_students() where material_id = '00000000-0000-0000-0000-00000000e601'), 1, 'fractions suggested for Cara''s goal');
reset role;
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2');
set role authenticated;
select tests.eq((select count(*) from public.materials_for_my_students() where student_name = 'Cara One'), 0, 'other tutor gets no suggestions for Cara');
reset role;

-- ===========================================================================
-- Clean up
-- ===========================================================================

select tests.claims(null);
delete from public.goal_skills where goal_id = '00000000-0000-0000-0000-00000000a601';
delete from public.learning_goals where id = '00000000-0000-0000-0000-00000000a601';
delete from public.materials;
delete from storage.objects where bucket_id = 'materials';
delete from public.curriculum_skills where framework_id in ('00000000-0000-0000-0000-00000000f601', '00000000-0000-0000-0000-00000000f602');
delete from public.curriculum_frameworks where id in ('00000000-0000-0000-0000-00000000f601', '00000000-0000-0000-0000-00000000f602');

\echo '  materials: all checks passed'
