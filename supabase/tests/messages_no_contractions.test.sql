-- Summary: checks the "no short forms" change for the database's own messages
-- (Carla, 16 Nov 2026). After every database change has run, no wording
-- inside CLG's database steps holds a short form such as "can't", "you're"
-- or "it's". It then saves a test step full of short forms, runs the change
-- again, and checks the step's message is written out correctly, its
-- possessive ("CLG's") is kept, and it still works. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;

-- A test helper: says whether a piece of text holds a short form: a word, an
-- apostrophe (doubled as inside a step's wording, single or curly), then t,
-- re, ve, ll, m or d, or "'s" after it, that, there, what, who, here or let.
create or replace function tests.has_message_short_form(p_text text) returns boolean -- takes the text, answers yes or no
language sql immutable as $f$ -- (a single question to the database)
  select coalesce(p_text, '') ~* ('(\m[a-z]+n(?:''''|''|’)t\M|\m(you|we|they|i|what|who|there|it|that)(?:''''|''|’)(re|ve|ll|m|d)\M|\m(it|that|there|what|who|here|let)(?:''''|''|’)s\M)'); -- looks for any short form, ignoring capitals
$f$;

-- 1. After the change runs, no CLG database step has a short form in its wording.
-- (Runs it first, because earlier test files run some older update files again.)
\ir ../migrations/20261119500200_messages_no_contractions.sql
select tests.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private') and tests.has_message_short_form(p.prosrc)), 0, 'no database step has a short form in its wording'); -- counts steps that still have one

-- 2. A new step with short forms is written out when the change runs again.
create or replace function private.test_short_form_message() returns text -- a test step that refuses with a message
language plpgsql as $f$ -- (written in PL/pgSQL)
begin -- starts the step
  raise exception 'You can''t do that. It''s CLG''s rule, so we won''t change it. You''ll need help, and we''re here.'; -- a message full of short forms and one possessive
end; -- ends the step
$f$;
\ir ../migrations/20261119500200_messages_no_contractions.sql
-- Runs the test step and checks the message it now gives.
do $t$
begin -- starts the check
  perform private.test_short_form_message(); -- runs the step (it always refuses)
  raise exception 'FAILED: the test step should have refused'; -- it did not refuse
exception when others then -- it refused:
  if sqlerrm <> 'You cannot do that. It is CLG''s rule, so we will not change it. You will need help, and we are here.' then -- with the wrong words:
    raise exception 'FAILED: message not written out correctly, got: %', sqlerrm; -- stops the tests and shows what it said
  end if; -- end of the words check
end; -- ends the check
$t$;

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  messages_no_contractions: all checks passed'
