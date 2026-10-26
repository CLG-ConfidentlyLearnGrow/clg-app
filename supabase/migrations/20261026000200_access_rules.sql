-- CLG access rules.
--
-- The rule: you see people you are linked to, admins see everyone.
--   * Parents see their own children and those children's current tutors.
--   * Tutors see only students with a current assignment, and only while
--     they hold every check needed for that student's state, verified and
--     in date (see check_requirements).
--   * Admins and tutors must have signed in with two-step login (aal2) for
--     any of their extra access to apply.
--
-- Helper functions live in the private schema, which the public API does
-- not expose. They run as the table owner so they can look across tables
-- without tripping the very rules they are used in.

grant usage on schema private to authenticated, service_role;

-- Invitations may be created by the bootstrap function before any admin
-- exists, and may carry an admin level.
alter table public.invitations alter column invited_by drop not null;
alter table public.invitations add column admin_level public.admin_level not null default 'staff';

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- True when the request comes from the server (service key) or a migration,
-- rather than from a signed-in person.
create function private.is_backend()
returns boolean language sql stable
set search_path = ''
as $$ select auth.uid() is null $$;

create function private.has_aal2()
returns boolean language sql stable
set search_path = ''
as $$ select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' $$;

create function private.has_role(p_role public.app_role)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.account_roles
    where account_id = auth.uid() and role = p_role
  )
$$;

create function private.is_admin()
returns boolean language sql stable security definer
set search_path = ''
as $$ select private.has_role('admin') and private.has_aal2() $$;

create function private.is_owner()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.is_admin() and exists (
    select 1 from public.admin_profiles
    where account_id = auth.uid() and level = 'owner'
  )
$$;

-- A tutor is cleared for a state when active and holding a verified,
-- in-date record of every check that state requires, plus the check for
-- the state the tutor works from. A state with no requirements listed
-- clears nobody, so a missing rule fails safe.
create function private.tutor_cleared_for_state(p_tutor uuid, p_state public.au_state)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.tutor_profiles where account_id = p_tutor and active
    )
    and exists (
      select 1 from public.check_requirements
      where state = p_state and basis = 'student_state'
    )
    and not exists (
      select 1
      from public.check_requirements r
      left join public.tutor_work_settings w on w.tutor_id = p_tutor
      where (
          (r.basis = 'student_state' and r.state = p_state)
          or (r.basis = 'tutor_state' and r.state = w.work_state)
        )
        and not exists (
          select 1 from public.tutor_checks c
          where c.tutor_id = p_tutor
            and c.kind = r.kind
            and c.verified_at is not null
            and c.expires_on >= current_date
        )
    )
$$;

create function private.tutor_cleared_for_student(p_tutor uuid, p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select private.tutor_cleared_for_state(p_tutor, s.state)
    from public.students s where s.id = p_student
  ), false)
$$;

create function private.assignment_is_current(p_starts date, p_ends date)
returns boolean language sql stable
set search_path = ''
as $$ select p_starts <= current_date and (p_ends is null or p_ends >= current_date) $$;

