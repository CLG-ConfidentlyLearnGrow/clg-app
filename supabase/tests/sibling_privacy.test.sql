-- Summary: tests that brothers and sisters keep their profiles private from
-- each other (Carla, 16 Nov 2026). When a parent has several children, each
-- child with their own login sees only their own profile, never a
-- sibling's, even though they share the parent and the family. The parent
-- still sees every one of their own children.
-- How it works: it picks the student with records in the most tables (from
-- the earlier test files, so new modules are covered as their tests add
-- data), gives that student a session, an invoice and a credit, and adds two
-- siblings with their own logins to the same family and parent: Kit (17) and
-- Ash (19, an adult). Then, signed in as each sibling, it sweeps every table
-- and view in the app for anything about the first student, and checks the
-- family-facing lists, the data download and the private calendar link.
-- Reuses access_rules.test.sql helpers and family_setup's tests.fails_with.

-- The database change must be safe to run twice, and billing.test.sql re-runs
-- an older billing file that it updates, so this runs it again first.
-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the database change 20261118900100_sibling_privacy.sql again.
\ir ../migrations/20261118900100_sibling_privacy.sql
-- Then runs 20261118900300_billing_only_payers.sql, which replaced its billing
-- rule: only the people paying see billing (Carla, 16 Nov 2026).
\ir ../migrations/20261118900300_billing_only_payers.sql

-- ---------------------------------------------------------------------------
-- Helper: what can the signed-in person see about another student?
-- ---------------------------------------------------------------------------
-- Looks in every app table and view for rows about the given student: rows
-- naming the student, their sessions, bookings or invoices, and (for
-- family-level tables with no student column, such as invoices and credits)
-- rows for their family. Gives back the names of any tables where something
-- shows, with how many rows, or an empty text when nothing shows.
-- The ids are passed in because the signed-in person can't look them up.
create function tests.sibling_leaks( -- takes:
  p_student uuid, -- the student whose profile should stay private,
  p_family uuid, -- their family,
  p_sessions uuid[], -- their sessions,
  p_bookings uuid[], -- their bookings,
  p_invoices uuid[] -- and their family's invoices.
) returns text -- gives back the tables where something shows (empty if none)
language plpgsql as $$ -- (runs as whoever is signed in, so the access rules apply)
declare -- working values:
  t record; -- one table or view
  v_where text; -- the rows about the student in that table
  v_count bigint; -- how many of those rows the signed-in person sees
  v_found text := ''; -- the tables where something shows
begin -- start
  for t in -- for each table or view in the app:
    select c.relname, -- its name,
           bool_or(a.attname = 'student_id') as has_student, -- whether it names a student,
           bool_or(a.attname = 'session_id') as has_session, -- a session,
           bool_or(a.attname = 'booking_id') as has_booking, -- a booking,
           bool_or(a.attname = 'invoice_id') as has_invoice, -- an invoice,
           bool_or(a.attname = 'family_id') as has_family -- or a family
    from pg_catalog.pg_class c -- (from the database's list of tables,
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace -- in their schema,
    join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped -- with their columns)
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') -- app tables and views only
    group by c.relname -- one row per table
    order by c.relname -- in name order
  loop -- (each table)
    v_where := case -- which rows are about the student:
      when t.relname = 'students' then format('id = %L', p_student) -- the student's own row,
      else concat_ws(' or ', -- otherwise any of:
        case when t.has_student then format('student_id = %L', p_student) end, -- rows naming the student,
        case when t.has_session then format('session_id = any (%L::uuid[])', p_sessions) end, -- rows about their sessions,
        case when t.has_booking then format('booking_id = any (%L::uuid[])', p_bookings) end, -- their bookings,
        case when t.has_invoice then format('invoice_id = any (%L::uuid[])', p_invoices) end, -- their family's invoices,
        case when t.relname = 'billing_invoices' then format('id = any (%L::uuid[])', p_invoices) end, -- the invoices themselves,
        case when t.has_family and not t.has_student then format('family_id = %L', p_family) end) -- family-level rows (tables with no student column)
    end; -- (end of the choice)
    continue when coalesce(v_where, '') = ''; -- nothing to check in this table: next
    begin -- tries the count:
      execute format('select count(*) from public.%I where %s', t.relname, v_where) into v_count; -- counts the rows the signed-in person sees
    exception when insufficient_privilege then -- not allowed to read the table at all:
      v_count := 0; -- sees nothing, which is a pass
    end; -- (end of the try)
    if v_count > 0 then -- something shows:
      v_found := v_found || t.relname || ' (' || v_count || ') '; -- notes the table and how many rows
    end if; -- (end of the check)
  end loop; -- (end of the tables)
  return btrim(v_found); -- hands back the list
