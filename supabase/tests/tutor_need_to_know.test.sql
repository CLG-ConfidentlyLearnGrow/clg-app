-- Summary: tutors see only what they need to tutor (Carla, 12 Nov 2026).
-- Every tutor-only account is signed in in turn (with two-step sign-in, so
-- their tutor access is switched on) and must see:
--   * no student they aren't currently matched with, in any table;
--   * no other family's records;
--   * no billing records except their own pay;
--   * no one else's contact details, and no parent they don't work with;
--   * no birth dates at all (they work from the year level).
-- It also checks add-on prices go to the family and not the tutor, and that
-- every students column except the birth date can still be read, so a new
-- column can't be hidden by accident.
-- Reuses access_rules.test.sql helpers (tests.claims, tests.eq, tests.fails)
-- and the accounts and students the earlier test files made.

-- Runs this update again: it must be safe to run twice, and an earlier test
-- file re-ran the study plans update, which put back the old add-on function.
\ir ../migrations/20261113100100_tutor_need_to_know.sql

-- ---------------------------------------------------------------------------
-- The students table: every column readable except the birth date
-- ---------------------------------------------------------------------------
-- Counts students columns the signed-in role can't read, apart from the birth date. Must be none.
select tests.eq((select count(*) from information_schema.columns c -- Counts columns
  where c.table_schema = 'public' and c.table_name = 'students' and c.column_name <> 'date_of_birth' -- of public.students, other than the birth date,
    and not has_column_privilege('authenticated', 'public.students', c.column_name, 'SELECT')), 0, -- that signed-in people can't read.
  'every students column except the birth date is readable (a new column needs a grant like the ones in 20261113100100)'); -- (the label says how to fix it).
select tests.eq(has_column_privilege('authenticated', 'public.students', 'date_of_birth', 'SELECT')::int, 0, 'the birth date column is not directly readable'); -- Checks the birth date itself is hidden.

-- ---------------------------------------------------------------------------
-- Scratch lists, made with full access before anyone signs in
-- ---------------------------------------------------------------------------
-- Every account whose only role is tutor.
create temp table tutor_only as -- A scratch list of tutor-only accounts:
  select distinct r.account_id as id -- each account once,
  from public.account_roles r -- from the roles table,
  where r.role = 'tutor' -- holding the tutor role,
    and not exists ( -- and no other role:
      select 1 from public.account_roles o where o.account_id = r.account_id and o.role <> 'tutor' -- (any other role rules them out).
    ); -- End of the list.
-- The students each tutor is matched with today (the most they may ever see).
create temp table tutor_teaches as -- A scratch list of tutor-student pairs:
  select distinct a.tutor_id, a.student_id -- each pair once,
  from public.tutor_assignments a -- from the matches,
  where private.assignment_is_current(a.starts_on, a.ends_on); -- that are current today.
-- The families of those students.
create temp table tutor_families as -- A scratch list of tutor-family pairs:
  select distinct t.tutor_id, s.family_id -- each pair once,
  from tutor_teaches t join public.students s on s.id = t.student_id -- from the students they teach,
  where s.family_id is not null; -- that have a family.
-- The parents of those students.
create temp table tutor_parents as -- A scratch list of tutor-parent pairs:
  select distinct t.tutor_id, l.parent_id -- each pair once,
  from tutor_teaches t join public.parent_student_links l on l.student_id = t.student_id; -- the parents of the students they teach.
-- Each table that names a student, a family or is a billing table, with the
-- columns that mark a row as the tutor's own record (their own session,
-- notice or pay line).
create temp table tables_to_check as -- A scratch list of tables:
  select c.table_name, -- the table,
         bool_or(c.column_name = 'student_id') as has_student, -- whether it names a student,
         bool_or(c.column_name = 'family_id') as has_family, -- whether it names a family,
         array_agg(c.column_name::text) filter (where c.column_name in ('tutor_id', 'account_id', 'payer_id')) as own_cols -- and the columns that can mark it as the tutor's own.
  from information_schema.columns c -- from the list of columns,
  join pg_catalog.pg_tables t on t.schemaname = 'public' and t.tablename = c.table_name -- only real tables (not views),
  where c.table_schema = 'public' -- in the public area,
  group by c.table_name -- one row per table,
  having bool_or(c.column_name in ('student_id', 'family_id')) or c.table_name like 'billing\_%'; -- that name a student or family, or are billing tables.
