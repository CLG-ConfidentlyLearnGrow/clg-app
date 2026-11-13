-- Summary: flag concerning words and phrases (Carla, 13 Nov 2026).
--
-- When someone writes text in the app (session summaries, staff notes,
-- student reflections, family notes, booking and request notes, term
-- reviews, evidence notes, learning needs), the database checks it against
-- a list of words and phrases that can point to a child safety risk, for
-- example "kill myself", "our little secret" or "add me on snapchat".
-- A match makes a private flag for a person to check. Nothing else happens
-- automatically: nobody is blocked, warned or told, and the text is saved
-- as normal. A person always decides what a flag means.
--
-- Who sees flags: the Child Safety Officer and the deputy (named on the
-- Child safety page), after two-step sign-in. Neither sees a flag on text
-- they wrote themselves, so words written by Carla go to Lauren only, and
-- the other way round.
--
-- Who edits the list: the Child Safety Officer, the deputy and the owner
-- (two-step sign-in). Tutors, parents and students can't read the list, so
-- it can't be worked around.
--
-- Urgent words (for example self-harm) also send an alert email straight
-- away, even in quiet hours. The email holds no names or words, only "open
-- the app". The flags count towards the red "Child safety" number in the
-- top bar.
--
-- The scanning is done by the database itself (a trigger on each table),
-- so it can't be skipped by any page. It only writes to this module's own
-- table, and if the check ever goes wrong the person's text is still saved.
--
-- Needs 20261113700100_child_safety_concerns.sql (the officer and deputy).
-- See docs/features/concerning-words.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Turning text into a simple form for matching
-- ---------------------------------------------------------------------------