create function private.is_tutor_of(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.has_role('tutor')
    and private.has_aal2()
    and private.tutor_cleared_for_student(auth.uid(), p_student)
    and exists (
      select 1 from public.tutor_assignments
      where tutor_id = auth.uid()
        and student_id = p_student
        and private.assignment_is_current(starts_on, ends_on)
    )
$$;

create function private.is_parent_of(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.parent_student_links
    where parent_id = auth.uid() and student_id = p_student
  )
$$;

create function private.can_manage_student(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.parent_student_links
    where parent_id = auth.uid() and student_id = p_student and can_manage
  )
$$;

create function private.is_student_self(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.students
    where id = p_student and account_id = auth.uid()
  )
$$;

create function private.can_view_student(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.is_admin()
    or private.is_parent_of(p_student)
    or private.is_student_self(p_student)
    or private.is_tutor_of(p_student)
$$;

-- Whose name and public profile may the current person see?
create function private.can_see_account(p_account uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select p_account = auth.uid()
    or private.is_admin()
    -- Admin names are visible to everyone signed in, so families know who
    -- they are talking to.
    or exists (
      select 1 from public.account_roles where account_id = p_account and role = 'admin'
    )
    -- A student's own login, seen by anyone who can see that student.
    or exists (
      select 1 from public.students s
      where s.account_id = p_account and private.can_view_student(s.id)
    )
    -- A tutor sees the parents of students they currently teach.
    or exists (
      select 1 from public.parent_student_links l
      where l.parent_id = p_account and private.is_tutor_of(l.student_id)
    )
    -- Families see the cleared tutors currently assigned to their children.
    or exists (
      select 1 from public.tutor_assignments a
      where a.tutor_id = p_account
        and private.assignment_is_current(a.starts_on, a.ends_on)
        and private.tutor_cleared_for_student(a.tutor_id, a.student_id)
        and (private.is_parent_of(a.student_id) or private.is_student_self(a.student_id))
    )
$$;

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

-- Records who changed what. Only ids and the names of changed columns are
-- stored, never the content, so the log itself holds no sensitive details.
create function private.audit_change()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_keys jsonb;
  v_changed text[];
begin
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into v_keys
  from jsonb_each(v_row)
  where key in ('id', 'role', 'kind', 'status', 'level')
     or key like '%\_id' escape '\';

  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into v_changed
    from jsonb_each(v_new)
    where value is distinct from v_old -> key;
  end if;

  insert into public.audit_log (actor_id, action, table_name, record_id, details)
  values (
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'student_id', v_row ->> 'account_id'),
    v_keys || jsonb_build_object('changed_columns', to_jsonb(coalesce(v_changed, '{}')))
  );
  return coalesce(new, old);
end;
$$;

create function private.log_event(p_action text, p_table text, p_record text, p_details jsonb default '{}')
returns void language sql security definer
set search_path = ''
as $$
  insert into public.audit_log (actor_id, action, table_name, record_id, details)
  values (auth.uid(), p_action, p_table, p_record, coalesce(p_details, '{}'))
$$;
revoke execute on function private.log_event(text, text, text, jsonb) from public;

create trigger audit after insert or update or delete on public.account_roles
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.admin_profiles
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.invitations
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.tutor_checks
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.check_requirements
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.tutor_work_settings
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.tutor_profiles
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.students
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.student_sensitive
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.parent_student_links
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.tutor_assignments
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.enrolments
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.consent_records
  for each row execute function private.audit_change();

-- ---------------------------------------------------------------------------
-- Guard triggers
-- ---------------------------------------------------------------------------

create function private.touch_updated_at()
returns trigger language plpgsql
set search_path = ''
as $$ begin new.updated_at := now(); return new; end; $$;

create trigger touch before update on public.accounts
  for each row execute function private.touch_updated_at();
create trigger touch before update on public.account_private
  for each row execute function private.touch_updated_at();
create trigger touch before update on public.students
  for each row execute function private.touch_updated_at();
create trigger touch before update on public.student_sensitive
  for each row execute function private.touch_updated_at();

-- Tutors may edit their bio and subjects, not whether they are active.
create function private.guard_tutor_profile()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.active is distinct from old.active
     and not (private.is_backend() or private.is_admin()) then
    raise exception 'Only an admin can change whether a tutor is active'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard before update on public.tutor_profiles
  for each row execute function private.guard_tutor_profile();

-- The state a tutor works from changes which checks they need, so only an
-- admin sets it.
create function private.guard_work_settings()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.work_state is distinct from old.work_state
     and not (private.is_backend() or private.is_admin()) then
    raise exception 'Only an admin can change the state a tutor works from'
      using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger guard before update on public.tutor_work_settings
  for each row execute function private.guard_work_settings();

-- Parents may edit their child's school, year level and goals. Which family
-- or login the record belongs to, the date of birth and the state (which
-- decide age and child safety rules) are changed by an admin.
create function private.guard_student()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if not (private.is_backend() or private.is_admin()) and (
       new.account_id is distinct from old.account_id
    or new.date_of_birth is distinct from old.date_of_birth
    or new.state is distinct from old.state
    or new.family_id is distinct from old.family_id
    or new.created_by is distinct from old.created_by
    or new.last_activity_at is distinct from old.last_activity_at
  ) then
    raise exception 'Only an admin can change this part of a student record'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard before update on public.students
  for each row execute function private.guard_student();

-- Only students aged 16 or over may have their own login. OAIC guidance
-- presumes under-15s can't make their own privacy decisions; CLG uses 16 to
-- also meet the highest EU age of digital consent.
create function private.check_student_login_age()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.account_id is not null
     and new.date_of_birth > (current_date - interval '16 years')::date then
    raise exception 'Students under 16 use the app through a parent account'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger check_login_age before insert or update on public.students
  for each row execute function private.check_student_login_age();

-- Admin entry of a check counts as verification against the screening
-- record, so stamp who did it. A police check counts for 5 years from the
-- date it was issued, so its expiry is worked out here.
create function private.stamp_tutor_check()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.kind = 'police_check' then
    if new.completed_on is null or new.completed_on > current_date then
      raise exception 'Enter the date the police check was issued' using errcode = '23514';
    end if;
    new.expires_on := new.completed_on + interval '5 years';
  end if;
  if tg_op = 'INSERT'
     or new.reference is distinct from old.reference
     or new.expires_on is distinct from old.expires_on
     or new.completed_on is distinct from old.completed_on
     or new.kind is distinct from old.kind then
    new.verified_by := auth.uid();
    new.verified_at := now();
  end if;
  return new;
end;
$$;
create trigger stamp before insert or update on public.tutor_checks
  for each row execute function private.stamp_tutor_check();

create function private.stamp_link_verification()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.verified_at is not null
     and (tg_op = 'INSERT' or old.verified_at is null) then
    new.verified_by := auth.uid();
  elsif new.verified_at is null then
    new.verified_by := null;
  end if;
  return new;
end;
$$;
create trigger stamp before insert or update on public.parent_student_links
  for each row execute function private.stamp_link_verification();

-- A tutor can only be assigned while cleared, and only to a student who is
-- an adult or whose parent link an admin has verified.
create function private.check_assignment()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_dob date;
begin
  if new.ends_on is not null and new.ends_on < current_date then
    return new; -- recording a past assignment
  end if;

  if not private.tutor_cleared_for_student(new.tutor_id, new.student_id) then
    raise exception 'This tutor does not hold every verified, in-date check needed for this student''s state'
      using errcode = '23514';
  end if;

  select date_of_birth into v_dob from public.students where id = new.student_id;
  if v_dob > (current_date - interval '18 years')::date and not exists (
    select 1 from public.parent_student_links
    where student_id = new.student_id and verified_at is not null
  ) then
    raise exception 'A parent link must be verified by an admin before a tutor is assigned to a child'
      using errcode = '23514';
  end if;

  return new;
end;
$$;
create trigger check_assignment before insert or update on public.tutor_assignments
  for each row execute function private.check_assignment();

-- ---------------------------------------------------------------------------
-- New users
-- ---------------------------------------------------------------------------

-- Tutor and admin roles come only from an invitation an admin recorded, and
-- are granted only once the invited email address is confirmed (by
-- accepting the invite link, or confirming a sign-up). That proves the person
-- controls the invited inbox. Nothing typed at sign-up can grant them.
create function private.accept_invitation(p_user uuid, p_email text)
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_inv public.invitations;
begin
  select * into v_inv from public.invitations
  where email = lower(trim(p_email)) and accepted_at is null and expires_at > now()
  limit 1;
  if v_inv.id is null then
    return false;
  end if;

  insert into public.account_roles (account_id, role, granted_by)
  values (p_user, v_inv.role, v_inv.invited_by)
  on conflict do nothing;
  if v_inv.role = 'admin' then
    insert into public.admin_profiles (account_id, level) values (p_user, v_inv.admin_level)
    on conflict do nothing;
  else
    insert into public.tutor_profiles (account_id) values (p_user)
    on conflict do nothing;
    insert into public.tutor_work_settings (tutor_id) values (p_user)
    on conflict do nothing;
  end if;
  update public.invitations set accepted_at = now() where id = v_inv.id;
  return true;
end;
$$;
revoke execute on function private.accept_invitation(uuid, text) from public;

-- Runs when Supabase Auth creates a user.
--   * Invited email: account only; the role arrives on email confirmation.
--   * Self sign-up: becomes a parent, or an adult learner (18+).
create function private.handle_new_user()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(new.email));
  v_name text := nullif(trim(new.raw_user_meta_data ->> 'full_name'), '');
  v_signup text := new.raw_user_meta_data ->> 'signup_as';
  v_dob date;
  v_state public.au_state;
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
    insert into public.account_roles (account_id, role) values (new.id, 'student');
    insert into public.students (account_id, full_name, date_of_birth, state, created_by)
    values (new.id, left(coalesce(v_name, split_part(v_email, '@', 1)), 200), v_dob, v_state, new.id);
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

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- First email confirmation: hand over any invitation for that address.
create function private.handle_email_confirmed()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  perform private.accept_invitation(new.id, new.email);
  return new;
end;
$$;
create trigger on_auth_user_confirmed after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
  execute function private.handle_email_confirmed();

-- Keep the stored email in step with Supabase Auth.
create function private.sync_user_email()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  update public.account_private set email = lower(trim(new.email))
  where account_id = new.id;
  return new;
end;
$$;
create trigger on_auth_user_email_changed after update of email on auth.users
  for each row execute function private.sync_user_email();

-- One-off setup: invite CLG's owner. Run from the Supabase SQL editor, then
-- send the invite from Authentication > Users > Invite user.
create function private.create_owner_invitation(p_email text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if exists (select 1 from public.admin_profiles where level = 'owner') then
    raise exception 'An owner already exists';
  end if;
  insert into public.invitations (email, role, admin_level)
  values (lower(trim(p_email)), 'admin', 'owner')
  returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function private.create_owner_invitation(text) from public;

-- ---------------------------------------------------------------------------
-- Row level security policies
-- ---------------------------------------------------------------------------

-- accounts: names only
create policy "see linked people" on public.accounts
  for select to authenticated using (private.can_see_account(id));
create policy "edit own name, admins edit any" on public.accounts
  for update to authenticated
  using (id = auth.uid() or private.is_admin())
  with check (id = auth.uid() or private.is_admin());

-- account_private: contact details
create policy "own contact details, admins see all" on public.account_private
  for select to authenticated using (account_id = auth.uid() or private.is_admin());
create policy "edit own contact details" on public.account_private
  for update to authenticated
  using (account_id = auth.uid() or private.is_admin())
  with check (account_id = auth.uid() or private.is_admin());
-- Email is managed by Supabase Auth, not edited here.
revoke update on public.account_private from authenticated;
grant update (phone) on public.account_private to authenticated;

-- account_roles
create policy "see own roles, admins see all" on public.account_roles
  for select to authenticated using (account_id = auth.uid() or private.is_admin());
create policy "admins grant roles" on public.account_roles
  for insert to authenticated
  with check (private.is_admin() and (role <> 'admin' or private.is_owner()));
create policy "admins remove roles" on public.account_roles
  for delete to authenticated
  using (
    private.is_admin()
    and account_id <> auth.uid()
    and (role <> 'admin' or private.is_owner())
  );

-- invitations
create policy "admins see invitations" on public.invitations
  for select to authenticated using (private.is_admin());
create policy "admins invite tutors, owners invite admins" on public.invitations
  for insert to authenticated
  with check (
    private.is_admin()
    and invited_by = auth.uid()
    and accepted_at is null
    and (role = 'tutor' or private.is_owner())
    and (admin_level = 'staff' or private.is_owner())
  );
create policy "admins cancel invitations" on public.invitations
  for delete to authenticated using (private.is_admin() and accepted_at is null);

-- admin_profiles
create policy "admins see admins" on public.admin_profiles
  for select to authenticated using (account_id = auth.uid() or private.is_admin());
create policy "owners manage admins" on public.admin_profiles
  for all to authenticated
  using (private.is_owner()) with check (private.is_owner());

-- tutor_profiles
create policy "see tutors you are linked to" on public.tutor_profiles
  for select to authenticated using (private.can_see_account(account_id));
create policy "tutors edit own profile, admins edit any" on public.tutor_profiles
  for update to authenticated
  using (account_id = auth.uid() or private.is_admin())
  with check (account_id = auth.uid() or private.is_admin());
create policy "admins create tutor profiles" on public.tutor_profiles
  for insert to authenticated with check (private.is_admin());

-- tutor_checks
create policy "tutors see own checks, admins see all" on public.tutor_checks
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin());
create policy "admins record checks" on public.tutor_checks
  for insert to authenticated with check (private.is_admin());
create policy "admins update checks" on public.tutor_checks
  for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy "admins delete checks" on public.tutor_checks
  for delete to authenticated using (private.is_admin());

-- check_requirements: everyone signed in can read the rules; admins change them
create policy "anyone signed in reads check rules" on public.check_requirements
  for select to authenticated using (true);
create policy "admins manage check rules" on public.check_requirements
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- tutor_work_settings: the tutor sets their hours; only admins set work state
create policy "tutors see own settings, admins see all" on public.tutor_work_settings
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin());
create policy "tutors edit own settings, admins edit any" on public.tutor_work_settings
  for update to authenticated
  using (tutor_id = auth.uid() or private.is_admin())
  with check (tutor_id = auth.uid() or private.is_admin());
