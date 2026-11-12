-- Tutors see only what they need to tutor (Carla, 12 Nov 2026).
--
-- "Need to ensure tutors only see the students they have been matched with,
-- no other student information - and no financial information or personal
-- information they do not need to know in order to be an effective tutor."
--
-- Most of this was already in place (tutors see only students they're
-- currently matched with, while their checks are in date, and no billing
-- rows). This update closes two small gaps:
--   1. A student's date of birth. Tutors could read it through the database
--      (no tutor page showed it). Tutors work from the year level, so the
--      birth date is now readable only by admins, the student's parents and
--      the student themselves, through student_birth_dates().
--   2. Add-on prices. The study plans note on a student's progress page
--      showed the add-on's price to tutors. The price now goes only to admins
--      and the student's family.
-- Every other students column stays readable as before, under the same
-- access rules. A test (tutor_need_to_know.test.sql) fails if a new students
-- column is added without being made readable, so it can't be missed.

-- ---------------------------------------------------------------------------
-- 1. Birth dates: hide the column, read it through a checked function
-- ---------------------------------------------------------------------------
-- Who may see a student's birth date: admins (including the support desk),
-- the student's parents, and the student themselves. Not tutors.
create or replace function private.can_see_birth_date(p_student uuid) -- Takes a student; answers yes or no.
returns boolean language sql stable security definer -- Reads across tables without tripping the access rules it's part of.
set search_path = '' -- Names every table in full, so nothing can be swapped in.
as $$ -- (the check)
  select private.is_admin() -- a full admin (signed in with two steps),
    or private.is_front_desk() -- or a support desk admin,
    or private.is_parent_of(p_student) -- or one of the student's parents,
    or private.is_student_self(p_student) -- or the student themselves.
$$; -- (end of the check)
revoke all on function private.can_see_birth_date(uuid) from public; -- Nobody calls it directly (it's used inside the function below).

-- Whether a student's birth date is still blank. Used by the parent's to-do
-- number ("details still to give"), which can no longer read the column.
create or replace function private.birth_date_missing(p_student uuid) -- Takes a student; answers yes or no.
returns boolean language sql stable security definer -- Reads the hidden column on the caller's behalf.
set search_path = '' -- Names every table in full.
as $$ -- (the check)
  select s.date_of_birth is null -- yes when no birth date is saved,
  from public.students s where s.id = p_student -- for this student,
    and private.can_see_birth_date(p_student) -- and only for someone allowed to know (others get no answer).
$$; -- (end of the check)
revoke all on function private.birth_date_missing(uuid) from public; -- Nobody calls it directly.
grant execute on function private.birth_date_missing(uuid) to authenticated; -- The to-do numbers run as the signed-in person, so they need it.

-- The birth dates the signed-in person may see: their own children (or
-- themselves), or every student for admins. The app reads birth dates here.
create or replace function public.student_birth_dates() -- No inputs: works from who is signed in.
returns table (student_id uuid, date_of_birth date) -- One row per student: the student and their birth date.
language sql stable security definer -- Reads the hidden column, with the check below.
set search_path = '' -- Names every table in full.
as $$ -- (the list)
  select s.id, s.date_of_birth -- each student's id and birth date,
  from public.students s -- from the students table,
  where private.can_see_birth_date(s.id) -- only where this person may know it.
$$; -- (end of the list)
revoke all on function public.student_birth_dates() from public, anon; -- Not for people who aren't signed in.
grant execute on function public.student_birth_dates() to authenticated; -- Signed-in people can ask (the check is inside).

-- Takes away reading the whole students table, then gives back every column
-- except the birth date. Done column by column from the live table, so it
-- matches whatever columns the database has. Writing (adding, editing) is
-- unchanged: parents and admins still save birth dates as before.
revoke select on public.students from authenticated; -- Stops signed-in people reading every column at once.
revoke select on public.students from anon; -- People who aren't signed in never read students (the row rules already stop them; this makes it plain).
do $$ -- (a block of steps)
declare -- The block's working values:
  c text; -- one column's name.
begin -- Starts the steps.
  for c in -- For each column of the students table
    select column_name from information_schema.columns -- (from the list of columns)
    where table_schema = 'public' and table_name = 'students' -- in public.students,
      and column_name <> 'date_of_birth' -- apart from the birth date:
  loop -- (each one)
    execute format('grant select (%I) on public.students to authenticated', c); -- lets signed-in people read that column (the row rules still apply).
  end loop; -- Next column.
end; -- End of the steps.
$$; -- (end of the block)

-- ---------------------------------------------------------------------------
-- 2. The parent's to-do number reads the birth date through the check
-- ---------------------------------------------------------------------------
-- to_do_counts is edited in place, so other changes to it stay.
do $$ -- (a block of steps)
declare -- The block's working values:
  v_def text; -- the to-do function's code.
begin -- Starts the steps.
  v_def := pg_get_functiondef('public.to_do_counts()'::regprocedure); -- Reads the current code.
  v_def := replace(v_def, chr(13), ''); -- Removes Windows line endings from pasting.
  if strpos(v_def, 'private.birth_date_missing(s.id)') > 0 then -- Already changed:
    return; -- nothing to do.
  end if; -- (end of that check)
  if strpos(v_def, 's.date_of_birth is null') = 0 then -- The line to change isn't there any more:
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message.
  end if; -- (end of that check)
  v_def := replace(v_def, 's.date_of_birth is null', 'private.birth_date_missing(s.id)'); -- Swaps the column read for the checked function.
  execute v_def; -- Saves the new code.
end; -- End of the steps.
$$; -- (end of the block)

-- ---------------------------------------------------------------------------
-- 3. "Download my data" still includes the family's own birth dates
-- ---------------------------------------------------------------------------
-- my_data_export leaves out columns the person can't read, so the birth date
-- would drop out. This adds it back for the person's own children (and
-- themselves), never anyone else's, even for admins. Edited in place.
do $$ -- (a block of steps)
declare -- The block's working values:
  v_def text; -- the export function's code.
