-- Summary: checks that the copied text on "No concern" flags is cleared
-- after 12 months (Carla, 15 Nov 2026), and that nothing else is: newer
-- "No concern" flags, flags being followed up or raised as a concern, and
-- flags not yet reviewed all keep their text. The rest of a cleared flag
-- stays. Reuses access_rules.test.sql people: tutor T1 (...11, teaches
-- Cara). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the clearing database change again (checks it can run twice).
\ir ../migrations/20261116100100_clear_no_concern_flags.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
insert into public.safety_word_flags (source_table, source_field, author_name, student_id, words, categories, text_copy, status, review_note, reviewed_at) -- five made-up flags:
values
  ('session_notes', 'next_step', 'Tutor One', :'cara', '{suicide}', '{self_harm}', 'old false alarm', 'no_concern', 'A book for English.', now() - interval '13 months'), -- a "No concern" flag decided 13 months ago,
  ('session_notes', 'next_step', 'Tutor One', :'cara', '{suicide}', '{self_harm}', 'recent false alarm', 'no_concern', 'A book for English.', now() - interval '11 months'), -- one decided 11 months ago,
  ('session_notes', 'next_step', 'Tutor One', :'cara', '{suicide}', '{self_harm}', 'old concern', 'raised_concern', 'Raised with CARL.', now() - interval '13 months'), -- an old one raised as a concern,
  ('session_notes', 'next_step', 'Tutor One', :'cara', '{suicide}', '{self_harm}', 'old follow up', 'following_up', null, now() - interval '13 months'), -- an old one being followed up,
  ('session_notes', 'next_step', 'Tutor One', :'cara', '{suicide}', '{self_harm}', 'not reviewed', 'new', null, null); -- and one not reviewed yet

select tests.eq(private.clear_no_concern_flag_text()::bigint, 1::bigint, 'one flag is cleared'); -- only the old "No concern" one
select tests.eq((select count(*) from public.safety_word_flags where review_note = 'A book for English.' and text_cleared_at is not null -- the old "No concern" flag:
  and text_copy like 'Cleared after 12 months%' and words = '{suicide}' and author_name = 'Tutor One' and reviewed_at is not null), 1::bigint, 'its text is replaced, the rest of the record stays'); -- cleared but still a record
select tests.eq((select count(*) from public.safety_word_flags where text_copy in ('recent false alarm', 'old concern', 'old follow up', 'not reviewed')), 4::bigint, 'newer, raised, followed-up and unreviewed flags keep their text'); -- untouched
select tests.eq(private.clear_no_concern_flag_text()::bigint, 0::bigint, 'running it again clears nothing more'); -- already done
select tests.eq((select count(*) from public.audit_log where action = 'clear_no_concern_flag_text' and details::text not like '%false alarm%'), 1::bigint, 'the activity log has the count but no words'); -- logged once, no details

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  clearing no-concern flag text: all checks passed'
