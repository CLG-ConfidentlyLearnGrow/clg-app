-- Summary: checks the concerning-words flags (Carla, 13 Nov 2026): that
-- matching finds whole words and phrases (with apostrophes, dashes and "*"
-- endings), that new text makes a private flag without stopping the save,
-- that edits only flag new words, that staff-only words ignore parents, who
-- can read flags and the word list (officer and deputy with two-step
-- sign-in, never their own writing), reviewing, the to-do number, and the
-- alert email (no names or words in it). Reuses access_rules.test.sql
-- people: owner Olive (...a0, officer here), operations admin Sam Staff
-- (...b0, deputy here), tutor T1 (...11, teaches Cara), tutor T2 (...12)
-- and parent P1 (...01, Cara's parent). Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the concerning-words database change again (checks it can run twice).
\ir ../migrations/20261114100100_safety_watch_words.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
update public.child_safety_contacts set officer_id = '00000000-0000-0000-0000-0000000000a0', deputy_id = '00000000-0000-0000-0000-0000000000b0' where id; -- Olive is officer, Sam Staff is deputy

-- 1. Matching: whole words, apostrophes, dashes, spacing and "*" endings.
select tests.eq((select count(*) from public.safety_watch_words), (select count(*) from public.safety_watch_words where added_by is null), 'the starting list is in place'); -- loaded once
select tests.eq((private.watch_normalise('I''m great at this skill') ~ private.watch_pattern('kill'))::int, 0, '"kill" doesn''t match inside "skill"'); -- whole words only
select tests.eq((private.watch_normalise('Don’t tell your MUM, ok?') ~ private.watch_pattern('don''t tell your mum'))::int, 1, 'curly apostrophes and capitals still match'); -- tidied the same way
select tests.eq((private.watch_normalise('talked about self-harm') ~ private.watch_pattern('self harm'))::int, 1, '"self-harm" matches "self harm"'); -- dash becomes a space
select tests.eq((private.watch_normalise('want   to' || chr(10) || 'die') ~ private.watch_pattern('want to die'))::int, 1, 'extra spaces and new lines still match'); -- any spacing
select tests.eq((private.watch_normalise('he was bullied again') ~ private.watch_pattern('bull*'))::int, 1, 'a "*" ending matches longer words'); -- any ending
select tests.eq((private.watch_normalise('a bull ran') ~ private.watch_pattern('bully*'))::int, 0, 'a "*" ending still needs the start of the word'); -- "bull" isn't "bully"
select tests.eq((private.watch_normalise('I feel like killing myself') ~ private.watch_pattern('kill* myself'))::int, 1, 'a "*" works on a word in the middle of a phrase'); -- "killing myself"
select tests.eq((private.watch_normalise('cost (a+b)?') ~ private.watch_pattern('(a+b)?'))::int, 1, 'special characters are matched as ordinary text'); -- no pattern tricks

-- 2. New text makes a flag, and the text is still saved.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- signs in as tutor T1 (the save runs as the database, so only the check is tested)
insert into public.session_notes (student_id, tutor_id, session_date, went_well, next_step) -- T1 writes a session summary:
values (:'cara', '00000000-0000-0000-0000-000000000011', current_date, 'Good work on fractions.', 'Talk to mum: Cara said everyone hates me and that she wants to die.') -- with two listed phrases
returning id as note1 \gset
-- (keeps the summary's id as note1)
select tests.eq((select count(*) from public.session_notes where id = :'note1'), 1::bigint, 'the summary is saved as normal'); -- not blocked
select tests.eq((select count(*) from public.safety_word_flags where source_id = :'note1'), 1::bigint, 'one flag for the box with the words'); -- one box matched
select tests.eq((select count(*) from public.safety_word_flags where source_id = :'note1' and source_table = 'session_notes' and source_field = 'next_step' -- the flag on the next-step box,
  and urgent and words = array['everyone hates me', 'want* to die'] and student_name = 'Cara One' and author_roles = 'tutor' and text_copy like 'Talk to mum%'), 1::bigint, 'the flag records the box, words, student, writer and a copy of the text'); -- filled in correctly
update public.session_notes set next_step = 'Talk to mum: Cara said everyone hates me and that she wants to die. Follow up.' where id = :'note1'; -- T1 edits the box, same words
select tests.eq((select count(*) from public.safety_word_flags where source_id = :'note1'), 1::bigint, 'an edit with the same words doesn''t flag again'); -- no repeat
update public.session_notes set homework = 'Cara is home alone after school.' where id = :'note1'; -- T1 adds a new listed phrase in another box
select tests.eq((select count(*) from public.safety_word_flags where source_id = :'note1' and source_field = 'homework' and words = array['home alone'] and not urgent), 1::bigint, 'a new word in an edit makes its own flag'); -- new flag
insert into public.session_notes (student_id, tutor_id, session_date, went_well, next_step) -- T1 writes another summary:
values (:'cara', '00000000-0000-0000-0000-000000000011', current_date, 'Great session.', 'Add me on snapchat for help.'); -- asking for contact off CLG
select tests.eq((select count(*) from public.safety_word_flags where 'snapchat' = any (words) and 'add me on' = any (words)), 1::bigint, 'staff-only words flag when a tutor writes them'); -- flagged for staff
select tests.claims('00000000-0000-0000-0000-000000000001'); -- signs in as parent P1
insert into public.session_notes (student_id, tutor_id, session_date, went_well, next_step) -- (stands in for a parent's note)
values (:'cara', '00000000-0000-0000-0000-000000000011', current_date, 'Fine.', 'Text me if you are running late.'); -- a parent asking for a text
select tests.eq((select count(*) from public.safety_word_flags where 'text me' = any (words)), 0::bigint, 'staff-only words don''t flag when a parent writes them'); -- not flagged
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the officer (Olive)
insert into public.session_notes (student_id, tutor_id, session_date, went_well, next_step) -- the officer writes a summary:
values (:'cara', '00000000-0000-0000-0000-000000000011', current_date, 'We read a book about suicide prevention.', 'Keep going.'); -- with a listed word
select tests.claims(null); -- back to the database itself

-- 3. Who can read flags.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the officer, with two-step sign-in
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.safety_word_flags), 3::bigint, 'the officer sees the tutor''s three flags'); -- the tutor's flags
select tests.eq((select count(*) from public.safety_word_flags where 'suicide' = any (words)), 0::bigint, 'the officer can''t see a flag on their own writing'); -- hidden from the writer
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'word_flags'), 3, 'the officer has three flags to review'); -- the to-do number
select tests.fails($q$insert into public.safety_word_flags (source_table, source_field, author_name, words, categories, text_copy) values ('x', 'y', 'z', '{a}', '{other}', 'made up')$q$, 'nobody adds flags directly'); -- refused
select tests.fails($q$update public.safety_word_flags set status = 'no_concern'$q$, 'nobody changes flags directly'); -- refused
select tests.fails($q$delete from public.safety_word_flags$q$, 'nobody deletes flags'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- the officer WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_word_flags), 0::bigint, 'without two-step sign-in the officer sees nothing'); -- hidden
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- the deputy
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_word_flags), 4::bigint, 'the deputy sees all four, including the officer''s'); -- all four
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- tutor T1 (who wrote them)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_word_flags), 0::bigint, 'the tutor who wrote the text can''t see the flags'); -- hidden
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'word_flags'), 0, 'the tutor has no number'); -- zero
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001'); -- parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_word_flags), 0::bigint, 'a parent sees no flags'); -- hidden
reset role; -- back to the database itself

