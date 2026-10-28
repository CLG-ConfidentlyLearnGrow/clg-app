-- Progress tracking, part 4 (module: progress): term reviews and the
-- monthly summary. See docs/features/term-reviews.md.
--
-- Term review: three weeks before a school term ends, each tutor gets a
-- review to write for each current student: how the term went against the
-- goals, the focus for next term, and a recommendation. An admin checks it,
-- then the family sees it and can reply or ask for a call. It sits beside
-- the "same again next term?" question scheduling already asks.
--
-- Monthly summary: on the 1st of each month, families get a short summary
-- in the app, written by the app from last month's notes (no tutor time).
--
-- Reads school_terms and sessions (scheduling) but never writes them.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Term reviews
-- ---------------------------------------------------------------------------
create table if not exists public.term_reviews (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  tutor_id uuid references public.tutor_profiles (account_id) on delete set null,
  -- For example "Term 4 2026".
  term_label text not null check (char_length(term_label) <= 50),
  term_starts_on date not null,
  term_ends_on date not null,
  -- Written to the family: how the term went against the goals.
  summary text check (char_length(summary) <= 2000),
  -- The goals or focus for next term.
  next_focus text check (char_length(next_focus) <= 1000),
  recommendation text check (recommendation in ('continue', 'change_focus', 'more_sessions', 'fewer_sessions', 'break')),
  recommendation_note text check (char_length(recommendation_note) <= 500),
  status text not null default 'draft' check (status in ('draft', 'submitted', 'returned', 'approved')),
  submitted_at timestamptz,
  returned_reason text check (char_length(returned_reason) <= 500),
  approved_by uuid references public.accounts (id) on delete set null,
  approved_at timestamptz,
  family_reply text check (char_length(family_reply) <= 2000),
  wants_call boolean not null default false,
  family_replied_by uuid references public.accounts (id) on delete set null,
  family_replied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('draft', 'returned') or (summary is not null and next_focus is not null and recommendation is not null))
);
create unique index if not exists term_reviews_once on public.term_reviews (student_id, tutor_id, term_ends_on);
create index if not exists term_reviews_tutor on public.term_reviews (tutor_id, status);

alter table public.term_reviews enable row level security;
revoke all on public.term_reviews from anon;
-- Every change goes through the functions below.
revoke insert, update, delete, truncate on public.term_reviews from authenticated;

drop trigger if exists audit on public.term_reviews;
create trigger audit after insert or update or delete on public.term_reviews
  for each row execute function private.audit_change();
drop trigger if exists touch on public.term_reviews;
create trigger touch before update on public.term_reviews
  for each row execute function private.touch_updated_at();

-- Families see a review once CLG has checked it. The tutor who writes it
-- (while they still teach the student) and admins see it at every stage.
drop policy if exists "see term reviews" on public.term_reviews;
create policy "see term reviews" on public.term_reviews
  for select to authenticated using (
    private.is_admin()
    or (tutor_id = auth.uid() and private.is_tutor_of(student_id))
    or (status = 'approved' and (private.is_parent_of(student_id) or private.is_student_self(student_id)))
  );

-- progress_notices learns the new kinds, and can point at a review.
alter table public.progress_notices add column if not exists review_id uuid references public.term_reviews (id) on delete cascade;
alter table public.progress_notices drop constraint if exists progress_notices_kind_check;
alter table public.progress_notices add constraint progress_notices_kind_check
  check (kind in ('session_update', 'note_reminder', 'note_overdue', 'step_due',
                  'review_due', 'review_to_check', 'review_returned', 'review_ready', 'review_reply',
                  'monthly_summary'));
create unique index if not exists progress_notices_review_once
  on public.progress_notices (account_id, review_id, kind) where review_id is not null and kind not in ('review_returned', 'review_reply');

-- ---------------------------------------------------------------------------
-- Making the reviews: daily, three weeks before the term ends.
-- ---------------------------------------------------------------------------
create or replace function private.queue_term_reviews()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Australia/Adelaide')::date;
  v_count integer;
