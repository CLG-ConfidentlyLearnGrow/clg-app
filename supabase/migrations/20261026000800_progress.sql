-- Progress tracking, first version. Built from the research brief in
-- docs/features/progress-tracking.md:
--   * 1 to 3 goals per subject, each made of curriculum skills
--   * each skill on a four-step scale, set by ability, not year level
--   * a short structured session note that ends in one next step
--   * a short student reflection after each session
--   * staff-only notes kept apart from everything families see
-- Every table hangs off students, so the shared access rules and the
-- automatic deletion apply.

create type public.skill_level as enum ('not_started', 'learning', 'secure_with_help', 'secure_on_own');
create type public.attendance as enum ('attended', 'late', 'absent', 'cut_short');
create type public.goal_status as enum ('active', 'achieved', 'stopped');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.learning_goals (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  -- Written so a parent understands it, for example "Solve two-step
  -- equations without prompts".
  title text not null check (char_length(title) between 3 and 200),
  target_date date,
  status public.goal_status not null default 'active',
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);
create index learning_goals_student on public.learning_goals (student_id, status);

create table public.goal_skills (
  goal_id uuid not null references public.learning_goals (id) on delete cascade,
  skill_id uuid not null references public.curriculum_skills (id) on delete restrict,
  primary key (goal_id, skill_id)
);

-- Where a student is on each skill now. Changed only through a session note
-- (save_session_note), so every change has a dated reason.
create table public.student_skill_levels (
  student_id uuid not null references public.students (id) on delete cascade,
  skill_id uuid not null references public.curriculum_skills (id) on delete restrict,
  level public.skill_level not null default 'not_started',
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (student_id, skill_id)
);

-- The structured note that replaces the Teams summary. "Went well" and
-- "next step" are written to the student and shown to the family as written.
create table public.session_notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  tutor_id uuid references public.tutor_profiles (account_id) on delete set null,
  session_date date not null,
  minutes integer check (minutes between 0 and 480),
  attendance public.attendance not null default 'attended',
  went_well text check (char_length(went_well) <= 1000),
  next_step text check (char_length(next_step) <= 500),
  homework text check (char_length(homework) <= 1000),
  homework_due date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- The evidence says the next step is the part that matters most, so a
  -- session that happened always has one.
  check (attendance = 'absent' or (next_step is not null and went_well is not null))
);
create index session_notes_student on public.session_notes (student_id, session_date desc);
create index session_notes_tutor on public.session_notes (tutor_id, session_date desc);

-- Skills worked on in a session, with the level before and after.
create table public.session_note_skills (
  note_id uuid not null references public.session_notes (id) on delete cascade,
  skill_id uuid not null references public.curriculum_skills (id) on delete restrict,
  level_before public.skill_level not null,
  level_after public.skill_level not null,
  primary key (note_id, skill_id)
);

