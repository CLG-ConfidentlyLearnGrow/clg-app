-- What each tutor teaches: a subject and the year levels for it. A tutor
-- can teach different subjects to different ages, for example Maths for
-- Years 3 to 10 and English for Years 7 to 12. Matching uses this to suggest
-- tutors for a student's subject and year level.

-- Year levels in order, so a range can be checked. Same list as
-- private.is_year_level and src/lib/students.ts.
create function private.year_level_rank(p text)
returns integer language sql immutable
set search_path = ''
as $$
  select array_position(array[
    'Foundation',
    'Year 1', 'Year 2', 'Year 3', 'Year 4', 'Year 5', 'Year 6',
    'Year 7', 'Year 8', 'Year 9', 'Year 10', 'Year 11', 'Year 12',
    'University or TAFE', 'Adult learner'
  ], p)
$$;

create table public.tutor_teaching (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  from_level text not null check (private.year_level_rank(from_level) is not null),
  to_level text not null check (private.year_level_rank(to_level) is not null),
  created_at timestamptz not null default now(),
  check (private.year_level_rank(from_level) <= private.year_level_rank(to_level))
);
-- One range per subject per tutor (change it rather than add a second).
create unique index tutor_teaching_one_per_subject on public.tutor_teaching (tutor_id, lower(subject));

alter table public.tutor_teaching enable row level security;
revoke all on public.tutor_teaching from anon;
create trigger audit after insert or update or delete on public.tutor_teaching
  for each row execute function private.audit_change();

create policy "tutors see own teaching, admins see all" on public.tutor_teaching
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin());
create policy "tutors manage own teaching" on public.tutor_teaching
  for all to authenticated
  using ((tutor_id = auth.uid() and private.has_aal2()) or private.is_admin())
  with check (
    (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()) or private.is_admin()
  );

-- Does this tutor teach this subject at this year level?
create function private.tutor_teaches(p_tutor uuid, p_subject text, p_level text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.tutor_teaching t
    where t.tutor_id = p_tutor
      and lower(t.subject) = lower(trim(p_subject))
      and private.year_level_rank(p_level)
          between private.year_level_rank(t.from_level) and private.year_level_rank(t.to_level)
  )
$$;

-- Admin matching list: tutors who are cleared for the student's state AND
-- teach at least one subject at the student's year level. "subjects" lists
-- only those matching subjects. A tutor who hasn't added what they teach
-- is not listed.
create or replace function public.eligible_tutors(p_student uuid)
returns table (tutor_id uuid, full_name text, subjects text[], max_weekly_hours numeric)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_level text;
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select s.year_level into v_level from public.students s where s.id = p_student;
  return query
    select t.account_id, a.full_name, m.subjects, w.max_weekly_hours
    from public.tutor_profiles t
    join public.accounts a on a.id = t.account_id
    left join public.tutor_work_settings w on w.tutor_id = t.account_id
    cross join lateral (
      select array_agg(tt.subject order by tt.subject) as subjects
      from public.tutor_teaching tt
      where tt.tutor_id = t.account_id
        and private.year_level_rank(v_level)
            between private.year_level_rank(tt.from_level) and private.year_level_rank(tt.to_level)
    ) m
    where private.tutor_cleared_for_student(t.account_id, p_student)
      and m.subjects is not null
    order by a.full_name;
end;
$$;

-- A tutor can only be assigned a subject they teach at the student's year
-- level. This applies to admins too. Recording a past assignment is allowed.
create function private.check_assignment_teaching()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_level text;
begin
  if private.is_backend() then return new; end if;
  if new.ends_on is not null and new.ends_on < current_date then return new; end if;

  select year_level into v_level from public.students where id = new.student_id;
  if v_level is null then
    raise exception 'Add this student''s year level before assigning a tutor'
      using errcode = '23514';
  end if;
  if not private.tutor_teaches(new.tutor_id, new.subject, v_level) then
    raise exception 'This tutor hasn''t listed % for %. They can add it under "What you teach" in their dashboard.',
      new.subject, v_level using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger check_assignment_teaching before insert or update on public.tutor_assignments
  for each row execute function private.check_assignment_teaching();
