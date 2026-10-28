-- "Become a learner too" (Carla, 2026-10-28). Anyone already signed in, such
-- as a tutor, admin or parent, can add a student profile to their own
-- account, the same as a student aged 16 or over signing up. One login,
-- one more dashboard tab. See docs/features/become-a-learner.md.
-- Safe to run more than once.

create or replace function public.add_me_as_learner(
  p_date_of_birth date,
  p_state public.au_state,
  p_year_level text,
  p_school text,
  p_subjects jsonb default '[]',
  p_goals text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_student uuid;
  v_item jsonb;
begin
  if v_me is null then
    raise exception 'Please sign in first' using errcode = '42501';
  end if;
  if exists (select 1 from public.students where account_id = v_me) then
    raise exception 'You already have a student profile' using errcode = '22023';
  end if;
  if p_date_of_birth is null or p_date_of_birth > current_date
     or p_date_of_birth < date '1900-01-02' then
    raise exception 'Please check your date of birth' using errcode = '22023';
  end if;
  if p_date_of_birth > (current_date - interval '16 years')::date then
    raise exception 'Students under 16 join through a parent account' using errcode = '22023';
  end if;
  if p_state is null then
    raise exception 'Please choose your state' using errcode = '22023';
  end if;
  if not coalesce(private.is_year_level(trim(p_year_level)), false) then
    raise exception 'Please choose your year level or stage of study' using errcode = '22023';
  end if;
  if nullif(trim(p_school), '') is null then
    raise exception 'Please enter your school, university or TAFE' using errcode = '22023';
  end if;

  insert into public.students (account_id, full_name, date_of_birth, state, year_level, school, goals, created_by)
  select v_me, a.full_name, p_date_of_birth, p_state, trim(p_year_level),
         left(trim(p_school), 200), nullif(left(trim(p_goals), 4000), ''), v_me
  from public.accounts a where a.id = v_me
  returning id into v_student;

  insert into public.account_roles (account_id, role, granted_by)
  values (v_me, 'student', v_me)
  on conflict do nothing;

  -- Each subject: {"subject": "...", "level": "Year 11" or null if unsure}.
  if jsonb_typeof(p_subjects) = 'array' then
    for v_item in select * from jsonb_array_elements(p_subjects) loop
      if nullif(trim(v_item ->> 'subject'), '') is not null then
        insert into public.student_subjects (student_id, subject, working_level)
        values (v_student, left(trim(v_item ->> 'subject'), 100), nullif(trim(v_item ->> 'level'), ''))
        on conflict do nothing;
      end if;
    end loop;
  end if;

  return v_student;
end;
$$;
revoke all on function public.add_me_as_learner(date, public.au_state, text, text, jsonb, text) from public, anon;
grant execute on function public.add_me_as_learner(date, public.au_state, text, text, jsonb, text) to authenticated;
