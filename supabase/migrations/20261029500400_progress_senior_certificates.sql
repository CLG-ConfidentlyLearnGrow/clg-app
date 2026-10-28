-- Progress tracking, part 6 (module: progress): senior certificates by
-- state. See docs/features/senior-certificates.md.
--
-- Each state has its own senior certificate for Years 11 and 12 (SACE in
-- South Australia, VCE in Victoria, HSC in New South Wales and so on). The
-- app keeps each certificate's completion rules as data, so adding a state
-- means loading rows, not changing code. SACE's rules are loaded now (all
-- CLG students are in SA); the others are listed, with their rules to be
-- loaded and checked before CLG takes students there.
--
-- Families, the student and the tutor list the senior subjects the student
-- is planning, studying and has finished, with the grade the school gave.
-- The app shows how far the student is towards the certificate. The school
-- and the SACE Board hold the official record; this is a planning aid.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The certificates and their rules (reference data; only admins change it)
-- ---------------------------------------------------------------------------
create table if not exists public.senior_certificates (
  code text primary key check (code ~ '^[A-Z_]{2,12}$'),
  name text not null check (char_length(name) between 2 and 200),
  states public.au_state[] not null,
  -- Credits (or units) needed in total; null until the rules are loaded.
  total_credits integer check (total_credits > 0),
  -- The grade scale at each stage, best first.
  stage1_grades text[],
  stage2_grades text[],
  rules_loaded boolean not null default false,
  source_url text check (source_url ~ '^https://'),
  checked_on date
);

create table if not exists public.certificate_requirements (
  certificate text not null references public.senior_certificates (code) on delete cascade,
  code text not null check (code ~ '^[a-z_0-9]{2,30}$'),
  name text not null check (char_length(name) between 2 and 200),
  plain_description text not null check (char_length(plain_description) between 2 and 500),
  -- 1 or 2, or null when any stage counts.
  stage integer check (stage in (1, 2)),
  min_credits integer not null check (min_credits > 0),
  -- The lowest grade that counts; null means any finished grade.
  min_grade text,
  -- Which subjects count: those marked with this area, or all of them.
  area text check (area in ('eif', 'literacy', 'numeracy', 'aif')),
  sort integer not null default 0,
  primary key (certificate, code)
);

alter table public.senior_certificates enable row level security;
alter table public.certificate_requirements enable row level security;
revoke all on public.senior_certificates, public.certificate_requirements from anon;
drop policy if exists "read certificates" on public.senior_certificates;
create policy "read certificates" on public.senior_certificates for select to authenticated using (true);
drop policy if exists "admins change certificates" on public.senior_certificates;
create policy "admins change certificates" on public.senior_certificates for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
drop policy if exists "read certificate rules" on public.certificate_requirements;
create policy "read certificate rules" on public.certificate_requirements for select to authenticated using (true);
drop policy if exists "admins change certificate rules" on public.certificate_requirements;
create policy "admins change certificate rules" on public.certificate_requirements for all to authenticated
  using (private.is_admin()) with check (private.is_admin());

-- SACE (South Australia). From the SACE Board's "What is the SACE?" page,
-- read 2026-10-28. Activating Identities and Futures replaced the Research
-- Project from 2025; a Research Project result still counts.
insert into public.senior_certificates (code, name, states, total_credits, stage1_grades, stage2_grades, rules_loaded, source_url, checked_on)
values (
  'SACE', 'South Australian Certificate of Education (SACE)', '{SA}', 200,
  array['A', 'B', 'C', 'D', 'E'],
  array['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D+', 'D', 'D-', 'E+', 'E', 'E-'],
  true, 'https://www.sace.sa.edu.au/studying/your-sace/what-is-the-sace', date '2026-10-28'
)
on conflict (code) do update set
  name = excluded.name, states = excluded.states, total_credits = excluded.total_credits,
  stage1_grades = excluded.stage1_grades, stage2_grades = excluded.stage2_grades,
  rules_loaded = excluded.rules_loaded, source_url = excluded.source_url, checked_on = excluded.checked_on;

