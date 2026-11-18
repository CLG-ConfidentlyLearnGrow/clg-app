-- Training (module: training): screenshot quiz questions and practice tasks
-- checked by CLG (Carla, 18 Nov 2026).
--
--   * Screenshot questions: a quiz question can show a picture (for example
--     a screenshot of the app) and ask what to press or where to write. The
--     picture is kept in the private training file store; staff can open it
--     only while they can see the module.
--   * Practice tasks: a module can end with a written task (for example a
--     mock session summary for a made-up student). The person writes it in
--     the app; a full admin approves it or sends it back with what to
--     change. The module is only finished once the quiz is passed AND the
--     task is approved. If the quiz was already passed, approving the task
--     finishes the module straight away (with its certificate, and paid if
--     it is compulsory or assigned).
--
-- Tasks use made-up students only: the task wording and the app both say
-- not to write real student information.
-- Safe to run more than once. Run after 20261121300200.

-- ---------------------------------------------------------------------------
-- 1. Screenshot questions.
-- ---------------------------------------------------------------------------
alter table public.training_questions add column if not exists image_path text; -- the picture shown with the question (a file in the training store), or blank
alter table public.training_questions add column if not exists image_alt text check (image_alt is null or char_length(image_alt) <= 300); -- a short description of the picture, for screen readers
grant select (image_path, image_alt) on public.training_questions to authenticated; -- people who can see the question can see its picture's name and description (the access rules still apply)

-- The training store also takes pictures (PNG, JPEG, WebP).
update storage.buckets set allowed_mime_types = array['video/mp4', 'video/webm', 'video/quicktime', 'application/pdf', 'image/png', 'image/jpeg', 'image/webp'] -- videos, PDFs and pictures
where id = 'training'; -- the training store

-- Staff can open a question's picture while they can see its module.
drop policy if exists "training: staff open question pictures" on storage.objects; -- removes the old rule (so this file can run twice)
create policy "training: staff open question pictures" on storage.objects -- staff can open a question's picture
  for select to authenticated -- for signed-in people
  using (bucket_id = 'training' and exists ( -- in the training store, when there is
    select 1 from public.training_questions q -- a question
    where q.image_path = storage.objects.name -- using this picture
      and private.training_can_see(q.module_id))); -- whose module they can see

-- ---------------------------------------------------------------------------
-- 2. Practice tasks: the task on the module, and what people send in.
-- ---------------------------------------------------------------------------
alter table public.training_modules add column if not exists practice_task text check (practice_task is null or char_length(practice_task) <= 4000); -- the task's instructions (blank: no task)
grant update (practice_task) on public.training_modules to authenticated; -- admins can change it in Training setup (the access rules still apply)

create table if not exists public.training_task_submissions ( -- what people send in
  id uuid primary key default gen_random_uuid(), -- the submission's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- who wrote it (removed with their account)
  module_id uuid not null references public.training_modules (id) on delete cascade, -- which module
  module_version int not null, -- which version of the module
  answer text not null check (char_length(answer) between 20 and 6000), -- what they wrote
  status text not null default 'submitted' check (status in ('submitted', 'approved', 'returned')), -- waiting, approved, or sent back
  feedback text check (feedback is null or char_length(feedback) <= 2000), -- what CLG said (for example what to change)
  reviewed_by uuid references public.accounts (id) on delete set null, -- the admin who checked it
  reviewed_at timestamptz, -- when it was checked
  created_at timestamptz not null default now(), -- when it was first sent
  updated_at timestamptz not null default now() -- when it was last sent or checked
); -- end of the table
create index if not exists training_task_submissions_person on public.training_task_submissions (account_id, module_id, created_at desc); -- finds a person's latest quickly
create index if not exists training_task_submissions_waiting on public.training_task_submissions (status, created_at); -- finds those waiting quickly

