-- Billing part 10 (module: billing): pay tutors for writing session summaries.
--
-- Carla (2026-11-12): tutors are paid for time after each session to write
-- the session summary (15 minutes now, maybe 5 later). This is added to
-- their pay automatically.
--
--   * Each completed session (signed on and off) gets a "Session summary"
--     pay line at the tutor's rate for that session's level.
--   * The minutes come from the scheduling setting summary_minutes (set by
--     admins). Until that setting exists, 15 minutes is used.
--   * Cancelled sessions and no-shows don't get summary time.
--   * Billing only reads the scheduling setting; it never changes it.
--
-- Safe to run more than once. Works whether or not the scheduling summary
-- time file has been run yet.

-- Allow the new kind of pay line, "summary", alongside the existing kinds.
alter table public.billing_pay_lines drop constraint if exists billing_pay_lines_kind_check; -- remove the old list of kinds
alter table public.billing_pay_lines add constraint billing_pay_lines_kind_check -- add the list back with "summary" included
  check (kind in ('session', 'late_cancel', 'min_topup', 'admin', 'tutoring_work', 'guaranteed', 'summary')); -- every kind of pay line

-- ---------------------------------------------------------------------------
-- How many minutes of summary time each session earns.
-- Reads the scheduling setting if it exists, otherwise 15 minutes.
-- ---------------------------------------------------------------------------
create or replace function private.billing_summary_minutes() -- returns the summary minutes per session
returns int language plpgsql stable security definer -- runs with the owner's rights so it can read the setting
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v int; -- the minutes found
begin
  if to_regclass('public.scheduling_settings') is null then -- the scheduling setting hasn't been added yet
    return 15; -- use CLG's current 15 minutes
  end if;
  execute 'select summary_minutes from public.scheduling_settings where id' into v; -- read the one settings row (written this way so the file runs before the setting exists)
  return coalesce(v, 15); -- 15 minutes if the row is missing
end;
$$;
revoke all on function private.billing_summary_minutes() from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- Work out summary pay for a range of days.
-- Removes summary lines not yet sent to Xero in the range, then adds one
-- for each completed session. Lines already sent to Xero stay as they are.
-- Returns how many summary lines are waiting to go to Xero in the range.
-- ---------------------------------------------------------------------------
create or replace function public.billing_build_summary_pay(p_from date, p_to date) -- days to work out, first and last
returns int language plpgsql security definer -- runs with the owner's rights; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_minutes int := private.billing_summary_minutes(); -- summary minutes per session
  r record; -- one session at a time
  n int := 0; -- how many lines are waiting
begin
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can work out pay' using errcode = '42501'; -- plain message for anyone else
  end if;
  if p_to < p_from or p_to - p_from > 62 then -- same limit as working out session pay
    raise exception 'Choose up to about two months at a time' using errcode = '22023'; -- plain message
  end if;

  delete from public.billing_pay_lines -- start fresh for this range
  where status = 'pending' and kind = 'summary' -- only summary lines not yet sent to Xero
    and work_date between p_from and p_to; -- only in the days asked for

  if v_minutes <= 0 then -- summary time switched off (set to 0)
    return 0; -- nothing to add
  end if;

  for r in -- each session in the range that earns summary time
    select se.id, se.tutor_id, se.level_kind, -- the session, its tutor, and school or tertiary
           (se.starts_at at time zone 'Australia/Adelaide')::date as day, -- the day it happened (Adelaide time)
           left(to_char(se.starts_at at time zone 'Australia/Adelaide', 'FMHH12:MIam') || ' ' -- start time, for example 4:00pm
                || split_part(trim(st.full_name), ' ', 1) || ', ' || se.subject, 180) as label -- student's first name and subject
    from public.sessions se -- sessions belong to scheduling; billing only reads them
    join public.students st on st.id = se.student_id -- for the student's first name
    where (se.starts_at at time zone 'Australia/Adelaide')::date between p_from and p_to -- in the days asked for
      and se.status::text = 'completed' -- only sessions that went ahead (not cancelled or no-show)
      and se.worked_from is not null and se.worked_to is not null -- the tutor signed on and off
      and not exists ( -- not already paid
        select 1 from public.billing_pay_lines l -- an existing line
        where l.session_id = se.id and l.kind = 'summary' and l.status = 'sent' -- summary for this session already sent to Xero
      )
  loop
    perform private.billing_add_pay_line(r.tutor_id, r.day, 'summary', r.level_kind, r.id, -- add the line at the tutor's rate for this level
      v_minutes, r.label || ' (session summary)'); -- the minutes, and a note saying what it's for
  end loop;
  select count(*) into n from public.billing_pay_lines -- count what was added
  where status = 'pending' and kind = 'summary' and work_date between p_from and p_to; -- summary lines waiting to go to Xero in the range
  return n; -- tell the caller how many there are
end;
$$;
revoke all on function public.billing_build_summary_pay(date, date) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_build_summary_pay(date, date) to authenticated, service_role; -- signed-in admins (checked inside) and the daily run
