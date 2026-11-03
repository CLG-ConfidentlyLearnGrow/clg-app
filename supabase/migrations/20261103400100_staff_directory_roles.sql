-- Staff directory part 2 (module: staff directory): roles and links.
--
-- Carla (2026-11-03): from the staff directory, add and remove each
-- person's roles, and resend links.
--
-- What this adds:
--   1. staff_directory() now also shows whether each person is a parent or
--      student, and when they last signed in (so admins can see who has
--      never signed in and needs a new link).
--   2. admin_add_role(): give an existing staff member another role.
--        tutor   owner or operations (as for inviting tutors). A tutor who
--                had finished becomes a current tutor again.
--        admin   owner only, at Operations, Support or Finance.
--        parent  owner or operations. Any children they add still need an
--                admin to confirm the link before a tutor is assigned.
--      A student role needs a student record, so it isn't added here (the
--      person uses "Become a learner" on their dashboard).
--   Removing a role uses admin_remove_role() from
--   20261102600400_remove_roles_delete_accounts.sql (owner only, name typed
--   to confirm). Resending links is done by the app with the existing
--   invite-link and password-link functions.
--
-- Safe to run more than once. Run after 20261102300100_staff_directory.sql
-- and 20261102600400_remove_roles_delete_accounts.sql.

-- ---------------------------------------------------------------------------
-- 1. The directory, with every role and the last sign-in
-- ---------------------------------------------------------------------------

-- The columns change, so the old version is removed first.
drop function if exists public.staff_directory();
create function public.staff_directory()
returns table (
  account_id uuid,
  full_name text,
  email text,
  job_title text,
  is_tutor boolean,
  is_admin boolean,
  is_parent boolean,
  is_student boolean,
  admin_level text,
  tutor_active boolean,
  work_state text,
  subjects text[],
  last_sign_in_at timestamptz
)
language sql stable security definer
set search_path = ''
as $$
  select a.id,
         a.full_name,
         p.email,
         j.job_title,
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'tutor'),
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin'),
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'parent'),
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'student'),
         (select ap.level::text from public.admin_profiles ap
          where ap.account_id = a.id
            and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin')),
         t.active,
         w.work_state::text,
         coalesce((select array_agg(tt.subject order by tt.subject)
                   from public.tutor_teaching tt where tt.tutor_id = a.id), '{}'),
         u.last_sign_in_at
  from public.accounts a
  left join auth.users u on u.id = a.id
  left join public.account_private p on p.account_id = a.id
  left join public.staff_job_titles j on j.account_id = a.id
  left join public.tutor_profiles t on t.account_id = a.id
  left join public.tutor_work_settings w on w.tutor_id = a.id
  where private.is_any_admin()
    and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor'))
  order by a.full_name
$$;
revoke execute on function public.staff_directory() from public, anon;
grant execute on function public.staff_directory() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Adding a role
-- ---------------------------------------------------------------------------

create or replace function public.admin_add_role(p_account uuid, p_role public.app_role, p_level text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_level text := coalesce(p_level, 'operations');
begin
  if not private.is_admin() then
    raise exception 'Only the owner or an operations admin can add roles' using errcode = '42501';
  end if;
  if not exists (select 1 from public.accounts where id = p_account) then
    raise exception 'We couldn''t find that account' using errcode = '22023';
  end if;
  if p_role is null or p_role not in ('tutor', 'admin', 'parent') then
    raise exception 'Choose tutor, admin or parent. For a student role, the person uses "Become a learner" on their dashboard' using errcode = '22023';
  end if;
  if p_role = 'admin' and not private.is_owner() then
    raise exception 'Only the owner can add admins' using errcode = '42501';
  end if;
  if p_role = 'admin' and v_level not in ('operations', 'support', 'finance') then
    raise exception 'Choose Operations, Support or Finance' using errcode = '22023';
  end if;
  if exists (select 1 from public.account_roles where account_id = p_account and role = p_role) then
    raise exception 'That person already has this role' using errcode = '23505';
  end if;

  insert into public.account_roles (account_id, role, granted_by)
  values (p_account, p_role, auth.uid());

  if p_role = 'admin' then
    insert into public.admin_profiles (account_id, level)
    values (p_account, v_level::public.admin_level)
    on conflict (account_id) do update set level = excluded.level;
  elsif p_role = 'tutor' then
    insert into public.tutor_profiles (account_id) values (p_account)
    on conflict (account_id) do update set active = true, ended_on = null;
    insert into public.tutor_work_settings (tutor_id) values (p_account)
    on conflict do nothing;
  elsif p_role = 'parent' then
    insert into public.parent_profiles (account_id) values (p_account)
    on conflict do nothing;
  end if;

  perform private.log_event('add_role', 'account_roles', p_account::text,
    jsonb_build_object('role', p_role, 'level', case when p_role = 'admin' then v_level end));
end;
$$;
revoke execute on function public.admin_add_role(uuid, public.app_role, text) from public, anon;
grant execute on function public.admin_add_role(uuid, public.app_role, text) to authenticated;
