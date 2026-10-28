-- Progress tracking, part 2 (module: progress). Finishes phase 1 of the
-- research brief (docs/features/progress-tracking.md):
--   * a session note can be written for a booked session, so the date and
--     length fill in by themselves and the app knows which sessions still
--     need a note
--   * "one thing to try at home" for parents (EEF parental engagement:
--     practical tips on habits, not re-teaching)
--   * the family gets an update in the app after each note (8pm to 8am
--     updates wait until 8am)
--   * the tutor is reminded 24 hr after a session with no note; admins are
--     told at 48 hr
--   * lists for tutors (their caseload) and admins (oversight): notes due,
--     students with no goals, students whose skills haven't moved in 4 or
--     more sessions, and the measures the brief names
--   * how long each note took to write, seen only by admins (the pilot's
--     gate is "notes under 3 minutes")
--
-- This module reads sessions (owned by scheduling) but never writes them.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- New columns on session notes
-- ---------------------------------------------------------------------------
alter table public.session_notes
  add column if not exists session_id uuid references public.sessions (id) on delete set null;
alter table public.session_notes
  add column if not exists home_tip text check (char_length(home_tip) <= 300);
-- One note per booked session.
create unique index if not exists session_notes_once_per_session
  on public.session_notes (session_id) where session_id is not null;

-- Tutors may still correct the tip within 7 days, like the rest of the note.
grant update (home_tip) on public.session_notes to authenticated;

-- How long the note took to write. Admins only: it measures the form, not
-- the tutor, and families have no need to see it.
create table if not exists public.session_note_stats (
  note_id uuid primary key references public.session_notes (id) on delete cascade,
  writing_seconds integer check (writing_seconds between 0 and 7200)
);
alter table public.session_note_stats enable row level security;
revoke all on public.session_note_stats from anon;
revoke insert, update, delete, truncate on public.session_note_stats from authenticated;
drop policy if exists "admins read note stats" on public.session_note_stats;
create policy "admins read note stats" on public.session_note_stats
  for select to authenticated using (private.is_admin());

