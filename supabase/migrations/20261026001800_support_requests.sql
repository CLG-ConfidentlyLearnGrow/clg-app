-- What each family is asking CLG for: the subjects a student wants help
-- with (one or more), the end goal (students.goals) and any other
-- information. Parents who manage a student can see and change these.
-- When a tutor is assigned, the matching curriculum is attached to the
-- student automatically. See docs/features/support-requests.md.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Extra information from the family
-- ---------------------------------------------------------------------------
alter table public.students
  add column if not exists extra_info text check (char_length(extra_info) <= 2000);

-- ---------------------------------------------------------------------------
-- Subjects a student wants help with
-- ---------------------------------------------------------------------------
create table if not exists public.student_subjects (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  added_by uuid references public.accounts (id) on delete set null,
  added_at timestamptz not null default now(),
  -- Maths is asked for as General, Essential or Advanced Maths, the same
  -- split tutors use.
  constraint student_subjects_maths_split
    check (lower(trim(subject)) not in ('maths', 'math', 'mathematics'))
);
-- The level the student is working at in this subject, which can differ
-- from their school year. Empty means the family isn't sure.
alter table public.student_subjects
  add column if not exists working_level text;
alter table public.student_subjects drop constraint if exists student_subjects_working_level;
alter table public.student_subjects
  add constraint student_subjects_working_level
  check (working_level is null or private.is_year_level(working_level));

create unique index if not exists student_subjects_once
  on public.student_subjects (student_id, lower(trim(subject)));

alter table public.student_subjects enable row level security;
revoke all on public.student_subjects from anon;

drop trigger if exists audit on public.student_subjects;
create trigger audit after insert or update or delete on public.student_subjects
  for each row execute function private.audit_change();

create or replace function private.stamp_student_subject()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.subject := trim(new.subject);
  new.added_by := auth.uid();
  new.added_at := now();
  if (select count(*) from public.student_subjects where student_id = new.student_id) >= 10 then
    raise exception 'A student can ask for up to 10 subjects' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists stamp on public.student_subjects;
create trigger stamp before insert on public.student_subjects
  for each row execute function private.stamp_student_subject();

drop policy if exists "see a student's subjects" on public.student_subjects;
create policy "see a student's subjects" on public.student_subjects
  for select to authenticated using (private.can_view_student(student_id));
drop policy if exists "parents and admins add subjects" on public.student_subjects;
create policy "parents and admins add subjects" on public.student_subjects
  for insert to authenticated
  with check (private.is_admin() or private.can_manage_student(student_id));
drop policy if exists "parents and admins remove subjects" on public.student_subjects;
create policy "parents and admins remove subjects" on public.student_subjects
  for delete to authenticated
  using (private.is_admin() or private.can_manage_student(student_id));
drop policy if exists "parents and admins change a subject's level" on public.student_subjects;
create policy "parents and admins change a subject's level" on public.student_subjects
  for update to authenticated
  using (private.is_admin() or private.can_manage_student(student_id))
  with check (private.is_admin() or private.can_manage_student(student_id));
-- Only the level can be changed; a different subject is removed and added.
revoke update on public.student_subjects from authenticated;
grant update (working_level) on public.student_subjects to authenticated;

-- ---------------------------------------------------------------------------
-- Adding a child now includes subjects, end goal and other information.
-- ---------------------------------------------------------------------------
drop function if exists public.add_my_child(text, date, public.au_state, text, text);