begin
  with due as (
    select st.id as student_id, ta.tutor_id, t.term, t.year, t.starts_on, t.ends_on
    from public.students st
    join public.school_terms t on t.state = st.state
      and t.ends_on between v_today and v_today + 21
    join public.tutor_assignments ta on ta.student_id = st.id
      and private.assignment_is_current(ta.starts_on, ta.ends_on)
    -- Only students who had a session note this term.
    where exists (select 1 from public.session_notes n
                  where n.student_id = st.id and n.tutor_id = ta.tutor_id
                    and n.session_date between t.starts_on and t.ends_on)
  ),
  made as (
    insert into public.term_reviews (student_id, tutor_id, term_label, term_starts_on, term_ends_on)
    select distinct d.student_id, d.tutor_id, 'Term ' || d.term || ' ' || d.year, d.starts_on, d.ends_on
    from due d
    on conflict do nothing
    returning id, student_id, tutor_id, term_label, term_ends_on
  )
  insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at)
  select m.tutor_id, m.student_id, m.id, 'review_due',
         left('Term review to write: ' || st.full_name, 200),
         left(format('Please write %s''s %s review by %s, so CLG can check it before the term ends.',
                     st.full_name, m.term_label, to_char(m.term_ends_on - 14, 'FMDD Mon')), 1000),
         private.outside_quiet_hours(now())
  from made m join public.students st on st.id = m.student_id
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.queue_term_reviews() from public;

-- ---------------------------------------------------------------------------
-- What the review covers: each active goal, with its skills at the start
-- and end of the term. Filled in for the tutor and shown to the family.
-- ---------------------------------------------------------------------------
create or replace function public.term_review_goals(p_review uuid)
returns table (goal_id uuid, goal_title text, subject text, skill text,
               level_at_start public.skill_level, level_now public.skill_level)
language sql stable security definer
set search_path = ''
as $$
  with r as (
    select * from public.term_reviews where id = p_review
  )
  select g.id, g.title, g.subject, coalesce(cs.plain_description, cs.description),
    coalesce(
      (select k.level_before from public.session_note_skills k join public.session_notes n on n.id = k.note_id
       where n.student_id = r.student_id and k.skill_id = cs.id and n.session_date >= r.term_starts_on
       order by n.session_date, n.created_at limit 1),
      (select k.level_after from public.session_note_skills k join public.session_notes n on n.id = k.note_id
       where n.student_id = r.student_id and k.skill_id = cs.id and n.session_date < r.term_starts_on
       order by n.session_date desc, n.created_at desc limit 1),
      'not_started'),
    coalesce((select l.level from public.student_skill_levels l
              where l.student_id = r.student_id and l.skill_id = cs.id), 'not_started')
  from r
  join public.learning_goals g on g.student_id = r.student_id
    and (g.status = 'active' or g.closed_at >= r.term_starts_on)
  join public.goal_skills gs on gs.goal_id = g.id
  join public.curriculum_skills cs on cs.id = gs.skill_id
  where exists (select 1 from public.term_reviews x where x.id = p_review and (
      private.is_admin()
      or (x.tutor_id = auth.uid() and private.is_tutor_of(x.student_id))
      or (x.status = 'approved' and (private.is_parent_of(x.student_id) or private.is_student_self(x.student_id)))))
  order by g.subject, g.created_at, cs.sort_order
$$;
revoke all on function public.term_review_goals(uuid) from public, anon;
grant execute on function public.term_review_goals(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Writing, checking and replying
-- ---------------------------------------------------------------------------

-- The tutor saves a draft, or sends it to CLG to check.
create or replace function public.save_term_review(
  p_review uuid,
  p_summary text,
  p_next_focus text,
  p_recommendation text,
  p_recommendation_note text default null,
  p_submit boolean default false
)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_r public.term_reviews;
begin
  select * into v_r from public.term_reviews where id = p_review for update;
  if v_r.id is null or not (
    private.is_admin() or (v_r.tutor_id = auth.uid() and private.is_tutor_of(v_r.student_id))
  ) then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  if v_r.status not in ('draft', 'returned') and not private.is_admin() then
    raise exception 'This review has already been sent to CLG' using errcode = '22023';
  end if;
  if p_submit and (nullif(btrim(p_summary), '') is null or nullif(btrim(p_next_focus), '') is null
                   or p_recommendation is null) then
    raise exception 'Write how the term went, the focus for next term, and a recommendation before sending' using errcode = '23514';
  end if;

  update public.term_reviews
  set summary = nullif(btrim(p_summary), ''),
      next_focus = nullif(btrim(p_next_focus), ''),
      recommendation = p_recommendation,
      recommendation_note = nullif(btrim(p_recommendation_note), ''),
      status = case when p_submit then 'submitted' else status end,
      submitted_at = case when p_submit then now() else submitted_at end
  where id = p_review;

  if p_submit then
    insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at)
    select r.account_id, v_r.student_id, p_review, 'review_to_check',
           left('Term review to check: ' || st.full_name, 200),
           'A tutor has sent a term review. Check it in Admin > Progress before the family sees it.',
           private.outside_quiet_hours(now())
    from (select distinct account_id from public.account_roles where role = 'admin') r
    cross join public.students st
    where st.id = v_r.student_id
    on conflict do nothing;
  end if;
