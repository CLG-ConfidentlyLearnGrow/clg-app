-- Progress tracking, part 3 (module: progress): learning roadmaps.
-- See docs/features/learning-roadmaps.md.
--
-- A roadmap turns what a student is working towards into small, dated
-- steps they can tick off:
--   * targets: a school assessment (with its due date, the current grade
--     and the grade they are aiming for) or a learning goal
--   * steps: small actions with a date, ticked off by the student (or a
--     parent for a young child); tutors review them each session
--   * each session note's next step becomes a step by itself, due by the
--     next booked session, so the roadmap adds no extra tutor time
--   * "Plan the steps" spreads a study plan across the weeks before an
--     assessment, using spaced and retrieval practice
--   * a reminder the day before a step is due
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.roadmap_targets (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  kind text not null check (kind in ('assessment', 'goal')),
  subject text check (char_length(subject) <= 100),
  -- For example "Term 4 algebra test" or "Read a chapter book on my own".
  title text not null check (char_length(title) between 3 and 200),
  due_on date,
  -- As the school writes them, for example "C" and "B", or "62%" and "75%".
  current_grade text check (char_length(current_grade) <= 20),
  target_grade text check (char_length(target_grade) <= 20),
  learning_goal_id uuid references public.learning_goals (id) on delete set null,
  status text not null default 'open' check (status in ('open', 'done', 'dropped')),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index if not exists roadmap_targets_student on public.roadmap_targets (student_id, status, due_on);

create table if not exists public.roadmap_steps (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  -- Steps without a target are the week's small steps (often a next step).
  target_id uuid references public.roadmap_targets (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 300),
  due_on date,
  -- Who added it: the student, a parent, a tutor, a planned study step, or
  -- a session note's next step.
  source text not null default 'tutor' check (source in ('student', 'parent', 'tutor', 'plan', 'next_step')),
  note_id uuid references public.session_notes (id) on delete set null,
  done_at timestamptz,
  done_by uuid references public.accounts (id) on delete set null,
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists roadmap_steps_student on public.roadmap_steps (student_id, done_at, due_on);
create index if not exists roadmap_steps_target on public.roadmap_steps (target_id);
create unique index if not exists roadmap_steps_once_per_note on public.roadmap_steps (note_id) where note_id is not null;

alter table public.roadmap_targets enable row level security;
alter table public.roadmap_steps enable row level security;
revoke all on public.roadmap_targets, public.roadmap_steps from anon;
revoke truncate on public.roadmap_targets, public.roadmap_steps from authenticated;
-- Targets are closed, not deleted, so the history stays.
revoke delete on public.roadmap_targets from authenticated;
-- Ticking a step goes through tick_roadmap_step.
revoke update on public.roadmap_steps from authenticated;
grant update (title, due_on) on public.roadmap_steps to authenticated;

drop trigger if exists audit on public.roadmap_targets;
create trigger audit after insert or update or delete on public.roadmap_targets
  for each row execute function private.audit_change();
drop trigger if exists audit on public.roadmap_steps;
create trigger audit after insert or update or delete on public.roadmap_steps
  for each row execute function private.audit_change();

-- ---------------------------------------------------------------------------
-- Who may plan: the student's own login, a parent who manages them, their
-- current tutor, or an admin. Anyone who can see the student can read.
-- ---------------------------------------------------------------------------
create or replace function private.can_plan_for(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.is_student_self(p_student)
      or private.can_manage_student(p_student)
      or private.is_tutor_of(p_student)
      or private.is_admin()
$$;

create or replace function private.planner_source(p_student uuid)
returns text language sql stable security definer
set search_path = ''
as $$
  select case
    when private.is_student_self(p_student) then 'student'
    when private.is_tutor_of(p_student) or private.is_admin() then 'tutor'
    else 'parent'
  end
$$;

drop policy if exists "see roadmap targets" on public.roadmap_targets;
create policy "see roadmap targets" on public.roadmap_targets
  for select to authenticated using (private.can_view_student(student_id));
drop policy if exists "plan roadmap targets" on public.roadmap_targets;
create policy "plan roadmap targets" on public.roadmap_targets
  for insert to authenticated with check (private.can_plan_for(student_id));
drop policy if exists "change roadmap targets" on public.roadmap_targets;
create policy "change roadmap targets" on public.roadmap_targets
  for update to authenticated
  using (private.can_plan_for(student_id)) with check (private.can_plan_for(student_id));

drop policy if exists "see roadmap steps" on public.roadmap_steps;
create policy "see roadmap steps" on public.roadmap_steps
  for select to authenticated using (private.can_view_student(student_id));
drop policy if exists "add roadmap steps" on public.roadmap_steps;
create policy "add roadmap steps" on public.roadmap_steps
  for insert to authenticated with check (private.can_plan_for(student_id));
drop policy if exists "change roadmap steps" on public.roadmap_steps;
create policy "change roadmap steps" on public.roadmap_steps
  for update to authenticated
  using (private.can_plan_for(student_id)) with check (private.can_plan_for(student_id));
-- A step can be removed by whoever added it, or by the tutor or an admin.
drop policy if exists "remove roadmap steps" on public.roadmap_steps;
create policy "remove roadmap steps" on public.roadmap_steps
  for delete to authenticated
  using (created_by = auth.uid() or private.is_tutor_of(student_id) or private.is_admin());

-- ---------------------------------------------------------------------------
-- Guards: stamp who and when; a target's goal and steps belong to the same
-- student; nothing moves to another student.
-- ---------------------------------------------------------------------------
create or replace function private.guard_roadmap_target()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
    new.status := 'open';
    new.closed_at := null;
  else
    if new.student_id is distinct from old.student_id or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
      raise exception 'A roadmap target cannot be moved to another student' using errcode = '42501';
    end if;
    if new.status = 'open' then
      new.closed_at := null;
    elsif old.status = 'open' then
      new.closed_at := now();
    end if;
  end if;
  if new.learning_goal_id is not null
     and (select student_id from public.learning_goals where id = new.learning_goal_id) is distinct from new.student_id then
    raise exception 'That goal belongs to another student' using errcode = '23514';
  end if;
  if new.kind = 'assessment' and new.due_on is null then
    raise exception 'Add the date of the assessment' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists guard on public.roadmap_targets;
create trigger guard before insert or update on public.roadmap_targets
  for each row execute function private.guard_roadmap_target();

create or replace function private.guard_roadmap_step()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Planned steps and next steps are added by the database's own
    -- functions, which say so with the clg.roadmap_system setting. Anything
    -- else is labelled by who is signed in.
    if coalesce(current_setting('clg.roadmap_system', true), '') <> 'on' then
      new.source := private.planner_source(new.student_id);
      new.note_id := null;
      new.created_by := auth.uid();
    end if;
    new.created_at := now();
    new.done_at := null;
    new.done_by := null;
  elsif new.student_id is distinct from old.student_id or new.target_id is distinct from old.target_id
     or new.created_by is distinct from old.created_by or new.source is distinct from old.source
     or new.note_id is distinct from old.note_id then
    raise exception 'A roadmap step cannot be moved' using errcode = '42501';
  end if;
  if new.target_id is not null
     and (select student_id from public.roadmap_targets where id = new.target_id) is distinct from new.student_id then
    raise exception 'That target belongs to another student' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists guard on public.roadmap_steps;
create trigger guard before insert or update on public.roadmap_steps
  for each row execute function private.guard_roadmap_step();

-- ---------------------------------------------------------------------------
-- Ticking a step off (or un-ticking it)
-- ---------------------------------------------------------------------------
create or replace function public.tick_roadmap_step(p_step uuid, p_done boolean default true)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_student uuid;
begin
  select student_id into v_student from public.roadmap_steps where id = p_step;
  if v_student is null or not private.can_plan_for(v_student) then
    raise exception 'Step not found' using errcode = 'P0002';
  end if;
  update public.roadmap_steps
  set done_at = case when p_done then coalesce(done_at, now()) end,
      done_by = case when p_done then coalesce(done_by, auth.uid()) end
  where id = p_step;
end;
$$;
revoke all on function public.tick_roadmap_step(uuid, boolean) from public, anon;
grant execute on function public.tick_roadmap_step(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- A session note's next step becomes a step, due by the next booked session
-- (or a week later if none is booked).
-- ---------------------------------------------------------------------------
create or replace function private.step_from_note()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_due date;
begin
  if new.next_step is null or new.attendance = 'absent' then
    return new;
  end if;
  select min(private.session_local_date(se.starts_at, se.student_id)) into v_due
  from public.sessions se
  where se.student_id = new.student_id and se.status = 'scheduled' and se.starts_at > now();
  perform set_config('clg.roadmap_system', 'on', true);
  insert into public.roadmap_steps (student_id, title, due_on, source, note_id, created_by)
  values (new.student_id, left(new.next_step, 300), coalesce(v_due, new.session_date + 7), 'next_step', new.id, new.tutor_id)
  on conflict do nothing;
  perform set_config('clg.roadmap_system', '', true);
  return new;
end;
$$;
drop trigger if exists roadmap_step on public.session_notes;
create trigger roadmap_step after insert on public.session_notes
  for each row execute function private.step_from_note();

-- The step follows a correction to the next step within the 7 days.
create or replace function private.step_follows_note()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if new.next_step is distinct from old.next_step and new.next_step is not null then
    update public.roadmap_steps set title = left(new.next_step, 300)
    where note_id = new.id and done_at is null;
  end if;
  return new;
end;
$$;
drop trigger if exists roadmap_step_follows on public.session_notes;
create trigger roadmap_step_follows after update of next_step on public.session_notes
  for each row execute function private.step_follows_note();


-- ---------------------------------------------------------------------------
-- "Plan the steps": a study plan spread across the days before an
-- assessment. Spacing practice out and testing yourself (retrieval
-- practice) beat cramming and re-reading. Everyone can edit or remove the
-- steps afterwards.
-- ---------------------------------------------------------------------------
create or replace function public.plan_assessment_steps(p_target uuid)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_t public.roadmap_targets;
  v_today date := (now() at time zone 'Australia/Adelaide')::date;
  v_last date;
  v_titles text[];
  v_n integer;
  v_i integer;
begin
  select * into v_t from public.roadmap_targets where id = p_target;
  if v_t.id is null or not private.can_plan_for(v_t.student_id) then
    raise exception 'Target not found' using errcode = 'P0002';
  end if;
  if v_t.kind <> 'assessment' or v_t.status <> 'open' then
    raise exception 'Steps can be planned for an open assessment only' using errcode = '22023';
  end if;
  if v_t.due_on <= v_today then
    raise exception 'The assessment date has passed' using errcode = '22023';
  end if;
  if exists (select 1 from public.roadmap_steps where target_id = p_target and source = 'plan') then
    raise exception 'Steps are already planned for this. Edit or remove them instead.' using errcode = '23514';
  end if;

  v_last := v_t.due_on - 1;
  if v_last - v_today >= 5 then
    v_titles := array[
      'List what the ' || v_t.title || ' covers, and mark the parts you find hard',
      'Test yourself on the first hard part without notes, then check your answers',
      'Practise the next hard part, mixing in questions from earlier parts',
      'Do a practice test in the time you will have',
      'Fix the mistakes from the practice test, then redo those questions',
      'Quick check: test yourself once more on each part (no cramming tonight)'
    ];
  else
    v_titles := array[
      'Do a practice test in the time you will have',
      'Fix the mistakes from the practice test, then redo those questions',
      'Quick check: test yourself once more on each part (no cramming tonight)'
    ];
  end if;
  v_n := array_length(v_titles, 1);

  perform set_config('clg.roadmap_system', 'on', true);
  for v_i in 1 .. v_n loop
    insert into public.roadmap_steps (student_id, target_id, title, due_on, source, created_by)
    values (
      v_t.student_id, p_target, left(v_titles[v_i], 300),
      v_today + ((v_last - v_today) * (v_i - 1)) / (v_n - 1),
      'plan', auth.uid()
    );
  end loop;
  perform set_config('clg.roadmap_system', '', true);
  return v_n;
end;
$$;
revoke all on function public.plan_assessment_steps(uuid) from public, anon;
grant execute on function public.plan_assessment_steps(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reminders: one notice the afternoon before steps are due, to the student
-- if they have their own login, otherwise to the parents who manage them.
-- ---------------------------------------------------------------------------
alter table public.progress_notices add column if not exists for_date date;
alter table public.progress_notices drop constraint if exists progress_notices_kind_check;
alter table public.progress_notices add constraint progress_notices_kind_check
  check (kind in ('session_update', 'note_reminder', 'note_overdue', 'step_due'));
create unique index if not exists progress_notices_day_once
  on public.progress_notices (account_id, student_id, kind, for_date) where for_date is not null;

create or replace function private.queue_step_reminders()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_tomorrow date := (now() at time zone 'Australia/Adelaide')::date + 1;
  v_count integer;
begin
  insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at, for_date)
  select p.account_id, d.student_id, 'step_due',
         left(case when p.is_self then 'Due tomorrow' else 'Due tomorrow for ' || private.first_name(d.full_name) end, 200),
         left(d.steps, 1000),
         private.outside_quiet_hours(now()),
         v_tomorrow
  from (
    select st.id as student_id, st.full_name, st.account_id,
           string_agg('• ' || rs.title, E'\n' order by rs.created_at) as steps
    from public.roadmap_steps rs
    join public.students st on st.id = rs.student_id
    left join public.roadmap_targets t on t.id = rs.target_id
    where rs.done_at is null and rs.due_on = v_tomorrow
      and (t.id is null or t.status = 'open')
    group by st.id, st.full_name, st.account_id
  ) d
  cross join lateral (
    select d.account_id, true as is_self where d.account_id is not null
    union all
    select l.parent_id, false from public.parent_student_links l
    where l.student_id = d.student_id and l.can_manage and d.account_id is null
  ) p
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.queue_step_reminders() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    -- 05:30 UTC is 4pm in Adelaide in summer (3pm in winter): after school.
    execute $job$
      select cron.schedule('clg-step-reminders', '30 5 * * *', 'select private.queue_step_reminders()')
    $job$;
  end if;
end;
$$;