create policy "admins create work settings" on public.tutor_work_settings
  for insert to authenticated with check (private.is_admin());

-- tutor_availability: the tutor manages their own slots
create policy "tutors see own availability, admins see all" on public.tutor_availability
  for select to authenticated using (tutor_id = auth.uid() or private.is_admin());
create policy "tutors manage own availability" on public.tutor_availability
  for all to authenticated
  using (tutor_id = auth.uid() or private.is_admin())
  with check (
    (tutor_id = auth.uid() and private.has_role('tutor')) or private.is_admin()
  );

-- parent_profiles
create policy "own parent profile, admins see all" on public.parent_profiles
  for select to authenticated using (account_id = auth.uid() or private.is_admin());
create policy "edit own parent profile" on public.parent_profiles
  for update to authenticated
  using (account_id = auth.uid() or private.is_admin())
  with check (account_id = auth.uid() or private.is_admin());
revoke update on public.parent_profiles from authenticated;
grant update (emergency_contact_name, emergency_contact_phone) on public.parent_profiles to authenticated;

-- families
create policy "see own family" on public.families
  for select to authenticated using (
    private.is_admin() or exists (
      select 1 from public.students s
      where s.family_id = families.id
        and (private.is_parent_of(s.id) or private.is_student_self(s.id))
    )
  );