-- 4. The word list: only the officer, deputy and owner.
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- tutor T2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.safety_watch_words), 0::bigint, 'a tutor can''t read the list'); -- hidden, so it can't be worked around
select tests.fails($q$insert into public.safety_watch_words (phrase, category) values ('sneaky', 'other')$q$, 'a tutor can''t add words'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- the deputy
set role authenticated; -- acts as a signed-in person
select tests.eq(((select count(*) from public.safety_watch_words) > 50)::int, 1, 'the deputy can read the list'); -- visible
insert into public.safety_watch_words (phrase, category, urgent) values ('Meet me after class', 'grooming', true); -- adds a phrase
select tests.fails($q$insert into public.safety_watch_words (phrase, category) values ('meet  me after-class', 'grooming')$q$, 'the same phrase can''t be added twice'); -- refused: same once tidied
select tests.fails($q$insert into public.safety_watch_words (phrase, category) values ('a*b', 'other')$q$, 'a "*" is only allowed at the end of a word'); -- refused
select tests.fails($q$insert into public.safety_watch_words (phrase, category) values ('hello *x', 'other')$q$, 'a word can''t start with "*"'); -- refused
select tests.fails($q$insert into public.safety_watch_words (phrase, category, added_by) values ('xyz', 'other', '00000000-0000-0000-0000-000000000011')$q$, 'nobody can fake who added a word'); -- refused: column not allowed
update public.safety_watch_words set active = false where phrase = 'home alone'; -- turns one word off
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_watch_words where phrase = 'Meet me after class' and added_by = '00000000-0000-0000-0000-0000000000b0'), 1::bigint, 'the database records who added it'); -- stamped
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- tutor T1 writes again
insert into public.session_notes (student_id, tutor_id, session_date, went_well, next_step) -- a summary:
values (:'cara', '00000000-0000-0000-0000-000000000011', current_date, 'Meet me after class tomorrow.', 'Cara is home alone on Fridays.') -- the new phrase and the word turned off
returning id as note2 \gset
-- (keeps the summary's id as note2)
select tests.eq((select count(*) from public.safety_word_flags where source_id = :'note2'), 1::bigint, 'a new word is checked straight away, and a word turned off isn''t'); -- only the new phrase

-- 5. Reviewing a flag.
select tests.claims(null); -- back to the database itself
select id as flag1 from public.safety_word_flags where source_id = :'note1' and source_field = 'next_step' \gset
-- (keeps the urgent flag's id as flag1)
select id as flag_own from public.safety_word_flags where 'suicide' = any (words) \gset
-- (keeps the officer's own flag id as flag_own)
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- tutor T1
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.safety_word_flag_review(%L, 'no_concern', 'Nothing to see')$q$, :'flag1'), 'a tutor can''t review flags'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the officer
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.safety_word_flag_review(%L, 'no_concern', '')$q$, :'flag1'), '"No concern" needs a note'); -- refused
select tests.fails(format($q$select public.safety_word_flag_review(%L, 'maybe', 'x')$q$, :'flag1'), 'the decision must be one of the choices'); -- refused
select tests.fails(format($q$select public.safety_word_flag_review(%L, 'no_concern', 'It was a book.')$q$, :'flag_own'), 'the officer can''t review a flag on their own writing'); -- refused
select public.safety_word_flag_review(:'flag1', 'raised_concern', 'Spoke to Cara''s mum and raised a concern.'); -- reviews the urgent flag
select tests.eq((select count(*) from public.safety_word_flags where id = :'flag1' and status = 'raised_concern' and reviewed_by_name = 'Olive Owner' and reviewed_at is not null), 1::bigint, 'the decision, who and when are recorded'); -- saved
select tests.eq((select n from public.to_do_counts() where area = 'safety' and section = 'word_flags'), 3, 'a reviewed flag leaves the to-do number'); -- 4 visible new minus 1
reset role; -- back to the database itself
select tests.eq((select count(*) from public.audit_log where action = 'safety_word_flag_review' and details::text not like '%want to die%' and details::text not like '%mum%'), 1::bigint, 'the activity log has the decision but no words'); -- nothing leaked

