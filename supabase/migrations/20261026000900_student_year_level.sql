-- Year level and school are needed to match each student with the right
-- tutor, so families and adult learners must give both.
--   * Year level comes from a fixed list (the same list as src/lib/students.ts).
--   * Parents and learners cannot leave either blank, or clear them later.
--   * Admins may still leave them blank while fixing a record.

create function private.is_year_level(p text)
returns boolean language sql immutable
set search_path = ''
as $$
  select p = any (array[
    'Foundation',
    'Year 1', 'Year 2', 'Year 3', 'Year 4', 'Year 5', 'Year 6',
    'Year 7', 'Year 8', 'Year 9', 'Year 10', 'Year 11', 'Year 12',
    'University or TAFE', 'Adult learner'
  ])
$$;

-- Only known year levels from now on. "not valid" leaves any older free-text
-- entries in place for an admin to tidy.
alter table public.students
  add constraint students_year_level_known
  check (year_level is null or private.is_year_level(year_level)) not valid;

create function private.require_student_details()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if private.is_backend() or private.is_admin() then
    return new;
  end if;
  if new.year_level is null then
    raise exception 'Please choose a year level. CLG uses it to match the right tutor.'
      using errcode = '23514';
  end if;
  if nullif(trim(new.school), '') is null then
    raise exception 'Please enter a school, university or TAFE. If home-schooled, write "Home schooled".'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger require_details before insert or update on public.students
  for each row execute function private.require_student_details();

-- A parent adds their child: now with year level and school required.
create or replace function public.add_my_child(
  p_full_name text,
  p_date_of_birth date,
  p_state public.au_state,
  p_year_level text default null,
  p_school text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_family uuid;
  v_student uuid;
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

  insert into public.students (family_id, full_name, date_of_birth, state, year_level, school, created_by)
  values (v_family, trim(p_full_name), p_date_of_birth, p_state, trim(p_year_level), left(trim(p_school), 200), auth.uid())
  returning id into v_student;

  insert into public.parent_student_links (parent_id, student_id)
  values (auth.uid(), v_student);

  return v_student;
end;
$$;

-- Sign-up: adult learners now give their year level (or stage of study)
-- and where they study. Everything else is unchanged.
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(new.email));
  v_name text := nullif(trim(new.raw_user_meta_data ->> 'full_name'), '');
  v_signup text := new.raw_user_meta_data ->> 'signup_as';
  v_dob date;
  v_state public.au_state;
  v_year text := nullif(trim(new.raw_user_meta_data ->> 'year_level'), '');
  v_school text := nullif(trim(new.raw_user_meta_data ->> 'school'), '');
begin
  insert into public.accounts (id, full_name)
  values (new.id, left(coalesce(v_name, split_part(v_email, '@', 1)), 200));
  insert into public.account_private (account_id, email) values (new.id, v_email);

  if exists (
    select 1 from public.invitations
    where email = v_email and accepted_at is null and expires_at > now()
  ) then
    if new.email_confirmed_at is not null then
      perform private.accept_invitation(new.id, v_email);
    end if;
    return new;
  end if;

  if v_signup = 'parent' then
    insert into public.account_roles (account_id, role) values (new.id, 'parent');
    insert into public.parent_profiles (account_id) values (new.id);
  elsif v_signup = 'learner' then
    begin
      v_dob := (new.raw_user_meta_data ->> 'date_of_birth')::date;
    exception when others then
      v_dob := null;
    end;
    if v_dob is null or v_dob > (current_date - interval '18 years')::date then
      raise exception 'Learners under 18 join through a parent account'
        using errcode = '23514';
    end if;
    begin
      v_state := (new.raw_user_meta_data ->> 'state')::public.au_state;
    exception when others then
      v_state := null;
    end;
    if v_state is null then
      raise exception 'Please choose your state' using errcode = '23514';
    end if;
    if v_year is null or not private.is_year_level(v_year) then
      raise exception 'Please choose your year level or stage of study' using errcode = '23514';
    end if;
    if v_school is null then
      raise exception 'Please enter your school, university or TAFE' using errcode = '23514';
    end if;
    insert into public.account_roles (account_id, role) values (new.id, 'student');
    insert into public.students (account_id, full_name, date_of_birth, state, year_level, school, created_by)
    values (new.id, left(coalesce(v_name, split_part(v_email, '@', 1)), 200), v_dob, v_state,
            v_year, left(v_school, 200), new.id);
  else
    -- Includes admin invites sent without an invitation record.
    raise exception 'Unknown sign-up type, or no current invitation for this email'
      using errcode = '22023';
  end if;

  -- Record agreement to the privacy policy and terms given on the sign-up form.
  if nullif(new.raw_user_meta_data ->> 'accepted_policies_version', '') is not null then
    insert into public.consent_records (account_id, kind, document_version)
    values
      (new.id, 'privacy_policy', left(new.raw_user_meta_data ->> 'accepted_policies_version', 40)),
      (new.id, 'terms_of_service', left(new.raw_user_meta_data ->> 'accepted_policies_version', 40));
  end if;

  return new;
end;
$$;

