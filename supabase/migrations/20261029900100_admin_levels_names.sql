-- Admin levels, part 1 of 2: the names of the levels.
--
-- Before: two admin levels, 'owner' and 'staff'.
-- After: four levels.
--   owner       Carla. Everything.
--   operations  Day-to-day running (was 'staff'; everyone who was 'staff'
--               becomes 'operations' and keeps the same access).
--   support     Office help: families, bookings, login links.
--   finance     Bookkeeper: invoices, payments, credits, tutor pay.
--
-- This file only changes the list of names. Postgres needs new names saved
-- before anything can use them, so the rules are in part 2
-- (20261029900200_admin_levels.sql). Run this file first, then part 2.
--
-- See docs/features/admin-levels.md. Safe to run more than once.

do $$
begin
  if exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'admin_level' and e.enumlabel = 'staff'
  ) then
    alter type public.admin_level rename value 'staff' to 'operations';
  end if;
end;
$$;

alter type public.admin_level add value if not exists 'support';
alter type public.admin_level add value if not exists 'finance';