end; -- end
$$; -- (end of the helper)
grant execute on function tests.sibling_leaks(uuid, uuid, uuid[], uuid[], uuid[]) to authenticated; -- lets signed-in test users run it

-- Helper: checks a text is empty, and shows it when it isn't.
create function tests.none(p_found text, p_label text) returns void -- takes what was found and a label
language plpgsql as $$ -- (written in PL/pgSQL)
begin -- start
  if coalesce(p_found, '') <> '' then -- something was found:
    raise exception 'FAIL %: %', p_label, p_found; -- stops, naming the label and what showed
  end if; -- (end of the check)
end; -- end
$$; -- (end of the helper)
grant execute on function tests.none(text, text) to authenticated; -- lets signed-in test users run it

-- ---------------------------------------------------------------------------
-- Set up: the first student, with a session, an invoice and a credit
-- ---------------------------------------------------------------------------
select tests.claims(null); -- signs out (the set-up runs as the test user, with the access rules off)
-- Picks the student with records in the most app tables (from earlier test
-- files), and keeps their id as kid, name as kid_name and parent as kid_parent.
with tables_with_students as materialized ( -- the app tables that name a student (worked out first):
  select c.relname from pg_catalog.pg_class c -- each table
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace -- in its schema
  join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attname = 'student_id' and not a.attisdropped -- with a student column
  where n.nspname = 'public' and c.relkind = 'r' -- app tables only
), per_student as ( -- how many of those tables have rows for each student:
  select s.id, s.full_name, -- the student and their name,
         (select count(*) from tables_with_students t -- the number of tables
          where (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from public.%I where student_id = %L', t.relname, s.id), false, true, '')))[1]::text::int > 0) as n -- with at least one row for them
  from public.students s -- for each student
  where s.account_id is null -- on a parent's account (no own login)
    and exists (select 1 from public.parent_student_links l where l.student_id = s.id) -- with a parent
)
select p.id as kid, p.full_name as kid_name, -- keeps the student's id and name,
       (select l.parent_id from public.parent_student_links l where l.student_id = p.id order by l.parent_id limit 1) as kid_parent -- and one of their parents
from per_student p order by p.n desc, p.full_name limit 1 \gset

-- Makes sure the student is in a family, and keeps the family id as fam.
insert into public.families (name) -- adds a family for them if they have none:
select 'Sibling Test Family' where (select family_id from public.students where id = :'kid') is null; -- (only when needed)
update public.students set family_id = (select id from public.families where name = 'Sibling Test Family') -- puts them in it:
where id = :'kid' and family_id is null; -- (only when they had none)
select family_id as fam from public.students where id = :'kid' \gset

-- A current tutor for the student (one already assigned, or tutor T1), kept as tut.
select coalesce((select a.tutor_id from public.tutor_assignments a where a.student_id = :'kid' order by a.starts_on desc limit 1), -- their latest tutor, or (next line) tutor T1 when they have none
                '00000000-0000-0000-0000-000000000011'::uuid) as tut \gset

-- A session for the student in 3 days, kept as kid_session.
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- adds a session:
values (:'kid', :'tut', :'fam', 'Sibling Privacy Maths', 'school', 'online', -- for the student, online,
        now() + interval '3 days', now() + interval '3 days 1 hour') -- in 3 days, for an hour,
returning id as kid_session \gset

-- An open invoice for the family with a line for that session, kept as kid_invoice.
insert into public.billing_invoices (family_id, family_name, plan, method, period_start, period_end, first_session_on, send_on, due_on, charge_on, status, subtotal_cents, total_cents) -- adds an invoice:
values (:'fam', 'Sibling Test', 'weekly', 'none', current_date, current_date + 6, current_date + 3, current_date, current_date + 2, current_date + 2, 'open', 9500, 9500) -- sent, for this week,
returning id as kid_invoice \gset
insert into public.billing_invoice_lines (invoice_id, session_id, student_id, line_date, description, minutes, billed_minutes, hourly_cents, amount_cents) -- adds its line:
values (:'kid_invoice', :'kid_session', :'kid', current_date + 3, 'Sibling Privacy Maths', 60, 60, 9500, 9500); -- for the student's session
insert into public.billing_credits (family_id, kind, amount_cents, note) -- adds a goodwill credit for the family:
values (:'fam', 'goodwill', 1000, 'Sibling privacy test'); -- ($10)

-- The student's sessions and bookings (including from earlier tests), as lists.
select coalesce(array_agg(id), '{}') as kid_sessions from public.sessions where student_id = :'kid' \gset
select coalesce(array_agg(id), '{}') as kid_bookings from public.bookings where student_id = :'kid' \gset
select coalesce(array_agg(id), '{}') as kid_invoices from public.billing_invoices where family_id = :'fam' \gset

-- ---------------------------------------------------------------------------
-- Set up: two siblings with their own logins, in the same family and parent
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values -- two learners sign up:
  ('00000000-0000-0000-0000-000000000081', 'sib-kit@example.com', -- Kit (account ...81),
   json_build_object('signup_as', 'learner', 'full_name', 'Kit Sibling', 'date_of_birth', (current_date - interval '17 years')::date, -- aged 17,
                     'state', 'SA', 'year_level', 'Year 11', 'school', 'Hill HS')), -- (state, year level and school),
  ('00000000-0000-0000-0000-000000000082', 'sib-ash@example.com', -- and Ash (account ...82),
   json_build_object('signup_as', 'learner', 'full_name', 'Ash Sibling', 'date_of_birth', (current_date - interval '19 years')::date, -- aged 19 (an adult),
                     'state', 'SA', 'year_level', 'Year 12', 'school', 'Hill HS')); -- (state, year level and school).
-- Keeps Kit's and Ash's student ids as kit and ash.
select id as kit from public.students where account_id = '00000000-0000-0000-0000-000000000081' \gset
select id as ash from public.students where account_id = '00000000-0000-0000-0000-000000000082' \gset
update public.students set family_id = :'fam' where id in (:'kit', :'ash'); -- puts both in the first student's family
insert into public.parent_student_links (parent_id, student_id, can_manage) values -- links both to the same parent:
  (:'kid_parent', :'kit', true), -- Kit,
  (:'kid_parent', :'ash', true); -- and Ash
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- gives Kit a session of their own:
values (:'kit', :'tut', :'fam', 'Kit Own English', 'school', 'online', now() + interval '4 days', now() + interval '4 days 1 hour'); -- (in 4 days)

-- ---------------------------------------------------------------------------
-- Kit (17, own login) sees nothing on their sibling's profile
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000081', 'aal2'); -- signs in as Kit (with two-step sign-in, the most access they could have)
set role authenticated; -- acts as a signed-in user, so the access rules apply
select tests.none(tests.sibling_leaks(:'kid', :'fam', :'kid_sessions', :'kid_bookings', :'kid_invoices'), 'Kit sees their sibling''s records in'); -- checks: no table or view shows anything about the sibling
select tests.eq((select count(*) from public.students), 1, 'Kit sees only their own student profile'); -- checks: only Kit's own profile
select tests.eq((select count(*) from public.students where id = :'kit'), 1, 'Kit still sees their own profile'); -- checks: Kit's own profile still shows
select tests.eq((select count(*) from public.sessions where student_id = :'kit'), 1, 'Kit still sees their own session'); -- checks: Kit's own session still shows
select tests.eq((select count(*) from public.student_birth_dates() where student_id <> :'kit'), 0, 'Kit sees no sibling''s birth date'); -- checks: no other birth dates
select tests.eq((select count(*) from public.list_bookings() where student_id = :'kid'), 0, 'Kit''s bookings list leaves out the sibling'); -- checks: booking list
select tests.eq((select count(*) from public.list_makeup_offers() where student_id = :'kid'), 0, 'Kit''s make-up list leaves out the sibling'); -- checks: make-up times list
select tests.eq((select count(*) from public.list_session_requests() where student_id = :'kid'), 0, 'Kit''s requests list leaves out the sibling'); -- checks: session requests list
select tests.eq((select count(*) from public.list_renewals() where booking_id = any (:'kid_bookings'::uuid[]) or student_name = :'kid_name'), 0, 'Kit''s renewals list leaves out the sibling'); -- checks: renewals list
select tests.eq((select count(*) from public.billing_my_plan_choices()), 0, 'Kit is not offered the family''s billing'); -- checks: no family billing
select tests.eq((select count(*) from (select public.my_data_export()::text as x) d where position(:'kid'::text in d.x) > 0 or position(:'kid_name' in d.x) > 0), 0, 'Kit''s data download leaves out the sibling'); -- checks: the download has no sibling id or name
-- Kit makes a private calendar link, and keeps its secret as kit_token.
select public.reset_family_calendar_link() as kit_token \gset
reset role; -- back to the test user (access rules off)

select tests.claims(null); -- signs out
set role anon; -- acts as a calendar app reading Kit's private link
select tests.eq((select count(*) from public.family_calendar_feed(:'kit_token') where session_id = any (:'kid_sessions'::uuid[])), 0, 'Kit''s calendar link leaves out the sibling''s sessions'); -- checks: no sibling sessions
select tests.eq((select count(*) from public.family_calendar_feed(:'kit_token')), 1, 'Kit''s calendar link shows their own session'); -- checks: their own session shows
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- Ash (19, an adult with own login) sees nothing on their sibling's profile
-- either, and isn't treated as paying for the whole family
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000082', 'aal2'); -- signs in as Ash (with two-step sign-in)
set role authenticated; -- acts as a signed-in user, so the access rules apply
select tests.none(tests.sibling_leaks(:'kid', :'fam', :'kid_sessions', :'kid_bookings', :'kid_invoices'), 'Ash (adult) sees their sibling''s records in'); -- checks: no table or view shows anything about the sibling
select tests.eq((select count(*) from public.students), 1, 'Ash sees only their own student profile'); -- checks: only Ash's own profile
select tests.eq((select count(*) from public.billing_my_plan_choices()), 0, 'Ash is not offered the whole family''s billing'); -- checks: no family billing
select tests.eq(coalesce((select public.billing_credit_balance(:'fam')), 0), 0, 'Ash sees no family credit balance'); -- checks: no family credit
select tests.fails_with(format($$select public.billing_accept_terms(%L, 'test')$$, :'fam'), 'Only the person who pays', 'Ash can''t accept terms for the whole family'); -- checks: refused, with the plain message
select tests.fails_with(format($$select public.billing_choose_plan(%L, 'monthly')$$, :'fam'), '', 'Ash can''t choose the plan for the whole family'); -- checks: refused
select tests.eq((select count(*) from (select public.my_data_export()::text as x) d where position(:'kid'::text in d.x) > 0 or position(:'kid_name' in d.x) > 0), 0, 'Ash''s data download leaves out the sibling'); -- checks: the download has no sibling id or name
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- The parent still sees all their own children, and (as the family's bill
-- payer) the family's billing
-- ---------------------------------------------------------------------------
select tests.claims(null); -- acts as the database itself while setting up
insert into public.billing_accounts (family_id, bill_payer_id) values (:'fam', :'kid_parent') -- names the parent as the bill payer:
on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id; -- (or changes it to the parent)
select tests.claims(:'kid_parent', 'aal2'); -- signs in as the shared parent
set role authenticated; -- acts as a signed-in user, so the access rules apply
select tests.eq((select count(*) from public.students where id in (:'kid', :'kit', :'ash')), 3, 'parent sees all three children'); -- checks: all three children
select tests.eq((select count(*) from public.sessions where id = :'kid_session'), 1, 'parent sees the first child''s session'); -- checks: the session
select tests.eq((select count(*) from public.billing_invoices where id = :'kid_invoice'), 1, 'parent sees the family''s invoice'); -- checks: the invoice
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'kid_invoice'), 1, 'parent sees the invoice line'); -- checks: its line
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 1, 'parent is offered the family''s billing'); -- checks: family billing
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- When CLG names the adult sibling as the family's bill payer, they see the
-- family's billing (an admin's deliberate choice, for example an older
-- sibling who pays for everyone)
-- ---------------------------------------------------------------------------
insert into public.billing_accounts (family_id, bill_payer_id) values (:'fam', '00000000-0000-0000-0000-000000000082') -- names Ash as the bill payer:
on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id; -- (or changes it to Ash)
select tests.claims('00000000-0000-0000-0000-000000000082', 'aal2'); -- signs in as Ash
set role authenticated; -- acts as a signed-in user, so the access rules apply
select tests.eq((select count(*) from public.billing_invoices where id = :'kid_invoice'), 1, 'named bill payer sees the family''s invoice'); -- checks: the invoice shows
select tests.eq((select count(*) from public.students), 1, 'named bill payer still sees only their own profile'); -- checks: still only their own profile
select tests.eq((select count(*) from public.sessions where student_id = :'kid'), 0, 'named bill payer still can''t see the sibling''s sessions'); -- checks: still no sibling sessions
reset role; -- back to the test user
-- Now Ash pays, the parent no longer sees the family's billing (only the
-- people paying see it, Carla 16 Nov 2026), but still sees every child.
select tests.claims(:'kid_parent', 'aal2'); -- signs in as the shared parent
set role authenticated; -- acts as a signed-in user, so the access rules apply
select tests.eq((select count(*) from public.billing_invoices where id = :'kid_invoice'), 0, 'a parent who no longer pays doesn''t see the invoice'); -- checks: hidden
select tests.eq((select count(*) from public.billing_my_plan_choices() where family_id = :'fam'), 0, 'and isn''t offered the family''s billing'); -- checks: hidden
select tests.eq(public.billing_i_pay()::int, 0, 'and gets no Billing tab'); -- checks: no tab
select tests.eq((select count(*) from public.students where id in (:'kid', :'kit', :'ash')), 3, 'but still sees all three children'); -- checks: children unchanged
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- Clean up: removes what this file added, so later test files start as before
-- ---------------------------------------------------------------------------
select tests.claims(null); -- signs out
delete from public.billing_invoice_lines where invoice_id = :'kid_invoice'; -- the invoice line,
delete from public.billing_invoices where id = :'kid_invoice'; -- the invoice,
delete from public.billing_credits where note = 'Sibling privacy test'; -- the credit,
delete from public.billing_accounts where family_id = :'fam' and bill_payer_id = '00000000-0000-0000-0000-000000000082'; -- the billing account naming Ash,
delete from public.family_calendar_links where account_id = '00000000-0000-0000-0000-000000000081'; -- Kit's calendar link,
delete from public.sessions where id = :'kid_session' or student_id = :'kit'; -- the sessions,
delete from public.parent_student_links where student_id in (:'kit', :'ash'); -- the parent links,
delete from public.students where id in (:'kit', :'ash'); -- the two siblings' profiles,
delete from auth.users where id in ('00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000000082'); -- and their accounts.
select 'PASS sibling privacy' as result; -- notes the pass