-- ---------------------------------------------------------------------------
-- Progress notices: updates to families, reminders to tutors and admins.
-- Shown in the app now; email reads email_sent_at once email is set up.
-- ---------------------------------------------------------------------------
create table if not exists public.progress_notices (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  note_id uuid references public.session_notes (id) on delete cascade,
  session_id uuid references public.sessions (id) on delete cascade,
  kind text not null check (kind in ('session_update', 'note_reminder', 'note_overdue')),
  title text not null check (char_length(title) <= 200),
  body text not null check (char_length(body) <= 1000),
  deliver_at timestamptz not null,
  read_at timestamptz,
  email_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists progress_notices_account on public.progress_notices (account_id, deliver_at desc);
-- Each update or reminder goes to each person once.
create unique index if not exists progress_notices_note_once
  on public.progress_notices (account_id, note_id, kind) where note_id is not null;
create unique index if not exists progress_notices_session_once
  on public.progress_notices (account_id, session_id, kind) where session_id is not null;

alter table public.progress_notices enable row level security;
revoke all on public.progress_notices from anon;
revoke insert, update, delete, truncate on public.progress_notices from authenticated;
drop policy if exists "own delivered progress notices" on public.progress_notices;
create policy "own delivered progress notices" on public.progress_notices
  for select to authenticated using (account_id = auth.uid() and deliver_at <= now());

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- A session's date where the student lives.
create or replace function private.session_local_date(p_starts timestamptz, p_student uuid)
returns date language sql stable security definer
set search_path = ''
as $$
  select (p_starts at time zone coalesce(
    private.state_timezone((select state from public.students where id = p_student)),
    'Australia/Adelaide'))::date
$$;

-- When the note for a session was written, or null if there isn't one yet.
-- Notes written before this change weren't linked to a session, so a note
-- for the same student, tutor and day also counts.
create or replace function private.session_note_written_at(p_session uuid)
returns timestamptz language sql stable security definer
set search_path = ''
as $$
  select min(n.created_at)
  from public.sessions se
  join public.session_notes n
    on n.session_id = se.id
    or (n.session_id is null and n.student_id = se.student_id and n.tutor_id = se.tutor_id
        and n.session_date = private.session_local_date(se.starts_at, se.student_id))
  where se.id = p_session
$$;

-- Does this session need a note? It happened (marked done, or booked and
-- now over) and isn't a no-show or cancelled.
create or replace function private.session_needs_note(p_status public.session_status, p_ends timestamptz)
returns boolean language sql stable
set search_path = ''
as $$ select p_ends <= now() and p_status in ('completed', 'scheduled') $$;

create or replace function private.first_name(p_full text)
returns text language sql immutable
set search_path = ''
as $$ select split_part(btrim(p_full), ' ', 1) $$;

-- ---------------------------------------------------------------------------
-- Saving a session note (replaces the first version)
-- ---------------------------------------------------------------------------
-- New: p_session links the note to a booked session (its date then comes
-- from the session), p_home_tip is the one thing to try at home, and
-- p_writing_seconds is how long the form was open. The family gets an
-- update in the app.
drop function if exists public.save_session_note(uuid, date, integer, public.attendance, text, text, text, date, text, jsonb);

create or replace function public.save_session_note(
  p_student uuid,
  p_session_date date,
  p_minutes integer,
  p_attendance public.attendance,
  p_went_well text,
  p_next_step text,
  p_homework text default null,
  p_homework_due date default null,
  p_staff_note text default null,
  p_skills jsonb default '[]',
  p_session uuid default null,
  p_home_tip text default null,
  p_writing_seconds integer default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_tutor uuid;
  v_note uuid;
  v_item jsonb;
  v_skill uuid;
  v_new public.skill_level;
  v_old public.skill_level;
  v_date date := p_session_date;
  v_s public.sessions;
  v_name text;
  v_body text;
begin
  if private.is_tutor_of(p_student) then
    v_tutor := auth.uid();
  elsif not private.is_admin() then
    raise exception 'Only this student''s tutor can write a session note' using errcode = '42501';
  end if;

  if p_session is not null then
    select * into v_s from public.sessions where id = p_session;
    if v_s.id is null or v_s.student_id <> p_student
       or (v_tutor is not null and v_s.tutor_id <> v_tutor and not private.is_admin()) then
      raise exception 'That session isn''t one of yours with this student' using errcode = '42501';
    end if;
    if v_s.status = 'cancelled' then
      raise exception 'That session was cancelled, so it doesn''t need a note' using errcode = '22023';
    end if;
    if v_s.starts_at > now() then
      raise exception 'That session hasn''t started yet' using errcode = '22023';
    end if;
    if exists (select 1 from public.session_notes where session_id = p_session) then
      raise exception 'That session already has a note. You can correct it for 7 days.' using errcode = '23514';
    end if;
    v_date := private.session_local_date(v_s.starts_at, p_student);
    -- An admin writing a note for a tutor's session records it as the tutor's.
    v_tutor := v_s.tutor_id;
  end if;

  -- Dates are Adelaide dates: the database clock runs on UTC, which is
  -- still "yesterday" on Adelaide mornings.
  if v_date > (now() at time zone 'Australia/Adelaide')::date
     or v_date < (now() at time zone 'Australia/Adelaide')::date - 30 then
    raise exception 'The session date must be in the last 30 days' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_skills, '[]')) <> 'array' then
    raise exception 'Skills must be a list' using errcode = '22023';
  end if;

  insert into public.session_notes
    (student_id, tutor_id, session_date, minutes, attendance, went_well, next_step, homework, homework_due,
     session_id, home_tip)
  values
    (p_student, v_tutor, v_date, p_minutes, p_attendance,
     nullif(btrim(p_went_well), ''), nullif(btrim(p_next_step), ''),
     nullif(btrim(p_homework), ''), p_homework_due,
     p_session, nullif(btrim(p_home_tip), ''))
  returning id into v_note;

  if nullif(btrim(p_staff_note), '') is not null then
    insert into public.session_staff_notes (note_id, body, written_by)
    values (v_note, btrim(p_staff_note), auth.uid());
  end if;

  if p_writing_seconds is not null then
    insert into public.session_note_stats (note_id, writing_seconds)
    values (v_note, least(greatest(p_writing_seconds, 0), 7200));
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_skills, '[]')) loop
    v_skill := (v_item ->> 'skill_id')::uuid;
    v_new := (v_item ->> 'level')::public.skill_level;

    if not exists (
      select 1 from public.goal_skills gs
      join public.learning_goals g on g.id = gs.goal_id
      where gs.skill_id = v_skill and g.student_id = p_student and g.status = 'active'
    ) then
      raise exception 'A skill in this note is not part of the student''s current goals' using errcode = '23514';
    end if;

    select level into v_old from public.student_skill_levels
    where student_id = p_student and skill_id = v_skill;
    v_old := coalesce(v_old, 'not_started');

    if abs(private.level_rank(v_new) - private.level_rank(v_old)) > 1 then
      raise exception 'A skill can move only one step per session' using errcode = '23514';
    end if;

    insert into public.session_note_skills (note_id, skill_id, level_before, level_after)
    values (v_note, v_skill, v_old, v_new);

    insert into public.student_skill_levels (student_id, skill_id, level, updated_by, updated_at)
    values (p_student, v_skill, v_new, auth.uid(), now())
    on conflict (student_id, skill_id)
    do update set level = excluded.level, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end loop;

  -- The family's update: what went well, the next step, and the tip.
  if p_attendance <> 'absent' then
    select private.first_name(full_name) into v_name from public.students where id = p_student;
    v_body := 'Next step: ' || coalesce(nullif(btrim(p_next_step), ''), '-');
    if nullif(btrim(p_home_tip), '') is not null then
      v_body := v_body || E'\nTry at home: ' || btrim(p_home_tip);
    end if;
    insert into public.progress_notices (account_id, student_id, note_id, kind, title, body, deliver_at)
    select p.account_id, p_student, v_note, 'session_update',
           left('New session note for ' || coalesce(v_name, 'your child'), 200),
           left(v_body, 1000),
           private.outside_quiet_hours(now())
    from (
      select l.parent_id as account_id from public.parent_student_links l where l.student_id = p_student
      union
      select s.account_id from public.students s where s.id = p_student and s.account_id is not null
    ) p
    where p.account_id is distinct from auth.uid()
    on conflict do nothing;
  end if;

  return v_note;
