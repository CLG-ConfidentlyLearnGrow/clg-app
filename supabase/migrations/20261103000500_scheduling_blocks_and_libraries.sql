-- Blocking a match, and confirmed libraries with opening hours (module:
-- scheduling). Carla, 2 Nov 2026.
--
-- Blocking:
--   * A tutor can block a student, and a family can block a tutor. A reason
--     is required.
--   * CLG's admins are told straight away and follow up with the person who
--     blocked, to understand what happened and help it not happen again.
--     The follow-up is recorded.
--   * The other person is not told. The app simply stops suggesting that
--     tutor and student together (finding times, offers, the waitlist, and
--     the admin's assign list). Existing bookings are not cancelled by the
--     block; the admin sorts those out in the follow-up.
--   * Only admins can lift a block.
--
-- Libraries:
--   * Tutors choose online and/or libraries. A tutor can suggest a library
--     that isn't on CLG's list yet.
--   * An admin confirms each library and adds its opening hours. Sessions
--     are only offered at confirmed libraries, inside opening hours.
--   * Libraries already on the list are kept as confirmed. Where no hours
--     have been added yet, any time is allowed until an admin adds them
--     (the Libraries list flags these).
--   * Sessions at home or at school can only be booked by an admin.
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Blocking
-- ---------------------------------------------------------------------------
create table if not exists public.match_blocks (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  blocked_by_role text not null check (blocked_by_role in ('tutor', 'family')),
  blocked_by uuid references public.accounts (id) on delete set null,
  reason text not null check (char_length(reason) between 10 and 2000),
  created_at timestamptz not null default now(),
  followed_up_at timestamptz,
  followed_up_by uuid references public.accounts (id) on delete set null,
  follow_up_note text check (char_length(follow_up_note) <= 2000),
  lifted_at timestamptz,
  lifted_by uuid references public.accounts (id) on delete set null
);
create unique index if not exists match_blocks_once
  on public.match_blocks (tutor_id, student_id, blocked_by_role) where lifted_at is null;
create index if not exists match_blocks_pair on public.match_blocks (tutor_id, student_id) where lifted_at is null;

alter table public.match_blocks enable row level security;
revoke all on public.match_blocks from anon;
revoke insert, update, delete, truncate on public.match_blocks from authenticated;
drop trigger if exists audit on public.match_blocks;
create trigger audit after insert or update or delete on public.match_blocks
  for each row execute function private.audit_change();

-- Admins see every block. The person who blocked sees their own. The other
-- side never sees it.
drop policy if exists "see own blocks" on public.match_blocks;
create policy "see own blocks" on public.match_blocks
  for select to authenticated using (
    private.is_admin()
    or (blocked_by_role = 'tutor' and tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
    or (blocked_by_role = 'family' and private.can_book_for(student_id))
  );

-- Is this tutor and student pair blocked (either way)?
create or replace function private.blocked_pair(p_tutor uuid, p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.match_blocks b
    where b.tutor_id = p_tutor and b.student_id = p_student and b.lifted_at is null
  )
$$;
revoke all on function private.blocked_pair(uuid, uuid) from public;
grant execute on function private.blocked_pair(uuid, uuid) to authenticated, service_role;

-- The tutor blocks a student they teach or have taught, or the family
-- blocks a tutor their child has had. Returns the block's id.
create or replace function public.block_match(p_tutor uuid, p_student uuid, p_reason text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_role text;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_id uuid;
  v_tutor text;
  v_student text;
begin
  if p_tutor = auth.uid() and private.has_role('tutor') and private.has_aal2() then
    v_role := 'tutor';
  elsif private.can_book_for(p_student) then
    v_role := 'family';
  else
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from public.tutor_assignments a where a.tutor_id = p_tutor and a.student_id = p_student)
     and not exists (select 1 from public.bookings b where b.tutor_id = p_tutor and b.student_id = p_student) then
    raise exception 'You can only block a tutor or student you have had sessions or offers with' using errcode = '22023';
  end if;
  if char_length(v_reason) < 10 then
    raise exception 'Please give a reason (at least 10 characters). Only CLG sees it.' using errcode = '22023';
  end if;
  if exists (select 1 from public.match_blocks b
             where b.tutor_id = p_tutor and b.student_id = p_student and b.blocked_by_role = v_role and b.lifted_at is null) then
    raise exception 'Already blocked' using errcode = '23505';
  end if;

  insert into public.match_blocks (tutor_id, student_id, blocked_by_role, blocked_by, reason)
  values (p_tutor, p_student, v_role, auth.uid(), left(v_reason, 2000))
  returning id into v_id;

  select full_name into v_tutor from public.accounts where id = p_tutor;
  select full_name into v_student from public.students where id = p_student;
  perform private.notify_admins('Block to follow up',
    case when v_role = 'tutor'
      then coalesce(v_tutor, 'A tutor') || ' has blocked ' || coalesce(v_student, 'a student')
      else coalesce(v_student, 'A student') || '''s family has blocked ' || coalesce(v_tutor, 'a tutor') end
    || '. Reason: ' || left(v_reason, 400)
    || ' Please follow up with them (Schedule > Blocks). The other person has not been told.');
  return v_id;
end;
$$;
revoke all on function public.block_match(uuid, uuid, text) from public, anon;
grant execute on function public.block_match(uuid, uuid, text) to authenticated;

-- An admin records the follow-up conversation.
create or replace function public.record_block_follow_up(p_id uuid, p_note text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins record follow-ups' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Please note what was discussed' using errcode = '22023';
  end if;
  update public.match_blocks
  set followed_up_at = now(), followed_up_by = auth.uid(), follow_up_note = left(btrim(p_note), 2000)
  where id = p_id;
  if not found then
    raise exception 'Block not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.record_block_follow_up(uuid, text) from public, anon;
grant execute on function public.record_block_follow_up(uuid, text) to authenticated;

-- An admin lifts a block (for example after the follow-up).
create or replace function public.lift_block(p_id uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins can lift a block' using errcode = '42501';
  end if;
  update public.match_blocks set lifted_at = now(), lifted_by = auth.uid()
  where id = p_id and lifted_at is null;
  if not found then
    raise exception 'Block not found' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.lift_block(uuid) from public, anon;
grant execute on function public.lift_block(uuid) to authenticated;

-- For the screens: blocks with names. Admins see all; the person who
-- blocked sees their own.
create or replace function public.list_blocks()
returns table (
  id uuid, tutor_id uuid, tutor_name text, student_id uuid, student_name text, blocked_by_role text,
  reason text, created_at timestamptz, followed_up_at timestamptz, follow_up_note text, lifted_at timestamptz
)
language sql stable security definer
set search_path = ''
as $$
  select b.id, b.tutor_id, a.full_name, b.student_id, s.full_name, b.blocked_by_role,
         b.reason, b.created_at, b.followed_up_at,
         case when private.is_admin() then b.follow_up_note end, b.lifted_at
  from public.match_blocks b
  join public.accounts a on a.id = b.tutor_id
  join public.students s on s.id = b.student_id
  where private.is_admin()
     or (b.blocked_by_role = 'tutor' and b.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
     or (b.blocked_by_role = 'family' and private.can_book_for(b.student_id))
  order by b.lifted_at is not null, b.followed_up_at is not null, b.created_at
$$;
revoke all on function public.list_blocks() from public, anon;
grant execute on function public.list_blocks() to authenticated;

-- ---------------------------------------------------------------------------
-- Libraries: confirmed by CLG, with opening hours
-- ---------------------------------------------------------------------------
alter table public.libraries add column if not exists confirmed_at timestamptz;
alter table public.libraries add column if not exists confirmed_by uuid references public.accounts (id) on delete set null;
alter table public.libraries add column if not exists suggested_by uuid references public.accounts (id) on delete set null;
-- Libraries already on CLG's list were added by admins: keep them confirmed.
update public.libraries set confirmed_at = created_at where confirmed_at is null and suggested_by is null;

-- A library an admin adds is confirmed as it is added; one a tutor
-- suggests waits for an admin.
create or replace function private.confirm_admin_library()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.suggested_by is null and new.confirmed_at is null then
    new.confirmed_at := now();
    new.confirmed_by := auth.uid();
  end if;
  return new;
end;
$$;
drop trigger if exists confirm_admin_library on public.libraries;
create trigger confirm_admin_library before insert on public.libraries
  for each row execute function private.confirm_admin_library();

create table if not exists public.library_hours (
  id uuid primary key default gen_random_uuid(),
  library_id uuid not null references public.libraries (id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),
  opens time not null,
  closes time not null,
  check (closes > opens)
);
create index if not exists library_hours_library on public.library_hours (library_id, weekday);

alter table public.library_hours enable row level security;
revoke all on public.library_hours from anon;
drop policy if exists "signed in people see library hours" on public.library_hours;
create policy "signed in people see library hours" on public.library_hours
  for select to authenticated using (true);
drop policy if exists "admins manage library hours" on public.library_hours;
create policy "admins manage library hours" on public.library_hours
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- Is the library open for the whole session on that weekday? A library
-- with no hours added yet counts as open (see the note at the top).
create or replace function private.library_open_weekly(p_library uuid, p_weekday smallint, p_start time, p_minutes integer)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select not exists (select 1 from public.library_hours h where h.library_id = p_library)
      or exists (
        select 1 from public.library_hours h
        where h.library_id = p_library and h.weekday = p_weekday
          and h.opens <= p_start
          and h.closes >= p_start + make_interval(mins => p_minutes)
          and p_start + make_interval(mins => p_minutes) > p_start
      )
$$;
revoke all on function private.library_open_weekly(uuid, smallint, time, integer) from public;

create or replace function private.library_open(p_library uuid, p_date date, p_start time, p_minutes integer)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.libraries l where l.id = p_library and l.active and l.confirmed_at is not null)
     and private.library_open_weekly(p_library, extract(isodow from p_date)::smallint, p_start, p_minutes)
$$;
revoke all on function private.library_open(uuid, date, time, integer) from public;

-- A tutor suggests a library that isn't on the list. It is added for them
-- (unconfirmed) and CLG's admins are asked to confirm it and add hours.
create or replace function public.suggest_library(p_name text, p_suburb text default null)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_state public.au_state;
begin
  if not (private.has_role('tutor') and private.has_aal2()) and not private.is_admin() then
    raise exception 'Only tutors can suggest a library' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) < 3 then
    raise exception 'Enter the library''s name' using errcode = '22023';
  end if;
  select coalesce(w.work_state, 'SA') into v_state from public.tutor_work_settings w where w.tutor_id = auth.uid();
  v_state := coalesce(v_state, 'SA');
  select l.id into v_id from public.libraries l where lower(l.name) = lower(btrim(p_name)) and l.state = v_state;
  if v_id is null then
    insert into public.libraries (name, suburb, state, suggested_by)
    values (left(btrim(p_name), 200), nullif(left(btrim(p_suburb), 100), ''), v_state, auth.uid())
    returning id into v_id;
    perform private.notify_admins('Library to confirm',
      btrim(p_name) || coalesce(' (' || nullif(btrim(p_suburb), '') || ')', '')
      || ' was suggested by a tutor. Please confirm it and add its opening hours under Schedule > Libraries.');
  end if;
  if exists (select 1 from public.tutor_profiles tp where tp.account_id = auth.uid()) then
    insert into public.tutor_places (tutor_id, library_id) values (auth.uid(), v_id) on conflict do nothing;
  end if;
  return v_id;
end;
$$;
revoke all on function public.suggest_library(text, text) from public, anon;
grant execute on function public.suggest_library(text, text) to authenticated;

-- An admin confirms a library. Hours must be added first.
create or replace function public.confirm_library(p_library uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins confirm libraries' using errcode = '42501';
  end if;
  if not exists (select 1 from public.library_hours h where h.library_id = p_library) then
    raise exception 'Add the library''s opening hours first' using errcode = '22023';
  end if;
  update public.libraries set confirmed_at = now(), confirmed_by = auth.uid()
  where id = p_library and confirmed_at is null;
end;
$$;
revoke all on function public.confirm_library(uuid) from public, anon;
grant execute on function public.confirm_library(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Finding times: skip blocked pairs; libraries must be confirmed and open
-- ---------------------------------------------------------------------------
-- Edited in place (the function is long and other files may have changed
-- it), only where the old text is still there.
do $$
declare
  v_def text;
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time)'::regprocedure);
  if strpos(v_def, 'private.blocked_pair') = 0 then
    v_def := replace(v_def,
      'and private.tutor_teaches(t.account_id, p_subject, v_level)',
      'and private.tutor_teaches(t.account_id, p_subject, v_level)
      and not private.blocked_pair(t.account_id, p_student)');
    v_def := replace(v_def,
      'join public.libraries l on l.id = tp.library_id and l.active',
      'join public.libraries l on l.id = tp.library_id and l.active and l.confirmed_at is not null');
    v_def := replace(v_def,
      'where tu.can_in_person and tp.library_id = any (coalesce(p_libraries, ''{}''))',
      'where tu.can_in_person and tp.library_id = any (coalesce(p_libraries, ''{}''))
      and private.library_open_weekly(tp.library_id, s.weekday, s.st, p_minutes)');
    if strpos(v_def, 'private.blocked_pair') = 0 or strpos(v_def, 'library_open_weekly') = 0 then
      raise exception 'find_session_times has changed; update this migration';
    end if;
    execute v_def;
  end if;

  -- The admin's assign list skips blocked pairs too.
  v_def := pg_catalog.pg_get_functiondef('public.eligible_tutors(uuid)'::regprocedure);
  if strpos(v_def, 'private.blocked_pair') = 0 then
    v_def := replace(v_def,
      'where private.tutor_cleared_for_student(t.account_id, p_student)',
      'where private.tutor_cleared_for_student(t.account_id, p_student)
      and not private.blocked_pair(t.account_id, p_student)');
    if strpos(v_def, 'private.blocked_pair') = 0 then
      raise exception 'eligible_tutors has changed; update this migration';
    end if;
    execute v_def;
  end if;

  -- Booking: home or school sessions are CLG only, and they skip the
  -- place check but not the tutor's checks or blocks.
  v_def := pg_catalog.pg_get_functiondef(
    'public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text)'::regprocedure);
  if strpos(v_def, '''school''') = 0 then
    v_def := replace(v_def,
      'if p_delivery = ''home'' and not private.is_front_desk() then
    raise exception ''Sessions are online or at a library. Please contact CLG about home sessions.''',
      'if p_delivery in (''home'', ''school'') and not private.is_front_desk() then
    raise exception ''Sessions are online or at a library. Sessions at home or at school are only arranged by CLG in special circumstances.''');
    v_def := replace(v_def,
      'if p_delivery = ''home'' then
    if not (private.tutor_cleared_for_student(p_tutor, p_student)',
      'if p_delivery in (''home'', ''school'') then
    if private.blocked_pair(p_tutor, p_student) then
      raise exception ''This tutor can''''t be matched with this student. Please choose another.'' using errcode = ''23514'';
    end if;
    if not (private.tutor_cleared_for_student(p_tutor, p_student)');
    if strpos(v_def, 'Sessions at home or at school') = 0 or strpos(v_def, 'blocked_pair') = 0 then
      raise exception 'request_booking has changed; update this migration';
    end if;
    execute v_def;
  end if;
end;
$$;
