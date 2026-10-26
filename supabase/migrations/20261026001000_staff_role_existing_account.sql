-- Adds a staff role to someone who already has a CLG account, for example
-- a parent who also tutors, or the owner who also tutors. Supabase can't send
-- an invitation to an email that already has an account, so this does the
-- same job directly.
-- Same rules as an invitation: any admin may add tutors; only the owner may
-- add admins. The email must already be confirmed by its owner.
-- Returns false when no confirmed account has that email (send an
-- invitation instead).
create function public.grant_staff_role(p_email text, p_role public.app_role)
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_user uuid;
begin
  if not private.is_admin() then
    raise exception 'Only admins can add staff' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('tutor', 'admin') then
    raise exception 'Choose tutor or admin' using errcode = '22023';
  end if;
  if p_role = 'admin' and not private.is_owner() then
    raise exception 'Only the owner can add admins' using errcode = '42501';
  end if;

  select u.id into v_user
  from auth.users u
  where lower(u.email) = v_email and u.email_confirmed_at is not null;
  if v_user is null then
    return false;
  end if;

  if exists (select 1 from public.account_roles where account_id = v_user and role = p_role) then
    raise exception 'That person already has this role' using errcode = '23505';
  end if;

  -- Recorded as an invitation (so it shows in the activity log) and accepted
  -- straight away.
  delete from public.invitations where email = v_email and accepted_at is null;
  insert into public.invitations (email, role, invited_by) values (v_email, p_role, auth.uid());
  perform private.accept_invitation(v_user, v_email);
  return true;
end;
$$;
revoke execute on function public.grant_staff_role(text, public.app_role) from public, anon;
grant execute on function public.grant_staff_role(text, public.app_role) to authenticated;
