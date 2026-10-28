-- Sending a new login link when the first one ran out (Carla, 2026-10-28).
-- An admin can offer a student their own login again, using the same email,
-- when the account made for the first offer was never used.
-- See docs/features/family-setup.md. Safe to run more than once.

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
  -- An account made for an earlier offer that was never used (email not
  -- confirmed, no roles) can be offered again with a fresh link.
  if exists (
    select 1 from auth.users u
    where lower(u.email) = v_email
      and (u.email_confirmed_at is not null
           or exists (select 1 from public.account_roles r where r.account_id = u.id))
  ) then
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
