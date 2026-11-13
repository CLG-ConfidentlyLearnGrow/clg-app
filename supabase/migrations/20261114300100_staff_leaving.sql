-- Summary: removing someone from the CLG team when they leave (Carla, 14 Nov
-- 2026). Module: staff directory.
--
-- Carla asked to be able to remove employees from the staff directory when
-- they are no longer part of the CLG team. One step, owner only, with the
-- person's name typed to confirm:
--   1. Their tutor and admin access ends straight away (their tutor matches
--      end too). It is refused while they still have sessions booked, so
--      those are moved to another tutor first.
--   2. Their private calendar link stops working for good (so it can't come
--      back to life if they rejoin later).
--   3. They are signed out on every device.
--   4. Their last day, and why they left, are written down. Tutors also get
--      a line in the shared "why people leave" record.
--   5. Nothing CLG must keep is deleted. Pay, hours, sessions, checks and
--      child safety records stay for 7 years after they leave (Fair Work
--      employee records rule), then the usual nightly clean-up removes them.
-- Former staff still show in the staff directory under "Left CLG", and can
-- be brought back by adding a role again.
--
-- Also fixes a gap in the nightly clean-up: an account with no roles left
-- was deleted after 12 months unused, even when it belonged to someone who
-- left the staff less than 7 years ago. Those accounts are now kept for the
-- full 7 years.
--
-- See docs/features/staff-leaving.md. Safe to run more than once. Run after
-- 20261103400100_staff_directory_roles.sql.

-- ---------------------------------------------------------------------------
-- 1. The record of staff who have left
-- ---------------------------------------------------------------------------

-- One row each time a staff member leaves CLG (someone who leaves, rejoins
-- and leaves again has two rows).
create table if not exists public.staff_departures ( -- the table, made only if it isn't there yet
  id uuid primary key default gen_random_uuid(), -- a unique id for the row
  account_id uuid not null references public.accounts (id) on delete cascade, -- who left (the row goes if their account is finally deleted, after the keeping period)
  full_name text not null, -- their name on the day they left, so the record still reads clearly later
  left_on date not null, -- their last day with CLG
  reason text not null check (reason in ( -- why they left, from a short fixed list:
    'own_study_or_work', -- study, or another job
    'moved', -- moved away
    'pay', -- pay
    'hours', -- not enough, or too many, hours
    'workload', -- workload
    'personal', -- personal or family reasons
    'contract_ended', -- their agreed time with CLG finished
    'clg_ended', -- CLG ended their employment
    'other' -- something else
  )), -- end of the list
  details text check (char_length(details) <= 1000), -- an optional short note (keep it brief; concerns belong in the child safety record)
  roles_removed text[] not null default '{}', -- which staff roles ended (tutor, admin)
  recorded_by uuid references public.accounts (id) on delete set null, -- the admin who recorded it
  created_at timestamptz not null default now() -- when it was recorded
); -- end of the table
create index if not exists staff_departures_account on public.staff_departures (account_id, left_on desc); -- Makes "when did this person last leave?" quick.

alter table public.staff_departures enable row level security; -- Turns on the access rules for this table.
revoke all on public.staff_departures from anon; -- People who aren't signed in get nothing.
revoke insert, update, delete, truncate on public.staff_departures from authenticated; -- Nobody writes it directly; only public.staff_leave() below does.
drop policy if exists "full admins see staff departures" on public.staff_departures; -- Removes the read rule if it's there, so this file can be run again.
create policy "full admins see staff departures" on public.staff_departures -- The read rule:
  for select to authenticated -- for reading, by signed-in people,
  using (private.is_admin()); -- only the owner and operations admins (why someone left can be sensitive).
drop trigger if exists audit on public.staff_departures; -- Removes the record-keeper if it's there, so this file can be run again.
create trigger audit after insert or update or delete on public.staff_departures -- Adds it back: after any change,
  for each row execute function private.audit_change(); -- writes a line in the audit log.

-- ---------------------------------------------------------------------------
-- 2. Removing someone from the team
-- ---------------------------------------------------------------------------

-- The owner removes a staff member who has left. Every step happens
-- together: if any step is refused, nothing changes.
create or replace function public.staff_leave( -- the function and its inputs:
  p_account uuid, -- who is leaving,
  p_left_on date, -- their last day,
  p_reason text, -- why they left (from the list above),
  p_details text, -- an optional short note,
  p_confirm_name text -- their full name, typed to confirm.
) -- end of the inputs
returns void language plpgsql security definer -- Gives nothing back; runs with the owner's rights so it can make every change.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_name text; -- Their name on file.
  v_tutor boolean; -- Whether they're a tutor.
  v_admin boolean; -- Whether they're an admin.
  v_booked integer; -- How many bookings they still have coming up.
  v_roles text[] := '{}'; -- The staff roles ended.