create or replace function public.add_my_child(
  p_full_name text,
  p_date_of_birth date,
  p_state public.au_state,
  p_year_level text default null,
  p_school text default null,
  p_subjects jsonb default null,
  p_goals text default null,
  p_extra_info text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_family uuid;
  v_student uuid;
  v_item jsonb;
begin
  if not private.has_role('parent') then
    raise exception 'Only parents can add a child' using errcode = '42501';
  end if;
  if p_date_of_birth > current_date or p_date_of_birth < (current_date - interval '25 years')::date then
    raise exception 'Please check the date of birth' using errcode = '22023';
  end if;
  if p_state is null then
    raise exception 'Please choose a state' using errcode = '22023';
  end if;
  if not coalesce(private.is_year_level(trim(p_year_level)), false) then
    raise exception 'Please choose your child''s year level' using errcode = '22023';
  end if;
  if nullif(trim(p_school), '') is null then
    raise exception 'Please enter your child''s school' using errcode = '22023';
  end if;
  if p_subjects is null or jsonb_typeof(p_subjects) <> 'array' or jsonb_array_length(p_subjects) = 0 then
    raise exception 'Please choose at least one subject' using errcode = '22023';
  end if;

  select s.family_id into v_family
  from public.parent_student_links l
  join public.students s on s.id = l.student_id
  where l.parent_id = auth.uid() and s.family_id is not null
  limit 1;

  if v_family is null then
    insert into public.families (name, created_by)
    select left(full_name, 190) || ' family', auth.uid()
    from public.accounts where id = auth.uid()
    returning id into v_family;
  end if;

  insert into public.students (family_id, full_name, date_of_birth, state, year_level, school, goals, extra_info, created_by)
  values (
    v_family, trim(p_full_name), p_date_of_birth, p_state, trim(p_year_level), left(trim(p_school), 200),
    nullif(left(trim(p_goals), 4000), ''), nullif(left(trim(p_extra_info), 2000), ''), auth.uid()
  )
  returning id into v_student;

  insert into public.parent_student_links (parent_id, student_id)
  values (auth.uid(), v_student);

  -- Each subject: {"subject": "...", "level": "Year 5" or null if unsure}.
  for v_item in select * from jsonb_array_elements(p_subjects) loop
    if nullif(trim(v_item ->> 'subject'), '') is not null then
      insert into public.student_subjects (student_id, subject, working_level)
      values (v_student, left(trim(v_item ->> 'subject'), 100), nullif(trim(v_item ->> 'level'), ''))
      on conflict do nothing;
    end if;
  end loop;

  return v_student;
end;
$$;
revoke all on function public.add_my_child(text, date, public.au_state, text, text, jsonb, text, text) from public, anon;
grant execute on function public.add_my_child(text, date, public.au_state, text, text, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Attach the right curriculum automatically when a tutor is assigned. It
-- uses the level the family gave for that subject, or the school year if
-- they weren't sure.
-- ---------------------------------------------------------------------------

-- Puts a subject name in a standard form so "General Maths" and "General
-- Mathematics", or "HASS F-6" and "Humanities and Social Sciences", match.
create or replace function private.norm_subject(p text)
returns text language sql immutable
set search_path = ''
as $$
  select trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
    lower(trim(coalesce(p, ''))),
    '\(.*\)', '', 'g'),                                   -- drop "(...)" notes
    '\s+(f|\d+)\s*[-–]\s*\d+$', ''),                      -- drop "F-6", "7-10"
    '\mmaths?\M', 'mathematics', 'g'),
    '^humanities and social sciences$', 'hass'),
    '\s+', ' ', 'g'))
$$;

-- Does a curriculum subject cover what the family asked for? "General
-- Maths" matches SACE "General Mathematics" exactly, and the Australian
-- Curriculum's "Mathematics" for Years 10 and below. Literacy and numeracy
-- map to English and Mathematics.
create or replace function private.subject_fits(p_requested text, p_curriculum text)
returns boolean language sql immutable
set search_path = ''
as $$
  with r as (
    select private.norm_subject(p_requested) as req, private.norm_subject(p_curriculum) as cur
  )
  select req <> '' and (
       cur = req
    or cur = regexp_replace(req, '^(general|essential|advanced|specialist|foundation) ', '')
    or (req = 'literacy' and cur = 'english')
    or (req = 'numeracy' and cur = 'mathematics')
  )
  from r
$$;

-- Does a curriculum level ("Year 7", "Year 11 (Stage 1)") cover the
-- student's year level? "Year 1" must not match "Year 11".
create or replace function private.level_fits(p_year_level text, p_level_band text)
returns boolean language sql immutable
set search_path = ''
as $$
  select p_year_level is not null and (
       lower(trim(p_level_band)) = lower(trim(p_year_level))
    or lower(trim(p_level_band)) like lower(trim(p_year_level)) || ' (%'
  )
$$;

create or replace function private.attach_curriculum()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.student_frameworks (student_id, framework_id)
  select distinct new.student_id, f.id
  from public.curriculum_frameworks f
  join public.students st on st.id = new.student_id
  where f.confirmed_at is not null
    and f.active
    and exists (
      select 1 from public.curriculum_skills s
      where s.framework_id = f.id
        and s.retired_at is null
        and private.subject_fits(new.subject, s.subject)
        and private.level_fits(
              coalesce(
                (select ss.working_level from public.student_subjects ss
                 where ss.student_id = new.student_id
                   and private.subject_fits(ss.subject, new.subject)
                   and ss.working_level is not null
                 limit 1),
                st.year_level),
              s.level_band)
    )
  on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists attach_curriculum on public.tutor_assignments;
create trigger attach_curriculum after insert on public.tutor_assignments
  for each row execute function private.attach_curriculum();