-- Access rules: the person (two-step login) and full admins can read them; only the steps below write them.
alter table public.training_task_submissions enable row level security; -- turns on access rules
revoke all on public.training_task_submissions from anon; -- signed-out visitors get nothing
drop policy if exists "own training tasks, admins all" on public.training_task_submissions; -- removes the old rule (so this file can run twice)
create policy "own training tasks, admins all" on public.training_task_submissions -- who can see a submission
  for select to authenticated using ((account_id = auth.uid() and private.has_aal2()) or private.is_admin()); -- their own, or a full admin
revoke insert, update, delete, truncate on public.training_task_submissions from authenticated; -- only the steps below write them

-- ---------------------------------------------------------------------------
-- 3. Recording a completion (shared by finishing a module and approving a
-- task). Paid when the module is compulsory or assigned to the person.
-- ---------------------------------------------------------------------------
create or replace function private.training_record_completion(p_account uuid, p_module uuid) -- takes the person and module
returns uuid language plpgsql security definer -- gives back the new completion's id; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  m public.training_modules; -- the module
  v_id uuid := gen_random_uuid(); -- the new completion's id
  v_today date := private.training_today(); -- today in Adelaide
begin -- start of the steps
  select * into m from public.training_modules where id = p_module; -- reads the module
  insert into public.training_completions ( -- records the completion
    id, account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, expires_on, certificate_no -- its details
  ) values ( -- the values:
    v_id, p_account, p_module, m.version, m.title, m.audience, m.minutes, -- the id, who, which module and version, its name, audience and set time,
    (m.required or exists (select 1 from public.training_assignments a where a.account_id = p_account and a.module_id = p_module)), -- paid when it is compulsory or assigned to them
    m.counts_toward_certified, -- whether it counts towards the quarter's hours
    v_today, -- the day (Adelaide)
    case when m.renew_months is not null then (v_today + make_interval(months => m.renew_months))::date end, -- when it needs redoing (if it does)
    'CLG-' || to_char(v_today, 'YYYY') || '-' || upper(left(replace(v_id::text, '-', ''), 8)) -- a certificate number, for example CLG-2026-1A2B3C4D
  ); -- end of the values
  return v_id; -- gives back the id
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_record_completion(uuid, uuid) from public; -- for the database's own use

-- Finishing a module waits for an approved practice task (edited in place,
-- so other changes made to the step are kept).
do $$ -- a one-off block
declare -- working values
  v_def text; -- the step's current code
begin -- start
  v_def := pg_catalog.pg_get_functiondef('public.training_finish(uuid, integer[])'::regprocedure); -- reads its current code
  if strpos(v_def, 'practice_task') = 0 then -- not changed yet:
    v_def := regexp_replace(v_def, '(\n\s*select \* into st from private\.training_state\(auth\.uid\(\), p_module\);)', -- before checking where they are up to,
      E'\n  if m.practice_task is not null and not exists ( -- the module has a practice task, and there is no\n'
      || E'    select 1 from public.training_task_submissions t -- submission\n'
      || E'    where t.account_id = auth.uid() and t.module_id = p_module and t.module_version = m.version and t.status = ''approved'') then -- approved for this version:\n'
      || E'    return jsonb_build_object(''passed'', true, ''score'', v_score, ''total'', v_total, ''wrong'', ''[]''::jsonb, ''waiting_task'', true); -- the quiz is passed, but the module waits for the task\n'
      || E'  end if; -- end of the task check\\1'); -- adds the task check
    execute v_def; -- saves the changed step
  end if; -- done
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 4. Sending in a practice task.
-- ---------------------------------------------------------------------------
create or replace function public.training_submit_task(p_module uuid, p_answer text) -- takes the module and what they wrote
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  m public.training_modules; -- the module
  v_name text; -- the person's name
