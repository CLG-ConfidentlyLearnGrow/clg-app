-- Progress: the plan for the next session is followed up like the summary
-- (Carla, 22 Nov 2026, from her notes on Emma's Job Proposal: the 12-hour
-- missing flag should cover the session summary and the next-session plan;
-- no plan is needed when there is no next session).
--
-- Before: a tutor was reminded at 6 hr, and admins told at 12 hr, only when
-- the session summary was missing. A summary saved without its plan (for
-- example if the plan failed to save, or the tutor left it for later) was
-- never followed up.
-- Now: when the summary is saved but its plan is missing, the student came,
-- and a next session with the same tutor is booked:
--   * at 6 hr the tutor gets "Plan for the next session due",
--   * at 12 hr the owner and Operations admins get "Plan for the next
--     session missing", so Emma can follow it up.
-- No plan is asked for when the student was absent, or when no next session
-- with that tutor is booked (the app also stops asking for one on the form).
-- Quiet hours still apply (the notices table's own rule handles them).
--
-- This is a new hourly job beside the summary reminders, so the summary
-- reminders are not changed.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Two new kinds of progress notice.
-- ---------------------------------------------------------------------------
alter table public.progress_notices drop constraint if exists progress_notices_kind_check; -- replaces the list of kinds
alter table public.progress_notices add constraint progress_notices_kind_check -- the new list:
  check (kind in ('session_update', 'note_reminder', 'note_overdue', 'step_due', -- session notes and roadmap steps,
                  'review_due', 'review_to_check', 'review_returned', 'review_ready', 'review_reply', -- term reviews,
                  'monthly_summary', 'evidence_added', -- old monthly summaries (kept readable) and uploads,
                  'review_offer', 'review_booked', -- term review offers,
                  'plan_reminder', 'plan_overdue')); -- and the plan for the next session (Carla, 22 Nov 2026)

-- ---------------------------------------------------------------------------
-- Sessions whose plan for the next session is missing: the summary is
-- saved, the student came, there is no plan, and a next session with the
-- same tutor is booked.
-- ---------------------------------------------------------------------------
create or replace function private.sessions_missing_plan(p_hours integer) -- how many hours after the session
returns table (session_id uuid, student_id uuid, tutor_id uuid, student_name text, tutor_name text, starts_at timestamptz) -- one row per session
language sql stable security definer -- reads sessions, summaries and plans with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the list
  select se.id, se.student_id, se.tutor_id, st.full_name, a.full_name, se.starts_at -- the session, student, tutor and time
  from public.sessions se -- from the sessions
  join public.students st on st.id = se.student_id -- with the student
  left join public.accounts a on a.id = se.tutor_id -- and the tutor's name
  join public.session_notes n on n.session_id = se.id -- that have a summary
  where private.session_needs_note(se.status, se.ends_at) -- a session that went ahead
    and se.ends_at <= now() - make_interval(hours => p_hours) -- at least this many hours ago
    and se.ends_at > now() - interval '7 days' -- in the last 7 days (plans can be added for 7 days)
    and n.attendance <> 'absent' -- the student came
    and not exists (select 1 from public.session_plans p where p.note_id = n.id) -- there is no plan
    and exists ( -- and a next session is booked
      select 1 from public.sessions nx -- another session:
      where nx.student_id = se.student_id and nx.tutor_id = se.tutor_id -- same student and tutor,
        and nx.status = 'scheduled' and nx.starts_at > se.ends_at) -- still to come, after this one
$$; -- end of the function
revoke all on function private.sessions_missing_plan(integer) from public; -- only used inside the database

-- ---------------------------------------------------------------------------
-- The hourly plan reminders: the tutor at 6 hr, admins at 12 hr.
-- ---------------------------------------------------------------------------
create or replace function private.queue_plan_reminders() -- no inputs
returns integer language plpgsql security definer -- adds notices with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_count integer := 0; -- how many notices were added
  v_rows integer; -- how many one step added
begin -- start
  insert into public.progress_notices (account_id, student_id, session_id, kind, title, body, deliver_at) -- the tutor's reminder:
  select m.tutor_id, m.student_id, m.session_id, 'plan_reminder', -- to the tutor, about this session,
         'Plan for the next session due', -- the title,
         left(format('Please add your plan for %s''s next session (from the session on %s). Open the student''s Progress page and choose "Plan for the next session".', -- the message:
                     m.student_name, private.when_text(m.starts_at)), 1000), -- the student and the session,
         now() -- now (quiet hours are applied by the notices table)
  from private.sessions_missing_plan(6) m -- plans missing 6 hr after the session
  where m.tutor_id is not null -- (a tutor to remind)
  on conflict do nothing; -- each tutor hears once per session
  get diagnostics v_rows = row_count; -- how many were added
  v_count := v_count + v_rows; -- adds them to the total

  insert into public.progress_notices (account_id, student_id, session_id, kind, title, body, deliver_at) -- the admins' notice:
  select r.account_id, m.student_id, m.session_id, 'plan_overdue', -- to each admin, about this session,
         'Plan for the next session missing', -- the title,
         left(format('%s has not added the plan for %s''s next session (from the session on %s, 12 hr or more ago). The summary is in, and the tutor has been reminded.', -- the message:
                     coalesce(m.tutor_name, 'The tutor'), m.student_name, private.when_text(m.starts_at)), 1000), -- the tutor, student and session,
         now() -- now (quiet hours are applied by the notices table)
  from private.sessions_missing_plan(12) m -- plans missing 12 hr after the session
  cross join ( -- for each owner and Operations admin:
    select distinct ar.account_id -- their account
    from public.account_roles ar -- from the roles
    left join public.admin_profiles ap on ap.account_id = ar.account_id -- with their admin level
    where ar.role = 'admin' and coalesce(ap.level, 'owner') in ('owner', 'operations') -- owner and Operations only
  ) r -- (end of the admins)
  on conflict do nothing; -- each admin hears once per session
  get diagnostics v_rows = row_count; -- how many were added
  return v_count + v_rows; -- hands back the total
end; -- end of the code
$$; -- end of the function
revoke all on function private.queue_plan_reminders() from public; -- only run by the hourly job

-- Runs it every hour at 15 minutes past (where the job runner is available).
do $$ -- a one-off block
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job runner is available:
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on (if it is not already)
    execute $job$ select cron.schedule('clg-plan-reminders', '15 * * * *', 'select private.queue_plan_reminders()') $job$; -- the hourly job (replaces one with the same name)
  end if; -- end of the check
end; -- finish
$$; -- end of the block