-- Makes text easy to compare: lower case, apostrophes removed ("don't"
-- becomes "dont"), dashes, underscores and slashes turned into spaces
-- ("self-harm" becomes "self harm"), and runs of spaces made single.
create or replace function private.watch_normalise(p_text text) -- takes any text
returns text -- gives back the simple form
language sql immutable -- the same text always gives the same answer
set search_path = '' -- only fully named functions, for safety
as $$ -- the steps, from the inside out:
  select btrim( -- 5. trims spaces off both ends,
    regexp_replace( -- 4. turns runs of spaces, tabs and new lines into one space,
      regexp_replace( -- 3. turns dashes, underscores and slashes into spaces,
        replace(replace(lower(coalesce(p_text, '')), '’', ''), '''', ''), -- 1-2. lower case, and removes curly and straight apostrophes,
        '[-_/]+', ' ', 'g'), -- (the dash, underscore and slash step)
      '\s+', ' ', 'g')) -- (the spaces step)
$$; -- end of the function
revoke all on function private.watch_normalise(text) from public; -- not for everyone by default
grant execute on function private.watch_normalise(text) to authenticated; -- needed when a signed-in person saves a word (the list's tidy-up columns use it)

-- Builds the search pattern for one word or phrase. The phrase must match
-- whole words ("kill" doesn't match "skill"). A "*" at the end of a word
-- means "any ending" ("bully*" matches bully, bullied, bullying, and
-- "want* to die" matches "wants to die"). Spaces in a phrase match any
-- spacing in the text.
create or replace function private.watch_pattern(p_phrase text) -- takes the phrase as the person typed it
returns text -- gives back the search pattern
language sql immutable -- the same phrase always gives the same pattern
set search_path = '' -- only fully named functions, for safety
as $$ -- the steps:
  select '(^|[^[:alnum:]])' -- starts at the beginning of the text or after a non-letter (a whole-word start),
    || replace( -- then the phrase, with each space allowed to be any spacing:
         replace( -- and each "*" allowed to be any ending:
           regexp_replace(private.watch_normalise(p_phrase), '([.^$|?+()\[\]{}\\])', '\\\1', 'g'), -- the phrase in simple form, with special characters made ordinary,
           '*', '[[:alnum:]]*'), -- (any ending)
         ' ', '\s+') -- (any spacing between words)
    || '($|[^[:alnum:]])' -- and ends at the end of the text or before a non-letter (a whole-word end).
$$; -- end of the function
revoke all on function private.watch_pattern(text) from public; -- not for everyone by default
grant execute on function private.watch_pattern(text) to authenticated; -- needed when a signed-in person saves a word (the list's tidy-up columns use it)

-- ---------------------------------------------------------------------------
-- Who can review flags and edit the list
-- ---------------------------------------------------------------------------

-- True when the signed-in person is the Child Safety Officer or the deputy and used two-step sign-in.
create or replace function private.is_safety_contact() -- no inputs
returns boolean -- gives back yes or no
language sql stable security definer -- reads the settings row, which people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select private.has_aal2() -- two-step sign-in,
    and exists ( -- and they hold one of the jobs:
      select 1 from public.child_safety_contacts c -- in the settings row
      where c.id and auth.uid() in (c.officer_id, c.deputy_id) -- they're the officer or the deputy
    ) -- end of the check
$$; -- end of the function
revoke all on function private.is_safety_contact() from public; -- for the database's own use only
grant execute on function private.is_safety_contact() to authenticated; -- used inside the access rules below

-- ---------------------------------------------------------------------------
-- The list of words and phrases to watch for
-- ---------------------------------------------------------------------------

create table if not exists public.safety_watch_words ( -- one row per word or phrase
  id uuid primary key default gen_random_uuid(), -- the word's id
  phrase text not null check (char_length(btrim(phrase)) between 2 and 100), -- the word or phrase as typed, e.g. "kill myself" or "bully*"
  phrase_key text generated always as (private.watch_normalise(phrase)) stored, -- its simple form (kept by the database), used to stop the same phrase being added twice
  pattern text generated always as (private.watch_pattern(phrase)) stored, -- its search pattern (kept by the database)
  category text not null check (category in ( -- what kind of risk it may point to:
    'self_harm', -- self-harm or suicide
    'abuse', -- abuse or neglect at home or elsewhere
    'grooming', -- grooming signs: secrets, photos, being alone
    'off_platform', -- moving contact off CLG (social media, private numbers)
    'bullying', -- bullying
    'violence', -- violence or weapons
    'sexual', -- sexual content
    'other')), -- anything else
  urgent boolean not null default false, -- true: also email the reviewer straight away
  staff_only boolean not null default false, -- true: only flag it when a tutor or admin wrote it (e.g. "text me" is normal from a parent)
  active boolean not null default true, -- false: kept on the list but not checked
  note text check (char_length(note) <= 300), -- why it's on the list, or what to look for
  added_by uuid references public.accounts (id) on delete set null, -- who added it (empty for the starting list)
  created_at timestamptz not null default now(), -- when it was added
  updated_at timestamptz not null default now(), -- when it last changed
  constraint safety_watch_words_long_enough check (char_length(replace(phrase_key, '*', '')) >= 2), -- at least two letters once tidied
  constraint safety_watch_words_star_at_word_end check (phrase_key !~ '[*][^ ]' and phrase_key !~ '(^| )[*]') -- a "*" is only allowed at the end of a word
); -- end of the table
create unique index if not exists safety_watch_words_unique on public.safety_watch_words (phrase_key); -- the same phrase can't be listed twice
alter table public.safety_watch_words enable row level security; -- turns on access rules
revoke all on public.safety_watch_words from anon, authenticated; -- starts with no access at all
grant select, delete on public.safety_watch_words to authenticated; -- signed-in people may read and remove, but only if the rule below allows
grant insert (phrase, category, urgent, staff_only, active, note) on public.safety_watch_words to authenticated; -- and add, setting only these columns
grant update (phrase, category, urgent, staff_only, active, note) on public.safety_watch_words to authenticated; -- and change only these columns

-- Only the officer, the deputy and the owner (all with two-step sign-in) can read or change the list.
drop policy if exists "safety contacts and owner manage watch words" on public.safety_watch_words; -- removes the old rule if the file is run again
create policy "safety contacts and owner manage watch words" on public.safety_watch_words -- the rule
  for all to authenticated -- for reading, adding, changing and removing
  using (private.is_safety_contact() or private.is_owner()) -- which rows they can see and change
  with check (private.is_safety_contact() or private.is_owner()); -- and what they can save

-- Fills in who added a word and when it changed, so nobody can fake those.
create or replace function private.safety_watch_words_stamp() -- runs before a word is saved
returns trigger -- a trigger function
language plpgsql -- step-by-step code
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if tg_op = 'INSERT' then -- a new word:
    new.added_by := auth.uid(); -- who added it (empty when the database adds the starting list)
    new.created_at := now(); -- when
  end if; -- end of the check
  new.updated_at := now(); -- when it last changed
  return new; -- carries on saving
end; -- ends the code
$$; -- end of the function
revoke all on function private.safety_watch_words_stamp() from public; -- for the database's own use only
drop trigger if exists stamp on public.safety_watch_words; -- removes the old trigger if the file is run again
create trigger stamp before insert or update on public.safety_watch_words -- before each save
  for each row execute function private.safety_watch_words_stamp(); -- fills in the stamps

-- The starting list, added only when the list is empty (so words the
-- officer removed don't come back if this file is run again). Built from
-- eSafety Commissioner, Kids Helpline and NSPCC guidance on warning signs
-- of self-harm, abuse, grooming and bullying (see the feature brief). The
-- officer can change any of it.
insert into public.safety_watch_words (phrase, category, urgent, staff_only, note) -- adds the starting words:
select v.phrase, v.category, v.urgent, v.staff_only, v.note -- each word's details
from (values -- the words:
  -- Self-harm and suicide: urgent, because the risk can be immediate.
  ('kill* myself', 'self_harm', true, false, 'Possible suicide risk. Also matches "killing myself".'), -- a direct statement
  ('suicide', 'self_harm', true, false, 'May be a topic in class (e.g. English, history); check the context.'), -- the word itself
  ('suicidal', 'self_harm', true, false, 'Possible suicide risk.'), -- the word itself
  ('want* to die', 'self_harm', true, false, 'Possible suicide risk. Also matches "wants to die".'), -- a direct statement
  ('wanna die', 'self_harm', true, false, 'Possible suicide risk.'), -- a casual spelling
  ('end my life', 'self_harm', true, false, 'Possible suicide risk.'), -- a direct statement
  ('better off dead', 'self_harm', true, false, 'Possible suicide risk.'), -- a common phrase
  ('better off without me', 'self_harm', true, false, 'Possible suicide risk.'), -- a common phrase
  ('no reason to live', 'self_harm', true, false, 'Possible suicide risk.'), -- a common phrase
  ('self harm', 'self_harm', true, false, 'Also matches "self-harm".'), -- the term
  ('hurt* myself', 'self_harm', true, false, 'Possible self-harm. Also matches "hurting myself".'), -- a direct statement
  ('cut* myself', 'self_harm', true, false, 'Possible self-harm. Also matches "cutting myself".'), -- a direct statement
  ('overdose', 'self_harm', false, false, 'Possible self-harm; also used in science and health classes.'), -- the word itself
  ('cant go on', 'self_harm', false, false, 'Possible distress; also matches "can''t go on".'), -- a common phrase
  -- Abuse and neglect: urgent where it describes harm to the child.
  ('hits me', 'abuse', true, false, 'Possible physical abuse.'), -- a direct statement
  ('beats me', 'abuse', true, false, 'Possible physical abuse; also used in games ("he always beats me").'), -- a direct statement
  ('touched me', 'abuse', true, false, 'Possible sexual abuse.'), -- a direct statement
  ('touches me', 'abuse', true, false, 'Possible sexual abuse.'), -- a direct statement
  ('molest*', 'abuse', true, false, 'Possible sexual abuse.'), -- molest, molested, molesting
  ('raped', 'abuse', true, false, 'Possible sexual abuse.'), -- the word itself
  ('abused', 'abuse', true, false, 'Possible abuse.'), -- the word itself
  ('scared to go home', 'abuse', true, false, 'Possible harm at home.'), -- a direct statement
  ('afraid to go home', 'abuse', true, false, 'Possible harm at home.'), -- a direct statement
  ('not safe at home', 'abuse', true, false, 'Possible harm at home.'), -- a direct statement
  ('no food at home', 'abuse', false, false, 'Possible neglect.'), -- a sign of neglect
  ('havent eaten', 'abuse', false, false, 'Possible neglect; also matches "haven''t eaten".'), -- a sign of neglect
  ('locked me in', 'abuse', true, false, 'Possible abuse.'), -- a direct statement
  -- Grooming signs (eSafety): secrets, photos, being alone. Urgent when it asks for secrecy or images.
  ('our secret', 'grooming', true, false, 'Grooming sign: asking a child to keep secrets.'), -- secrecy
  ('our little secret', 'grooming', true, false, 'Grooming sign: asking a child to keep secrets.'), -- secrecy
  ('dont tell your parents', 'grooming', true, false, 'Grooming sign: cutting out parents.'), -- secrecy
  ('dont tell your mum', 'grooming', true, false, 'Grooming sign: cutting out parents.'), -- secrecy
  ('dont tell your mom', 'grooming', true, false, 'Grooming sign: cutting out parents.'), -- secrecy
  ('dont tell your dad', 'grooming', true, false, 'Grooming sign: cutting out parents.'), -- secrecy
  ('dont tell anyone', 'grooming', true, false, 'Grooming sign: secrecy.'), -- secrecy
  ('keep this between us', 'grooming', true, false, 'Grooming sign: secrecy.'), -- secrecy
  ('delete this message', 'grooming', true, false, 'Grooming sign: hiding contact.'), -- hiding contact
  ('send me a photo', 'grooming', true, false, 'Grooming sign: asking for images.'), -- images
  ('send me a pic', 'grooming', true, false, 'Grooming sign: asking for images.'), -- images
  ('send pics', 'grooming', true, false, 'Grooming sign: asking for images.'), -- images
  ('nudes', 'grooming', true, false, 'Possible image-based abuse.'), -- images
  ('home alone', 'grooming', false, false, 'Possible grooming or supervision concern; check the context.'), -- being alone
  ('meet up alone', 'grooming', true, false, 'Grooming sign: arranging time alone.'), -- being alone
  -- Moving contact off CLG: only from staff (normal for parents to share numbers). Not urgent.
  ('snapchat', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- social media
  ('instagram', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- social media
  ('whatsapp', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- messaging
  ('tiktok', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- social media
  ('discord', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- messaging
  ('telegram', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- messaging
  ('dm me', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- private messages
  ('text me', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- private messages
  ('add me on', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- social media
  ('my personal number', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- phone numbers
  ('private chat', 'off_platform', false, true, 'Code of conduct: no private contact with students outside CLG.'), -- private messages
  -- Bullying: not urgent, but worth a look.
  ('bullied', 'bullying', false, false, 'Possible bullying.'), -- the word itself
  ('bullying', 'bullying', false, false, 'Possible bullying; also a class topic.'), -- the word itself
  ('everyone hates me', 'bullying', false, false, 'Possible bullying or low mood.'), -- a direct statement
  ('nobody likes me', 'bullying', false, false, 'Possible bullying or low mood.'), -- a direct statement
  ('no friends', 'bullying', false, false, 'Possible isolation.'), -- a direct statement
  -- Violence and weapons.
  ('kill you', 'violence', true, false, 'A threat; also said in jest, so check the context.'), -- a threat
  ('going to hurt', 'violence', false, false, 'Possible threat.'), -- a threat
  ('brought a knife', 'violence', true, false, 'Possible weapon.'), -- a weapon
  ('gun', 'violence', false, false, 'Possible weapon; also used in history and English.'), -- a weapon
  -- Sexual content.
  ('porn*', 'sexual', true, false, 'Sexual content.'), -- porn, porno, pornography
  ('naked', 'sexual', true, false, 'Sexual content; also used in science and art.'), -- the word itself
  ('sexy', 'sexual', true, false, 'Sexual content.') -- the word itself
) as v (phrase, category, urgent, staff_only, note) -- (names for the columns above)
where not exists (select 1 from public.safety_watch_words); -- only when the list is empty

-- ---------------------------------------------------------------------------
-- The flags: one row each time new text matches the list
-- ---------------------------------------------------------------------------

create table if not exists public.safety_word_flags ( -- one row per flagged piece of text
  id uuid primary key default gen_random_uuid(), -- the flag's id
  source_table text not null check (char_length(source_table) <= 63), -- where the text was written, e.g. "session_notes"
  source_field text not null check (char_length(source_field) <= 63), -- which box, e.g. "went_well"
  source_id text check (char_length(source_id) <= 100), -- the id of the row it was written in (to find it)
  author_id uuid references public.accounts (id) on delete set null, -- who wrote it (empty if the system wrote it or their account is deleted)
  author_name text not null check (char_length(author_name) between 1 and 200), -- their name, copied so the record stays complete
  author_roles text not null default '' check (char_length(author_roles) <= 100), -- their roles at the time, e.g. "tutor"
  student_id uuid references public.students (id) on delete set null, -- the student the text is about (if known)
  student_name text check (char_length(student_name) <= 200), -- their name, copied so the record stays complete
  words text[] not null, -- the words and phrases that matched
  categories text[] not null, -- what kinds of risk they may point to
  urgent boolean not null default false, -- true when any matched word is urgent
  text_copy text not null check (char_length(text_copy) <= 8000), -- a copy of the text as written, so it's kept even if edited or deleted later
  status text not null default 'new' check (status in ('new', 'no_concern', 'following_up', 'raised_concern')), -- where the review is up to
  review_note text check (char_length(review_note) <= 2000), -- what the reviewer decided and why
  reviewed_by uuid references public.accounts (id) on delete set null, -- who reviewed it
  reviewed_by_name text check (char_length(reviewed_by_name) <= 200), -- their name, copied
  reviewed_at timestamptz, -- when it was reviewed
  email_id uuid, -- the id of the alert email being sent (urgent flags only)
  emailed_at timestamptz, -- when the alert email was handed over to send
  created_at timestamptz not null default now() -- when the text was flagged
); -- end of the table
create index if not exists safety_word_flags_status on public.safety_word_flags (status, created_at desc); -- finds new flags quickly
create index if not exists safety_word_flags_unsent on public.safety_word_flags (created_at) where urgent and emailed_at is null; -- finds alerts still to email quickly
alter table public.safety_word_flags enable row level security; -- turns on access rules
revoke all on public.safety_word_flags from anon, authenticated; -- no direct changes: flags are made by the database and reviewed through the function below
grant select on public.safety_word_flags to authenticated; -- signed-in people may read, but only the rows the rule below allows

-- Only the officer and the deputy (two-step sign-in), and never a flag on text they wrote themselves.
drop policy if exists "safety contacts read flags" on public.safety_word_flags; -- removes the old rule if the file is run again
create policy "safety contacts read flags" on public.safety_word_flags -- the reading rule
  for select to authenticated -- for signed-in people reading
  using ( -- a flag is visible when:
    private.is_safety_contact() -- they're the officer or deputy with two-step sign-in,
    and author_id is distinct from auth.uid() -- and they didn't write the text.
  ); -- end of the rule

-- ---------------------------------------------------------------------------
-- The check itself
-- ---------------------------------------------------------------------------

-- The list's words that appear in a piece of text. Staff-only words count
-- only when a tutor or admin wrote it.
create or replace function private.watch_word_matches(p_text text, p_by_staff boolean) -- takes the text, and whether staff wrote it
returns table (phrase text, category text, urgent boolean) -- each word that matched
language sql stable security definer -- reads the list, which most people can't read
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select w.phrase, w.category, w.urgent -- the word's details
  from public.safety_watch_words w -- from the list
  where w.active -- only words being checked
    and (not w.staff_only or p_by_staff) -- staff-only words only for staff
    and private.watch_normalise(p_text) ~ w.pattern -- and it appears in the text (whole words)
$$; -- end of the function
revoke all on function private.watch_word_matches(text, boolean) from public; -- for the database's own use only

-- Runs after text is saved in a watched table. The boxes to check are
-- named when the trigger is added (below). For an edit, only words that
-- weren't there before make a flag, so fixing a typo doesn't flag again.
-- Any problem in here is caught, so the person's text is always saved.
create or replace function private.scan_watch_words() -- runs after a save
returns trigger -- a trigger function
language plpgsql security definer -- writes flags, which people can't write directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_me uuid := auth.uid(); -- who is writing (empty for the system)
  v_new jsonb := to_jsonb(new); -- the saved row, as a set of named values
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else null end; -- the row before an edit (empty for new rows)
  v_by_staff boolean; -- whether a tutor or admin is writing
  v_field text; -- the box being checked
  v_text text; -- its text now
  v_old_text text; -- its text before (for an edit)
  v_words text[]; -- the new words that matched
  v_categories text[]; -- their kinds of risk
  v_urgent boolean; -- whether any is urgent
  v_student uuid; -- the student the text is about
begin -- starts the code
  v_by_staff := v_me is not null and private.is_staff_account(v_me); -- staff if they have the admin or tutor role
  foreach v_field in array tg_argv loop -- for each box named for this table:
    v_text := v_new ->> v_field; -- its text now
    continue when v_text is null or btrim(v_text) = ''; -- nothing written: skip it
    v_old_text := v_old ->> v_field; -- its text before
    continue when v_old_text is not distinct from v_text; -- unchanged: skip it
    select array_agg(m.phrase order by m.phrase), -- the new words that matched,
           array_agg(distinct m.category), -- their kinds of risk,
           coalesce(bool_or(m.urgent), false) -- and whether any is urgent
      into v_words, v_categories, v_urgent -- kept for below
    from private.watch_word_matches(v_text, v_by_staff) m -- the words in the text now
    where v_old_text is null -- (a new row: all of them)
       or not exists (select 1 from private.watch_word_matches(v_old_text, v_by_staff) o where o.phrase = m.phrase); -- (an edit: only words that weren't there before)
    continue when v_words is null; -- nothing matched: next box
    v_student := case -- the student it's about:
      when v_new ? 'student_id' then (v_new ->> 'student_id')::uuid -- from the row itself,
      when v_new ? 'note_id' then (select n.student_id from public.session_notes n where n.id = (v_new ->> 'note_id')::uuid) -- or from the session summary it belongs to,
      else null end; -- or not known.
    insert into public.safety_word_flags ( -- saves the flag:
      source_table, source_field, source_id, -- where it was written,
      author_id, author_name, author_roles, -- who wrote it,
      student_id, student_name, -- who it's about,
      words, categories, urgent, text_copy -- and what matched.
    ) values ( -- the values:
      tg_table_name, v_field, left(coalesce(v_new ->> 'id', v_new ->> 'note_id', v_new ->> 'student_id'), 100), -- the table, the box and the row's id,
      v_me, -- the writer's account,
      coalesce((select nullif(a.full_name, '') from public.accounts a where a.id = v_me), 'Written by the system'), -- their name,
      coalesce((select string_agg(r.role::text, ', ' order by r.role) from public.account_roles r where r.account_id = v_me), ''), -- their roles,
      v_student, -- the student,
      (select left(s.full_name, 200) from public.students s where s.id = v_student), -- the student's name,
      v_words, v_categories, v_urgent, -- the words, kinds and urgency,
      left(v_text, 8000) -- and a copy of the text.
    ); -- end of the values
  end loop; -- next box
  return null; -- (an "after" trigger: the saved row isn't changed)
exception when others then -- if anything above went wrong:
  raise warning 'Concerning-words check skipped for %: %', tg_table_name, sqlerrm; -- notes it in the database log
  return null; -- and lets the person's text save anyway
end; -- ends the code
$$; -- end of the function
revoke all on function private.scan_watch_words() from public; -- for the database's own use only

-- Adds the check to each table with text people write, naming the boxes to
-- check. A table that doesn't exist (yet) is skipped.
do $$ -- a small block of code
declare -- the working values:
  v_watch record; -- one table and its boxes
begin -- starts the block
  for v_watch in -- for each table and its boxes:
    select * from (values -- the list:
      ('session_notes', array['went_well', 'next_step', 'homework']), -- session summaries (tutors)
      ('session_staff_notes', array['body']), -- private staff notes on a session (tutors)
      ('student_reflections', array['what_was_hard', 'what_i_will_try']), -- student reflections (students)
      ('family_notes', array['body']), -- family feedback and home progress (parents)
      ('learning_evidence', array['title', 'note', 'tutor_comment']), -- uploaded work and its notes
      ('session_requests', array['note', 'staff_note']), -- requests for extra sessions
      ('bookings', array['family_note', 'tutor_note']), -- booking notes
      ('term_reviews', array['summary', 'next_focus', 'recommendation_note', 'returned_reason', 'family_reply']), -- term reviews and family replies
      ('waitlist', array['note']), -- waitlist notes
      ('student_sensitive', array['learning_needs', 'support_strategies']) -- learning needs and support strategies
    ) as t (tbl, fields) -- (names for the columns above)
  loop -- for each one:
    continue when to_regclass('public.' || v_watch.tbl) is null; -- the table isn't there: skip it
    execute format('drop trigger if exists watch_words_scan on public.%I', v_watch.tbl); -- removes the old check if the file is run again
    execute format( -- adds the check:
      'create trigger watch_words_scan after insert or update of %s on public.%I for each row execute function private.scan_watch_words(%s)', -- after a new row or a change to those boxes,
      (select string_agg(quote_ident(f), ', ') from unnest(v_watch.fields) f), -- the boxes to watch for changes,
      v_watch.tbl, -- the table,
      (select string_agg(quote_literal(f), ', ') from unnest(v_watch.fields) f)); -- and the boxes to check.
  end loop; -- next table
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- Reviewing a flag (the officer or deputy)
-- ---------------------------------------------------------------------------

-- Records what the reviewer decided: no concern, following up, or raised
-- as a concern. A note is needed for anything but "following up", so the
-- record shows why.
create or replace function public.safety_word_flag_review(p_id uuid, p_status text, p_note text) -- takes the flag, the decision and a note
returns void -- gives nothing back
language plpgsql security definer -- changes a table people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not exists ( -- the flag must be one they can review:
    select 1 from public.safety_word_flags f -- the flag
    where f.id = p_id -- this one
      and private.is_safety_contact() -- they're the officer or deputy with two-step sign-in
      and f.author_id is distinct from auth.uid() -- and they didn't write the text
  ) then -- not allowed:
    raise exception 'Only the Child Safety Officer or deputy can review this (with two-step sign-in).' using errcode = '42501'; -- plain message, "not allowed" code
  end if; -- end of the check
  if coalesce(p_status, '') not in ('new', 'no_concern', 'following_up', 'raised_concern') then -- not one of the choices
    raise exception 'Please choose what you decided.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_status in ('no_concern', 'raised_concern') and char_length(btrim(coalesce(p_note, ''))) < 2 then -- a decision with no reason
    raise exception 'Please add a short note saying why.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.safety_word_flags f -- saves the decision:
  set status = p_status, -- the decision,
      review_note = nullif(left(btrim(coalesce(p_note, '')), 2000), ''), -- the note (if any),
      reviewed_by = auth.uid(), -- who decided,
      reviewed_by_name = (select a.full_name from public.accounts a where a.id = auth.uid()), -- their name,
      reviewed_at = now() -- and when.
  where f.id = p_id; -- this flag
  perform private.log_event('safety_word_flag_review', 'safety_word_flags', p_id::text, jsonb_build_object('status', p_status)); -- notes the decision in the activity log (id and decision only, no words)
end; -- ends the code
$$; -- end of the function
revoke all on function public.safety_word_flag_review(uuid, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.safety_word_flag_review(uuid, text, text) to authenticated; -- signed-in people can try (the check is inside)

-- ---------------------------------------------------------------------------
-- Alert emails for urgent flags (no names or words, only "open the app")
-- ---------------------------------------------------------------------------

-- Who gets the email for a flag: the officer, unless the officer wrote the
-- text (or there's no officer), then the deputy. Nobody if neither fits.
create or replace function private.watch_word_reviewer(p_author uuid) -- takes who wrote the text
returns uuid -- gives back an account id (or nothing)
language sql stable security definer -- reads the settings row
set search_path = '' -- only fully named tables, for safety
as $$ -- the choice
  select case -- picks:
    when c.officer_id is not null and c.officer_id is distinct from p_author then c.officer_id -- the officer, if they didn't write it,
    when c.deputy_id is not null and c.deputy_id is distinct from p_author then c.deputy_id -- otherwise the deputy, if they didn't write it,
    else null end -- otherwise nobody.
  from public.child_safety_contacts c where c.id -- from the settings row
$$; -- end of the function
revoke all on function private.watch_word_reviewer(uuid) from public; -- for the database's own use only

-- Any urgent flag waiting to be emailed? (Sent straight away, even in quiet hours.)
create or replace function private.watch_word_emails_waiting() -- no inputs
returns boolean -- gives back yes or no
language sql stable security definer -- reads flags
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- is there one:
    select 1 from public.safety_word_flags f -- a flag
    where f.urgent and f.emailed_at is null and f.status = 'new' -- urgent, not yet emailed, not yet reviewed
      and f.created_at > now() - interval '30 days' -- made in the last 30 days
      and private.watch_word_reviewer(f.author_id) is not null -- with someone to email
  ) -- end of the check
$$; -- end of the function
revoke all on function private.watch_word_emails_waiting() from public; -- for the database's own use only

-- Hands waiting alerts to the email sender and marks them sent.
create or replace function public.watch_word_emails_claim(p_limit integer default 50) -- takes how many at most
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- one email per flag
language plpgsql security definer -- reads and marks flags
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  return query -- hands back:
  with due as ( -- the flags to email:
    select f.id, private.watch_word_reviewer(f.author_id) as reviewer -- each flag and who to email
    from public.safety_word_flags f -- from the flags
    where f.urgent and f.emailed_at is null and f.status = 'new' -- urgent, not yet emailed, not yet reviewed
      and f.created_at > now() - interval '30 days' -- made in the last 30 days
      and private.watch_word_reviewer(f.author_id) is not null -- with someone to email
    order by f.created_at -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update of f skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.safety_word_flags f -- each flag taken
    set email_id = gen_random_uuid(), emailed_at = now() -- gets a new email id and the time
    from due where f.id = due.id -- (only the ones taken)
    returning f.email_id, due.reviewer, f.created_at -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(a.full_name), -- their first name
    'Urgent: words that may point to a child safety risk'::text, -- the subject
    'The CLG app noticed words that may point to a child safety risk in something written on ' -- the message: what,
      || to_char(m.created_at at time zone 'Australia/Adelaide', 'FMDy FMDD FMMon, FMHH12:MI am') || ' (Adelaide time).' -- and when,
      || E'\n\nIt may be nothing (for example, a class topic), so a person needs to check it.' -- why a person must look,
      || E'\n\nTo keep it confidential, the details are only in the app. You''ll need two-step sign-in to open it.', -- and why there are no details
    '/safety/flags'::text, -- the page the button opens
    'Check the flag'::text, -- the button's words
    'You get this email because CLG has named you as a child safety contact. These emails can''t be turned off.'::text -- the small print
  from marked m -- from the flags taken
  join public.accounts a on a.id = m.reviewer -- with the reviewer's name
  join public.account_private ap on ap.account_id = m.reviewer; -- and email
end; -- ends the code
$$; -- end of the function
revoke all on function public.watch_word_emails_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.watch_word_emails_claim(integer) to service_role; -- the email sender

-- Puts alerts back if sending failed (only ones taken in the last hour).
create or replace function public.watch_word_emails_release(p_ids uuid[]) -- takes the email ids
returns void -- gives nothing back
language sql security definer -- changes flags
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  update public.safety_word_flags set email_id = null, emailed_at = null -- clears the email marks
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for those emails, taken in the last hour
$$; -- end of the function
revoke all on function public.watch_word_emails_release(uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.watch_word_emails_release(uuid[]) to service_role; -- the email sender

-- Wakes the email sender for these alerts too. The shared check is
-- extended rather than copied, so changes other modules made to it are kept.
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the shared check's code
begin -- starts the block
  if to_regprocedure('private.emails_waiting()') is null then -- the shared check isn't there
    return; -- nothing to do
  end if; -- end of the check
  v_def := pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure); -- reads its current code
  if strpos(v_def, 'private.watch_word_emails_waiting()') = 0 then -- not added yet
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.watch_word_emails_waiting()\n$function$\n'); -- adds "or a flag alert is waiting" at the end
    execute v_def; -- saves the new code
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code

-- ---------------------------------------------------------------------------
-- To-do number: new flags add to the red "Child safety" number in the top
-- bar for the officer and deputy. to_do_counts is edited in place, so other
-- changes to it stay.
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- the working values:
  v_def text; -- the to-do function's code
begin -- starts the block
  v_def := pg_get_functiondef('public.to_do_counts()'::regprocedure); -- reads the current code
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'section := ''word_flags''') > 0 then -- already added
    return; -- nothing to do
  end if; -- end of the check
  if strpos(v_def, E'  -- Billing (owner, operations and finance).\n') = 0 then -- the place to add it has changed
    raise exception 'to_do_counts has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  v_def := replace(v_def, -- adds the flags number just before the billing numbers:
    E'  -- Billing (owner, operations and finance).\n', -- the place to add it
    E'  -- Child safety: flagged words not yet reviewed (officer and deputy only; row level security decides).\n' -- a comment saying what it is
    || E'  area := ''safety''; section := ''word_flags'';\n' -- the area and section names
    || E'  n := (select count(*) from public.safety_word_flags where status = ''new'');\n' -- the count (row level security limits it to the flags they may see)
    || E'  return next;\n\n' -- hands back the row
    || E'  -- Billing (owner, operations and finance).\n'); -- and puts back the billing comment
  execute v_def; -- saves the new code
end; -- ends the block
$$; -- end of the code
