-- When an admin sets up a family, only the parent's name and email and the
-- child's name are needed. The family fills in the rest (date of birth,
-- state, year level, school, subjects and goal) when they first sign in.
-- No tutor can be assigned and nothing can be booked until the student's
-- details are complete. See docs/features/family-setup.md.
-- Safe to run more than once.

-- Date of birth and state can now wait for the family to fill them in.
alter table public.students alter column date_of_birth drop not null;
alter table public.students alter column state drop not null;

-- Families can fill in a missing date of birth or state once. After that,
-- only an admin can change them, since they decide which child safety rules
-- and tutor checks apply.
create or replace function private.guard_student()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if private.is_backend() or private.is_admin() then
    return new;
  end if;
  if new.account_id is distinct from old.account_id
    or (new.date_of_birth is distinct from old.date_of_birth and old.date_of_birth is not null)
    or (new.state is distinct from old.state and old.state is not null)
    or new.family_id is distinct from old.family_id
    or new.created_by is distinct from old.created_by
    or new.last_activity_at is distinct from old.last_activity_at
  then
    raise exception 'Only an admin can change this part of a student record'
      using errcode = '42501';
  end if;
  if old.date_of_birth is null and new.date_of_birth is not null
     and (new.date_of_birth > current_date or new.date_of_birth < (current_date - interval '25 years')::date) then
    raise exception 'Please check the date of birth' using errcode = '22023';
  end if;
  return new;
end;
$$;

-- Are the details CLG needs to match and keep a student safe all there?
create or replace function private.student_details_complete(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.students
    where id = p_student
      and date_of_birth is not null
      and state is not null
      and year_level is not null
      and nullif(trim(school), '') is not null
  )
$$;

create or replace function private.require_complete_student()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if not private.student_details_complete(new.student_id) then
    raise exception 'This student''s details aren''t finished yet (date of birth, state, year level and school). The family can finish them on their dashboard.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
-- Named to run before the other assignment checks, so this message shows first.
drop trigger if exists check_a_student_details on public.tutor_assignments;
create trigger check_a_student_details before insert on public.tutor_assignments
  for each row execute function private.require_complete_student();
drop trigger if exists check_a_student_details on public.bookings;
create trigger check_a_student_details before insert on public.bookings
  for each row execute function private.require_complete_student();

-- ---------------------------------------------------------------------------
-- Adding a child: admins may leave everything but the name for the family
-- to fill in. Parents adding their own child still give everything.
-- ---------------------------------------------------------------------------
drop function if exists private.add_child_for(uuid, uuid, text, date, public.au_state, text, text, jsonb, text, text);
create or replace function private.add_child_for(
  p_parent uuid,
  p_verified_by uuid,
  p_full_name text,
  p_date_of_birth date,
  p_state public.au_state,
  p_year_level text,
  p_school text,
  p_subjects jsonb,
  p_goals text,
  p_extra_info text,
  p_family_finishes boolean default false
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_family uuid;
  v_student uuid;
  v_item jsonb;
begin
  if nullif(trim(p_full_name), '') is null then
    raise exception 'Please enter the child''s name' using errcode = '22023';
  end if;
  if (p_date_of_birth is not null or not p_family_finishes)
     and (p_date_of_birth is null or p_date_of_birth > current_date
          or p_date_of_birth < (current_date - interval '25 years')::date) then
    raise exception 'Please check the date of birth' using errcode = '22023';
  end if;
  if p_state is null and not p_family_finishes then
    raise exception 'Please choose a state' using errcode = '22023';
  end if;
  if (nullif(trim(p_year_level), '') is not null or not p_family_finishes)
     and not coalesce(private.is_year_level(trim(p_year_level)), false) then
    raise exception 'Please choose the child''s year level' using errcode = '22023';
  end if;
  if nullif(trim(p_school), '') is null and not p_family_finishes then
    raise exception 'Please enter the child''s school' using errcode = '22023';
  end if;
  if not p_family_finishes and (p_subjects is null or jsonb_typeof(p_subjects) <> 'array' or jsonb_array_length(p_subjects) = 0) then
    raise exception 'Please choose at least one subject' using errcode = '22023';
  end if;

  select s.family_id into v_family
  from public.parent_student_links l
  join public.students s on s.id = l.student_id
  where l.parent_id = p_parent and s.family_id is not null
  limit 1;

  if v_family is null then
    insert into public.families (name, created_by)
    select left(full_name, 190) || ' family', auth.uid()
    from public.accounts where id = p_parent
    returning id into v_family;
  end if;

  insert into public.students (family_id, full_name, date_of_birth, state, year_level, school, goals, extra_info, created_by)
  values (
    v_family, trim(p_full_name), p_date_of_birth, p_state, nullif(trim(p_year_level), ''),
    nullif(left(trim(p_school), 200), ''),
    nullif(left(trim(p_goals), 4000), ''), nullif(left(trim(p_extra_info), 2000), ''), auth.uid()
  )
  returning id into v_student;

  -- A link made by an admin is already checked.
  insert into public.parent_student_links (parent_id, student_id, verified_by, verified_at)
  values (p_parent, v_student, p_verified_by, case when p_verified_by is null then null else now() end);

  -- Each subject: {"subject": "...", "level": "Year 5" or null if unsure}.
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
revoke all on function private.add_child_for(uuid, uuid, text, date, public.au_state, text, text, jsonb, text, text, boolean) from public, anon, authenticated;

create or replace function public.admin_add_child(
  p_parent uuid,
  p_full_name text,
  p_date_of_birth date,
  p_state public.au_state,
  p_year_level text,
  p_school text,
  p_subjects jsonb,
  p_goals text default null,
  p_extra_info text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can add a child to a family' using errcode = '42501';
  end if;
  if not exists (select 1 from public.parent_profiles where account_id = p_parent) then
    raise exception 'That account is not a parent account' using errcode = '22023';
  end if;
  return private.add_child_for(p_parent, auth.uid(), p_full_name, p_date_of_birth, p_state,
    p_year_level, p_school, p_subjects, p_goals, p_extra_info, true);
end;
$$;
