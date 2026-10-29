-- Admin levels, part 2 of 2: who can do what.
--
-- Run 20261029900100_admin_levels_names.sql first.
--
--   owner       Everything. The only level that adds or removes admins,
--               changes admin levels, prices, pay rates, billing rules and
--               how long records are kept, and erases records.
--   operations  Day-to-day running: families, matching, bookings, tutor
--               checks, progress, curriculum, invoices. Can see tutor pay
--               but not change it. (This is what "staff admin" was.)
--   support     Office help: family contact details, setting up families,
--               login links, bookings and sessions, whether a family is
--               paused. No progress notes, tutor checks or money.
--   finance     Bookkeeper: invoices, payments, credits, tutor pay and pay
--               rates. Sees names on invoices; no learning records, child
--               details or tutor checks.
--
-- How it works:
--   * private.is_admin() now means owner or operations. Every rule written
--     before today used it, so operations keeps exactly what staff admins
--     had, and the two new levels start with nothing.
--   * Support and finance are then given only what they need, below.
--   * Emergency owner access: an operations admin can ask for owner powers
--     if the owner is unreachable. They must write a reason. Access starts
--     48 hours later unless the owner cancels, lasts 7 days, then ends by
--     itself. The owner's own admin access can never be changed or removed
--     by anyone else, including someone using emergency access.
--
-- Every admin level still needs two-step login.
-- See docs/features/admin-levels.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Emergency owner access (read by the helpers below, so it comes first)
-- ---------------------------------------------------------------------------

