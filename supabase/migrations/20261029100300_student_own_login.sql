-- Giving a student on a parent's account their own login (Carla,
-- 2026-10-28). Students 16 or over may stay on a parent's account; when
-- they're ready, an admin enters the student's own email and the student
-- gets a link to choose a password. The student keeps their record, history
-- and tutor, and the parent keeps seeing it. See docs/features/student-own-login.md.
-- Safe to run more than once.

-- An admin's offer of a login for one student, sent to one email address.
create table if not exists public.student_login_offers (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  email text not null check (email = lower(email) and char_length(email) <= 320),
  offered_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  accepted_by uuid references public.accounts (id) on delete set null
);
create index if not exists student_login_offers_email on public.student_login_offers (email)
  where accepted_at is null;
alter table public.student_login_offers enable row level security;

drop policy if exists "admins see login offers" on public.student_login_offers;
create policy "admins see login offers" on public.student_login_offers
  for select to authenticated using (private.is_admin());
-- Offers are made only through admin_offer_student_login below.

drop trigger if exists audit on public.student_login_offers;
create trigger audit after insert or update or delete on public.student_login_offers
  for each row execute function private.audit_change();

-- Hands the student record over to the new login. Runs only once the email
-- is confirmed, which proves the student controls that inbox.
create or replace function private.accept_student_login(p_user uuid, p_email text)
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_offer public.student_login_offers;
begin
  select * into v_offer from public.student_login_offers
  where email = lower(trim(p_email)) and accepted_at is null and expires_at > now()
  order by created_at desc
  limit 1;
  if v_offer.id is null then
    return false;
  end if;

  -- check_login_age still refuses anyone under 16.
  update public.students set account_id = p_user
  where id = v_offer.student_id and account_id is null;
  if not found then
    return false;
  end if;
  insert into public.account_roles (account_id, role, granted_by)
  values (p_user, 'student', v_offer.offered_by)
  on conflict do nothing;
  update public.accounts a set full_name = s.full_name
  from public.students s
  where a.id = p_user and s.id = v_offer.student_id;
  update public.student_login_offers
  set accepted_at = now(), accepted_by = p_user
  where id = v_offer.id;
  return true;
end;
$$;
revoke execute on function private.accept_student_login(uuid, text) from public;

-- An admin offers a student their own login. The app then makes the account
-- and sends the link.
create or replace function public.admin_offer_student_login(p_student uuid, p_email text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_student public.students;
  v_id uuid;
begin
  if not private.is_admin() then
    raise exception 'Only admins can give a student their own login' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 320 then
    raise exception 'Please check the email address' using errcode = '22023';
  end if;
  select * into v_student from public.students where id = p_student;
  if v_student.id is null then
    raise exception 'We couldn''t find that student' using errcode = '22023';
  end if;
  if v_student.account_id is not null then
    raise exception 'This student already has their own login' using errcode = '22023';
  end if;
  if v_student.date_of_birth is null then
    raise exception 'Please add the student''s date of birth first' using errcode = '22023';
  end if;
  if v_student.date_of_birth > (current_date - interval '16 years')::date then
    raise exception 'Students under 16 use CLG through a parent''s account' using errcode = '22023';
  end if;
  if exists (select 1 from public.account_private where email = v_email)
     or exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'That email already has a CLG account. Please use the student''s own email' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.invitations
    where email = v_email and accepted_at is null and expires_at > now()
  ) then
    raise exception 'That email has a staff invitation waiting. Please use a different email' using errcode = '22023';
  end if;

  -- A new offer replaces any earlier one for the same student or email.
  delete from public.student_login_offers
  where accepted_at is null and (student_id = p_student or email = v_email);
  insert into public.student_login_offers (student_id, email, offered_by)
  values (p_student, v_email, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_offer_student_login(uuid, text) from public, anon;
grant execute on function public.admin_offer_student_login(uuid, text) to authenticated;

-- First email confirmation also hands over an offered student login.
create or replace function private.handle_email_confirmed()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.accept_invitation(new.id, new.email) then
    perform private.accept_student_login(new.id, new.email);
  end if;
  return new;
end;
$$;

-- Sign-ups: same as before, plus the offered student login.
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

  -- CLG has offered a student on a parent's account their own login: make
  -- the account only. The student record is handed over when the email is
  -- confirmed (see accept_student_login).
  if exists (
    select 1 from public.student_login_offers
    where email = v_email and accepted_at is null and expires_at > now()
  ) then
    if new.email_confirmed_at is not null then
      perform private.accept_student_login(new.id, v_email);
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
    if v_dob is null or v_dob > (current_date - interval '16 years')::date then
      raise exception 'Students under 16 join through a parent account'
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