-- For CLG staff only: never shown to the student or family.
create table public.session_staff_notes (
  note_id uuid primary key references public.session_notes (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  written_by uuid references public.accounts (id) on delete set null,
  written_at timestamptz not null default now()
);

-- The student's own reflection (or a parent's, for a young child).
create table public.student_reflections (
  note_id uuid primary key references public.session_notes (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  -- 1 = not confident yet, 4 = very confident.
  confidence smallint not null check (confidence between 1 and 4),
  what_was_hard text check (char_length(what_was_hard) <= 500),
  what_i_will_try text check (char_length(what_i_will_try) <= 500),
  written_by uuid references public.accounts (id) on delete set null,
  written_at timestamptz not null default now()
);

alter table public.learning_goals enable row level security;
alter table public.goal_skills enable row level security;
alter table public.student_skill_levels enable row level security;
alter table public.session_notes enable row level security;
alter table public.session_note_skills enable row level security;
alter table public.session_staff_notes enable row level security;
alter table public.student_reflections enable row level security;
revoke all on public.learning_goals, public.goal_skills, public.student_skill_levels,
  public.session_notes, public.session_note_skills, public.session_staff_notes,
  public.student_reflections from anon;

create trigger audit after insert or update or delete on public.learning_goals
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.goal_skills
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.student_skill_levels
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.session_notes
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.session_staff_notes
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.student_reflections
  for each row execute function private.audit_change();
create trigger touch before update on public.session_notes
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

-- At most 3 active goals per subject, so the focus stays clear. Who created
-- a goal is stamped, and closing one records when.
create function private.guard_goal()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
  elsif new.student_id is distinct from old.student_id
     or new.created_by is distinct from old.created_by then
    raise exception 'A goal cannot be moved to another student' using errcode = '42501';
  end if;

  if new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active' or new.subject <> old.subject) then
    if (select count(*) from public.learning_goals
        where student_id = new.student_id and subject = new.subject
          and status = 'active' and id <> new.id) >= 3 then
      raise exception 'This student already has 3 active goals in %. Close one first.', new.subject
        using errcode = '23514';
    end if;
  end if;

  if new.status = 'active' then
    new.closed_at := null;
  elsif tg_op = 'INSERT' or old.status = 'active' then
    new.closed_at := now();
  end if;
  return new;
end;
$$;
create trigger guard before insert or update on public.learning_goals
  for each row execute function private.guard_goal();

-- Families can't edit a tutor's note; tutors can correct their own note for
-- 7 days, but not move it to another student or tutor.
create function private.guard_session_note()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.student_id is distinct from old.student_id
     or new.tutor_id is distinct from old.tutor_id
     or new.created_at is distinct from old.created_at then
    raise exception 'A session note cannot be moved' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger guard before update on public.session_notes
  for each row execute function private.guard_session_note();

create function private.stamp_reflection()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.written_by := auth.uid();
  new.written_at := now();
  if new.student_id is distinct from (select student_id from public.session_notes where id = new.note_id) then
    raise exception 'That reflection belongs to another student' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger stamp before insert or update on public.student_reflections
  for each row execute function private.stamp_reflection();

create function private.note_student(p_note uuid)
returns uuid language sql stable security definer
set search_path = ''
as $$ select student_id from public.session_notes where id = p_note $$;

create function private.goal_student(p_goal uuid)
returns uuid language sql stable security definer
set search_path = ''
as $$ select student_id from public.learning_goals where id = p_goal $$;

-- ---------------------------------------------------------------------------
-- Access rules
-- ---------------------------------------------------------------------------

-- Goals: everyone who can see the student sees them; their tutors and
-- admins write them.
create policy "see goals" on public.learning_goals
  for select to authenticated using (private.can_view_student(student_id));
create policy "tutors and admins add goals" on public.learning_goals
  for insert to authenticated
  with check (private.is_tutor_of(student_id) or private.is_admin());
create policy "tutors and admins update goals" on public.learning_goals
  for update to authenticated
  using (private.is_tutor_of(student_id) or private.is_admin())
  with check (private.is_tutor_of(student_id) or private.is_admin());
revoke delete, truncate on public.learning_goals from authenticated;

create policy "see goal skills" on public.goal_skills
  for select to authenticated using (private.can_view_student(private.goal_student(goal_id)));
create policy "tutors and admins add goal skills" on public.goal_skills
  for insert to authenticated
  with check (private.is_tutor_of(private.goal_student(goal_id)) or private.is_admin());
create policy "tutors and admins remove goal skills" on public.goal_skills
  for delete to authenticated
  using (private.is_tutor_of(private.goal_student(goal_id)) or private.is_admin());

-- Skill levels: read by anyone who can see the student; written only by
-- save_session_note.
create policy "see skill levels" on public.student_skill_levels
  for select to authenticated using (private.can_view_student(student_id));
revoke insert, update, delete, truncate on public.student_skill_levels from authenticated;

-- Session notes: families read them; written through save_session_note;
-- the tutor who wrote one may correct it for 7 days.
create policy "see session notes" on public.session_notes
  for select to authenticated using (private.can_view_student(student_id));
create policy "tutor corrects own recent note" on public.session_notes
  for update to authenticated
  using (
    (tutor_id = auth.uid() and private.is_tutor_of(student_id) and created_at > now() - interval '7 days')
    or private.is_admin()
  )
  with check (
    (tutor_id = auth.uid() and private.is_tutor_of(student_id))
    or private.is_admin()
  );
revoke insert, delete, truncate on public.session_notes from authenticated;
revoke update on public.session_notes from authenticated;
grant update (minutes, attendance, went_well, next_step, homework, homework_due)
  on public.session_notes to authenticated;

create policy "see note skills" on public.session_note_skills
  for select to authenticated using (private.can_view_student(private.note_student(note_id)));
revoke insert, update, delete, truncate on public.session_note_skills from authenticated;

-- Staff notes: the student's current tutors and admins only. Never families.
create policy "staff read staff notes" on public.session_staff_notes
  for select to authenticated
  using (private.is_tutor_of(private.note_student(note_id)) or private.is_admin());
revoke insert, update, delete, truncate on public.session_staff_notes from authenticated;

-- Reflections: written by the student or a parent who manages them, read by
-- anyone who can see the student.
create policy "see reflections" on public.student_reflections
  for select to authenticated using (private.can_view_student(student_id));
create policy "student or parent writes reflection" on public.student_reflections
  for insert to authenticated
  with check (private.is_student_self(student_id) or private.can_manage_student(student_id));
create policy "student or parent edits reflection" on public.student_reflections
  for update to authenticated
  using (written_by = auth.uid())
  with check (private.is_student_self(student_id) or private.can_manage_student(student_id));
revoke delete, truncate on public.student_reflections from authenticated;

-- ---------------------------------------------------------------------------
-- Saving a session note
-- ---------------------------------------------------------------------------

create function private.level_rank(p public.skill_level)
returns integer language sql immutable
set search_path = ''
as $$ select array_position(enum_range(null::public.skill_level), p) $$;

-- Saves the note, the staff note and the skills worked on in one step.
-- p_skills is a list like [{"skill_id": "...", "level": "learning"}].
-- Each skill must belong to one of the student's active goals, and can move
-- at most one step up or down per session.
create function public.save_session_note(
  p_student uuid,
  p_session_date date,
  p_minutes integer,
  p_attendance public.attendance,
  p_went_well text,
  p_next_step text,
  p_homework text default null,
  p_homework_due date default null,
  p_staff_note text default null,
  p_skills jsonb default '[]'
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
begin
  if private.is_tutor_of(p_student) then
    v_tutor := auth.uid();
  elsif not private.is_admin() then
    raise exception 'Only this student''s tutor can write a session note' using errcode = '42501';
  end if;
  if p_session_date > current_date or p_session_date < current_date - 30 then
    raise exception 'The session date must be in the last 30 days' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_skills, '[]')) <> 'array' then
    raise exception 'Skills must be a list' using errcode = '22023';
  end if;

  insert into public.session_notes
    (student_id, tutor_id, session_date, minutes, attendance, went_well, next_step, homework, homework_due)
  values
    (p_student, v_tutor, p_session_date, p_minutes, p_attendance,
     nullif(btrim(p_went_well), ''), nullif(btrim(p_next_step), ''),
     nullif(btrim(p_homework), ''), p_homework_due)
  returning id into v_note;

  if nullif(btrim(p_staff_note), '') is not null then
    insert into public.session_staff_notes (note_id, body, written_by)
    values (v_note, btrim(p_staff_note), auth.uid());
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

  return v_note;
end;
$$;
revoke execute on function public.save_session_note(uuid, date, integer, public.attendance, text, text, text, date, text, jsonb) from public, anon;
grant execute on function public.save_session_note(uuid, date, integer, public.attendance, text, text, text, date, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Automatic deletion: a session counts as activity.
-- ---------------------------------------------------------------------------

create or replace function private.student_last_activity(p_student uuid)
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
     from public.enrolments e where e.student_id = s.id),
    (select max(n.session_date)::timestamptz from public.session_notes n where n.student_id = s.id)
  )
  from public.students s where s.id = p_student
$$;