insert into public.certificate_requirements (certificate, code, name, plain_description, stage, min_credits, min_grade, area, sort) values
  ('SACE', 'eif', 'Exploring Identities and Futures', '10 credits at Stage 1, usually in Year 10 or 11, with a C or better.', 1, 10, 'C', 'eif', 1),
  ('SACE', 'literacy', 'Literacy', '20 credits of Stage 1 English subjects with a C or better.', 1, 20, 'C', 'literacy', 2),
  ('SACE', 'numeracy', 'Numeracy', '10 credits of Stage 1 Maths subjects with a C or better.', 1, 10, 'C', 'numeracy', 3),
  ('SACE', 'aif', 'Activating Identities and Futures', '10 credits at Stage 2 with a C- or better (a Research Project counts too).', 2, 10, 'C-', 'aif', 4),
  ('SACE', 'stage2', 'Other Stage 2 subjects', 'At least 60 more credits at Stage 2 with a C- or better.', 2, 60, 'C-', null, 5),
  ('SACE', 'total', 'Total', '200 credits in all, including the ones above.', null, 200, null, null, 6)
on conflict (certificate, code) do update set
  name = excluded.name, plain_description = excluded.plain_description, stage = excluded.stage,
  min_credits = excluded.min_credits, min_grade = excluded.min_grade, area = excluded.area, sort = excluded.sort;

-- The other states: listed so students there are matched to the right
-- certificate. Rules to be loaded (and checked against the official source)
-- before CLG takes senior students in that state.
insert into public.senior_certificates (code, name, states) values
  ('NTCET', 'Northern Territory Certificate of Education and Training (NTCET)', '{NT}'),
  ('HSC', 'Higher School Certificate (HSC)', '{NSW}'),
  ('VCE', 'Victorian Certificate of Education (VCE)', '{VIC}'),
  ('QCE', 'Queensland Certificate of Education (QCE)', '{QLD}'),
  ('WACE', 'Western Australian Certificate of Education (WACE)', '{WA}'),
  ('TCE', 'Tasmanian Certificate of Education (TCE)', '{TAS}'),
  ('ACT_SSC', 'ACT Senior Secondary Certificate', '{ACT}')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- The student's senior subjects
-- ---------------------------------------------------------------------------
create table if not exists public.senior_subjects (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  certificate text not null references public.senior_certificates (code),
  subject text not null check (char_length(subject) between 2 and 100),
  stage integer not null check (stage in (1, 2)),
  credits integer not null check (credits in (10, 20)),
  -- Which compulsory part it counts towards, if any.
  area text check (area in ('eif', 'literacy', 'numeracy', 'aif')),
  school_year integer check (school_year between 2020 and 2100),
  status text not null default 'planned' check (status in ('planned', 'studying', 'finished')),
  -- As the school reported it, for a finished subject.
  grade text check (char_length(grade) <= 3),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status = 'finished' or grade is null)
);
create index if not exists senior_subjects_student on public.senior_subjects (student_id, stage, subject);

alter table public.senior_subjects enable row level security;
revoke all on public.senior_subjects from anon;
revoke truncate on public.senior_subjects from authenticated;
revoke update on public.senior_subjects from authenticated;
grant update (subject, stage, credits, area, school_year, status, grade) on public.senior_subjects to authenticated;

drop policy if exists "see senior subjects" on public.senior_subjects;
create policy "see senior subjects" on public.senior_subjects
  for select to authenticated using (private.can_view_student(student_id));
-- The student (own login), a parent who manages them, their tutor, or an admin.
drop policy if exists "add senior subjects" on public.senior_subjects;
create policy "add senior subjects" on public.senior_subjects
  for insert to authenticated with check (private.can_plan_for(student_id));
drop policy if exists "change senior subjects" on public.senior_subjects;
create policy "change senior subjects" on public.senior_subjects
  for update to authenticated using (private.can_plan_for(student_id)) with check (private.can_plan_for(student_id));
