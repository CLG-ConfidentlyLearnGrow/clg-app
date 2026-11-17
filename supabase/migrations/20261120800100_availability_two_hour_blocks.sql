-- Summary: casual tutors give their available times in blocks of at least
-- 2 hours (Carla, 18 Nov 2026).
--
-- Carla: "Tutor availability must be given in minimum 2 hour blocks (because
-- tutors are paid in a minimum of 2 hour blocks - except for part-time and
-- full-time employees with approved and agreed to regular hours)."
--
-- How it works:
--   * Every time a tutor adds or changes an available time, the database
--     checks how long it is. If it is shorter than 2 hours and the tutor is
--     casual, it is refused with a plain message.
--   * The rule does not apply to part-time or full-time staff who have
--     agreed weekly hours entered on Admin > Billing > Staff pay.
--   * Anyone with no pay details yet counts as casual (casual is the usual
--     starting point, and the safer choice for pay).
--   * Times already saved are not changed or removed. The tutor dashboard
--     marks any that are shorter than 2 hours so the tutor can replace them.
--
-- Tutor profile module (tutor_availability). It only reads billing's pay
-- details; it never changes them. Safe to run more than once.
-- Run after 20261119700100_travel_distance.sql.

-- ---------------------------------------------------------------------------
-- 1. The shortest available time allowed for a tutor, in minutes
-- ---------------------------------------------------------------------------
-- 120 minutes for casual tutors (and anyone without pay details yet), and
-- 0 (no minimum) for part-time or full-time staff with agreed weekly hours.
create or replace function private.availability_min_minutes(p_tutor uuid) -- takes the tutor's account
returns integer -- gives back the shortest time allowed, in minutes
language sql stable security definer -- reads billing's pay details whoever is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select case -- choose:
    when exists ( -- there is a pay details row
      select 1 from public.billing_staff_pay sp -- in billing's staff pay table
      where sp.account_id = p_tutor -- for this tutor
        and sp.employment in ('part_time', 'full_time') -- who is part-time or full-time
        and sp.guaranteed_weekly_minutes is not null -- with agreed weekly hours
    ) then 0 -- then there is no minimum
    else 120 -- otherwise (casual, or no pay details yet) 2 hours
  end -- end of the choice
$$; -- end of the function
revoke all on function private.availability_min_minutes(uuid) from public, anon, authenticated; -- only used inside the database

-- The signed-in tutor's own minimum, for the dashboard to explain the rule
-- and mark older times that are too short.
create or replace function public.my_availability_min_minutes() -- no inputs: it is for the person asking
returns integer -- gives back the shortest time allowed, in minutes
language sql stable security definer -- reads the pay details for the person asking only
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer:
  select private.availability_min_minutes(auth.uid()) -- the minimum for the signed-in person
$$; -- end of the function
revoke all on function public.my_availability_min_minutes() from public, anon; -- not for signed-out visitors
grant execute on function public.my_availability_min_minutes() to authenticated; -- signed-in people (they only learn their own)

-- ---------------------------------------------------------------------------
-- 2. The check that runs every time an available time is saved
-- ---------------------------------------------------------------------------
create or replace function private.check_availability_length() -- a trigger function (no inputs)
returns trigger -- hands back the row to save
language plpgsql security definer -- reads billing's pay details whoever saves the time
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_min integer := private.availability_min_minutes(new.tutor_id); -- the shortest time allowed for this tutor
begin -- start
  if v_min > 0 and new.ends_at - new.starts_at < make_interval(mins => v_min) then -- a casual tutor's time that is too short:
    raise exception 'Casual tutors give available times in blocks of at least 2 hours, because casual work is paid in blocks of at least 2 hours. Please make this time at least 2 hours long.' -- plain refusal
      using errcode = '22023'; -- (the "not allowed value" code)
  end if; -- end of the check
  return new; -- saves the row
end; -- finish
$$; -- end of the function
revoke all on function private.check_availability_length() from public; -- only run by the trigger below

drop trigger if exists check_length on public.tutor_availability; -- replaces the trigger if this is run again
create trigger check_length before insert or update of starts_at, ends_at, tutor_id on public.tutor_availability -- before a time is added, or its times change:
  for each row execute function private.check_availability_length(); -- check it is long enough