create table if not exists public.emergency_owner_access (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references public.accounts (id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
  requested_at timestamptz not null default now(),
  -- 48 hours after the request.
  starts_at timestamptz not null,
  -- 7 days after it starts.
  ends_at timestamptz not null,
  cancelled_at timestamptz,
  cancelled_by uuid references public.accounts (id) on delete set null,
  check (ends_at > starts_at)
);
alter table public.emergency_owner_access enable row level security;
drop trigger if exists audit on public.emergency_owner_access;
create trigger audit after insert or update or delete on public.emergency_owner_access
  for each row execute function private.audit_change();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- The level saved for the signed-in admin, ignoring emergency access.
-- Null for anyone who isn't an admin or hasn't used two-step login.
create or replace function private.my_saved_admin_level()
returns text language sql stable security definer
set search_path = ''
as $$
  select case
    when private.has_role('admin') and private.has_aal2() then
      (select level::text from public.admin_profiles where account_id = auth.uid())
  end
$$;
revoke execute on function private.my_saved_admin_level() from public;
grant execute on function private.my_saved_admin_level() to authenticated, service_role;

-- True while this operations admin's emergency owner access is running.
create or replace function private.has_emergency_access()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.my_saved_admin_level() = 'operations'
    and exists (
      select 1 from public.emergency_owner_access e
      where e.requested_by = auth.uid()
        and e.cancelled_at is null
        and now() >= e.starts_at and now() < e.ends_at
    )
$$;
revoke execute on function private.has_emergency_access() from public;
grant execute on function private.has_emergency_access() to authenticated, service_role;

-- The level the signed-in admin is acting at: their saved level, or owner
-- while emergency access is running.
create or replace function private.my_admin_level()
returns text language sql stable security definer
set search_path = ''
as $$
  select case when private.has_emergency_access() then 'owner' else private.my_saved_admin_level() end
$$;
revoke execute on function private.my_admin_level() from public;
grant execute on function private.my_admin_level() to authenticated, service_role;

-- Owner or operations: the full admin tools.
create or replace function private.is_admin()
returns boolean language sql stable security definer
set search_path = ''
as $$ select coalesce(private.my_admin_level() in ('owner', 'operations'), false) $$;

create or replace function private.is_owner()
returns boolean language sql stable security definer
set search_path = ''
as $$ select coalesce(private.my_admin_level() = 'owner', false) $$;

-- Owner, operations or support: families, bookings and login links.
create or replace function private.is_front_desk()
returns boolean language sql stable security definer
set search_path = ''
as $$ select coalesce(private.my_admin_level() in ('owner', 'operations', 'support'), false) $$;
revoke execute on function private.is_front_desk() from public;
grant execute on function private.is_front_desk() to authenticated, service_role;

-- Owner, operations or finance: invoices, payments and credits.
create or replace function private.is_finance_admin()
returns boolean language sql stable security definer
set search_path = ''
as $$ select coalesce(private.my_admin_level() in ('owner', 'operations', 'finance'), false) $$;
revoke execute on function private.is_finance_admin() from public;
grant execute on function private.is_finance_admin() to authenticated, service_role;

-- Owner or finance: changing tutor pay and pay rates.
create or replace function private.is_pay_admin()
returns boolean language sql stable security definer
set search_path = ''
as $$ select coalesce(private.my_admin_level() in ('owner', 'finance'), false) $$;
revoke execute on function private.is_pay_admin() from public;
grant execute on function private.is_pay_admin() to authenticated, service_role;

-- Any admin level.
create or replace function private.is_any_admin()
returns boolean language sql stable security definer
set search_path = ''
as $$ select private.my_admin_level() is not null $$;
revoke execute on function private.is_any_admin() from public;
grant execute on function private.is_any_admin() to authenticated, service_role;

-- Is this account the saved owner? (Emergency access doesn't count.)
create or replace function private.is_saved_owner(p_account uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.admin_profiles where account_id = p_account and level::text = 'owner')
$$;
revoke execute on function private.is_saved_owner(uuid) from public;
grant execute on function private.is_saved_owner(uuid) to authenticated, service_role;

-- For the app: the level the signed-in person is acting at, or null.
create or replace function public.my_admin_level()
returns text language sql stable security definer
set search_path = ''
as $$ select private.my_admin_level() $$;
revoke execute on function public.my_admin_level() from public, anon;
grant execute on function public.my_admin_level() to authenticated;

-- Every admin has a saved level. Anyone with the admin role but no level
-- (there shouldn't be any) gets operations, which is what they had before.
insert into public.admin_profiles (account_id, level)
select r.account_id, 'operations'
from public.account_roles r
where r.role = 'admin'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Tools for switching existing rules to a new level check
-- ---------------------------------------------------------------------------
-- Rather than copy out dozens of long rules, these rewrite an existing rule
-- in place, swapping one check for another (for example "is an admin" for
-- "is an admin or finance"). Running them twice changes nothing more.

-- Swaps p_from for p_to in the table rules (policies) of one table.
-- p_policy limits it to one named rule.
create or replace function private.retarget_policies(p_table text, p_from text, p_to text, p_policy text default null)
returns void language plpgsql
set search_path = ''
as $$
declare
  r record;
  v_sql text;
begin
  for r in
    select policyname, qual, with_check from pg_catalog.pg_policies
    where schemaname = 'public' and tablename = p_table
      and (p_policy is null or policyname = p_policy)
  loop
    if strpos(coalesce(r.qual, ''), p_from) = 0 and strpos(coalesce(r.with_check, ''), p_from) = 0 then
      continue;
    end if;
    v_sql := format('alter policy %I on public.%I', r.policyname, p_table);
    if r.qual is not null then
      v_sql := v_sql || ' using (' || replace(r.qual, p_from, p_to) || ')';
    end if;
    if r.with_check is not null then
      v_sql := v_sql || ' with check (' || replace(r.with_check, p_from, p_to) || ')';
    end if;
    execute v_sql;
  end loop;
end;
$$;
revoke execute on function private.retarget_policies(text, text, text, text) from public;

-- Swaps p_from for p_to inside a function (schema.name, every version).
create or replace function private.retarget_function(p_name text, p_from text, p_to text)
returns void language plpgsql
set search_path = ''
as $$
declare
  r record;
  v_def text;
begin
  for r in
    select p.oid from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname || '.' || p.proname = p_name
  loop
    v_def := pg_catalog.pg_get_functiondef(r.oid);
    if strpos(v_def, p_from) > 0 then
      execute replace(v_def, p_from, p_to);
    end if;
  end loop;
end;
$$;
revoke execute on function private.retarget_function(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- Support: families, bookings, login links
-- ---------------------------------------------------------------------------

-- Functions support may use (operations and the owner still can).
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_find_account', 'public.admin_add_child', 'public.admin_offer_student_login',
    'public.request_booking', 'public.respond_to_booking', 'public.cancel_session',
    'public.list_bookings', 'public.list_sessions', 'public.list_waitlist', 'public.list_renewals',
    'private.can_book_for', 'private.cancel_role',
    'private.guard_student', 'private.require_student_details'
  ] loop
    perform private.retarget_function(f, 'private.is_admin()', 'private.is_front_desk()');
  end loop;
end;
$$;

-- What support can read. Each is an extra "may see" rule; the existing
-- rules for families, tutors and full admins are unchanged.
do $$
declare
  t text;
begin
  foreach t in array array[
    'account_private', 'account_roles', 'parent_profiles', 'families', 'students',
    'student_subjects', 'parent_student_links', 'tutor_assignments', 'tutor_profiles',
    'tutor_availability', 'tutor_places', 'tutor_session_settings', 'bookings', 'sessions',
    'away_dates', 'waitlist', 'school_terms', 'term_renewals', 'student_login_offers'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists "support desk sees" on public.%I', t);
      execute format('create policy "support desk sees" on public.%I for select to authenticated using (private.is_front_desk())', t);
    end if;
  end loop;
end;
$$;

-- Support may correct a family's name, email and phone.
drop policy if exists "support desk edits names" on public.accounts;
create policy "support desk edits names" on public.accounts
  for update to authenticated using (private.is_front_desk()) with check (private.is_front_desk());
drop policy if exists "support desk edits contact details" on public.account_private;
create policy "support desk edits contact details" on public.account_private
  for update to authenticated using (private.is_front_desk()) with check (private.is_front_desk());

-- Every admin level sees people's names (finance needs them for invoices
-- and pay). Contact details stay with the levels above.
drop policy if exists "admins see names" on public.accounts;
create policy "admins see names" on public.accounts
  for select to authenticated using (private.is_any_admin());

-- Whether each family is paused for an overdue bill, without any other
-- money details. For support (and the levels above).
create or replace function public.family_pause_status()
returns table (family_id uuid, family_name text, paused boolean, paused_since timestamptz)
language sql stable security definer
set search_path = ''
as $$
  select f.id, f.name, coalesce(b.paused, false), b.paused_since
  from public.families f
  left join public.billing_accounts b on b.family_id = f.id
  where private.is_front_desk() or private.is_finance_admin()
  order by f.name
$$;
revoke execute on function public.family_pause_status() from public, anon;
grant execute on function public.family_pause_status() to authenticated;

-- ---------------------------------------------------------------------------
-- Finance: invoices, payments, credits, tutor pay
-- ---------------------------------------------------------------------------

-- Every billing table rule that said "admin" now says "admin or finance".
do $$
declare
  t text;
begin
  for t in
    select c.relname from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'billing\_%'
  loop
    perform private.retarget_policies(t, 'private.is_admin()', 'private.is_finance_admin()');
  end loop;
end;
$$;

-- Every billing function that said "admin" now says "admin or finance".
do $$
declare
  f text;
begin
  for f in
    select distinct n.nspname || '.' || p.proname from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.proname like 'billing\_%'
  loop
    perform private.retarget_function(f, 'private.is_admin()', 'private.is_finance_admin()');
  end loop;
end;
$$;

-- Changing tutor pay and pay rates: owner and finance only. Operations
-- can still see it.
select private.retarget_policies('billing_staff_pay', 'private.is_finance_admin()', 'private.is_pay_admin()', 'admins set pay');
select private.retarget_function('public.billing_add_admin_time', 'private.is_finance_admin()', 'private.is_pay_admin()');
select private.retarget_function('public.billing_remove_pay_line', 'private.is_finance_admin()', 'private.is_pay_admin()');
select private.retarget_function('public.billing_build_pay', 'private.is_finance_admin()', 'private.is_pay_admin()');
select private.retarget_function('public.billing_mark_pay_sent', 'private.is_finance_admin()', 'private.is_pay_admin()');

-- Prices and kept family rates are billing rules: only the owner changes
-- them. Finance and operations can still read them.
select private.retarget_policies('billing_price_items', 'private.is_finance_admin()', 'private.is_owner()', 'admins manage prices');
select private.retarget_policies('billing_family_rates', 'private.is_finance_admin()', 'private.is_owner()', 'admins manage family rates');
drop policy if exists "finance reads family rates" on public.billing_family_rates;
create policy "finance reads family rates" on public.billing_family_rates
  for select to authenticated using (private.is_finance_admin());

-- Finance sees family names (on invoices).
drop policy if exists "finance sees families" on public.families;
create policy "finance sees families" on public.families
  for select to authenticated using (private.is_finance_admin());

-- ---------------------------------------------------------------------------
-- Staff and levels
-- ---------------------------------------------------------------------------

-- The owner's own admin access can't be changed or removed through the app
-- by anyone, and nobody can be made a second owner. (A restrictive rule
-- applies on top of every other rule.)
drop policy if exists "owner level is fixed (insert)" on public.admin_profiles;
create policy "owner level is fixed (insert)" on public.admin_profiles
  as restrictive for insert to authenticated with check (level::text <> 'owner');
drop policy if exists "owner level is fixed (update)" on public.admin_profiles;
create policy "owner level is fixed (update)" on public.admin_profiles
  as restrictive for update to authenticated using (level::text <> 'owner') with check (level::text <> 'owner');
drop policy if exists "owner level is fixed (delete)" on public.admin_profiles;
create policy "owner level is fixed (delete)" on public.admin_profiles
  as restrictive for delete to authenticated using (level::text <> 'owner');
drop policy if exists "owner keeps admin role" on public.account_roles;
create policy "owner keeps admin role" on public.account_roles
  as restrictive for delete to authenticated
  using (not (role = 'admin' and private.is_saved_owner(account_id)));

-- Activity log: the owner reads all of it; other admins read their own.
drop policy if exists "admins read audit log" on public.audit_log;
create policy "admins read audit log" on public.audit_log
  for select to authenticated
  using (private.is_owner() or (actor_id = auth.uid() and private.is_any_admin()));

-- Every staff member: name, email, whether they tutor, and their admin
-- level. Owner and operations only.
create or replace function public.staff_list()
returns table (
  account_id uuid,
  full_name text,
  email text,
  is_tutor boolean,
  tutor_active boolean,
  admin_level text
)
language sql stable security definer
set search_path = ''
as $$
  select a.id, a.full_name, p.email,
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'tutor'),
         t.active,
         (select ap.level::text from public.admin_profiles ap
          where ap.account_id = a.id
            and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin'))
  from public.accounts a
  left join public.account_private p on p.account_id = a.id
  left join public.tutor_profiles t on t.account_id = a.id
  where private.is_admin()
    and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor'))
  order by a.full_name
$$;
revoke execute on function public.staff_list() from public, anon;
grant execute on function public.staff_list() to authenticated;

-- The owner changes an admin's level (not their own, and never to owner).
create or replace function public.set_admin_level(p_account uuid, p_level text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_old text;
begin
  if not private.is_owner() then
    raise exception 'Only the owner can change admin levels' using errcode = '42501';
  end if;
  if p_level is null or p_level not in ('operations', 'support', 'finance') then
    raise exception 'Choose Operations, Support or Finance' using errcode = '22023';
  end if;
  if p_account = auth.uid() then
    raise exception 'You can''t change your own level' using errcode = '42501';
  end if;
  if not exists (select 1 from public.account_roles where account_id = p_account and role = 'admin') then
    raise exception 'That person isn''t an admin' using errcode = '22023';
  end if;
  select level::text into v_old from public.admin_profiles where account_id = p_account;
  if v_old = 'owner' then
    raise exception 'The owner''s level can''t be changed' using errcode = '42501';
  end if;
  insert into public.admin_profiles (account_id, level)
  values (p_account, p_level::public.admin_level)
  on conflict (account_id) do update set level = excluded.level;
  -- Someone moved off operations loses any emergency access with it.
  if p_level <> 'operations' then
    update public.emergency_owner_access
    set cancelled_at = now(), cancelled_by = auth.uid()
    where requested_by = p_account and cancelled_at is null and ends_at > now();
  end if;
end;
$$;
revoke execute on function public.set_admin_level(uuid, text) from public, anon;
grant execute on function public.set_admin_level(uuid, text) to authenticated;

-- Invitations now carry the admin level. Only the owner invites admins.
drop function if exists public.create_staff_invite_link(text, public.app_role);
create or replace function public.create_staff_invite_link(p_email text, p_role public.app_role, p_level text default null)
returns text language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_level text := case when p_role = 'admin' then coalesce(p_level, 'operations') else 'operations' end;
  v_open public.invitations;
  v_token text;
begin
  if not private.is_admin() then
    raise exception 'Only admins can invite staff' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('tutor', 'admin') then
    raise exception 'Choose tutor or admin' using errcode = '22023';
  end if;
  if p_role = 'admin' and not private.is_owner() then
    raise exception 'Only the owner can invite admins' using errcode = '42501';
  end if;
  if v_level not in ('operations', 'support', 'finance') then
    raise exception 'Choose Operations, Support or Finance' using errcode = '22023';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if exists (
    select 1 from auth.users
    where lower(email) = v_email and email_confirmed_at is not null
  ) then
    raise exception 'That email already has a CLG account. Add the role to it instead' using errcode = '23505';
  end if;

  -- An earlier invitation not yet used (still open, or expired) is replaced.
  -- Only the owner can replace an admin invitation.
  select * into v_open from public.invitations
  where email = v_email and accepted_at is null;
  if v_open.id is not null then
    if v_open.role = 'admin' and not private.is_owner() then
      raise exception 'That email has an admin invitation waiting. Only the owner can change it' using errcode = '42501';
    end if;
    delete from public.invitations where id = v_open.id;
  end if;

  -- 64 random hex characters from Postgres's secure random source.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (email, role, admin_level, invited_by, link_hash, expires_at)
  values (v_email, p_role, v_level::public.admin_level, auth.uid(), private.invite_link_hash(v_token), now() + interval '7 days');
  return v_token;
end;
$$;
revoke execute on function public.create_staff_invite_link(text, public.app_role, text) from public, anon;
grant execute on function public.create_staff_invite_link(text, public.app_role, text) to authenticated;

drop function if exists public.grant_staff_role(text, public.app_role);
create or replace function public.grant_staff_role(p_email text, p_role public.app_role, p_level text default null)
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_level text := case when p_role = 'admin' then coalesce(p_level, 'operations') else 'operations' end;
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
  if v_level not in ('operations', 'support', 'finance') then
    raise exception 'Choose Operations, Support or Finance' using errcode = '22023';
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
  insert into public.invitations (email, role, admin_level, invited_by)
  values (v_email, p_role, v_level::public.admin_level, auth.uid());
  perform private.accept_invitation(v_user, v_email);
  return true;
end;
$$;
revoke execute on function public.grant_staff_role(text, public.app_role, text) from public, anon;
grant execute on function public.grant_staff_role(text, public.app_role, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Emergency owner access: asking, cancelling, seeing
-- ---------------------------------------------------------------------------

revoke insert, update, delete on public.emergency_owner_access from authenticated, anon;

-- The owner and operations admins see requests (so both know what's going on).
drop policy if exists "owner and operations see emergency access" on public.emergency_owner_access;
create policy "owner and operations see emergency access" on public.emergency_owner_access
  for select to authenticated
  using (private.my_saved_admin_level() in ('owner', 'operations'));

-- An operations admin asks for owner powers. A reason is required.
-- Returns the request's id. The app emails the owner straight away.
create or replace function public.request_emergency_owner_access(p_reason text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_id uuid;
begin
  if coalesce(private.my_saved_admin_level(), '') <> 'operations' then
    raise exception 'Only an Operations admin can ask for emergency owner access' using errcode = '42501';
  end if;
  if char_length(v_reason) < 10 then
    raise exception 'Please write why you need owner access (at least 10 characters)' using errcode = '22023';
  end if;
  if char_length(v_reason) > 1000 then
    raise exception 'Please keep the reason under 1000 characters' using errcode = '22023';
  end if;
  -- One request at a time, across everyone.
  lock table public.emergency_owner_access in share row exclusive mode;
  if exists (
    select 1 from public.emergency_owner_access
    where cancelled_at is null and ends_at > now()
  ) then
    raise exception 'There is already an emergency access request waiting or running' using errcode = '23505';
  end if;
  insert into public.emergency_owner_access (requested_by, reason, starts_at, ends_at)
  values (auth.uid(), v_reason, now() + interval '48 hours', now() + interval '48 hours' + interval '7 days')
  returning id into v_id;
  perform private.log_event('emergency_access_requested', 'emergency_owner_access', v_id::text,
    jsonb_build_object('reason', v_reason));
  return v_id;
end;
$$;
revoke execute on function public.request_emergency_owner_access(text) from public, anon;
grant execute on function public.request_emergency_owner_access(text) to authenticated;

-- The owner cancels a request (before or after it starts), or the person
-- who asked withdraws it. Returns who had asked, so the app can email them.
create or replace function public.cancel_emergency_owner_access(p_id uuid)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.emergency_owner_access;
begin
  select * into v_row from public.emergency_owner_access
  where id = p_id and cancelled_at is null and ends_at > now()
  for update;
  if v_row.id is null then
    raise exception 'That request has already ended or been cancelled' using errcode = '22023';
  end if;
  if not (
    private.my_saved_admin_level() = 'owner'
    or (v_row.requested_by = auth.uid() and private.my_saved_admin_level() is not null)
  ) then
    raise exception 'Only the owner can cancel emergency access' using errcode = '42501';
  end if;
  update public.emergency_owner_access
  set cancelled_at = now(), cancelled_by = auth.uid()
  where id = v_row.id;
  perform private.log_event('emergency_access_cancelled', 'emergency_owner_access', v_row.id::text, '{}');
  return v_row.requested_by;
end;
$$;
revoke execute on function public.cancel_emergency_owner_access(uuid) from public, anon;
grant execute on function public.cancel_emergency_owner_access(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Emergency owner access: emails when it starts and when it ends
-- ---------------------------------------------------------------------------
-- The email to the owner when someone asks, and to the person who asked when
-- the owner cancels, are sent by the app straight away. These two are sent
-- by the app's email sender (see docs/features/sending-emails.md).

alter table public.emergency_owner_access add column if not exists start_emailed_at timestamptz;
alter table public.emergency_owner_access add column if not exists end_emailed_at timestamptz;

-- Any start or end email waiting?
create or replace function private.emergency_emails_waiting()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.emergency_owner_access e
    where e.cancelled_at is null
      and (
        (e.start_emailed_at is null and now() >= e.starts_at and now() < e.ends_at)
        or (e.end_emailed_at is null and now() >= e.ends_at and now() < e.ends_at + interval '3 days')
      )
  )
$$;
revoke all on function private.emergency_emails_waiting() from public;

-- Hands the due emails to the sender and marks them sent. One email per
-- request each time: "has started" or "has ended".
create or replace function public.emergency_access_emails_claim(p_limit integer default 50)
returns table (id uuid, email text, first_name text, subject text, body text, link text)
language plpgsql security definer
set search_path = ''
as $$
declare
  r record;
  v_end boolean;
  v_until text;
begin
  for r in
    select e.*, ap.email as to_email, a.full_name
    from public.emergency_owner_access e
    join public.account_private ap on ap.account_id = e.requested_by
    join public.accounts a on a.id = e.requested_by
    where e.cancelled_at is null
      and (
        (e.start_emailed_at is null and now() >= e.starts_at and now() < e.ends_at)
        or (e.end_emailed_at is null and now() >= e.ends_at and now() < e.ends_at + interval '3 days')
      )
    order by e.starts_at
    limit least(greatest(p_limit, 1), 100)
    for update of e skip locked
  loop
    v_end := now() >= r.ends_at;
    v_until := to_char(r.ends_at at time zone 'Australia/Adelaide', 'FMDay FMDD FMMonth, FMHH12:MI am');
    if v_end then
      update public.emergency_owner_access
      set end_emailed_at = now(), start_emailed_at = coalesce(start_emailed_at, now())
      where emergency_owner_access.id = r.id;
    else
      update public.emergency_owner_access set start_emailed_at = now()
      where emergency_owner_access.id = r.id;
    end if;
    id := r.id;
    email := r.to_email;
    first_name := private.first_name(r.full_name);
    subject := case when v_end then 'Your emergency owner access has ended'
                    else 'Your emergency owner access has started' end;
    body := case when v_end
      then 'Your 7 days of emergency owner access in the CLG app have ended. You are back to your usual Operations admin access.'
      else 'The owner didn''t cancel your request, so you now have owner access in the CLG app until ' || v_until
        || ' (Adelaide time). Everything you do is recorded in the activity log. It ends by itself.' end;
    link := '/admin';
    return next;
  end loop;
end;
$$;
revoke all on function public.emergency_access_emails_claim(integer) from public, anon, authenticated;
grant execute on function public.emergency_access_emails_claim(integer) to service_role;

-- Puts emails back if sending failed (only ones marked in the last hour).
create or replace function public.emergency_access_emails_release(p_ids uuid[])
returns void language sql security definer
set search_path = ''
as $$
  update public.emergency_owner_access
  set end_emailed_at = case when end_emailed_at > now() - interval '1 hour' then null else end_emailed_at end,
      start_emailed_at = case
        when end_emailed_at > now() - interval '1 hour' and now() >= ends_at then start_emailed_at
        when start_emailed_at > now() - interval '1 hour' then null
        else start_emailed_at end
  where id = any (p_ids)
$$;
revoke all on function public.emergency_access_emails_release(uuid[]) from public, anon, authenticated;
grant execute on function public.emergency_access_emails_release(uuid[]) to service_role;

-- Wake the email sender for these too. The shared check is extended rather
-- than copied, so changes other modules make to it are kept.
do $$
declare
  v_def text;
begin
  if to_regprocedure('private.emails_waiting()') is null then
    return;
  end if;
  v_def := pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure);
  if strpos(v_def, 'private.emergency_emails_waiting()') = 0 then
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.emergency_emails_waiting()\n$function$\n');
    execute v_def;
  end if;
end;
$$;
