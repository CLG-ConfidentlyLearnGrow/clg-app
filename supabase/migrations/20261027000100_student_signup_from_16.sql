-- Students aged 16 or over can now create their own account (Carla,
-- 2026-10-26). Under-16s still use CLG through a parent's account; the
-- check_student_login_age rule already enforces 16 for any student login.
-- Only the age in the sign-up check changes. Safe to run more than once.

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
