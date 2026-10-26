-- Automatic deletion of personal information once CLG no longer needs it
-- (Australian Privacy Principle 11.2), on the timetable in CLG's privacy
-- policy.
--
-- How it works:
--   * retention_rules holds how long each kind of record is kept. Only the
--     owner can change a period, and every change is logged.
--   * retention_holds lets an admin stop a student or account from being
--     deleted, for example while a child safety concern, complaint or legal
--     matter is open.
--   * private.run_retention() deletes everything that is due. It runs every
--     night (scheduled at the end of this file) and records how many
--     records it deleted, never what they were.
--   * public.upcoming_deletions() shows admins what is due in the next 30
--     days, so they can place a hold in time.
--   * public.erase_student() deletes a student early when a family asks.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.retention_rules (
  kind text primary key check (kind in (
    'student_records', 'unused_accounts', 'former_tutors', 'activity_log'
  )),
  keep_for interval not null check (keep_for >= interval '30 days'),
  description text not null,
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.retention_rules (kind, keep_for, description) values
  ('student_records', interval '2 years',
   'Student records, learning needs and links: kept until 2 years after the last lesson, assignment or enrolment.'),
  ('unused_accounts', interval '12 months',
   'Accounts with no children, enrolments or staff role: deleted after 12 months without signing in.'),
  ('former_tutors', interval '7 years',
   'Tutor profile, child safety checks and availability: kept until 7 years after the tutor leaves CLG.'),
  ('activity_log', interval '7 years',
   'The activity log (ids only, no content), which is also the record of consent given and withdrawn.');

create table public.retention_holds (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students (id) on delete cascade,
  account_id uuid references public.accounts (id) on delete cascade,
  -- Keep this short and general. Concern details belong in the child safety
  -- record, not here.
  reason text not null check (char_length(reason) between 3 and 300),
  placed_by uuid references public.accounts (id) on delete set null,
  placed_at timestamptz not null default now(),
  released_by uuid references public.accounts (id) on delete set null,
  released_at timestamptz,
  check (num_nonnulls(student_id, account_id) = 1)
);
create index retention_holds_student on public.retention_holds (student_id) where released_at is null;
create index retention_holds_account on public.retention_holds (account_id) where released_at is null;

-- What each nightly run deleted: counts only.
create table public.retention_log (
  id bigint generated always as identity primary key,
  ran_at timestamptz not null default now(),
  kind text not null,
  deleted integer not null
);

-- When a tutor stopped working with CLG. Starts the 7-year clock.
alter table public.tutor_profiles add column ended_on date;
alter table public.tutor_profiles
  add constraint ended_tutor_is_inactive check (ended_on is null or not active);

alter table public.retention_rules enable row level security;
alter table public.retention_holds enable row level security;
alter table public.retention_log enable row level security;
revoke all on public.retention_rules, public.retention_holds, public.retention_log from anon;

create trigger audit after insert or update or delete on public.retention_rules
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.retention_holds
  for each row execute function private.audit_change();

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

-- Tutors may edit their bio and subjects, not whether they are active or
-- when they left.
create or replace function private.guard_tutor_profile()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if (new.active is distinct from old.active or new.ended_on is distinct from old.ended_on)
     and not (private.is_backend() or private.is_admin()) then
    raise exception 'Only an admin can change whether a tutor is active'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create function private.stamp_retention_change()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'retention_rules' then
    new.updated_by := auth.uid();
    new.updated_at := now();
  elsif tg_op = 'INSERT' then
    new.placed_by := auth.uid();
    new.placed_at := now();
    new.released_by := null;
    new.released_at := null;
  else
    -- A hold can only be released, never edited or re-opened.
    if old.released_at is not null
       or new.student_id is distinct from old.student_id
       or new.account_id is distinct from old.account_id
       or new.reason is distinct from old.reason
       or new.placed_by is distinct from old.placed_by
       or new.placed_at is distinct from old.placed_at
       or new.released_at is null then
      raise exception 'A hold can only be released' using errcode = '42501';
    end if;
    new.released_by := auth.uid();
    new.released_at := now();
  end if;
  return new;
end;
$$;
create trigger stamp before update on public.retention_rules
  for each row execute function private.stamp_retention_change();
create trigger stamp before insert or update on public.retention_holds
  for each row execute function private.stamp_retention_change();

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------

create policy "admins read retention rules" on public.retention_rules
  for select to authenticated using (private.is_admin());
create policy "owner changes retention periods" on public.retention_rules
  for update to authenticated using (private.is_owner()) with check (private.is_owner());
revoke insert, delete, truncate on public.retention_rules from authenticated;

create policy "admins read holds" on public.retention_holds
  for select to authenticated using (private.is_admin());
create policy "admins place holds" on public.retention_holds
  for insert to authenticated with check (private.is_admin());
create policy "admins release holds" on public.retention_holds
  for update to authenticated using (private.is_admin()) with check (private.is_admin());
revoke delete, truncate on public.retention_holds from authenticated;

create policy "admins read retention log" on public.retention_log
  for select to authenticated using (private.is_admin());
revoke insert, update, delete, truncate on public.retention_log from authenticated;

-- ---------------------------------------------------------------------------
-- What is due
-- ---------------------------------------------------------------------------

create function private.keep_for(p_kind text)
returns interval language sql stable
set search_path = ''
as $$ select keep_for from public.retention_rules where kind = p_kind $$;

-- The latest sign that a student is still with CLG. An open tutor
-- assignment or a live enrolment counts as "now", so current students are
-- never due.
create function private.student_last_activity(p_student uuid)
returns timestamptz language sql stable
set search_path = ''
as $$
  select greatest(
    s.last_activity_at,
    s.created_at,
    (select max(case when a.ends_on is null or a.ends_on >= current_date then now()
                     else a.ends_on::timestamptz end)
     from public.tutor_assignments a where a.student_id = s.id),
    (select max(case when e.status <> 'ended' or e.ends_on >= current_date then now()
                     else coalesce(e.ends_on::timestamptz, e.created_at) end)
     from public.enrolments e where e.student_id = s.id)
  )
  from public.students s where s.id = p_student
$$;

create function private.has_hold(p_student uuid, p_account uuid)
returns boolean language sql stable
set search_path = ''
as $$
  select exists (
    select 1 from public.retention_holds h
    where h.released_at is null
      and ((p_student is not null and h.student_id = p_student)
        or (p_account is not null and h.account_id = p_account))
  )
$$;

-- Everything that is (or will be) due for deletion by p_at.
-- kind: 'student', 'account' or 'tutor'.
create function private.retention_due(p_at timestamptz)
returns table (kind text, record_id uuid, due_at timestamptz)
language sql stable
set search_path = ''
as $$
  -- Students no longer with CLG.
  select 'student', s.id, private.student_last_activity(s.id) + private.keep_for('student_records')
  from public.students s
  where private.student_last_activity(s.id) + private.keep_for('student_records') <= p_at
    and not private.has_hold(s.id, s.account_id)

  union all

  -- Former tutors.
  select 'tutor', t.account_id, t.ended_on::timestamptz + private.keep_for('former_tutors')
  from public.tutor_profiles t
  where not t.active
    and t.ended_on is not null
    and t.ended_on::timestamptz + private.keep_for('former_tutors') <= p_at
    and not private.has_hold(null, t.account_id)

  union all

  -- Accounts with nothing left to keep: no staff role, no linked children,
  -- no student record, and no sign-in for the set period.
  select 'account', a.id, greatest(a.created_at, u.last_sign_in_at) + private.keep_for('unused_accounts')
  from public.accounts a
  join auth.users u on u.id = a.id
  where greatest(a.created_at, u.last_sign_in_at) + private.keep_for('unused_accounts') <= p_at
    and not exists (select 1 from public.account_roles r
                    where r.account_id = a.id and r.role in ('admin', 'tutor'))
    and not exists (select 1 from public.parent_student_links l where l.parent_id = a.id)
    and not exists (select 1 from public.students s where s.account_id = a.id)
    and not private.has_hold(null, a.id)
$$;

-- ---------------------------------------------------------------------------
-- Deleting
-- ---------------------------------------------------------------------------

-- Deletes one student and everything that belongs to them (learning needs,
-- parent links, tutor assignments, enrolments, consents). If the student had
-- their own login and nothing else depends on it, the login goes too.
create function private.delete_student(p_student uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_account uuid;
  v_family uuid;
begin
  select account_id, family_id into v_account, v_family
  from public.students where id = p_student;

  delete from public.students where id = p_student;

  if v_account is not null and not exists (
    select 1 from public.account_roles
    where account_id = v_account and role <> 'student'
  ) and not private.has_hold(null, v_account) then
    delete from auth.users where id = v_account;
  end if;

  if v_family is not null and not exists (
    select 1 from public.students where family_id = v_family
  ) then
    delete from public.families where id = v_family;
  end if;
end;
$$;

-- Deletes a former tutor's records. A tutor who is also a parent or admin
-- keeps their login; only the tutor side is removed.
create function private.delete_former_tutor(p_tutor uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.account_roles where account_id = p_tutor and role <> 'tutor'
  ) then
    delete from public.tutor_profiles where account_id = p_tutor;
    delete from public.account_roles where account_id = p_tutor and role = 'tutor';
  else
    delete from auth.users where id = p_tutor;
  end if;
end;
$$;

-- The nightly job. Safe to run more than once.
create function private.run_retention()
returns table (kind text, deleted integer)
language plpgsql security definer
set search_path = ''
as $$
declare
  r record;
  v_students integer := 0;
  v_tutors integer := 0;
  v_accounts integer := 0;
  v_log integer := 0;
begin
  for r in select d.kind, d.record_id from private.retention_due(now()) d loop
    if r.kind = 'student' then
      perform private.delete_student(r.record_id);
      v_students := v_students + 1;
    elsif r.kind = 'tutor' then
      perform private.delete_former_tutor(r.record_id);
      v_tutors := v_tutors + 1;
    end if;
  end loop;

  -- Accounts are checked after students, so a parent whose last child was
  -- just removed is judged on their own sign-in date.
  for r in select d.record_id from private.retention_due(now()) d where d.kind = 'account' loop
    delete from auth.users where id = r.record_id;
    v_accounts := v_accounts + 1;
  end loop;

  delete from public.audit_log where at < now() - private.keep_for('activity_log');
  get diagnostics v_log = row_count;

  -- Failed-login records (90 days) and old account locks.
  perform private.purge_login_attempts();

  insert into public.retention_log (kind, deleted) values
    ('student_records', v_students),
    ('former_tutors', v_tutors),
    ('unused_accounts', v_accounts),
    ('activity_log', v_log);

  return query values
    ('student_records'::text, v_students),
    ('former_tutors', v_tutors),
    ('unused_accounts', v_accounts),
    ('activity_log', v_log);
end;
$$;

revoke execute on function private.run_retention() from public;
revoke execute on function private.delete_student(uuid) from public;
revoke execute on function private.delete_former_tutor(uuid) from public;
revoke execute on function private.retention_due(timestamptz) from public;

-- ---------------------------------------------------------------------------
-- For admins
-- ---------------------------------------------------------------------------

-- What will be deleted in the next p_days days, with names, so an admin can
-- place a hold in time.
create function public.upcoming_deletions(p_days integer default 30)
returns table (kind text, record_id uuid, full_name text, due_on date)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select d.kind, d.record_id,
           coalesce(s.full_name, a.full_name),
           greatest(d.due_at, now())::date
    from private.retention_due(now() + make_interval(days => least(greatest(p_days, 0), 366))) d
    left join public.students s on d.kind = 'student' and s.id = d.record_id
    left join public.accounts a on d.kind <> 'student' and a.id = d.record_id
    order by d.due_at, 3;
end;
$$;

-- Deletes a student straight away when a family asks (APP 11.2). Owner only,
-- needs the student's name typed exactly, and refused while a hold is on.
create function public.erase_student(p_student uuid, p_confirm_name text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_name text;
  v_account uuid;
begin
  if not private.is_owner() then
    raise exception 'Only the owner can erase a student' using errcode = '42501';
  end if;
  select full_name, account_id into v_name, v_account from public.students where id = p_student;
  if v_name is null then
    raise exception 'Student not found' using errcode = 'P0002';
  end if;
  if p_confirm_name is distinct from v_name then
    raise exception 'The name typed does not match the student' using errcode = '22023';
  end if;
  if private.has_hold(p_student, v_account) then
    raise exception 'This student has a hold on their records, so they cannot be erased yet'
      using errcode = '23514';
  end if;
  perform private.log_event('erase_on_request', 'students', p_student::text);
  perform private.delete_student(p_student);
end;
$$;

revoke execute on function public.upcoming_deletions(integer) from public, anon;
revoke execute on function public.erase_student(uuid, text) from public, anon;
grant execute on function public.upcoming_deletions(integer) to authenticated;
grant execute on function public.erase_student(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Schedule: every night at 17:00 UTC (about 3am in Adelaide).
-- Uses Supabase's pg_cron. Skipped where pg_cron isn't installed, such as
-- the local test database.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-retention-nightly', '0 17 * * *', 'select private.run_retention()')
    $job$;
  end if;
end;
$$;