end;
$$;
revoke all on function public.save_term_review(uuid, text, text, text, text, boolean) from public, anon;
grant execute on function public.save_term_review(uuid, text, text, text, text, boolean) to authenticated;

-- An admin approves (the family then sees it) or sends it back with a reason.
create or replace function public.check_term_review(p_review uuid, p_approve boolean, p_reason text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_r public.term_reviews;
  v_name text;
begin
  if not private.is_admin() then
    raise exception 'Only admins can check term reviews' using errcode = '42501';
  end if;
  select * into v_r from public.term_reviews where id = p_review for update;
  if v_r.id is null then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  if v_r.status <> 'submitted' then
    raise exception 'Only a review sent by the tutor can be checked' using errcode = '22023';
  end if;
  select private.first_name(full_name) into v_name from public.students where id = v_r.student_id;

  if p_approve then
    update public.term_reviews
    set status = 'approved', approved_by = auth.uid(), approved_at = now(), returned_reason = null
    where id = p_review;
    insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at)
    select p.account_id, v_r.student_id, p_review, 'review_ready',
           left(v_r.term_label || ' review for ' || coalesce(v_name, 'your child'), 200),
           'How the term went, the focus for next term, and the tutor''s recommendation. You can reply or ask for a call.',
           private.outside_quiet_hours(now())
    from (
      select l.parent_id as account_id from public.parent_student_links l where l.student_id = v_r.student_id
      union
      select s.account_id from public.students s where s.id = v_r.student_id and s.account_id is not null
    ) p
    on conflict do nothing;
  else
    if nullif(btrim(p_reason), '') is null then
      raise exception 'Say what needs changing' using errcode = '23514';
    end if;
    update public.term_reviews
    set status = 'returned', returned_reason = left(btrim(p_reason), 500)
    where id = p_review;
    if v_r.tutor_id is not null then
      insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at)
      values (v_r.tutor_id, v_r.student_id, p_review, 'review_returned',
              left('Term review sent back: ' || coalesce(v_name, 'student'), 200),
              left('CLG asked for a change: ' || btrim(p_reason), 1000),
              private.outside_quiet_hours(now()));
    end if;
  end if;
end;
$$;
revoke all on function public.check_term_review(uuid, boolean, text) from public, anon;
grant execute on function public.check_term_review(uuid, boolean, text) to authenticated;

-- The family replies, and can ask for a call. Goes to CLG's admins and the
-- tutor (a shared reply, never a private chat).
create or replace function public.reply_term_review(p_review uuid, p_reply text, p_wants_call boolean default false)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_r public.term_reviews;
begin
  select * into v_r from public.term_reviews where id = p_review for update;
  if v_r.id is null or v_r.status <> 'approved'
     or not (private.is_parent_of(v_r.student_id) or private.is_student_self(v_r.student_id)) then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  if nullif(btrim(p_reply), '') is null and not p_wants_call then
    raise exception 'Write a reply, or tick that you''d like a call' using errcode = '23514';
  end if;
  update public.term_reviews
  set family_reply = left(nullif(btrim(p_reply), ''), 2000), wants_call = coalesce(p_wants_call, false),
      family_replied_by = auth.uid(), family_replied_at = now()
  where id = p_review;

  insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at)
  select a.account_id, v_r.student_id, p_review, 'review_reply',
         left('Reply to ' || v_r.term_label || ' review: ' || st.full_name, 200),
         left(case when p_wants_call then 'The family would like a call. ' else '' end
              || coalesce(nullif(btrim(p_reply), ''), ''), 1000),
         private.outside_quiet_hours(now())
  from (
    select distinct account_id from public.account_roles where role = 'admin'
    union
    select v_r.tutor_id where v_r.tutor_id is not null
  ) a
  cross join public.students st
  where st.id = v_r.student_id and a.account_id is distinct from auth.uid()
  on conflict do nothing;
