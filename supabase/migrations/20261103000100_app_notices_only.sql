-- App notices only, and new quiet hours (shared core). Carla, 2 Nov 2026.
--
-- 1. Families, tutors and staff hear about sessions, bookings, progress and
--    pauses in the app only. Notification emails stop, so when CLG does
--    send an email (a sign-in link, a password reset, an invitation) people
--    don't ignore it. Two kinds of email stay, because they are about
--    account security, not day-to-day notices:
--      * the owner's security alert summary
--      * emergency owner access starting and ending (to the admin who asked)
--    The app's sender (src/app/api/email/cron) no longer asks the
--    scheduling, progress or billing modules for emails. Their claim
--    functions are left in place, unused, so turning email back on later is
--    a code change only.
-- 2. Quiet hours are now 9pm to 6am Adelaide time (were 8pm to 8am).
--    Anything due then waits until 6am. A final "session in 1 hour"
--    reminder that would land in quiet hours (an early-morning session)
--    goes at 8:30pm the evening before instead of 7:30pm.
--
-- See docs/features/sending-emails.md and docs/features/scheduling.md.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Quiet hours: 9pm to 6am
-- ---------------------------------------------------------------------------
create or replace function private.outside_quiet_hours(p_at timestamptz)
returns timestamptz language sql stable
set search_path = ''
as $$
  with l as (select (p_at at time zone 'Australia/Adelaide') as t)
  select case
    when t::time >= time '21:00' then ((t::date + 1) + time '06:00') at time zone 'Australia/Adelaide'
    when t::time < time '06:00' then (t::date + time '06:00') at time zone 'Australia/Adelaide'
    else p_at
  end
  from l
$$;

-- The final reminder fallback moves from 7:30pm to 8:30pm the evening
-- before. The rest of the function is unchanged, so it is edited in place
-- rather than copied (keeps any later changes to the reminder text).
do $$
declare
  v_def text;
begin
  if to_regprocedure('private.queue_reminders()') is null then
    return;
  end if;
  v_def := pg_catalog.pg_get_functiondef('private.queue_reminders()'::regprocedure);
  if strpos(v_def, 'time ''19:30''') > 0 then
    v_def := replace(v_def, 'time ''19:30''', 'time ''20:30''');
    v_def := replace(v_def, 'goes at 7:30pm the evening before', 'goes at 8:30pm the evening before');
    execute v_def;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Email: only security emails wake the sender now
-- ---------------------------------------------------------------------------
create or replace function private.emails_waiting()
returns boolean language sql stable security definer
set search_path = ''
as $$
  -- Notification emails are off (app notices only). Only the owner's
  -- security alerts and emergency access emails are sent.
  select private.emergency_emails_waiting()
      or private.security_alerts_waiting()
$$;
revoke all on function private.emails_waiting() from public;

-- Nobody's reminder settings send email any more. The column stays (the
-- old claim functions read it) but is switched off for everyone.
alter table public.notice_settings alter column by_email set default false;
update public.notice_settings set by_email = false where by_email;