create policy "admins manage families" on public.families
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- students
create policy "see linked students" on public.students
  for select to authenticated using (private.can_view_student(id));
create policy "admins and managing parents edit students" on public.students
  for update to authenticated
  using (private.is_admin() or private.can_manage_student(id))
  with check (private.is_admin() or private.can_manage_student(id));
create policy "admins create students" on public.students
  for insert to authenticated with check (private.is_admin());
create policy "admins delete students" on public.students
  for delete to authenticated using (private.is_admin());

-- student_sensitive: no direct access. Use read_student_sensitive() and
-- save_student_sensitive(), which check access and log every use.
revoke all on public.student_sensitive from authenticated;

-- parent_student_links
create policy "see relevant parent links" on public.parent_student_links
  for select to authenticated using (
    private.is_admin()
    or parent_id = auth.uid()
    or private.is_tutor_of(student_id)
    or private.is_student_self(student_id)
  );
create policy "admins manage parent links" on public.parent_student_links
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- tutor_assignments
create policy "see relevant assignments" on public.tutor_assignments
  for select to authenticated using (
    private.is_admin()
    or tutor_id = auth.uid()
    or private.is_parent_of(student_id)
    or private.is_student_self(student_id)
  );
create policy "admins manage assignments" on public.tutor_assignments
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- programs
create policy "anyone signed in sees active programs" on public.programs
  for select to authenticated using (active or private.is_admin());
