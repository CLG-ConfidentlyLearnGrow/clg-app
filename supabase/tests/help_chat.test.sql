-- Summary: checks the help chat (Carla, 16 Nov 2026). A parent can ask CLG
-- about their own child (never someone else's), the help desk admins for that
-- kind of question read and answer it, other parents, tutors and siblings
-- never see it, admins can start a chat with the parents they choose, emails
-- say nothing private and skip chats already read, messages are checked for
-- concerning words, and a parent who is no longer linked to a child stops
-- seeing chats about them. Reuses access_rules.test.sql people: owner Olive
-- (...a0), operations admin Sam Staff (...b0), tutor T1 (...11, teaches Cara
-- and Ada), tutor T2 (...12), parent P1 (...01, Cara's parent), parent P2
-- (...02, Cal and Vic's parent), adult learner Ada (...21, her own login).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the help chat database change again (checks it can run twice).
\ir ../migrations/20261119910100_help_chat.sql

-- ---------------------------------------------------------------------------
-- Setting up
-- ---------------------------------------------------------------------------
select tests.claims(null); -- acts as the database itself while setting up
\set olive '00000000-0000-0000-0000-0000000000a0'
-- (Olive's account id: the owner)
\set sam '00000000-0000-0000-0000-0000000000b0'
-- (Sam Staff's account id: an operations admin)
\set t1 '00000000-0000-0000-0000-000000000011'
-- (tutor T1's account id)
\set t2 '00000000-0000-0000-0000-000000000012'
-- (tutor T2's account id)
\set p1 '00000000-0000-0000-0000-000000000001'
-- (parent P1's account id)
\set p2 '00000000-0000-0000-0000-000000000002'
-- (parent P2's account id)
\set ada '00000000-0000-0000-0000-000000000021'
-- (adult learner Ada's account id)
\set cal_login '00000000-0000-0000-0000-000000000031'
-- (the teenager's account id, given to Cal below)
\set sue '00000000-0000-0000-0000-0000000009a1'
-- (Sue Support's account id: a support admin added below)
\set fin '00000000-0000-0000-0000-0000000009a2'
-- (Fran Finance's account id: a finance admin added below)
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values -- adds two more staff sign-ups:
  (:'sue', 'sue.support@clg.example', now(), '{"signup_as":"parent","full_name":"Sue Support"}'), -- Sue,
  (:'fin', 'fran.finance@clg.example', now(), '{"signup_as":"parent","full_name":"Fran Finance"}'); -- and Fran.
insert into public.account_roles (account_id, role) values (:'sue', 'admin'), (:'fin', 'admin') on conflict do nothing; -- both are admins
insert into public.admin_profiles (account_id, level) values (:'sue', 'support'), (:'fin', 'finance') -- Sue is support, Fran is finance
on conflict (account_id) do update set level = excluded.level; -- (replacing any level they had)
select id as cara from public.students where full_name = 'Cara One' \gset
-- (keeps Cara's student id as cara)
select id as cal from public.students where full_name = 'Cal Two' \gset
-- (keeps Cal's student id as cal)
select id as vic from public.students where full_name = 'Vic Two' \gset
-- (keeps Vic's student id as vic)
select id as ada_student from public.students where account_id = :'ada' \gset
-- (keeps Ada's student id as ada_student)
update public.students set account_id = :'cal_login', date_of_birth = current_date - interval '16 years 1 month' where id = :'cal'; -- Cal is 16 and has his own login (Vic's brother)

-- ---------------------------------------------------------------------------
-- 1. A parent asks about their own child, and nobody else's
-- ---------------------------------------------------------------------------
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person, so access rules apply
select tests.eq((select count(*) from public.help_my_students() where id = :'cara' and connection = 'child'), 1::bigint, 'a parent can ask about their own child'); -- Cara is listed
select tests.eq((select count(*) from public.help_my_students() where id in (:'cal', :'vic')), 0::bigint, 'a parent cannot ask about other children'); -- Cal and Vic are not
select public.help_start_chat('missing_info', 'Question about: School', 'Cara is changing school next term. Which one should I put?', :'cara', 'school') as chat1 \gset
-- (P1 asks about Cara's school; keeps the chat id as chat1)
select public.help_start_chat('billing', 'Invoice question', 'Can I pay by the term instead?') as chat_bill \gset
-- (P1 asks a billing question; keeps the chat id as chat_bill)
select tests.fails(format($q$select public.help_start_chat('missing_info', 'About Vic', 'Hello', %L, 'school')$q$, :'vic'), 'a parent cannot start a chat about another family''s child'); -- refused
select tests.fails($q$select public.help_start_chat('missing_info', 'No child', 'Hello', null, 'school')$q$, 'a missing detail needs a child'); -- refused
select tests.fails($q$select public.help_start_chat('nonsense', 'Title', 'Hello')$q$, 'the topic must be on the list'); -- refused
select tests.fails($q$select public.help_start_chat('other', 'x', 'Hello')$q$, 'a title is needed'); -- refused
select tests.fails($q$select public.help_start_chat('other', 'Title', '   ')$q$, 'a message is needed'); -- refused
select tests.fails(format($q$select public.help_start_chat('other', 'Title', 'Hello', %L, 'shoe_size')$q$, :'cara'), 'the missing detail must be on the list'); -- refused
select tests.fails(format($q$insert into public.help_messages (chat_id, author_name, body) values (%L, 'x', 'Direct insert')$q$, :'chat1'), 'nobody adds messages directly'); -- refused
select tests.fails($q$insert into public.help_chats (started_by_name, topic, subject) values ('x', 'other', 'Direct insert')$q$, 'nobody adds chats directly'); -- refused
select tests.eq((select count(*) from public.help_chat_list(false)), 2::bigint, 'the parent sees their two chats'); -- both listed
select tests.eq((select count(*) from public.help_messages where chat_id = :'chat1'), 1::bigint, 'the parent reads their own messages'); -- the first message
select tests.fails($q$select count(*) from public.help_chat_emails$q$, 'nobody signed in can read the email queue'); -- refused
reset role; -- back to the database itself
select tests.eq((select count(*) from public.help_chats where id = :'chat1' and status = 'waiting_on_clg' and student_id = :'cara'), 1::bigint, 'a new chat waits for CLG'); -- waiting for CLG
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat1' and account_id in (:'olive', :'sam')), 2::bigint, 'with nobody looking after it, the owner and operations admins get an email'); -- both queued
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat1' and account_id = :'p1'), 0::bigint, 'the writer is never emailed about their own message'); -- not queued
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat1' and send_after < now() + interval '4 minutes'), 0::bigint, 'emails wait at least a few minutes'); -- not straight away

-- ---------------------------------------------------------------------------
-- 2. Other people never see it
-- ---------------------------------------------------------------------------
select tests.claims(:'p2'); -- signs in as parent P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id in (:'chat1', :'chat_bill')), 0::bigint, 'another parent cannot see the chats'); -- hidden
select tests.eq((select count(*) from public.help_messages where chat_id = :'chat1'), 0::bigint, 'another parent cannot read the messages'); -- hidden
select tests.fails(format($q$select public.help_reply(%L, 'Sneaky reply')$q$, :'chat1'), 'another parent cannot write in the chat'); -- refused
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1 (Cara's tutor)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 0::bigint, 'the child''s tutor does not see the family''s chat with CLG'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal1'); -- Sam WITHOUT two-step sign-in
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 0::bigint, 'an admin without two-step sign-in sees nothing'); -- hidden
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- 3. The help desk: who answers which kind of chat
-- ---------------------------------------------------------------------------
select tests.claims(:'sue', 'aal2'); -- signs in as Sue (support admin)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 1::bigint, 'a support admin sees general chats'); -- visible
select tests.eq((select count(*) from public.help_chats where id = :'chat_bill'), 0::bigint, 'a support admin does not see billing chats'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'fin', 'aal2'); -- signs in as Fran (finance admin)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id = :'chat_bill'), 1::bigint, 'a finance admin sees billing chats'); -- visible
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 0::bigint, 'a finance admin does not see other chats'); -- hidden
reset role; -- back to the database itself
select tests.claims(:'sam', 'aal2'); -- signs in as Sam (operations admin)
set role authenticated; -- acts as a signed-in person
select tests.eq((select n from public.to_do_counts() where area = 'admin' and section = 'help')::bigint, 2::bigint, 'the help desk number counts chats waiting for CLG'); -- two waiting
select tests.eq((select count(*) from public.help_desk_admins('billing') where account_id = :'sue'), 0::bigint, 'support admins are not offered for billing chats'); -- not listed
select tests.eq((select count(*) from public.help_desk_admins('billing') where account_id = :'fin'), 1::bigint, 'finance admins are offered for billing chats'); -- listed
select tests.fails(format($q$select public.help_update_chat(%L, 'waiting_on_clg', %L)$q$, :'chat_bill', :'sue'), 'a billing chat cannot be given to a support admin'); -- refused
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as Olive (owner)
set role authenticated; -- acts as a signed-in person
select public.help_reply(:'chat1', 'Thanks! Please put the new school once Cara starts there.') as reply1 \gset
-- (Olive replies; keeps the message id as reply1)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.help_chats where id = :'chat1' and status = 'waiting_on_you' and assigned_to = :'olive'), 1::bigint, 'a CLG reply puts the chat with the family, looked after by the admin who replied'); -- updated
select tests.eq((select count(*) from public.help_messages where id = :'reply1' and from_clg and student_id = :'cara'), 1::bigint, 'the reply is marked as from CLG and carries the student'); -- marked
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat1' and account_id = :'p1' and emailed_at is null), 1::bigint, 'the parent gets an email about the reply'); -- queued

-- ---------------------------------------------------------------------------
-- 4. New-message numbers, reading, closing and reopening
-- ---------------------------------------------------------------------------
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select n from public.to_do_counts() where area = 'help' and section = 'unread')::bigint, 1::bigint, 'the parent has one chat with a new message'); -- one new
select tests.eq((select count(*) from public.help_chat_list(false) where id = :'chat1' and unread), 1::bigint, 'the list marks the chat as new'); -- marked
select public.help_mark_read(:'chat1'); -- P1 opens the chat
select tests.eq((select n from public.to_do_counts() where area = 'help' and section = 'unread')::bigint, 0::bigint, 'after reading, nothing is new'); -- none new
select tests.fails(format($q$select public.help_update_chat(%L, 'closed', %L)$q$, :'chat1', :'olive'), 'a parent cannot choose who looks after a chat'); -- refused
select tests.fails(format($q$select public.help_update_chat(%L, 'waiting_on_you')$q$, :'chat1'), 'a parent cannot mark a chat as waiting on themselves'); -- refused
select public.help_update_chat(:'chat1', 'closed'); -- P1 closes it (question answered)
select tests.eq((select count(*) from public.help_chats where id = :'chat1' and status = 'closed' and closed_at is not null), 1::bigint, 'the parent can close their chat'); -- closed
select public.help_reply(:'chat1', 'Sorry, one more question about the school.'); -- P1 writes again
select tests.eq((select count(*) from public.help_chats where id = :'chat1' and status = 'waiting_on_clg' and closed_at is null), 1::bigint, 'a new message reopens the chat with CLG'); -- reopened
reset role; -- back to the database itself
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat1' and account_id = :'olive' and emailed_at is null), 1::bigint, 'the admin looking after it is emailed (only one waiting email each)'); -- one waiting
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat1' and account_id = :'sam' and emailed_at is null), 1::bigint, 'the first email to Sam is still waiting, and no second one was added'); -- still one

-- ---------------------------------------------------------------------------
-- 5. Emails: no message words, and none for chats already read
-- ---------------------------------------------------------------------------
update public.help_chat_emails set send_after = now() - interval '1 minute' where chat_id = :'chat1'; -- makes the chat's emails due now
insert into public.help_chat_reads (chat_id, account_id, last_read_at) values (:'chat1', :'sam', now() + interval '1 second') -- Sam has read the chat since
on conflict (chat_id, account_id) do update set last_read_at = excluded.last_read_at; -- (or moves his read time)
set role service_role; -- acts as the email sender
create temp table claimed as select * from public.help_chat_emails_claim(50); -- collects the due emails
reset role; -- back to the database itself
select tests.eq((select count(*) from claimed where email = 'sam.staff@clg.example' or first_name = 'Sam'), 0::bigint, 'no email for someone who has already read the chat'); -- skipped
select tests.eq((select count(*) from claimed where link = '/help/' || :'chat1'), (select count(*) from claimed), 'each email links to the chat'); -- linked
select tests.eq((select count(*) from claimed where body like '%school%' or subject like '%School%' or body like '%Cara%'), 0::bigint, 'emails never include the message, title or child'); -- nothing private
select tests.eq((select count(*) from claimed), 1::bigint, 'one email is sent (to Olive)'); -- just Olive
drop table claimed; -- tidies up

-- ---------------------------------------------------------------------------
-- 6. Admins start a chat with the people they choose
-- ---------------------------------------------------------------------------
select tests.claims(:'olive', 'aal2'); -- signs in as Olive (owner)
set role authenticated; -- acts as a signed-in person
select public.help_start_chat_with(array[:'p2']::uuid[], 'missing_info', 'Vic''s year level', 'Hello! Could you add Vic''s year level for next year?', :'vic', 'year_level') as chat_vic \gset
-- (Olive asks P2 about Vic's year level; keeps the chat id as chat_vic)
select tests.fails(format($q$select public.help_start_chat_with(array[%L]::uuid[], 'missing_info', 'Vic', 'Hello', %L, 'school')$q$, :'p1', :'vic'), 'only the child''s own parents (or the child, or their tutors) can be in a chat about them'); -- refused
select tests.fails(format($q$select public.help_start_chat_with(array[%L]::uuid[], 'missing_info', 'Vic', 'Hello', %L, 'school')$q$, :'cal_login', :'vic'), 'a brother or sister cannot be added to a chat about their sibling'); -- refused
select tests.fails($q$select public.help_start_chat_with(array[]::uuid[], 'other', 'Nobody', 'Hello')$q$, 'someone must be chosen'); -- refused
select public.help_start_chat_with(array[:'t1']::uuid[], 'other', 'Training reminder', 'Hi! Please finish the safety module this week.') as chat_tutor \gset
-- (Olive starts a chat with tutor T1, not about a student; keeps its id as chat_tutor)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.help_chats where id = :'chat_vic' and started_by_clg and status = 'waiting_on_you' and assigned_to = :'olive'), 1::bigint, 'an admin-started chat waits for the family and is looked after by that admin'); -- set up
select tests.eq((select count(*) from public.help_chat_emails where chat_id = :'chat_vic' and account_id = :'p2'), 1::bigint, 'the parent is emailed about the new chat'); -- queued
select tests.claims(:'sue', 'aal2'); -- signs in as Sue (support admin, not the one who started it)
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.help_start_chat_with(array[%L]::uuid[], 'billing', 'Invoice', 'Hello')$q$, :'p1'), 'a support admin cannot start a billing chat'); -- refused
reset role; -- back to the database itself
select tests.claims(:'cal_login'); -- signs in as Cal (Vic's brother, his own login)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id = :'chat_vic'), 0::bigint, 'a sibling never sees a chat about their brother or sister'); -- hidden
select tests.eq((select count(*) from public.help_my_students() where id = :'vic'), 0::bigint, 'a student cannot ask about their sibling'); -- not listed
select tests.eq((select count(*) from public.help_my_students() where id = :'cal' and connection = 'self'), 1::bigint, 'a student with their own login can ask about themselves'); -- listed
reset role; -- back to the database itself
select tests.claims(:'p2'); -- signs in as parent P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chat_list(false) where id = :'chat_vic' and unread), 1::bigint, 'the parent sees the new chat, marked new'); -- visible
select public.help_reply(:'chat_vic', 'Done, thank you.'); -- P2 replies
reset role; -- back to the database itself
select tests.claims(:'t1', 'aal2'); -- signs in as tutor T1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chat_list(false) where id = :'chat_tutor'), 1::bigint, 'a tutor sees a chat CLG started with them'); -- visible
select tests.eq((select count(*) from public.help_my_students() where id in (:'cara', :'ada_student') and connection = 'student'), 2::bigint, 'a tutor can ask about the students they tutor'); -- both listed
select tests.eq((select count(*) from public.help_chat_members where chat_id = :'chat_tutor' and account_id <> :'t1'), 0::bigint, 'a member sees only their own membership row'); -- own only
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- 7. Concerning words are checked in every message
-- ---------------------------------------------------------------------------
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select public.help_reply(:'chat1', 'My child said they want to kill myself, in those words.') as msg_words \gset
-- (P1 writes a message with concerning words; keeps its id as msg_words)
reset role; -- back to the database itself
select tests.eq((select count(*) from public.safety_word_flags where source_table = 'help_messages' and source_id = :'msg_words' and student_id = :'cara'), 1::bigint, 'a message with concerning words is flagged, naming the child'); -- flagged

-- ---------------------------------------------------------------------------
-- 8. A parent who is no longer linked to the child stops seeing the chat
-- ---------------------------------------------------------------------------
delete from public.parent_student_links where parent_id = :'p1' and student_id = :'cara'; -- P1 is no longer linked to Cara
select tests.claims(:'p1'); -- signs in as parent P1
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 0::bigint, 'an unlinked parent no longer sees chats about the child'); -- hidden
select tests.eq((select count(*) from public.help_chats where id = :'chat_bill'), 1::bigint, 'their chats not about a child stay'); -- still visible
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- 9. The activity log holds ids only, and old chats are tidied away
-- ---------------------------------------------------------------------------
select tests.eq((select least(count(*), 1) from public.audit_log where action like 'help%'), 1::bigint, 'help chat actions are in the activity log'); -- logged (so the next check means something)
select tests.eq((select count(*) from public.audit_log where action like 'help%' and (details::text like '%school%' or details::text like '%kill%' or details::text like '%Invoice%')), 0::bigint, 'no message words in the activity log'); -- nothing leaked
update public.help_chats set last_message_at = now() - interval '25 months' where id = :'chat_bill'; -- makes one chat over 2 years old
select private.help_chat_tidy(); -- runs the nightly tidy-up
select tests.eq((select count(*) from public.help_chats where id = :'chat_bill'), 0::bigint, 'chats are deleted 2 years after their last message'); -- deleted
select tests.eq((select count(*) from public.help_messages where chat_id = :'chat_bill'), 0::bigint, 'their messages go with them'); -- deleted

-- ---------------------------------------------------------------------------
-- 10. Permission to quote without a name, and keeping chats past 2 years
-- ---------------------------------------------------------------------------
select tests.claims(:'cal_login'); -- signs in as Cal (16, his own login)
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_quote_permission() where not agreed and not can_choose), 1::bigint, 'a learner under 18 cannot choose to be quoted'); -- not offered
select tests.fails($q$select public.set_quote_permission(true, 'test')$q$, 'a learner under 18 cannot agree to be quoted'); -- refused
reset role; -- back to the database itself
select tests.claims(:'p2'); -- signs in as parent P2
set role authenticated; -- acts as a signed-in person
select tests.eq((select count(*) from public.my_quote_permission() where not agreed and can_choose), 1::bigint, 'quoting is off until the person turns it on'); -- off to start
select public.set_quote_permission(true, 'test'); -- P2 agrees to be quoted without their name
select tests.eq((select count(*) from public.my_quote_permission() where agreed), 1::bigint, 'the choice is saved'); -- saved
select tests.fails(format($q$select public.help_keep_chat(%L, 'practice')$q$, :'chat_vic'), 'a parent cannot keep a chat'); -- refused
select tests.eq((select count(*) from public.help_chat_is_kept(:'chat_vic') k where k), 0::bigint, 'families are never told whether a chat is kept'); -- not shown
reset role; -- back to the database itself
select tests.claims(:'sue', 'aal2'); -- signs in as Sue (support admin)
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.help_keep_chat(%L, 'practice')$q$, :'chat_vic'), 'a support admin cannot keep a chat'); -- refused
reset role; -- back to the database itself
select tests.claims(:'olive', 'aal2'); -- signs in as Olive (owner)
set role authenticated; -- acts as a signed-in person
select tests.fails(format($q$select public.help_keep_chat(%L, 'testimonial')$q$, :'chat1'), 'a chat cannot be a testimonial unless everyone who wrote in it agreed to be quoted'); -- refused (P1 has not agreed)
select public.help_keep_chat(:'chat_vic', 'testimonial'); -- keeps P2's chat as a testimonial (P2 agreed)
select tests.fails(format($q$select public.help_keep_chat(%L, 'forever')$q$, :'chat_tutor'), 'the reason must be on the list'); -- refused
select tests.eq((select count(*) from public.help_chat_is_kept(:'chat1') k where k), 1::bigint, 'admins see that a chat with a safety flag is kept'); -- shown
reset role; -- back to the database itself
update public.help_chats set last_message_at = now() - interval '25 months'; -- makes every chat over 2 years old
select private.help_chat_tidy(); -- runs the nightly tidy-up
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 1::bigint, 'a chat with a possible safety concern is kept'); -- kept
select tests.eq((select count(*) from public.help_chats where id = :'chat_vic'), 1::bigint, 'a chat CLG chose to keep is kept'); -- kept
select tests.eq((select count(*) from public.help_chats where id = :'chat_tutor'), 0::bigint, 'other old chats are deleted'); -- deleted
update public.safety_word_flags set status = 'no_concern' where source_table = 'help_messages' and source_id = :'msg_words'; -- the flag is checked and closed as "No concern"
select private.help_chat_tidy(); -- runs the nightly tidy-up again
select tests.eq((select count(*) from public.help_chats where id = :'chat1'), 0::bigint, 'once the flag is closed as no concern, the old chat is deleted'); -- deleted

-- Undoes everything above.
rollback;