end;
$$;
revoke all on function public.reply_term_review(uuid, text, boolean) from public, anon;
grant execute on function public.reply_term_review(uuid, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Monthly summary, written by the app: sessions, skills moved up, goals
-- reached and roadmap steps done last month. Nothing on a month with no
-- sessions.
-- ---------------------------------------------------------------------------
create or replace function private.monthly_summary_text(p_student uuid, p_from date, p_to date)
returns text language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_sessions integer;
  v_up integer;
  v_goals text;
  v_steps integer;
  v_next text;
  v_text text;
begin
  select count(*) into v_sessions from public.session_notes
  where student_id = p_student and attendance <> 'absent' and session_date between p_from and p_to;
  if v_sessions = 0 then
    return null;
  end if;
  select count(*) into v_up from public.session_note_skills k join public.session_notes n on n.id = k.note_id
  where n.student_id = p_student and n.session_date between p_from and p_to
    and private.level_rank(k.level_after) > private.level_rank(k.level_before);
  select string_agg(title, '; ') into v_goals from public.learning_goals
  where student_id = p_student and status = 'achieved' and closed_at::date between p_from and p_to;
  v_steps := 0;
  if to_regclass('public.roadmap_steps') is not null then
    execute 'select count(*) from public.roadmap_steps where student_id = $1 and done_at::date between $2 and $3'
      into v_steps using p_student, p_from, p_to;
  end if;
  select next_step into v_next from public.session_notes
  where student_id = p_student and next_step is not null
  order by session_date desc, created_at desc limit 1;

  v_text := v_sessions || case when v_sessions = 1 then ' session' else ' sessions' end;
  v_text := v_text || E'\nSkills moved up a step: ' || v_up;
  if v_goals is not null then
    v_text := v_text || E'\nGoals reached: ' || v_goals;
  end if;
  if v_steps > 0 then
    v_text := v_text || E'\nRoadmap steps done: ' || v_steps;
  end if;
  if v_next is not null then
    v_text := v_text || E'\nNow working on: ' || v_next;
  end if;
  return left(v_text, 1000);
end;
$$;

-- p_month: the first day of the month to summarise. Left out, it runs on
-- the 1st (Adelaide time) for the month just ended, and does nothing on
-- other days.
create or replace function private.queue_monthly_summaries(p_month date default null)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Australia/Adelaide')::date;
  v_from date;
  v_to date;
  v_count integer;
begin
  if p_month is null then
    if extract(day from v_today) <> 1 then
      return 0;
    end if;
    v_from := (date_trunc('month', v_today) - interval '1 month')::date;
  else
    v_from := date_trunc('month', p_month)::date;
  end if;
  v_to := (v_from + interval '1 month' - interval '1 day')::date;
  insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at, for_date)
  select p.account_id, s.id, 'monthly_summary',
         left(to_char(v_from, 'FMMonth') || ' for ' || private.first_name(s.full_name), 200),
         s.body, private.outside_quiet_hours(now()), v_from
  from (
    select st.id, st.full_name, st.account_id, private.monthly_summary_text(st.id, v_from, v_to) as body
    from public.students st
  ) s
  cross join lateral (
    select l.parent_id as account_id from public.parent_student_links l where l.student_id = s.id
    union
    select s.account_id where s.account_id is not null
  ) p
  where s.body is not null
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.queue_monthly_summaries(date) from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    -- 23:00 UTC is 9:30am the next day in Adelaide (8:30am in winter).
    execute $job$
      select cron.schedule('clg-term-reviews', '0 23 * * *', 'select private.queue_term_reviews()')
    $job$;
    execute $job$
      select cron.schedule('clg-monthly-summaries', '0 23 * * *', 'select private.queue_monthly_summaries()')
    $job$;
  end if;
end;
$$;
