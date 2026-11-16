-- Summary: the first-time app tour (Carla, 16 Nov 2026).
--
-- The first time someone opens a dashboard, a short step-by-step tour shows
-- them the main parts of it and why each one matters. Parents, students,
-- tutors and each admin level (owner, operations, support, finance) have
-- their own tour. Someone with several roles gets each role's tour the first
-- time they open that dashboard.
--
-- This file keeps one small row per person per tour: how far they got, and
-- whether they finished or closed it. That stops the tour opening again on
-- every visit, lets "Carry on the tour" start where they left off, and lets
-- CLG show a tour again after a big change (by raising its version number in
-- the app's code).
--
-- Privacy: the row holds no personal details beyond "this account reached
-- step 4 of the parent tour". People only ever see their own rows, and rows
-- are deleted with the account.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The table
-- ---------------------------------------------------------------------------

-- One row per person per tour.
create table if not exists public.app_tour_progress ( -- one row per person per tour
  account_id uuid not null references public.accounts (id) on delete cascade, -- the person (removed with their account)
  tour text not null check (tour in ('parent', 'student', 'tutor', 'owner', 'operations', 'support', 'finance')), -- which tour (a dashboard, or an admin level)
  version smallint not null check (version between 1 and 1000), -- which edition of the tour they saw (raised in the app after a big change)
  step smallint not null default 0 check (step between 0 and 100), -- the last step they reached (0 is the welcome step)
  finished boolean not null default false, -- true once they reached the end
  updated_at timestamptz not null default now(), -- when this last changed
  primary key (account_id, tour) -- one row each
); -- end of the table
alter table public.app_tour_progress enable row level security; -- turns on access rules
revoke all on public.app_tour_progress from anon, authenticated; -- no direct changes: saving goes through app_tour_save() below
grant select on public.app_tour_progress to authenticated; -- signed-in people may read, but only their own rows (rule below)

-- ---------------------------------------------------------------------------
-- Access rule
-- ---------------------------------------------------------------------------

-- People see only their own tour progress.
drop policy if exists "read own tour progress" on public.app_tour_progress; -- removes the old rule if the file is run again
create policy "read own tour progress" on public.app_tour_progress -- the reading rule
  for select to authenticated -- for signed-in people reading
  using (account_id = auth.uid()); -- only their own rows

-- ---------------------------------------------------------------------------
-- Saving progress
-- ---------------------------------------------------------------------------

-- Saves how far the signed-in person got in one of their own tours. A tour
-- belongs to someone only if they hold that role: the parent tour needs the
-- parent role, and the admin level tours need the admin role. (Admins who
-- replay someone else's tour from the App guide don't save anything.)
create or replace function public.app_tour_save( -- the saving function
  p_tour text, -- which tour
  p_version integer, -- which edition of it
  p_step integer, -- the step they reached
  p_finished boolean -- whether they reached the end
) -- end of the inputs
returns void -- gives nothing back
language plpgsql security definer -- writes to a table people can't write to directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_role public.app_role; -- the role the tour belongs to
begin -- starts the code
  if auth.uid() is null then -- not signed in
    raise exception 'Please sign in first.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_tour is null or p_tour not in ('parent', 'student', 'tutor', 'owner', 'operations', 'support', 'finance') then -- not a real tour
    raise exception 'That tour does not exist.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_role := case when p_tour in ('parent', 'student', 'tutor') then p_tour::public.app_role else 'admin'::public.app_role end; -- the admin level tours belong to the admin role
  if not private.has_role(v_role) then -- not their dashboard
    raise exception 'You can only save the tour for your own dashboards.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_version is null or p_version not between 1 and 1000 or p_step is null or p_step not between 0 and 100 then -- numbers out of range
    raise exception 'That tour step does not exist.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.app_tour_progress (account_id, tour, version, step, finished, updated_at) -- saves the progress,
  values (auth.uid(), p_tour, p_version, p_step, coalesce(p_finished, false), now()) -- for this person and tour,
  on conflict (account_id, tour) do update set -- or, if they've a row already, updates it:
    version = excluded.version, -- the edition they saw,
    step = excluded.step, -- the step they reached,
    finished = excluded.finished or (public.app_tour_progress.finished and public.app_tour_progress.version = excluded.version), -- finished stays true for the same edition (a replay closed early doesn't undo it),
    updated_at = excluded.updated_at; -- and when.
end; -- ends the code
$$; -- end of the function
revoke all on function public.app_tour_save(text, integer, integer, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.app_tour_save(text, integer, integer, boolean) to authenticated; -- signed-in people

-- Check you can run after this file: should give back true.
-- select to_regclass('public.app_tour_progress') is not null and to_regprocedure('public.app_tour_save(text, integer, integer, boolean)') is not null;
