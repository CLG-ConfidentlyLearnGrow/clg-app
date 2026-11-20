-- Summary: checks the app-speed update (Carla asked how to keep the app
-- fast, 18 Nov 2026; see docs/features/app-speed.md):
--   1. every access rule asks "same for every row" questions (who is signed
--      in, is this an admin, and so on) only once per request, wrapped in
--      (select ...). A new rule written the slow way makes this test fail,
--      with a message saying which rule to fix;
--   2. the update can run twice without changing anything the second time;
--   3. the "summaries still to write" list is in the fast form;
--   4. who can see sessions is unchanged: a parent sees only their own
--      child's sessions, and the other parent sees none of them.
-- Reuses access_rules.test.sql people: parent P1 (...01), parent P2 (...02),
-- tutor T1 (...11). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the app-speed update again (checks it can run twice).
\ir ../migrations/20261122100100_faster_access_rules.sql

-- ===========================================================================
-- 1 and 2: no access rule is left in the slow form.
-- ===========================================================================
do $$ -- Runs the check below.
declare -- Working values:
  v_slow text; -- the names of any rules still in the slow form.
begin -- Start of the check.
  select string_agg(schemaname || '.' || tablename || ' "' || policyname || '"', ', ') -- Lists each slow rule by area, table and name,
    into v_slow -- keeping the list here,
  from pg_catalog.pg_policies -- from the database's list of access rules,
  where schemaname in ('public', 'private', 'storage') -- in the app's areas and the file store,
    and (private.fast_rule_text(qual) is distinct from qual -- where the "using" part would still change if rewritten,
         or private.fast_rule_text(with_check) is distinct from with_check); -- or the "with check" part would.
  if v_slow is not null then -- If any were found:
    raise exception 'FAIL: these access rules ask "same for every row" questions once per row (slow). Wrap auth.uid(), private.is_admin() and similar in (select ...), or run supabase/migrations/20261122100100_faster_access_rules.sql again: %', v_slow; -- stops, naming them.
  end if; -- End of the check.
end; -- End of the check.
$$; -- End of the block.

-- ===========================================================================
-- 3: the "summaries still to write" list asks "is this an admin?" once.
-- ===========================================================================
select tests.eq( -- Checks a number:
  (select count(*) from pg_catalog.pg_proc -- counts functions
   where oid = 'public.list_notes_due()'::regprocedure -- that are the "summaries still to write" list
     and prosrc like '%(select private.is_admin())%'), -- and ask "is this an admin?" in the fast form,
  1, -- expecting exactly one,
  'summaries still to write list uses the fast form'); -- (label shown if it fails).

-- ===========================================================================
-- 4: who sees sessions is unchanged after the rewrite.
-- ===========================================================================
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)

select tests.claims(null); -- Acts as the database itself while setting up.
set local session_replication_role = replica; -- Skips the booking checks while adding test sessions directly (setting up only).
insert into public.sessions (student_id, tutor_id, family_id, subject, level_kind, delivery, starts_at, ends_at) -- Adds three test sessions:
select l.student_id, :'t1', s.family_id, 'Mathematics', 'school', 'online', -- for parent P1's child, with tutor T1,
       now() + (g || ' days')::interval, now() + (g || ' days')::interval + interval '1 hour' -- one each day for the next three days,
from public.parent_student_links l -- using parent P1's link to their child,
join public.students s on s.id = l.student_id -- and that child's family,
cross join generate_series(1, 3) g -- three times over,
where l.parent_id = :'p1' -- only parent P1's links,
  and l.student_id not in (select student_id from public.parent_student_links where parent_id = :'p2') -- and only a child parent P2 is not linked to.
limit 3; -- (no more than three).
set local session_replication_role = origin; -- Turns the normal checks back on.

set local role authenticated; -- Acts as a signed-in person from here.
select tests.claims(:'p1'); -- Signs in as parent P1.
select tests.eq((select count(*) from public.sessions), 3, 'parent sees their own child''s sessions'); -- Checks: P1 sees all three.
select tests.claims(:'p2'); -- Signs in as parent P2.
select tests.eq((select count(*) from public.sessions s where s.starts_at > now()), 0, 'other parent sees none of them'); -- Checks: P2 sees none.
reset role; -- Goes back to the database itself.

-- Undoes everything above.
rollback;
\echo '  fast access rules: all checks passed'