begin -- Starts the steps.
  v_def := pg_get_functiondef('public.my_data_export()'::regprocedure); -- Reads the current code.
  v_def := replace(v_def, chr(13), ''); -- Removes Windows line endings from pasting.
  if strpos(v_def, 'student_birth_dates') > 0 then -- Already changed:
    return; -- nothing to do.
  end if; -- (end of that check)
  if strpos(v_def, E'  return jsonb_build_object(\n') = 0 then -- The place to add it has changed:
    raise exception 'my_data_export has changed since this update was written. Ask for an updated file.'; -- plain message.
  end if; -- (end of that check)
  v_def := replace(v_def, -- Adds the birth dates just before the export is handed back:
    E'  return jsonb_build_object(\n', -- (finds the line that hands the export back)
    E'  -- Birth dates of the person''s own children (and themselves), read through the check.\n' -- (and puts in front of it: a comment,)
    || E'  select coalesce(jsonb_agg(to_jsonb(b)), ''[]'') into v_rows\n' -- (reads the birth dates as a list,)
    || E'  from public.student_birth_dates() b where b.student_id = any (v_students);\n' -- (for their own children and themselves only,)
    || E'  if jsonb_array_length(v_rows) > 0 then\n' -- (and if there are any,)
    || E'    v_out := v_out || jsonb_build_object(''student_birth_dates'', v_rows);\n' -- (adds them to the export,)
    || E'  end if;\n\n' -- (end of that,)
    || E'  return jsonb_build_object(\n'); -- (then the original line.)
  execute v_def; -- Saves the new code.
end; -- End of the steps.
$$; -- (end of the block)

-- ---------------------------------------------------------------------------
-- 4. Add-on prices go to admins and the family, not tutors
-- ---------------------------------------------------------------------------
-- Same as before, except the price and its period are blank for anyone who
-- isn't an admin, the student's parent or the student. Tutors still see
-- whether the student has the add-on, so they know what they can plan.
create or replace function public.add_on_for_student(p_code text, p_student uuid) -- Takes the add-on's code and a student.
returns table (has_it boolean, mode text, name text, price_cents int, price_period text) -- Whether they have it, how it's set up, its name and price.
language sql stable security definer -- Reads across tables, with the checks below.
set search_path = '' -- Names every table in full.
as $$ -- (the answer)
  select coalesce(private.has_add_on(a.code, p_student), false), -- whether the student has it (no if unknown),
         a.mode, a.name, -- free or paid, and its name,
         case when private.is_admin() or private.is_finance_admin() -- the price, only for admins
                or private.is_parent_of(p_student) or private.is_student_self(p_student) -- or the family,
              then a.price_cents end, -- (blank for anyone else),
         case when private.is_admin() or private.is_finance_admin() -- and how often it's charged, on the same rule
                or private.is_parent_of(p_student) or private.is_student_self(p_student) -- (admins or the family),
              then a.price_period end -- (blank for anyone else).
  from public.add_ons a -- from the add-ons list,
  where a.code = p_code and private.can_view_student(p_student) -- for this add-on, and only for people who can see the student.
$$; -- (end of the answer)
revoke all on function public.add_on_for_student(text, uuid) from public, anon; -- Not for people who aren't signed in.
grant execute on function public.add_on_for_student(text, uuid) to authenticated; -- Signed-in people can ask (the checks are inside).