drop policy if exists "remove senior subjects" on public.senior_subjects;
create policy "remove senior subjects" on public.senior_subjects
  for delete to authenticated using (private.can_plan_for(student_id));

drop trigger if exists audit on public.senior_subjects;
create trigger audit after insert or update or delete on public.senior_subjects
  for each row execute function private.audit_change();
drop trigger if exists touch on public.senior_subjects;
create trigger touch before update on public.senior_subjects
  for each row execute function private.touch_updated_at();

-- A grade must be on the certificate's scale for that stage.
create or replace function private.guard_senior_subject()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_scale text[];
begin
  select case when new.stage = 1 then c.stage1_grades else c.stage2_grades end
  into v_scale from public.senior_certificates c where c.code = new.certificate;
  if new.grade is not null then
    new.grade := upper(btrim(new.grade));
    if v_scale is not null and not new.grade = any(v_scale) then
      raise exception 'Use a grade from the Stage % scale: %', new.stage, array_to_string(v_scale, ', ')
        using errcode = '23514';
    end if;
  end if;
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$;
drop trigger if exists guard on public.senior_subjects;
create trigger guard before insert or update on public.senior_subjects
  for each row execute function private.guard_senior_subject();

-- The certificate for a student, from the state they live in.
create or replace function public.student_certificate(p_student uuid)
returns text language sql stable security definer
set search_path = ''
as $$
  select c.code from public.students s
  join public.senior_certificates c on s.state = any(c.states)
  where s.id = p_student and private.can_view_student(p_student)
  order by c.code limit 1
$$;
revoke all on function public.student_certificate(uuid) from public, anon;
grant execute on function public.student_certificate(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- How far the student is towards each requirement: credits finished with a
-- good enough grade, and credits still under way or planned.
-- ---------------------------------------------------------------------------
create or replace function private.grade_meets(p_grade text, p_min text, p_scale text[])
returns boolean language sql immutable
set search_path = ''
as $$
  select case
    when p_grade is null then false
    when p_min is null then true
    -- Stage 1 grades have no + or -: a "C" meets a "C-".
    else coalesce(array_position(p_scale, p_grade), 999)
      <= coalesce(array_position(p_scale, p_min), array_position(p_scale, rtrim(p_min, '+-')), 0)
  end
$$;

create or replace function public.certificate_progress(p_student uuid)
returns table (
  code text, name text, plain_description text, min_credits integer,
  credits_done integer, credits_under_way integer, met boolean
)
language sql stable security definer
set search_path = ''
as $$
  with cert as (
    select c.* from public.senior_certificates c
    where c.code = public.student_certificate(p_student) and c.rules_loaded
  ),
  subj as (
    select s.* from public.senior_subjects s, cert
    where s.student_id = p_student and s.certificate = cert.code
  )
  select r.code, r.name, r.plain_description, r.min_credits,
         coalesce(sum(s.credits) filter (where s.status = 'finished' and private.grade_meets(
           s.grade, r.min_grade, case when s.stage = 1 then cert.stage1_grades else cert.stage2_grades end)), 0)::integer,
         coalesce(sum(s.credits) filter (where s.status <> 'finished'), 0)::integer,
         coalesce(sum(s.credits) filter (where s.status = 'finished' and private.grade_meets(
           s.grade, r.min_grade, case when s.stage = 1 then cert.stage1_grades else cert.stage2_grades end)), 0) >= r.min_credits
  from cert
  join public.certificate_requirements r on r.certificate = cert.code
  left join subj s on (r.stage is null or s.stage = r.stage)
    and (r.area is null or s.area = r.area)
    -- "Other Stage 2 subjects" means beyond the Stage 2 compulsory one.
    and not (r.area is null and r.stage = 2 and s.area is not distinct from 'aif')
  where private.can_view_student(p_student)
  group by r.certificate, r.code, r.name, r.plain_description, r.min_credits, r.sort
  order by r.sort
$$;
revoke all on function public.certificate_progress(uuid) from public, anon;
grant execute on function public.certificate_progress(uuid) to authenticated;