-- A scratch table to note anything a tutor can see that they shouldn't.
create temp table tutor_leaks (tutor_id uuid, what text, n bigint); -- Each row: the tutor, what kind of record, and how many.
grant select on tutor_only, tutor_teaches, tutor_families, tutor_parents, tables_to_check to authenticated; -- Lets the signed-in role read the lists (test only).
grant insert, select on tutor_leaks to authenticated; -- Lets the signed-in role note leaks (test only).
select tests.eq((select count(*) >= 2 from tutor_only)::int, 1, 'there are tutor-only accounts to check'); -- Makes sure the sweep really checks someone.
select tests.eq((select count(*) >= 1 from tutor_only o join tutor_teaches t on t.tutor_id = o.id)::int, 1, 'at least one tutor-only account teaches a student'); -- And that at least one of them has a student to see.

-- ---------------------------------------------------------------------------
-- The sweep: every tutor-only account, every table
-- ---------------------------------------------------------------------------
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
do $$ -- (a block of steps)
declare -- The block's working values:
  me uuid; -- the tutor being checked,
  t record; -- one table to check,
  v_where text; -- the rule for "a row this tutor shouldn't see",
  v_n bigint; -- how many such rows they can see.
begin -- Starts the steps.
  for me in select id from tutor_only loop -- For each tutor-only account:
    perform set_config('request.jwt.claims', -- signs in as them,
      json_build_object('sub', me, 'role', 'authenticated', 'aal', 'aal2')::text, true); -- (their id, the signed-in role, two-step sign-in so tutor access is on).

    -- Students they aren't matched with today.
    insert into tutor_leaks -- Notes them:
      select me, 'students (' || s.full_name || ')', 1 from public.students s -- (each student they can see, by name, so a failure says who)
      where not exists (select 1 from tutor_teaches x where x.tutor_id = me and x.student_id = s.id); -- (that they don't teach today).

    -- Every table naming a student, family or billing: rows that aren't
    -- about their students or family, and aren't their own records.
    for t in select * from tables_to_check loop -- For each table:
      -- Billing tables: any row that isn't their own (only their own pay is theirs to see).
      -- Other tables: rows about a student they don't teach or a family they don't work with.
      v_where := case -- (which kind of table)
        when t.table_name like 'billing\_%' then 'true' -- a billing table: every row counts to start with,
        else coalesce(nullif(concat_ws(' or ', -- otherwise: a row naming
          case when t.has_student then -- a student they don't teach,
            format('(student_id is not null and student_id not in (select student_id from tutor_teaches where tutor_id = %L))', me) end, -- (the student isn't on their list)
          case when t.has_family then -- or a family they don't work with
            format('(family_id is not null and family_id not in (select family_id from tutor_families where tutor_id = %L))', me) end -- (the family isn't on their list)
        ), ''), 'false') -- (a blank student or family doesn't count; a table with neither has nothing to count),
      end; -- (end of the kind)
      v_where := format('(%s)', v_where) || coalesce(' and ' || ( -- and leaves out their own records:
        select string_agg(format('%I is distinct from %L', col, me), ' and ') from unnest(t.own_cols) col), ''); -- (rows where they're the tutor, account or payer).
      begin -- Starts an inner block, so "not allowed at all" counts as nothing seen.
        execute format('select count(*) from public.%I where %s', t.table_name, v_where) into v_n; -- Counts the rows they can see that they shouldn't.
      exception when insufficient_privilege then -- If they can't read the table at all:
        v_n := 0; -- that's nothing seen.
      end; -- End of the inner block.
      if t.table_name in ('billing_price_items', 'billing_school_periods') then -- CLG's public price list and school term dates are open to everyone signed in:
        v_n := 0; -- not a leak.
      end if; -- (end of that case)
      insert into tutor_leaks values (me, t.table_name, v_n); -- Notes the count.
    end loop; -- Next table.

    -- Other people's contact details and parent profiles.
    insert into tutor_leaks select me, 'account_private', count(*) from public.account_private where account_id <> me; -- Others' email and phone.
    insert into tutor_leaks select me, 'parent_profiles', count(*) from public.parent_profiles where account_id <> me; -- Parents' emergency contacts and payment ids.
    insert into tutor_leaks select me, 'families', count(*) from public.families; -- Family records (tutors don't need them).
    -- Names of parents they don't work with.
    insert into tutor_leaks -- Notes them:
      select me, 'parent names', count(*) from public.accounts a -- (each name they can see)
      where exists (select 1 from public.parent_profiles p where p.account_id = a.id) -- (that belongs to a parent)
        and a.id <> me -- (not themselves)
        and not exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor')) -- (who isn't also CLG staff, whose names are shown to everyone)
        and not exists (select 1 from tutor_parents x where x.tutor_id = me and x.parent_id = a.id); -- (and isn't a parent of a student they teach).
    -- Birth dates.
    insert into tutor_leaks select me, 'student_birth_dates', count(*) from public.student_birth_dates(); -- Birth dates through the app's function.
  end loop; -- Next tutor.
end; -- End of the steps.
$$; -- (end of the block)
reset role; -- Goes back to the all-powerful test user (access rules off).
-- Shows exactly what leaked, if anything, so a failure is easy to read.
select tests.eq((select coalesce(sum(n), 0) from tutor_leaks)::bigint, 0, -- Checks no tutor saw anything they shouldn't:
  'tutor-only accounts see only their matched students: ' || coalesce((select string_agg(what || ' x' || n, ', ') from tutor_leaks where n > 0), 'none')); -- (the label names any leak).

-- ---------------------------------------------------------------------------
-- A matched tutor: sees their student, but not the birth date or prices
-- ---------------------------------------------------------------------------
-- Picks a tutor-only account, one student they teach and can see, and one of that student's parents (to compare).
select o.id as tutor, t.student_id as student, l.parent_id as parent -- the tutor, student and parent,
from tutor_only o join tutor_teaches t on t.tutor_id = o.id -- a tutor-only account and a student they teach,
join public.parent_student_links l on l.student_id = t.student_id -- a student with a parent,
where private.tutor_cleared_for_student(o.id, t.student_id) -- whose checks are in date for that student,
order by o.id, t.student_id, l.parent_id limit 1 \gset
update public.add_ons set mode = 'paid', price_cents = 2500 where code = 'study_plans'; -- Makes study plans a paid add-on for a moment ($25 a month).

select tests.claims(:'tutor', 'aal2'); -- Signs in as the tutor, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.students where id = :'student'), 1, 'tutor sees their matched student'); -- Checks the tutor can see their student.
select tests.fails(format($$select date_of_birth from public.students where id = %L$$, :'student'), 'tutor reads a birth date'); -- Checks the birth date can't be read directly.
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'student')), 1, 'tutor sees whether the add-on is on'); -- Checks the tutor still gets the add-on's details,
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'student') where price_cents is null and price_period is null), 1, 'tutor sees no add-on price'); -- but not its price.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims(:'parent'); -- Signs in as the student's parent.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_birth_dates() where student_id = :'student' and date_of_birth is not null), 1, 'parent sees their child''s birth date'); -- Checks the parent still gets the birth date,
select tests.eq((select count(*) from public.add_on_for_student('study_plans', :'student') where price_cents = 2500), 1, 'parent sees the add-on price'); -- and the add-on price.
select tests.eq(((public.my_data_export() -> 'records' -> 'student_birth_dates') is not null)::int, 1, 'parent''s data download includes birth dates'); -- And their data download still includes birth dates.
reset role; -- Goes back to the all-powerful test user (access rules off).

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as the owner, with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.eq((select count(*) from public.student_birth_dates()), (select count(*) from public.students), 'admins see every student''s birth date'); -- Checks admins get every birth date.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- ---------------------------------------------------------------------------
-- Tidy up, so later test files start from the same place
-- ---------------------------------------------------------------------------
update public.add_ons set mode = 'free', price_cents = null where code = 'study_plans'; -- Puts study plans back to free.
select tests.claims(null); -- Signs out, so no one is signed in.

-- Prints that every check in this file passed.
\echo '  tutors see only what they need: all checks passed'
