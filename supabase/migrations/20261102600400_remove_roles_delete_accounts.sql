-- Removing a role from an account, and deleting an account (Carla, 2 Nov
-- 2026). Owner only, with the person's name typed to confirm.
--
-- Removing a role keeps the records under the usual keeping rules (the
-- "timebomb"), so nothing is lost early:
--   student  The login no longer opens the student record. The record is
--            kept and deleted 2 years after the student's last activity.
--   tutor    Tutor access ends today: they're marked as finished, open
--            assignments end, and records are deleted 7 years later.
--            Refused while they still have sessions booked.
--   parent   They no longer see their children. Children with no other
--            parent are kept under the student rule.
--   admin    Admin access ends. The owner can't remove their own admin
--            role, or another owner's.
-- An account with no roles left is deleted after 12 months unused.
--
-- Deleting an account is for test accounts and on-request deletions.
-- Billing records that must be kept stop the deletion, with a plain message.
-- See docs/features/remove-roles-delete-accounts.md. Safe to run more than once.

create or replace function public.admin_remove_role(p_account uuid, p_role public.app_role, p_confirm_name text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  if not private.is_owner() then
    raise exception 'Only the owner can remove a role' using errcode = '42501';
  end if;
  select full_name into v_name from public.accounts where id = p_account;
  if v_name is null then
    raise exception 'We couldn''t find that account' using errcode = '22023';
  end if;
  if trim(p_confirm_name) is distinct from v_name then
    raise exception 'The name typed doesn''t match the account' using errcode = '22023';
  end if;
  if not exists (select 1 from public.account_roles where account_id = p_account and role = p_role) then
    raise exception 'This account doesn''t have that role' using errcode = '22023';
  end if;

  if p_role = 'admin' then
    if p_account = auth.uid() then
      raise exception 'You can''t remove your own admin role' using errcode = '22023';
    end if;
    if exists (select 1 from public.admin_profiles where account_id = p_account and level::text = 'owner') then
      raise exception 'An owner''s admin role can''t be removed here' using errcode = '22023';
    end if;
    delete from public.admin_profiles where account_id = p_account;

  elsif p_role = 'tutor' then
    if exists (
      select 1 from public.bookings
      where tutor_id = p_account and status in ('requested', 'confirmed') and last_date >= current_date
    ) then
      raise exception 'This tutor still has sessions booked. Move or cancel them in Sessions first' using errcode = '23514';
    end if;
    update public.tutor_profiles
    set active = false, ended_on = coalesce(ended_on, current_date)
    where account_id = p_account;
    update public.tutor_assignments
    set ends_on = greatest(starts_on, current_date)
    where tutor_id = p_account and (ends_on is null or ends_on > current_date);

  elsif p_role = 'parent' then
    delete from public.parent_student_links where parent_id = p_account;

  elsif p_role = 'student' then
    update public.students set account_id = null where account_id = p_account;
  end if;

  delete from public.account_roles where account_id = p_account and role = p_role;
  perform private.log_event('remove_role', 'account_roles', p_account::text, jsonb_build_object('role', p_role));
end;
$$;
revoke all on function public.admin_remove_role(uuid, public.app_role, text) from public, anon;
grant execute on function public.admin_remove_role(uuid, public.app_role, text) to authenticated;

create or replace function public.admin_delete_account(p_account uuid, p_confirm_name text, p_with_students boolean default false)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_name text;
  v_student uuid;
begin
  if not private.is_owner() then
    raise exception 'Only the owner can delete an account' using errcode = '42501';
  end if;
  select full_name into v_name from public.accounts where id = p_account;
  if v_name is null then
    raise exception 'We couldn''t find that account' using errcode = '22023';
  end if;
  if trim(p_confirm_name) is distinct from v_name then
    raise exception 'The name typed doesn''t match the account' using errcode = '22023';
  end if;
  if p_account = auth.uid() then
    raise exception 'You can''t delete your own account' using errcode = '22023';
  end if;
  if exists (select 1 from public.admin_profiles where account_id = p_account and level::text = 'owner') then
    raise exception 'An owner''s account can''t be deleted here' using errcode = '22023';
  end if;
  if private.has_hold(null, p_account) then
    raise exception 'This account has a hold on its records, so it can''t be deleted yet' using errcode = '23514';
  end if;

  if p_with_students then
    -- Their own student record, and children who have no other parent.
    for v_student in
      select s.id from public.students s where s.account_id = p_account
      union
      select l.student_id from public.parent_student_links l
      where l.parent_id = p_account
        and not exists (select 1 from public.parent_student_links o
                        where o.student_id = l.student_id and o.parent_id <> p_account)
    loop
      if private.has_hold(v_student, null) then
        raise exception 'One of their students has a hold on their records, so it can''t be deleted yet' using errcode = '23514';
      end if;
      perform private.delete_student(v_student);
    end loop;
  end if;

  perform private.log_event('delete_account', 'accounts', p_account::text,
    jsonb_build_object('with_students', p_with_students));
  begin
    delete from auth.users where id = p_account;
  exception when foreign_key_violation then
    raise exception 'This account has billing or session records CLG must keep, so it can''t be deleted. Remove its roles instead'
      using errcode = '23514';
  end;
end;
$$;
revoke all on function public.admin_delete_account(uuid, text, boolean) from public, anon;
grant execute on function public.admin_delete_account(uuid, text, boolean) to authenticated;