begin -- start of the steps.
  if not private.is_owner() then -- Only the owner (signed in with two steps) can do this:
    raise exception 'Only the owner can remove someone from the team' using errcode = '42501'; -- everyone else is refused, in plain words.
  end if; -- End of the owner check.
  select full_name into v_name from public.accounts where id = p_account; -- Looks up their name.
  if v_name is null then -- No such account:
    raise exception 'We couldn''t find that person' using errcode = '22023'; -- says so.
  end if; -- End of the account check.
  if trim(coalesce(p_confirm_name, '')) is distinct from v_name then -- The typed name doesn't match:
    raise exception 'The name typed doesn''t match. Type it exactly as shown' using errcode = '22023'; -- refuses, so nobody is removed by mistake.
  end if; -- End of the name check.
  if p_account = auth.uid() then -- Removing themselves:
    raise exception 'You can''t remove yourself from the team' using errcode = '22023'; -- refuses.
  end if; -- End of the self check.
  if exists (select 1 from public.admin_profiles where account_id = p_account and level::text = 'owner') then -- Removing an owner:
    raise exception 'An owner can''t be removed here' using errcode = '22023'; -- refuses (the business can't be left without its owner).
  end if; -- End of the owner-account check.
  v_tutor := exists (select 1 from public.account_roles where account_id = p_account and role = 'tutor'); -- Notes whether they're a tutor.
  v_admin := exists (select 1 from public.account_roles where account_id = p_account and role = 'admin'); -- Notes whether they're an admin.
  if not (v_tutor or v_admin) then -- Neither:
    raise exception '% isn''t a current tutor or admin', v_name using errcode = '22023'; -- says so plainly.
  end if; -- End of the staff check.
  if p_left_on is null then -- No last day given:
    raise exception 'Enter their last day' using errcode = '22023'; -- asks for it.
  end if; -- End of the date check.
  if p_left_on > current_date then -- A day in the future:
    raise exception 'Their last day can''t be in the future. Do this on or after their last day' using errcode = '22023'; -- their access would end too early otherwise.
  end if; -- End of the future check.
  if p_left_on < current_date - 366 then -- More than a year ago:
    raise exception 'Their last day must be within the past year' using errcode = '22023'; -- catches a mistyped year.
  end if; -- End of the past check.
  if p_reason is null or p_reason not in ('own_study_or_work', 'moved', 'pay', 'hours', 'workload', 'personal', 'contract_ended', 'clg_ended', 'other') then -- Not one of the listed reasons:
    raise exception 'Choose why they left' using errcode = '22023'; -- asks for one.
  end if; -- End of the reason check.

  if v_tutor then -- For tutors:
    select count(*) into v_booked -- counts their bookings
    from public.bookings b -- in the bookings table
    where b.tutor_id = p_account and b.status in ('requested', 'confirmed') and b.last_date >= current_date; -- that are still waiting or confirmed, and not yet over.
    if v_booked > 0 then -- Any left:
      raise exception '% still has % booking(s) coming up. Move them to another tutor or end them in Sessions first', v_name, v_booked using errcode = '23514'; -- refuses, so no student is left without a tutor.
    end if; -- End of the bookings check.
    perform public.admin_remove_role(p_account, 'tutor', p_confirm_name); -- Ends their tutor access, marks them finished and ends their matches (the shared step, which also logs it).
    v_roles := array_append(v_roles, 'tutor'); -- Notes the tutor role ended.
    if to_regclass('public.tutor_calendar_links') is not null then -- If the calendar link feature is in this database:
      execute 'delete from public.tutor_calendar_links where tutor_id = $1' using p_account; -- removes their calendar link for good, so it can't work again if they rejoin.
    end if; -- End of the calendar step.
    perform public.record_leaving( -- Adds a line to the shared "why people leave" record:
      'tutor', null, p_account, p_left_on, -- a tutor, this person, their last day,
      case when p_reason in ('contract_ended', 'clg_ended') then 'other' else p_reason end, -- the reason (the shared list has no "contract ended" or "CLG ended", so those count as "other"),
      p_details); -- and the note.
  end if; -- End of the tutor steps.

  if v_admin then -- For admins:
    perform public.admin_remove_role(p_account, 'admin', p_confirm_name); -- ends their admin access (the shared step, which also logs it).
    v_roles := array_append(v_roles, 'admin'); -- Notes the admin role ended.
  end if; -- End of the admin steps.

  if to_regclass('auth.sessions') is not null then -- If the sign-in sessions table is there (it always is on Supabase):
    execute 'delete from auth.sessions where user_id = $1' using p_account; -- signs them out on every device (any open page stops working within the hour, and their access is already gone).
  end if; -- End of the sign-out step.

  insert into public.staff_departures (account_id, full_name, left_on, reason, details, roles_removed, recorded_by) -- Writes down that they left:
  values (p_account, v_name, p_left_on, p_reason, nullif(left(trim(coalesce(p_details, '')), 1000), ''), v_roles, auth.uid()); -- who, their name, last day, reason, the note (trimmed, blank if empty), the roles ended and who recorded it.
  perform private.log_event('staff_left', 'staff_departures', p_account::text, jsonb_build_object('roles', v_roles)); -- Logs it in the activity log (ids and roles only).
end; -- end of the steps.
$$; -- end of the function
revoke all on function public.staff_leave(uuid, date, text, text, text) from public, anon; -- Takes away the default permission first.
grant execute on function public.staff_leave(uuid, date, text, text, text) to authenticated; -- Signed-in people may call it; the owner check inside does the rest.

-- ---------------------------------------------------------------------------
-- 3. The directory, now with people who have left
-- ---------------------------------------------------------------------------

-- The columns change, so the old version is removed first.
drop function if exists public.staff_directory(); -- Removes the old version.
create function public.staff_directory() -- Every current staff member, plus everyone who has left the staff.
returns table ( -- the columns:
  account_id uuid, -- their account,
  full_name text, -- their name,
  email text, -- their email,
  job_title text, -- their job title,
  is_tutor boolean, -- whether they're a tutor now,
  is_admin boolean, -- whether they're an admin now,
  is_parent boolean, -- whether they're a parent,
  is_student boolean, -- whether they're a student,
  admin_level text, -- their admin level (admins only),
  tutor_active boolean, -- whether their tutor profile is on,
  work_state text, -- the state they work from,
  subjects text[], -- the subjects they teach,
  last_sign_in_at timestamptz, -- when they last signed in,
  left_on date, -- their last day, if they've left the staff (blank for current staff),
  leaving_reason text, -- why they left (owner and operations only; blank for others),
  upcoming_bookings integer, -- how many bookings they have coming up (tutors),
  current_students integer -- how many students they're matched with now (tutors).
) -- end of the columns
language sql stable security definer -- Reads only; runs with the owner's rights so it can join the tables.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the query:
  select a.id, -- their account,
         a.full_name, -- name,
         p.email, -- email,
         j.job_title, -- job title,
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'tutor'), -- tutor now?
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin'), -- admin now?
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'parent'), -- parent?
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'student'), -- student?
         (select ap.level::text from public.admin_profiles ap -- their admin level,
          where ap.account_id = a.id -- for this person,
            and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin')), -- only while they're an admin,
         t.active, -- whether their tutor profile is on,
         w.work_state::text, -- the state they work from,
         coalesce((select array_agg(tt.subject order by tt.subject) -- the subjects they teach, in order,
                   from public.tutor_teaching tt where tt.tutor_id = a.id), '{}'), -- (none if they teach none),
         u.last_sign_in_at, -- when they last signed in,
         case when d.left_on is not null -- if they have a leaving record
                and not exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor')) -- and no staff role now,
              then d.left_on end, -- their last day (blank once they rejoin),
         case when d.left_on is not null and private.is_admin() -- the reason, for the owner and operations only,
                and not exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor')) -- while they're still away,
              then d.reason end, -- (blank otherwise),
         (select count(*)::integer from public.bookings b -- how many bookings
          where b.tutor_id = a.id and b.status in ('requested', 'confirmed') and b.last_date >= current_date), -- they still have coming up,
         (select count(distinct ta.student_id)::integer from public.tutor_assignments ta -- how many different students
          where ta.tutor_id = a.id and (ta.ends_on is null or ta.ends_on > current_date)) -- they're matched with now.
  from public.accounts a -- from every account,
  left join auth.users u on u.id = a.id -- with their sign-in details,
  left join public.account_private p on p.account_id = a.id -- their email,
  left join public.staff_job_titles j on j.account_id = a.id -- their job title,
  left join public.tutor_profiles t on t.account_id = a.id -- their tutor profile,
  left join public.tutor_work_settings w on w.tutor_id = a.id -- their work settings,
  left join lateral ( -- and their most recent leaving record:
    select sd.left_on, sd.reason from public.staff_departures sd -- its date and reason,
    where sd.account_id = a.id -- for this person,
    order by sd.left_on desc, sd.created_at desc limit 1 -- the latest one.
  ) d on true -- (kept even if they have none)
  where private.is_any_admin() -- Only admins (any level) see the directory.
    and ( -- Shows people who are:
      exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor')) -- staff now,
      or d.left_on is not null -- or have left the staff.
    ) -- end of who is shown
  order by a.full_name -- In name order.
$$; -- end of the function
revoke execute on function public.staff_directory() from public, anon; -- Takes away the default permission first.
grant execute on function public.staff_directory() to authenticated; -- Signed-in people may call it; the admin check inside does the rest.

-- ---------------------------------------------------------------------------
-- 4. Keeping former staff accounts for the full 7 years
-- ---------------------------------------------------------------------------

-- The list of records due for deletion by a given time, used by the nightly
-- clean-up and the "coming up for deletion" list. Same as before, except an
-- unused account is now kept while it belongs to a former staff member still
-- inside the 7-year keeping period (the "former_tutors" period).
create or replace function private.retention_due(p_at timestamptz) -- Takes the time to check against.
returns table (kind text, record_id uuid, due_at timestamptz) -- Gives back what kind of record, which one, and when it's due.
language sql stable -- Reads only.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the query:
  -- Students no longer with CLG.
  select 'student', s.id, private.student_last_activity(s.id) + private.keep_for('student_records') -- a student, and when they're due,
  from public.students s -- from every student,
  where private.student_last_activity(s.id) + private.keep_for('student_records') <= p_at -- whose keeping period has passed,
    and not private.has_hold(s.id, s.account_id) -- and who has no hold.

  union all -- plus:

  -- Former tutors.
  select 'tutor', t.account_id, t.ended_on::timestamptz + private.keep_for('former_tutors') -- a tutor, and when they're due,
  from public.tutor_profiles t -- from every tutor profile,
  where not t.active -- that is switched off,
    and t.ended_on is not null -- with a finish date,
    and t.ended_on::timestamptz + private.keep_for('former_tutors') <= p_at -- whose keeping period has passed,
    and not private.has_hold(null, t.account_id) -- and who has no hold.

  union all -- plus:

  -- Accounts with nothing left to keep: no staff role, no linked children,
  -- no student record, no sign-in for the set period, and not a former
  -- staff member still inside the 7-year keeping period.
  select 'account', a.id, greatest(a.created_at, u.last_sign_in_at) + private.keep_for('unused_accounts') -- an account, and when it's due,
  from public.accounts a -- from every account,
  join auth.users u on u.id = a.id -- with its sign-in details,
  where greatest(a.created_at, u.last_sign_in_at) + private.keep_for('unused_accounts') <= p_at -- unused for the set period,
    and not exists (select 1 from public.account_roles r -- with no
                    where r.account_id = a.id and r.role in ('admin', 'tutor')) -- staff role,
    and not exists (select 1 from public.parent_student_links l where l.parent_id = a.id) -- no linked children,
    and not exists (select 1 from public.students s where s.account_id = a.id) -- no student record,
    and not exists (select 1 from public.staff_departures sd -- not someone who left the staff
                    where sd.account_id = a.id -- (this person)
                      and sd.left_on::timestamptz + private.keep_for('former_tutors') > p_at) -- less than 7 years ago,
    and not exists (select 1 from public.tutor_profiles tp -- not a former tutor
                    where tp.account_id = a.id -- (this person)
                      and coalesce(tp.ended_on, current_date)::timestamptz + private.keep_for('former_tutors') > p_at) -- whose tutor records are still being kept,
    and not private.has_hold(null, a.id) -- and with no hold.
$$; -- end of the function
revoke execute on function private.retention_due(timestamptz) from public; -- Nobody calls it directly; only the clean-up functions use it.

-- ---------------------------------------------------------------------------
-- 5. Ending a tutor's matches is always allowed
-- ---------------------------------------------------------------------------
-- Found while building this: the two checks that guard tutor matches ran
-- even when a match was being ENDED. Removing a tutor switches their profile
-- off first, so the "is this tutor cleared?" check always failed, and a
-- tutor with any current student could never be removed (the same happened
-- to a tutor whose Working with Children Check had run out). Starting or
-- changing a match is still fully checked; only ending one early (same
-- tutor, student and subject, with an earlier end date) skips the checks,
-- because ending a match can only reduce a tutor's access to a child.

-- True when an update to a match only ends it (or ends it sooner).
create or replace function private.assignment_only_ending(p_old public.tutor_assignments, p_new public.tutor_assignments) -- Takes the match before and after the change.
returns boolean language sql immutable -- Gives back true or false; the same inputs always give the same answer.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the test:
  select p_new.tutor_id = p_old.tutor_id -- same tutor,
     and p_new.student_id = p_old.student_id -- same student,
     and p_new.subject = p_old.subject -- same subject,
     and p_new.starts_on = p_old.starts_on -- same start date,
     and p_new.ends_on is not null -- now has an end date,
     and (p_old.ends_on is null or p_new.ends_on <= p_old.ends_on) -- which is no later than before.
$$; -- end of the function
revoke execute on function private.assignment_only_ending(public.tutor_assignments, public.tutor_assignments) from public; -- Only the checks below use it.

-- A tutor can only be matched while cleared, and only to a student who is
-- an adult or whose parent link an admin has verified. (Same as before,
-- plus the first step: ending a match is always allowed.)
create or replace function private.check_assignment() -- The check run before a match is added or changed.
returns trigger language plpgsql security definer -- Runs as a trigger, with the owner's rights so it can read the checks.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_dob date; -- The student's date of birth.
begin -- start of the steps.
  if tg_op = 'UPDATE' and private.assignment_only_ending(old, new) then -- Only ending the match:
    return new; -- always allowed (it only reduces access).
  end if; -- End of the ending case.
  if new.ends_on is not null and new.ends_on < current_date then -- A match that ended in the past:
    return new; -- recording a past match is allowed.
  end if; -- End of the past case.

  if not private.tutor_cleared_for_student(new.tutor_id, new.student_id) then -- The tutor isn't cleared for the student's state:
    raise exception 'This tutor does not hold every verified, in-date check needed for this student''s state' -- refuses, in plain words.
      using errcode = '23514'; -- (the "rule broken" error code)
  end if; -- End of the clearance check.

  select date_of_birth into v_dob from public.students where id = new.student_id; -- Looks up the student's date of birth.
  if v_dob > (current_date - interval '18 years')::date and not exists ( -- A child, with no
    select 1 from public.parent_student_links -- parent link
    where student_id = new.student_id and verified_at is not null -- that an admin has verified:
  ) then -- (end of the test)
    raise exception 'A parent link must be verified by an admin before a tutor is assigned to a child' -- refuses, in plain words.
      using errcode = '23514'; -- (the "rule broken" error code)
  end if; -- End of the parent link check.

  return new; -- Everything checks out: the change goes ahead.
end; -- end of the steps.
$$; -- end of the function

-- The tutor must teach the subject at the student's level. (Same as
-- before, plus the first step: ending a match is always allowed.)
create or replace function private.check_assignment_teaching() -- The second check run before a match is added or changed.
returns trigger language plpgsql security definer -- Runs as a trigger, with the owner's rights so it can read what tutors teach.
set search_path = '' -- Uses full names only, so nothing can be swapped in.
as $$ -- the steps:
declare -- working values:
  v_level text; -- The level the student works at in this subject.
begin -- start of the steps.
  if private.is_backend() then return new; end if; -- The app's own background jobs skip this check.
  if tg_op = 'UPDATE' and private.assignment_only_ending(old, new) then return new; end if; -- Only ending the match: always allowed.
  if new.ends_on is not null and new.ends_on < current_date then return new; end if; -- A match that ended in the past: allowed.

  v_level := private.matching_level(new.student_id, new.subject); -- Works out the student's level in this subject.
  if v_level is null then -- No level known:
    raise exception 'Add this student''s year level before assigning a tutor' -- asks for it.
      using errcode = '23514'; -- (the "rule broken" error code)
  end if; -- End of the level check.
  if not private.tutor_teaches(new.tutor_id, new.subject, v_level) then -- The tutor doesn't teach it at that level:
    raise exception 'This tutor hasn''t listed % for %. They can add it under "What you teach" in their dashboard.', -- refuses, saying what's missing,
      new.subject, v_level using errcode = '23514'; -- (the subject and level, and the "rule broken" error code).
  end if; -- End of the teaching check.
  return new; -- Everything checks out: the change goes ahead.
end; -- end of the steps.
$$; -- end of the function
