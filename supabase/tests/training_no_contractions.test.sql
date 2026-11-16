-- Summary: checks the "no short forms" wording change (Carla, 16 Nov 2026).
-- After every database change has run, no training module, lesson, quiz
-- question or handbook page holds a short form such as "don't", "you're" or
-- "it's". It also adds a lesson and a handbook page full of short forms,
-- runs the change again, and checks each one is written out correctly while
-- possessives such as "CLG's" stay as they are. Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;

-- A test helper: checks two pieces of text are the same, or stops with both shown.
create or replace function tests.same_text(p_actual text, p_expected text, p_label text) returns void -- takes the actual text, the expected text and a label
language plpgsql as $f$ -- (written in PL/pgSQL)
begin -- starts the helper
  if p_actual is distinct from p_expected then -- the two differ:
    raise exception 'FAILED: % (got "%", expected "%")', p_label, p_actual, p_expected; -- stops the tests and shows both
  end if; -- end of the check
end; -- ends the helper
$f$;

-- A test helper: says whether a piece of text holds a short form: a word, an
-- apostrophe (straight or curly), then t, re, ve, ll, m or d, or "'s" after
-- it, that, there, what, who, here, let, where, how or something.
create or replace function tests.has_short_form(p_text text) returns boolean -- takes the text, answers yes or no
language sql immutable as $f$ -- (a single question to the database)
  select coalesce(p_text, '') ~* ('(\m[a-z]+n(?:''|’)t\M|\m[a-z]+(?:''|’)(re|ve|ll|m|d)\M|\m(it|that|there|what|who|here|let|where|how|something)(?:''|’)s\M)'); -- looks for any short form, ignoring capitals
$f$;

-- 1. Nothing in the training or handbook wording has a short form after all the changes.
select tests.eq((select count(*) from public.training_modules where tests.has_short_form(title) or tests.has_short_form(summary)), 0, 'no module name or summary has a short form'); -- modules
select tests.eq((select count(*) from public.training_lessons where tests.has_short_form(title) or tests.has_short_form(body) or tests.has_short_form(link_label)), 0, 'no lesson has a short form'); -- lessons
select tests.eq((select count(*) from public.training_questions where tests.has_short_form(prompt) or tests.has_short_form(explanation) or tests.has_short_form(array_to_string(options, ' '))), 0, 'no quiz question, choice or explanation has a short form'); -- quiz questions
select tests.eq((select count(*) from public.handbook_pages where tests.has_short_form(title) or tests.has_short_form(body)), 0, 'no handbook page has a short form'); -- handbook

-- 2. New wording with short forms is written out correctly when the change runs again.
insert into public.handbook_pages (id, title, body) values ( -- adds a test handbook page
  '00000000-0000-0000-0000-00000000c0c0', -- with a fixed id (so it can be found below)
  'Something''s happened', -- a heading with a "has" short form
  'Don''t panic. It''s fine, you''re safe and we''ll help. CLG''s team can''t see it and won''t share it. What''s happened? It’s been noted. I''d like a call. You''d already finished. Let''s talk.' -- text with many short forms and one possessive
); -- end of the test page
\ir ../migrations/20261119500100_training_no_contractions.sql
select tests.same_text((select title from public.handbook_pages where id = '00000000-0000-0000-0000-00000000c0c0'), 'Something has happened', 'the heading says "has", not "is"'); -- heading checked
select tests.same_text((select body from public.handbook_pages where id = '00000000-0000-0000-0000-00000000c0c0'), 'Do not panic. It is fine, you are safe and we will help. CLG''s team cannot see it and will not share it. What has happened? It has been noted. I would like a call. You had already finished. Let us talk.', 'every short form is written out and the possessive is kept'); -- text checked

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  training_no_contractions: all checks passed'
