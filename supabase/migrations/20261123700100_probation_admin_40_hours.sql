-- Summary: admin staff probation is now 3 months or 40 hours (one full-time
-- work week, 8 hours x 5 days), whichever comes first (Carla, 22 Nov 2026).
-- This replaces 30 hours. Tutors stay at 3 months or 30 completed sessions.
--
-- What this file does:
--   1. Any admin probation record still at the old 30 hours changes to 40.
--   2. New admin probation records (set up by the owner or by the daily
--      run) start at 40 hours. Tutor records still start at 30 sessions.
--
-- Module: staff_probation. Changes only its own table. Safe to run more than
-- once. Run after 20261123400100_staff_probation.sql.

-- ---------------------------------------------------------------------------
-- 1. New admin records start at 40 hours
-- ---------------------------------------------------------------------------
-- The table's default (30) suits tutors. This step swaps it for 40 when a
-- new record is for an admin role and nobody chose a different number.
create or replace function private.staff_probation_admin_target() -- runs before each new record is saved
returns trigger -- a record-changing step
language plpgsql -- written in PL/pgSQL
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if new.kind = 'admin' and new.target = 30 then -- an admin record with the standard number:
    new.target := 40; -- one full-time work week (8 hours x 5 days)
  end if; -- end of the check
  return new; -- saves the record
end; -- finish
$$; -- end of the function
revoke all on function private.staff_probation_admin_target() from public, anon, authenticated; -- only used by the table step below

drop trigger if exists admin_target on public.staff_probations; -- replaces the step if run again
create trigger admin_target before insert on public.staff_probations -- before each new record,
  for each row execute function private.staff_probation_admin_target(); -- sets 40 hours for admin roles

-- ---------------------------------------------------------------------------
-- 2. Existing admin records move to 40 hours
-- ---------------------------------------------------------------------------
update public.staff_probations -- probation records
set target = 40, reminded_on = null -- 40 hours, and allows a fresh reminder for the new due date
where kind = 'admin' -- admin roles only
  and target = 30 -- still at the old number
  and status = 'on_probation'; -- and still on probation (finished ones keep their history)