begin -- start of the steps
  if not private.training_staff() then -- not a tutor or admin with two-step login:
    raise exception 'Please sign in with two-step login to do training' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select * into m from public.training_modules where id = p_module; -- reads the module
  if not found or m.status <> 'published' or not private.training_fits(auth.uid(), m.audience) then -- missing, not published, or not for them:
    raise exception 'This training is not available to you' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  if m.practice_task is null then -- no task on this module:
    raise exception 'This module has no practice task' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if char_length(trim(coalesce(p_answer, ''))) < 20 then -- too short:
    raise exception 'Please write a bit more before sending it' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if char_length(p_answer) > 6000 then -- too long:
    raise exception 'Please keep it under 6,000 characters' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if exists (select 1 from public.training_task_submissions t where t.account_id = auth.uid() and t.module_id = p_module and t.module_version = m.version and t.status = 'approved') then -- already approved:
    raise exception 'Your practice task for this module is already approved' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  update public.training_task_submissions t -- an earlier one still waiting or sent back:
  set answer = p_answer, status = 'submitted', updated_at = now() -- is replaced and waits again
  where t.account_id = auth.uid() and t.module_id = p_module and t.module_version = m.version and t.status in ('submitted', 'returned'); -- (for this version)
  if not found then -- none yet:
    insert into public.training_task_submissions (account_id, module_id, module_version, answer) -- adds it
    values (auth.uid(), p_module, m.version, p_answer); -- who, which module and version, and what they wrote
  end if; -- end of the choice
  select a.full_name into v_name from public.accounts a where a.id = auth.uid(); -- their name
  perform private.notify_admins('Practice task to check: ' || coalesce(v_name, 'someone'), -- tells the admins
    coalesce(v_name, 'Someone') || ' sent the practice task for "' || m.title || '". Check it under Training setup, Practice tasks.'); -- who, which module and where to check
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_submit_task(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.training_submit_task(uuid, text) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 5. Checking a practice task (full admins): approve, or send back with
-- what to change. Approving finishes the module if the quiz is passed.
-- ---------------------------------------------------------------------------
create or replace function public.training_review_task(p_submission uuid, p_approve boolean, p_feedback text default null) -- takes the submission, the decision and any feedback
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  t public.training_task_submissions; -- the submission
  m public.training_modules; -- its module
  v_quiz_ok boolean; -- whether the quiz is passed for this version
  st record; -- where the person is up to
  v_finished boolean := false; -- whether approving finished the module
begin -- start of the steps
  if not (private.is_admin() and private.has_aal2()) then -- not a full admin with two-step login:
    raise exception 'Only CLG owner or operations admins can check practice tasks' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select * into t from public.training_task_submissions where id = p_submission for update; -- reads the submission (and holds it)
  if not found or t.status <> 'submitted' then -- missing, or already checked:
    raise exception 'This practice task is not waiting to be checked' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if not p_approve and char_length(trim(coalesce(p_feedback, ''))) < 5 then -- sent back without saying why:
    raise exception 'Please say what to change' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if t.account_id = auth.uid() then -- checking their own:
    raise exception 'Someone else needs to check your own practice task' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  update public.training_task_submissions -- saves the decision:
  set status = case when p_approve then 'approved' else 'returned' end, -- approved or sent back,
      feedback = nullif(trim(coalesce(p_feedback, '')), ''), reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now() -- with feedback, who and when
  where id = t.id; -- this submission
  select * into m from public.training_modules where id = t.module_id; -- reads the module
  if p_approve and m.version = t.module_version then -- approved, for the current version:
    v_quiz_ok := not exists (select 1 from public.training_questions q where q.module_id = m.id) -- no quiz,
      or exists (select 1 from public.training_attempts a where a.account_id = t.account_id and a.module_id = m.id and a.module_version = m.version and a.score = a.total); -- or a full-marks try for this version
    select * into st from private.training_state(t.account_id, m.id); -- where they are up to
    if v_quiz_ok and st.state not in ('done', 'renew_soon') then -- quiz passed and not finished yet:
      perform private.training_record_completion(t.account_id, m.id); -- finishes the module
      v_finished := true; -- notes it
    end if; -- end of that case
  end if; -- end of the approved case
  perform private.add_notice(t.account_id, null, null, 'check_renewal', -- tells the person:
    case when p_approve then 'Practice task approved: ' else 'Practice task to redo: ' end || m.title, -- approved or to redo,
    case when p_approve and v_finished then 'CLG approved your practice task for "' || m.title || '". The module is finished and your certificate is ready under Training.' -- approved and finished,
         when p_approve then 'CLG approved your practice task for "' || m.title || '". Pass the quiz to finish the module.' -- approved, quiz still to do,
         else 'CLG has sent back your practice task for "' || m.title || '" with what to change. Open the module under Training to see it and send it again.' end, now()); -- sent back
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_review_task(uuid, boolean, text) from public, anon; -- not for signed-out visitors
grant execute on function public.training_review_task(uuid, boolean, text) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- 6. The practice tasks Carla listed (18 Nov), on modules 12, 19, 25 and 27
-- (only where the module has no task yet). Made-up students only.
-- ---------------------------------------------------------------------------
update public.training_modules m set practice_task = v.task -- sets the task
from (values -- (module, task):
  ('7a000000-0000-4000-8000-000000000012', $t$Write a session summary for this made-up session.

Mia, Year 6, maths, 1-hour online session. You worked on equivalent fractions using fraction walls. She got 6 out of 10 in the warm-up and 9 out of 10 by the end, but still hesitates when simplifying. Her mum's Progress at home note says Mia practised times tables every night this week.

Write the summary as you would for her family, with one next step. CLG checks for: the skill worked on (not just the topic), how she went with evidence, one clear and measurable next step, plain words a parent can follow, and nothing about health. Write it yourself, without AI tools.$t$),
  ('7a000000-0000-4000-8000-000000000019', $t$Write two or three comments on this made-up Year 9 history paragraph, against the rubric below. Do not rewrite any of it.

Paragraph: "World War One started in 1914. There were lots of reasons it started. Countries had alliances and they had big armies. Franz Ferdinand was shot. This made the war start because everyone joined in."

Rubric (a part of it): a clear topic sentence that answers the question; specific evidence (names, dates, facts); explains how the evidence supports the argument.

CLG checks that each comment names something done well or one thing to improve, points to the rubric, asks a question or gives a next step the student can act on, and does not write any of the work for them.$t$),
  ('7a000000-0000-4000-8000-000000000025', $t$Write a short term review for this made-up student, using the four parts from module 24.

Sam, Year 8, English, 10 weekly sessions. Term goal 1: write a paragraph with a topic sentence, two pieces of evidence and a link, without prompts, by week 10 (reached in week 8). Term goal 2: read a set text chapter each week and answer three questions on it (in progress: 6 of 10 weeks). Term goal 3: improve spelling (changed in week 4 to "spell 18 of 20 weekly words correctly", now 15 of 20). Summaries mention that Sam's confidence grew once he started planning paragraphs with a template. His dad's Progress at home notes say Sam read on the bus most days in the second half of term.

CLG checks that every goal is covered (reached, in progress, changed), with specific examples, what helped most (including what the family reported), next term's focus and a recommendation with why, in plain words and with nothing about health.$t$),
  ('7a000000-0000-4000-8000-000000000027', $t$Set up a plan for this made-up student, written out here (not in the app).

Lily, Year 10, maths. Her family wants her ready for Year 11 Mathematical Methods. Her school has a test on quadratics in week 6 and an investigation due in week 9 this term.

Write: one measurable year goal, one measurable term goal that leads to it, and the two assessment targets with their weeks. CLG checks that each goal says what, how well, by when and how it will be checked (module 26), and that the term goal clearly leads to the year goal.$t$)
) as v(mod, task) -- (the columns of the list above)
where m.id = v.mod::uuid and m.practice_task is null; -- only where there is no task yet
