-- Admins can set up a family's account for them (for example after a phone
-- call, or for families already with CLG): the parent's account is made
-- from the app, and the admin adds each child with their subjects, goal and
-- other information. The family then gets a link to choose a password and
-- agrees to the privacy policy and terms when they first sign in.
-- See docs/features/family-setup.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Adding a child, shared by parents (add_my_child) and admins
-- (admin_add_child). Checks the details and creates the student, the link to
-- the parent and the subjects.
-- ---------------------------------------------------------------------------
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
  p_extra_info text
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
  if p_date_of_birth is null or p_date_of_birth > current_date
     or p_date_of_birth < (current_date - interval '25 years')::date then
    raise exception 'Please check the date of birth' using errcode = '22023';
  end if;
  if p_state is null then
    raise exception 'Please choose a state' using errcode = '22023';
  end if;
  if not coalesce(private.is_year_level(trim(p_year_level)), false) then
    raise exception 'Please choose the child''s year level' using errcode = '22023';
  end if;
  if nullif(trim(p_school), '') is null then
    raise exception 'Please enter the child''s school' using errcode = '22023';
  end if;
  if p_subjects is null or jsonb_typeof(p_subjects) <> 'array' or jsonb_array_length(p_subjects) = 0 then
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
    v_family, trim(p_full_name), p_date_of_birth, p_state, trim(p_year_level), left(trim(p_school), 200),
    nullif(left(trim(p_goals), 4000), ''), nullif(left(trim(p_extra_info), 2000), ''), auth.uid()
  )
  returning id into v_student;

  -- A link made by an admin is already checked.
  insert into public.parent_student_links (parent_id, student_id, verified_by, verified_at)
  values (p_parent, v_student, p_verified_by, case when p_verified_by is null then null else now() end);

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
revoke all on function private.add_child_for(uuid, uuid, text, date, public.au_state, text, text, jsonb, text, text) from public, anon, authenticated;

-- Parents adding their own child: unchanged behaviour.
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
begin
  if not private.has_role('parent') then
    raise exception 'Only parents can add a child' using errcode = '42501';
  end if;
  return private.add_child_for(auth.uid(), null, p_full_name, p_date_of_birth, p_state,
    p_year_level, p_school, p_subjects, p_goals, p_extra_info);
end;
$$;
revoke all on function public.add_my_child(text, date, public.au_state, text, text, jsonb, text, text) from public, anon;
grant execute on function public.add_my_child(text, date, public.au_state, text, text, jsonb, text, text) to authenticated;

-- Admins adding a child to a parent's account.
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
    p_year_level, p_school, p_subjects, p_goals, p_extra_info);
end;
$$;
revoke all on function public.admin_add_child(uuid, text, date, public.au_state, text, text, jsonb, text, text) from public, anon;
grant execute on function public.admin_add_child(uuid, text, date, public.au_state, text, text, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admins finding an account by email, to add a child to an existing parent
-- instead of making a second account.
-- ---------------------------------------------------------------------------
create or replace function public.admin_find_account(p_email text)
returns table (account_id uuid, full_name text, is_parent boolean, is_student boolean)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can look up accounts' using errcode = '42501';
  end if;
  return query
    select a.id, a.full_name,
           exists (select 1 from public.parent_profiles pp where pp.account_id = a.id),
           exists (select 1 from public.students s where s.account_id = a.id)
    from public.account_private ap
    join public.accounts a on a.id = ap.account_id
    where ap.email = lower(trim(p_email));
end;
$$;
revoke all on function public.admin_find_account(text) from public, anon;
grant execute on function public.admin_find_account(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Has this person agreed to the current privacy policy and terms? Families
-- set up by CLG agree when they first sign in.
-- ---------------------------------------------------------------------------
create or replace function public.my_policy_consent(p_version text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select count(distinct kind) = 2 from public.consent_records
  where account_id = auth.uid() and student_id is null and withdrawn_at is null
    and document_version = p_version
    and kind in ('privacy_policy', 'terms_of_service')
$$;
revoke all on function public.my_policy_consent(text) from public, anon;
grant execute on function public.my_policy_consent(text) to authenticated;
