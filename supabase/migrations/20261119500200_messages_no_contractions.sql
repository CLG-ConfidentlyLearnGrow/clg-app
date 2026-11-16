-- Summary: writes out every short form (contraction) in the messages the
-- database itself writes (Carla, 16 Nov 2026: no "don't", "you're", "it's"
-- and so on in anything people read, so nothing can be misread). These are
-- the plain error messages shown when the app refuses something (for example
-- "You can't book that time" becomes "You cannot book that time"), and the
-- wording of the notices and emails the database puts together, such as
-- reminders, offers and child safety alerts.
--
-- How it works: it looks through every database step (function) CLG has,
-- finds each one whose wording holds a short form, writes the short forms
-- out, and saves the step again. Only words change: what each step does, who
-- may use it and its settings all stay exactly the same. Possessives such as
-- "CLG's" are left alone. Because it reads the steps as they are in the live
-- database, it also catches any made or changed outside these files.
-- Safe to run more than once: a second run finds nothing left to change.
-- Messages already sent (notices and emails in people's inboxes) are left as
-- they were.

-- A short-lived helper that writes out the short forms in a piece of text.
-- Inside a step's wording an apostrophe is written as two (''), so it looks
-- for that, a single straight one, or a curly one. It lives in this
-- session's temporary area only and disappears afterwards.
create or replace function pg_temp.expand_message_contractions(t text) -- takes a piece of text
returns text -- and hands back the same text with short forms written out
language plpgsql -- written in the database's step-by-step language
as $$
declare
  pair text[]; -- one short form and its full wording, worked through in turn
  a constant text := '(?:''''|''|’)'; -- an apostrophe: doubled, single or curly (longest first)
begin
  if t is null then return null; end if; -- nothing to change in an empty value
  foreach pair slice 1 in array array[ -- each short form and its full wording, most specific first:
    -- "has" forms, where the next word shows "'s" means "has", not "is".
    ['\m(something|Something|that|what|it|there|That|What|It|There)' || a || 's (been|happened|changed|got|gone|had)\M', '\1 has \2'], -- something's happened, it's been
    ['\m(it|It)' || a || 's already been\M', '\1 has already been'], -- it's already been
    -- "had" and "would" forms of "'d".
    ['\m(I|you|You|we|We|they|They)' || a || 'd (already|been|finished|done|seen)\M', '\1 had \2'], -- you'd already finished
    ['\m(I|you|You|we|We|they|They)' || a || 'd\M', '\1 would'], -- you'd like
    -- "not" forms.
    ['\mcan' || a || 't\M', 'cannot'], ['\mCan' || a || 't\M', 'Cannot'], -- can't
    ['\mwon' || a || 't\M', 'will not'], ['\mWon' || a || 't\M', 'Will not'], -- won't
    ['\m(do|does|did|is|are|was|were|could|should|would|have|has|had|must|need)n' || a || 't\M', '\1 not'], -- don't, isn't, couldn't and so on
    ['\m(Do|Does|Did|Is|Are|Was|Were|Could|Should|Would|Have|Has|Had|Must|Need)n' || a || 't\M', '\1 not'], -- the same at the start of a sentence
    -- "are", "have", "will" and "am" forms.
    ['\m(you|You|we|We|they|They|what|What|who|Who|there|There)' || a || 're\M', '\1 are'], -- you're, we're
    ['\m(I|you|You|we|We|they|They)' || a || 've\M', '\1 have'], -- I've, you've
    ['\m(I|you|You|we|We|they|They|it|It|that|That)' || a || 'll\M', '\1 will'], -- you'll, it'll
    ['\mI' || a || 'm\M', 'I am'], -- I'm
    -- "is" and "us" forms (after the "has" forms above).
    ['\m(it|It|that|That|there|There|what|What|who|Who|here|Here|where|Where|how|How)' || a || 's\M', '\1 is'], -- it's, what's, there's
    ['\mlet' || a || 's\M', 'let us'], ['\mLet' || a || 's\M', 'Let us'] -- let's
  ] loop -- for each pair:
    t := regexp_replace(t, pair[1], pair[2], 'g'); -- swaps every match for the full wording
  end loop; -- end of the list
  return t; -- hands back the written-out text
end;
$$;

-- Goes through CLG's own database steps and saves again each one whose
-- wording holds a short form, with the short forms written out.
do $$
declare
  f record; -- one database step, worked through in turn
  v_old text; -- the step's full definition as it is now
  v_new text; -- the same definition with short forms written out
  v_count int := 0; -- how many steps were updated (shown at the end)
begin
  for f in -- for each step:
    select p.oid -- its internal number
    from pg_proc p -- from the list of database steps
    join pg_namespace n on n.oid = p.pronamespace -- with the area it lives in
    where n.nspname in ('public', 'private') -- only CLG's own areas (never Supabase's or the database's)
      and p.prokind = 'f' -- only ordinary steps (not groupings or procedures)
      and p.prosrc is distinct from pg_temp.expand_message_contractions(p.prosrc) -- only steps whose wording has a short form
  loop
    v_old := pg_get_functiondef(f.oid); -- reads the step's full definition
    v_new := pg_temp.expand_message_contractions(v_old); -- writes out its short forms
    if v_new is distinct from v_old then -- something changed:
      execute v_new; -- saves the step again (same name, settings and permissions; only the words differ)
      v_count := v_count + 1; -- counts it
    end if; -- end of that case
  end loop; -- end of the steps
  raise notice 'Wrote out the short forms in % database steps.', v_count; -- reports how many were updated
end;
$$;

-- Removes the helper now the messages are updated.
drop function pg_temp.expand_message_contractions(text); -- tidies up (it would vanish at the end of the session anyway)