-- 6. Alert emails for urgent flags: no names or words.
select tests.claims(null); -- acts as the database itself
select tests.eq(private.watch_word_emails_waiting()::int, 1, 'urgent alerts are waiting'); -- waiting
select tests.eq(private.emails_waiting()::int, 1, 'the shared email check sees them'); -- the sender would wake
create temp table claimed as select * from public.watch_word_emails_claim(50); -- takes the waiting emails
select tests.eq((select count(*) from claimed), 2::bigint, 'one email per urgent flag not yet reviewed'); -- the officer's and the new phrase; not-urgent and reviewed ones are skipped
select tests.eq((select count(*) from claimed where body ilike '%cara%' or body ilike '%suicide%' or body ilike '%snapchat%' or subject ilike '%cara%'), 0::bigint, 'emails hold no names or words'); -- confidential
select tests.eq((select count(*) from claimed c join public.account_private ap on ap.email = c.email where ap.account_id = '00000000-0000-0000-0000-0000000000b0'), 1::bigint, 'the flag on the officer''s writing is emailed to the deputy'); -- goes to the other contact
select tests.eq(private.watch_word_emails_waiting()::int, 0, 'nothing waiting once taken'); -- all taken
select public.watch_word_emails_release(array(select id from claimed)); -- puts them back (as if sending failed)
select tests.eq(private.watch_word_emails_waiting()::int, 1, 'put back to try again'); -- waiting again

-- 7. A problem in the check never stops the save.
alter table public.safety_watch_words disable row level security; -- (setting up a broken word, which the rules would normally stop)
update public.safety_watch_words set active = true where phrase = 'home alone'; -- turns the word back on
alter table public.safety_word_flags add constraint test_break check (source_table <> 'session_notes') not valid; -- makes any new flag fail to save
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- tutor T1
insert into public.session_notes (student_id, tutor_id, session_date, went_well, next_step) -- a summary that would be flagged:
values (:'cara', '00000000-0000-0000-0000-000000000011', current_date, 'Cara is home alone.', 'Keep going.') returning id as note3 \gset
-- (keeps the summary's id as note3)
select tests.claims(null); -- back to the database itself
select tests.eq((select count(*) from public.session_notes where id = :'note3'), 1::bigint, 'the text is still saved when the check fails'); -- saved anyway

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  concerning words: all checks passed'