end;
$$;
revoke execute on function public.save_session_note(uuid, date, integer, public.attendance, text, text, text, date, text, jsonb, uuid, text, integer) from public, anon;
grant execute on function public.save_session_note(uuid, date, integer, public.attendance, text, text, text, date, text, jsonb, uuid, text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Reminders: every hour. Tutor at 24 hr, admins at 48 hr.
-- ---------------------------------------------------------------------------
-- Only sessions from the last 7 days, so a missed week doesn't flood
-- anyone; older gaps still show in the admin lists.
create or replace function private.queue_note_reminders()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  insert into public.progress_notices (account_id, student_id, session_id, kind, title, body, deliver_at)
  select se.tutor_id, se.student_id, se.id, 'note_reminder',
         'Session note due',
         left(format('Please write the note for %s''s session on %s. Notes are due within 24 hr.',
                     st.full_name, private.when_text(se.starts_at)), 1000),
         private.outside_quiet_hours(now())
  from public.sessions se
  join public.students st on st.id = se.student_id
  where private.session_needs_note(se.status, se.ends_at)
    and se.ends_at <= now() - interval '24 hours'
    and se.ends_at > now() - interval '7 days'
    and private.session_note_written_at(se.id) is null
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  insert into public.progress_notices (account_id, student_id, session_id, kind, title, body, deliver_at)
  select r.account_id, se.student_id, se.id, 'note_overdue',
         'Session note overdue',
         left(format('%s hasn''t written the note for %s''s session on %s (48 hr or more).',
                     coalesce(a.full_name, 'The tutor'), st.full_name, private.when_text(se.starts_at)), 1000),
         private.outside_quiet_hours(now())
  from public.sessions se
  join public.students st on st.id = se.student_id
  left join public.accounts a on a.id = se.tutor_id
  cross join (select distinct account_id from public.account_roles where role = 'admin') r
  where private.session_needs_note(se.status, se.ends_at)
    and se.ends_at <= now() - interval '48 hours'
    and se.ends_at > now() - interval '7 days'
    and private.session_note_written_at(se.id) is null
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke all on function private.queue_note_reminders() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-note-reminders', '10 * * * *', 'select private.queue_note_reminders()')
    $job$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- For the screens
-- ---------------------------------------------------------------------------

-- Notices read: all of mine, or only those about one student.
create or replace function public.mark_progress_notices_read(p_student uuid default null)
returns void language sql security definer
set search_path = ''
as $$
  update public.progress_notices set read_at = now()
  where account_id = auth.uid() and read_at is null and deliver_at <= now()
    and (p_student is null or student_id = p_student)
$$;
revoke all on function public.mark_progress_notices_read(uuid) from public, anon;
grant execute on function public.mark_progress_notices_read(uuid) to authenticated;

-- Sessions from the last 30 days that still need a note. A tutor sees
-- their own; an admin sees everyone's.
create or replace function public.list_notes_due()
returns table (
  session_id uuid, student_id uuid, student_name text, tutor_id uuid, tutor_name text,
  subject text, starts_at timestamptz, ends_at timestamptz, minutes integer, hours_since_end integer
)
language sql stable security definer
set search_path = ''
as $$
  select se.id, se.student_id, st.full_name, se.tutor_id, a.full_name,
         se.subject, se.starts_at, se.ends_at,
         (extract(epoch from se.ends_at - se.starts_at) / 60)::integer,
         floor(extract(epoch from now() - se.ends_at) / 3600)::integer
  from public.sessions se
  join public.students st on st.id = se.student_id
  left join public.accounts a on a.id = se.tutor_id
  where private.session_needs_note(se.status, se.ends_at)
    and se.ends_at > now() - interval '30 days'
    and (private.is_admin()
         or (se.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2()))
    and private.session_note_written_at(se.id) is null
  order by se.ends_at
$$;
revoke all on function public.list_notes_due() from public, anon;
grant execute on function public.list_notes_due() to authenticated;

-- Students worth a look: a tutor's own current students, or (for admins)
-- every student with a current tutor. "Notes since movement" counts the
-- sessions attended since a skill last changed level; 4 or more means the
-- plan may need a change.
create or replace function public.progress_students_to_check()
returns table (
  student_id uuid, student_name text, year_level text, tutor_names text,
  active_goals integer, last_note_on date, notes_since_movement integer, notes_due integer
)
language sql stable security definer
set search_path = ''
as $$
  with mine as (
    select st.id, st.full_name, st.year_level::text as year_level
    from public.students st
    where (private.is_admin() and exists (
             select 1 from public.tutor_assignments ta
             where ta.student_id = st.id and private.assignment_is_current(ta.starts_on, ta.ends_on)))
       or private.is_tutor_of(st.id)
  ),
  last_move as (
    select n.student_id, max(n.created_at) as at
    from public.session_notes n
    where exists (select 1 from public.session_note_skills k
                  where k.note_id = n.id and k.level_before <> k.level_after)
    group by n.student_id
  )
  select m.id, m.full_name, m.year_level,
    (select string_agg(distinct a.full_name, ', ')
       from public.tutor_assignments ta join public.accounts a on a.id = ta.tutor_id
       where ta.student_id = m.id and private.assignment_is_current(ta.starts_on, ta.ends_on)),
    (select count(*)::integer from public.learning_goals g where g.student_id = m.id and g.status = 'active'),
    (select max(n.session_date) from public.session_notes n where n.student_id = m.id),
    (select count(*)::integer from public.session_notes n
       left join last_move lm on lm.student_id = n.student_id
       where n.student_id = m.id and n.attendance <> 'absent'
         and (lm.at is null or n.created_at > lm.at)),
    (select count(*)::integer from public.sessions se
       where se.student_id = m.id
         and private.session_needs_note(se.status, se.ends_at)
         and se.ends_at > now() - interval '30 days'
         and (private.is_admin() or se.tutor_id = auth.uid())
         and private.session_note_written_at(se.id) is null)
  from mine m
  order by m.full_name
$$;
revoke all on function public.progress_students_to_check() from public, anon;
grant execute on function public.progress_students_to_check() to authenticated;

-- The brief's measures, per tutor, for a date range. Admins only.
create or replace function public.progress_measures(p_from date, p_to date)
returns table (
  tutor_id uuid, tutor_name text,
  sessions_held integer, sessions_noted integer, noted_within_24_hr integer,
  notes integer, notes_with_reflection integer, median_writing_seconds integer, skills_moved_up integer
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can see these measures' using errcode = '42501';
  end if;
  return query
  with held as (
    select se.tutor_id, se.ends_at, private.session_note_written_at(se.id) as noted_at
    from public.sessions se
    where se.status = 'completed'
      and private.session_local_date(se.starts_at, se.student_id) between p_from and p_to
  ),
  written as (
    select n.id, n.tutor_id from public.session_notes n
    where n.session_date between p_from and p_to and n.tutor_id is not null
  ),
  tutors as (
    select h.tutor_id from held h union select w.tutor_id from written w
  )
  select t.tutor_id, a.full_name,
    (select count(*)::integer from held h where h.tutor_id = t.tutor_id),
    (select count(*)::integer from held h where h.tutor_id = t.tutor_id and h.noted_at is not null),
    (select count(*)::integer from held h where h.tutor_id = t.tutor_id and h.noted_at <= h.ends_at + interval '24 hours'),
    (select count(*)::integer from written w where w.tutor_id = t.tutor_id),
    (select count(*)::integer from written w
       where w.tutor_id = t.tutor_id and exists (select 1 from public.student_reflections r where r.note_id = w.id)),
    (select (percentile_cont(0.5) within group (order by s.writing_seconds))::integer
       from written w join public.session_note_stats s on s.note_id = w.id
       where w.tutor_id = t.tutor_id and s.writing_seconds is not null),
    (select count(*)::integer from written w join public.session_note_skills k on k.note_id = w.id
       where w.tutor_id = t.tutor_id and private.level_rank(k.level_after) > private.level_rank(k.level_before))
  from tutors t
  left join public.accounts a on a.id = t.tutor_id
  order by a.full_name;
end;
$$;
revoke all on function public.progress_measures(date, date) from public, anon;
grant execute on function public.progress_measures(date, date) to authenticated;
