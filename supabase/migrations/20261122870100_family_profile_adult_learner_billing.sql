-- Summary: two changes that go with renaming the "Parent" profile to
-- "Family" (Carla, 20 Nov 2026).
--
-- 1. Adult learners can pay from their own Student profile. Carla chose the
--    name "Family" on the condition that a learner who pays for themselves
--    does it from their Student account, with no Family profile. Billing in
--    CLG works per family, but a student who signed up on their own (or was
--    set up by an admin as "a student with their own login", or used
--    "Become a learner") was saved with no family at all. With no family
--    they never got a Billing tab, could not choose a plan, agree to the
--    payment terms or pay, and no invoice could be made for them. Now:
--      * every new student with their own login and no family gets one
--        straight away: their own (named "<their name> family"), or, if they
--        already look after children at CLG (a parent who chose "Become a
--        learner"), the family their children are in, so the household
--        keeps one bill;
--      * every existing student with their own login and no family is given
--        one in the same way.
--    Who may pay is unchanged (20261118900300_billing_only_payers.sql): an
--    adult learner (18 or over) who is the only learner in their family,
--    with no parent linked, may start the family's payments, which makes
--    them the bill payer.
--
-- 2. The database's own messages that name the profile now say "Family"
--    instead of "parent" (for example "Only parents can add a child"). Only
--    the words change; what each step does stays exactly the same. Wording
--    about a real parent or guardian (for example consent for a child) is
--    left alone, because Australian privacy law speaks of parents and
--    guardians. The internal role name stays "parent", so nothing else
--    changes.
--
-- Safe to run more than once. Run AFTER every earlier change (it reads the
-- live database's steps as they are now).

-- ---------------------------------------------------------------------------
-- 1a. Give each new student with their own login a family
-- ---------------------------------------------------------------------------
-- Runs just before a student record is saved. When the record has its own
-- login and no family, it picks the family: the one their own children are
-- in (if they look after any), or a new family of their own.
create or replace function private.student_own_family() -- no inputs: it works on the record being saved
returns trigger -- runs as part of saving a student
language plpgsql security definer -- may read and add families on the person's behalf
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if new.family_id is not null or new.account_id is null then -- already in a family, or no login of their own:
    return new; -- nothing to do (children added by a parent always come with a family)
  end if; -- end of that case
  select s.family_id into new.family_id -- uses the family their own children are in, if any:
  from public.parent_student_links l -- the children this person looks after
  join public.students s on s.id = l.student_id -- and those children's records
  where l.parent_id = new.account_id and s.family_id is not null -- with a family
  order by s.created_at -- the oldest record first, so the choice is always the same
  limit 1; -- one family is enough
  if new.family_id is null then -- no children at CLG:
    insert into public.families (name, created_by) -- makes a family of their own,
    values (left(new.full_name, 190) || ' family', new.account_id) -- named after them, made by them
    returning id into new.family_id; -- and puts them in it
  end if; -- end of that case
  return new; -- saves the record with its family
end; -- end of the code
$$; -- end of the function
revoke all on function private.student_own_family() from public; -- for the database's own use only

drop trigger if exists students_own_family on public.students; -- removes an older copy, so this can run twice
create trigger students_own_family -- the step that runs it:
before insert on public.students -- just before each new student record is saved
for each row execute function private.student_own_family(); -- once per record

-- ---------------------------------------------------------------------------
-- 1b. Give existing students with their own login a family
-- ---------------------------------------------------------------------------
-- Works through each student who has their own login but no family, and
-- puts them in their children's family or a new family of their own, the
-- same way as above.
do $$ -- a one-off block of steps
declare
  r record; -- one student, worked through in turn
  v_family uuid; -- the family chosen for them
  v_count int := 0; -- how many students were given a family (shown at the end)
begin -- starts the steps
  for r in -- for each student:
    select id, account_id, full_name from public.students -- their id, login and name
    where family_id is null and account_id is not null -- with their own login and no family
  loop -- one at a time:
    v_family := null; -- starts with no family chosen
    select s.family_id into v_family -- their children's family, if any:
    from public.parent_student_links l -- the children this person looks after
    join public.students s on s.id = l.student_id -- and those children's records
    where l.parent_id = r.account_id and s.family_id is not null -- with a family
    order by s.created_at -- the oldest record first
    limit 1; -- one family is enough
    if v_family is null then -- no children at CLG:
      insert into public.families (name, created_by) -- makes a family of their own,
      values (left(r.full_name, 190) || ' family', r.account_id) -- named after them
      returning id into v_family; -- and keeps its id
    end if; -- end of that case
    update public.students set family_id = v_family where id = r.id; -- puts the student in it
    v_count := v_count + 1; -- counts them
  end loop; -- end of the students
  raise notice 'Gave % students with their own login a family.', v_count; -- reports how many
end; -- end of the steps
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 2. Messages that name the profile say "Family"
-- ---------------------------------------------------------------------------
-- A short-lived helper that swaps the old wording for the new in a piece of
-- text. It lives in this session's temporary area only.
create or replace function pg_temp.family_profile_words(t text) -- takes a piece of text
returns text -- and hands back the same text with the new wording
language plpgsql -- written in the database's step-by-step language
as $$ -- the code
declare
  pair text[]; -- one old wording and its new wording, worked through in turn
begin -- starts the code
  if t is null then return null; end if; -- nothing to change in an empty value
  foreach pair slice 1 in array array[ -- each old wording and its new wording:
    ['Only parents can add a child', 'Only someone with a Family profile can add a child'], -- adding a child
    ['That account is not a parent account', 'That account does not have a Family profile'], -- an admin adding a child to an account
    ['Only parents and students can make a family calendar link', 'Only someone with a Family or Student profile can make a family calendar link'], -- the calendar link
    ['Choose tutor, admin or parent.', 'Choose tutor, admin or family.'] -- an admin adding a role
  ] loop -- for each pair:
    t := replace(t, pair[1], pair[2]); -- swaps every copy of the old wording
  end loop; -- end of the list
  return t; -- hands back the new text
end; -- end of the code
$$; -- end of the helper

-- Goes through CLG's own database steps and saves again each one whose
-- wording holds the old words, with the new words in place.
do $$ -- a one-off block of steps
declare
  f record; -- one database step, worked through in turn
  v_old text; -- the step's full definition as it is now
  v_new text; -- the same definition with the new words
  v_count int := 0; -- how many steps were updated (shown at the end)
begin -- starts the steps
  for f in -- for each step:
    select p.oid -- its internal number
    from pg_proc p -- from the list of database steps
    join pg_namespace n on n.oid = p.pronamespace -- with the area it lives in
    where n.nspname in ('public', 'private') -- only CLG's own areas
      and p.prokind = 'f' -- only ordinary steps
      and p.prosrc is distinct from pg_temp.family_profile_words(p.prosrc) -- only steps holding the old words
  loop -- one at a time:
    v_old := pg_get_functiondef(f.oid); -- reads the step's full definition
    v_new := pg_temp.family_profile_words(v_old); -- puts in the new words
    if v_new is distinct from v_old then -- something changed:
      execute v_new; -- saves the step again (same name, settings and permissions; only the words differ)
      v_count := v_count + 1; -- counts it
    end if; -- end of that case
  end loop; -- end of the steps
  raise notice 'Updated the wording in % database steps.', v_count; -- reports how many
end; -- end of the steps
$$; -- end of the block

-- Removes the helper now the messages are updated.
drop function pg_temp.family_profile_words(text); -- tidies up (it would vanish at the end of the session anyway)
