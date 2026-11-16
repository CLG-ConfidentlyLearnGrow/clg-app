-- Training (module: training): safety modules never count towards the
-- quarter's training hours, automatically (Carla, 16 Nov 2026).
--
-- Before this, admins had to untick "Counts towards the hours each
-- quarter" on safety modules. Now the database decides: a module that is
-- needed before new students (a safety module) never counts, and every
-- other module does. The tick box is gone from the module form.
--
-- Safe to run more than once. Run after 20261118300100_tutor_applications.sql.

-- Keeps module dates right (same as before), and now also sets whether a
-- module counts towards the quarter's hours from whether it's a safety module.
create or replace function private.training_module_dates() -- runs before a module is added or changed
returns trigger language plpgsql -- a trigger function
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if new.status = 'published' and new.required_since is null then -- published without a compulsory date:
    new.required_since := private.training_today(); -- starts the time allowed today
  end if; -- end of that case
  if tg_op = 'UPDATE' and new.required and not old.required then -- just made compulsory:
    new.required_since := private.training_today(); -- everyone gets the full time allowed from today
  end if; -- end of that case
  new.counts_toward_certified := not new.holds_matching; -- safety modules never count towards the quarter's hours; all others do
  new.updated_at := now(); -- notes when it was changed
  return new; -- the change goes ahead
end; -- end of the steps
$$; -- end of the function

-- Puts existing modules right (the step above runs on this change too).
update public.training_modules -- changes modules:
set counts_toward_certified = not holds_matching -- counts unless it's a safety module
where counts_toward_certified is distinct from (not holds_matching); -- only ones that are wrong now

-- Completions already recorded for safety modules stop counting too.
update public.training_completions c -- changes completions:
set counts_toward_certified = false -- they don't count towards the quarter's hours
from public.training_modules m -- looking at their module
where m.id = c.module_id and m.holds_matching and c.counts_toward_certified; -- only safety-module completions still counted