create policy "admins manage programs" on public.programs
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- enrolments
create policy "see own enrolments" on public.enrolments
  for select to authenticated using (
    private.is_admin()
    or private.is_parent_of(student_id)
    or private.is_student_self(student_id)
  );
create policy "admins manage enrolments" on public.enrolments
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- consent_records: insert-only for the person giving consent
create policy "see own consent, admins see all" on public.consent_records
  for select to authenticated using (account_id = auth.uid() or private.is_admin());
create policy "record own consent" on public.consent_records
  for insert to authenticated with check (
    account_id = auth.uid()
    and withdrawn_at is null
    and (student_id is null or private.can_manage_student(student_id))
  );
revoke update, delete on public.consent_records from authenticated;

-- audit_log: admins read, nobody edits
create policy "admins read audit log" on public.audit_log
  for select to authenticated using (private.is_admin());
revoke insert, update, delete, truncate on public.audit_log from authenticated, service_role;

-- Each tutor's latest verified record of each check they hold, with its
-- status, plus any check their work state needs that is missing. Respects
-- the rules above (admins see all, tutors see their own).
create view public.tutor_check_status
with (security_invoker = true) as
with needed as (
  select c.tutor_id, c.kind
  from public.tutor_checks c
  where c.verified_at is not null
  union
  select w.tutor_id, r.kind
  from public.tutor_work_settings w
  join public.check_requirements r on r.state = w.work_state and r.basis = 'tutor_state'
  union
  -- Every active tutor needs a police check.
  select t.account_id, 'police_check'::public.tutor_check_kind
  from public.tutor_profiles t
  where t.active
)
select
  n.tutor_id,
  a.full_name,
  n.kind,
  c.reference,
  c.expires_on,
  case
    when c.expires_on is null then 'missing'
    when c.expires_on < current_date then 'expired'
    when c.expires_on < current_date + 60 then 'expiring_soon'
    else 'current'
  end as status
