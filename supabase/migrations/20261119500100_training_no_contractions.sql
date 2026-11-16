-- Summary: writes out every short form (contraction) in the training and
-- handbook wording held in the database, so nothing can be misread (Carla,
-- 16 Nov 2026: no "don't", "you're", "it's" and so on in anything people
-- read, especially anything that could be read in a legal sense). For
-- example "don't" becomes "do not", "you're" becomes "you are" and
-- "Something's happened" becomes "Something has happened". It changes only
-- the wording, never the meaning, and leaves possessives such as "CLG's"
-- alone. It covers module names and summaries, lesson titles, text and link
-- words, quiz questions, answer choices and explanations, and handbook
-- titles and pages, including drafts and any edits made in the app since.
-- Past completion records (and the certificates they print) are left as they
-- were, because they record what someone finished at the time.
-- Safe to run more than once: a second run finds nothing left to change.

-- A short-lived helper that writes out the short forms in one piece of text.
-- It lives in this session's temporary area only and disappears afterwards.
create or replace function pg_temp.expand_contractions(t text) -- takes a piece of text
returns text -- and hands back the same text with short forms written out
language plpgsql -- written in the database's step-by-step language
as $$
declare
  pair text[]; -- one short form and its full wording, worked through in turn
  a constant text := '(?:''|’)'; -- an apostrophe, either straight or curly (written as a choice so it works whatever the database's character set)
begin
  if t is null then return null; end if; -- nothing to change in an empty value
  foreach pair slice 1 in array array[ -- each short form and its full wording, most specific first:
    -- "has" forms, where the next word shows "'s" means "has", not "is".
    ['something' || a || 's happened', 'something has happened'], -- something's happened
    ['Something' || a || 's happened', 'Something has happened'], -- Something's happened
    ['\m(that|what|it|there|That|What|It|There)' || a || 's (been|happened|changed|got|gone|had)\M', '\1 has \2'], -- that's happened, it's been
    ['\m(it|It)' || a || 's already been\M', '\1 has already been'], -- it's already been
    -- "had" and "would" forms of "'d".
    ['\m(I|you|You|we|We|they|They)' || a || 'd (already|been|finished|done|seen)\M', '\1 had \2'], -- you'd already finished
    ['\m(I|you|You|we|We|they|They)' || a || 'd\M', '\1 would'], -- I'd like, you'd start
    -- "not" forms.
    ['\mcan' || a || 't\M', 'cannot'], ['\mCan' || a || 't\M', 'Cannot'], -- can't
    ['\mwon' || a || 't\M', 'will not'], ['\mWon' || a || 't\M', 'Will not'], -- won't
    ['\m(do|does|did|is|are|was|were|could|should|would|have|has|had|must|need)n' || a || 't\M', '\1 not'], -- don't, isn't, couldn't and so on
    ['\m(Do|Does|Did|Is|Are|Was|Were|Could|Should|Would|Have|Has|Had|Must|Need)n' || a || 't\M', '\1 not'], -- the same at the start of a sentence
    -- "are", "have", "will" and "am" forms.
    ['\m(you|You|we|We|they|They|what|What|who|Who|there|There)' || a || 're\M', '\1 are'], -- you're, they're
    ['\m(I|you|You|we|We|they|They)' || a || 've\M', '\1 have'], -- I've, you've
    ['\m(I|you|You|we|We|they|They|it|It|that|That)' || a || 'll\M', '\1 will'], -- you'll, it'll
    ['\mI' || a || 'm\M', 'I am'], -- I'm
    -- "is" and "us" forms (after the "has" forms above).
    ['\m(it|It|that|That|there|There|what|What|who|Who|here|Here|where|Where|how|How)' || a || 's\M', '\1 is'], -- it's, what's, there's
    ['\mlet' || a || 's\M', 'let us'], ['\mLet' || a || 's\M', 'Let us'] -- let's
  ] loop -- for each pair:
    t := regexp_replace(t, pair[1], pair[2], 'g'); -- swaps every match in the text for the full wording
  end loop; -- end of the list
  return t; -- hands back the written-out text
end;
$$;

-- Module names and summaries.
update public.training_modules -- in the training modules,
set title = pg_temp.expand_contractions(title), -- writes out the name
    summary = pg_temp.expand_contractions(summary) -- and the summary,
where title is distinct from pg_temp.expand_contractions(title) -- only where the name has a short form
   or summary is distinct from pg_temp.expand_contractions(summary); -- or the summary does.

-- Lesson titles, text and link words.
update public.training_lessons -- in the lessons,
set title = pg_temp.expand_contractions(title), -- writes out the heading,
    body = pg_temp.expand_contractions(body), -- the text
    link_label = pg_temp.expand_contractions(link_label) -- and the words shown for a link,
where title is distinct from pg_temp.expand_contractions(title) -- only where the heading has a short form,
   or body is distinct from pg_temp.expand_contractions(body) -- or the text does,
   or link_label is distinct from pg_temp.expand_contractions(link_label); -- or the link words do.

-- Quiz questions, answer choices and explanations.
update public.training_questions -- in the quiz questions,
set prompt = pg_temp.expand_contractions(prompt), -- writes out the question,
    options = (select array_agg(pg_temp.expand_contractions(o) order by n) from unnest(options) with ordinality as x(o, n)), -- each answer choice, kept in the same order (so the right answer stays right),
    explanation = pg_temp.expand_contractions(explanation) -- and the explanation,
where prompt is distinct from pg_temp.expand_contractions(prompt) -- only where the question has a short form,
   or explanation is distinct from pg_temp.expand_contractions(explanation) -- or the explanation does,
   or exists (select 1 from unnest(options) o where o is distinct from pg_temp.expand_contractions(o)); -- or any answer choice does.

-- Older update files add a draft question only when no question with the same
-- words is there. If one of them is run again later (for example by a
-- catch-up script), it no longer sees the written-out question and adds the
-- old wording as a copy; running this file again then writes that copy out
-- too. This removes such a copy, keeping the first, so a draft module never
-- asks the same question twice. Published modules are never touched.
delete from public.training_questions q -- removes a question
using public.training_modules m -- (looking at its module)
where m.id = q.module_id -- from its own module,
  and m.status = 'draft' -- only while that module is a draft,
  and exists (select 1 from public.training_questions e -- when the same module already has
              where e.module_id = q.module_id -- another question
                and e.prompt = q.prompt -- with exactly the same words
                and e.position < q.position); -- placed earlier (so the first one stays).

-- Handbook titles and pages.
update public.handbook_pages -- in the handbook,
set title = pg_temp.expand_contractions(title), -- writes out the heading
    body = pg_temp.expand_contractions(body) -- and the page text,
where title is distinct from pg_temp.expand_contractions(title) -- only where the heading has a short form
   or body is distinct from pg_temp.expand_contractions(body); -- or the text does.

-- Removes the helper now the wording is updated.
drop function pg_temp.expand_contractions(text); -- tidies up (it would vanish at the end of the session anyway)