from needed n
join public.accounts a on a.id = n.tutor_id
left join lateral (
  select reference, expires_on from public.tutor_checks
  where tutor_id = n.tutor_id and kind = n.kind and verified_at is not null
  order by expires_on desc limit 1
) c on true;

-- The states each tutor is currently cleared to teach students in.
create view public.tutor_cleared_states
with (security_invoker = true) as
select t.account_id as tutor_id, a.full_name, st.state
from public.tutor_profiles t
join public.accounts a on a.id = t.account_id
cross join unnest(enum_range(null::public.au_state)) as st(state)
where private.tutor_cleared_for_state(t.account_id, st.state);
revoke all on public.tutor_cleared_states from anon;

revoke all on public.tutor_check_status from anon;

-- ---------------------------------------------------------------------------
-- Functions the app calls
-- ---------------------------------------------------------------------------

-- A parent adds their child. Creates the family on first use. The link
-- starts unverified; an admin verifies it before any tutor is assigned.
create function public.add_my_child(
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

  if p_state is null then
    raise exception 'Please choose a state' using errcode = '22023';
  end if;

  insert into public.students (family_id, full_name, date_of_birth, state, year_level, school, created_by)
  values (v_family, trim(p_full_name), p_date_of_birth, p_state, nullif(trim(p_year_level), ''), nullif(trim(p_school), ''), auth.uid())
  returning id into v_student;

  insert into public.parent_student_links (parent_id, student_id)
  values (auth.uid(), v_student);

  return v_student;
end;
$$;

create function public.read_student_sensitive(p_student uuid)
returns table (learning_needs text, support_strategies text, updated_at timestamptz)
language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.can_view_student(p_student) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  perform private.log_event('view', 'student_sensitive', p_student::text);
  return query
    select s.learning_needs, s.support_strategies, s.updated_at
    from public.student_sensitive s where s.student_id = p_student;
end;
$$;

create function public.save_student_sensitive(
  p_student uuid,
  p_learning_needs text,
  p_support_strategies text
)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not (private.is_admin() or private.can_manage_student(p_student) or private.is_tutor_of(p_student)) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  insert into public.student_sensitive (student_id, learning_needs, support_strategies, updated_by)
  values (p_student, p_learning_needs, p_support_strategies, auth.uid())
  on conflict (student_id) do update
    set learning_needs = excluded.learning_needs,
        support_strategies = excluded.support_strategies,
        updated_by = excluded.updated_by;
end;
$$;

create function public.withdraw_consent(p_consent uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  update public.consent_records
  set withdrawn_at = now()
  where id = p_consent and account_id = auth.uid() and withdrawn_at is null;
  if not found then
    raise exception 'Consent record not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Tutors cleared to teach a given student, with their weekly hour limit.
-- Being listed is not a promise of work: matching also weighs availability,
-- subjects and fit.
create function public.eligible_tutors(p_student uuid)
returns table (tutor_id uuid, full_name text, subjects text[], max_weekly_hours numeric)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select t.account_id, a.full_name, t.subjects, w.max_weekly_hours
    from public.tutor_profiles t
    join public.accounts a on a.id = t.account_id
    left join public.tutor_work_settings w on w.tutor_id = t.account_id
    where private.tutor_cleared_for_student(t.account_id, p_student)
    order by a.full_name;
end;
$$;
revoke execute on function public.eligible_tutors(uuid) from public, anon;
grant execute on function public.eligible_tutors(uuid) to authenticated;

-- The signed-in person's own roles, used by the app to pick their home screen.
create function public.my_roles()
returns setof public.app_role language sql stable security definer
set search_path = ''
as $$ select role from public.account_roles where account_id = auth.uid() $$;

revoke execute on function public.add_my_child(text, date, public.au_state, text, text) from public, anon;
revoke execute on function public.read_student_sensitive(uuid) from public, anon;
revoke execute on function public.save_student_sensitive(uuid, text, text) from public, anon;
revoke execute on function public.withdraw_consent(uuid) from public, anon;
revoke execute on function public.my_roles() from public, anon;
grant execute on function public.add_my_child(text, date, public.au_state, text, text) to authenticated;
grant execute on function public.read_student_sensitive(uuid) to authenticated;
grant execute on function public.save_student_sensitive(uuid, text, text) to authenticated;
grant execute on function public.withdraw_consent(uuid) to authenticated;
grant execute on function public.my_roles() to authenticated;
