-- Training (module: training): save a module part way through (Carla,
-- 18 Nov 2026). A tutor or admin can tick off the lessons they have done and
-- save the quiz answers they have chosen so far, then come back another time
-- and carry on where they stopped. For example, when a module takes 30
-- minutes but they only have 15 minutes set aside today.
--
-- One row per person per module holds:
--   * which lessons they have marked as done;
--   * the quiz answers they saved (not marked until they check them).
-- The person and full admins can read it. Only the training_save_progress
-- step below writes it, and it checks the module is published and for them.
-- Nothing here changes completions, certificates or pay.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The saved places.
-- ---------------------------------------------------------------------------
create table if not exists public.training_progress ( -- where each person is up to in a module
  account_id uuid not null references public.accounts (id) on delete cascade, -- whose place it is (removed with their account)
  module_id uuid not null references public.training_modules (id) on delete cascade, -- which module (removed with a deleted draft)
  done_lessons uuid[] not null default '{}', -- the lessons they have marked as done
  saved_answers int[] not null default '{}', -- the quiz answers saved so far, in question order (0 means not answered yet)
  updated_at timestamptz not null default now(), -- when they last saved
  primary key (account_id, module_id) -- one row per person per module
); -- end of the table

-- Access rules: the person (with two-step login) and full admins can read it.
alter table public.training_progress enable row level security; -- turns on access rules
revoke all on public.training_progress from anon; -- signed-out visitors get nothing
drop policy if exists "own training progress, admins all" on public.training_progress; -- removes the old rule (so this file can run twice)
create policy "own training progress, admins all" on public.training_progress -- who can see a saved place
  for select to authenticated using ((account_id = auth.uid() and private.has_aal2()) or private.is_admin()); -- their own (two-step login), or a full admin
revoke insert, update, delete, truncate on public.training_progress from authenticated; -- only the step below writes it

-- ---------------------------------------------------------------------------
-- Saves the signed-in person's place in a module.
--   p_done_lesson: a lesson to mark as done (or blank).
--   p_answers: the quiz answers to keep (blank keeps the saved ones; an
--   empty list clears them, for example after the quiz is passed).
-- ---------------------------------------------------------------------------
create or replace function public.training_save_progress(p_module uuid, p_done_lesson uuid default null, p_answers int[] default null) -- takes the module, a lesson and answers
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  m public.training_modules; -- the module
begin -- start of the steps
  if not private.training_staff() then -- not a tutor or admin with two-step login:
    raise exception 'Please sign in with two-step login to do training' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select * into m from public.training_modules where id = p_module; -- reads the module
  if not found or m.status <> 'published' or not private.training_fits(auth.uid(), m.audience) then -- missing, not published, or not for them:
    raise exception 'This training is not available to you' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  if p_done_lesson is not null and not exists (select 1 from public.training_lessons l where l.id = p_done_lesson and l.module_id = p_module) then -- a lesson from another module:
    raise exception 'That lesson is not part of this module' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  if p_answers is not null and cardinality(p_answers) > (select count(*) from public.training_questions q where q.module_id = p_module) then -- more answers than questions:
    raise exception 'Something went wrong with the answers. Please reload the page' using errcode = '22023'; -- refuses, in plain words
  end if; -- end of that check
  insert into public.training_progress as p (account_id, module_id, done_lessons, saved_answers) -- adds their place, or updates it:
  values (auth.uid(), p_module, -- who and which module,
    case when p_done_lesson is null then '{}' else array[p_done_lesson] end, -- the lesson done (if any),
    coalesce(p_answers, '{}')) -- and the answers (if any)
  on conflict (account_id, module_id) do update set -- already has a place: updates it:
    done_lessons = case when p_done_lesson is null or p_done_lesson = any(p.done_lessons) then p.done_lessons else p.done_lessons || p_done_lesson end, -- adds the lesson once,
    saved_answers = coalesce(p_answers, p.saved_answers), -- swaps the answers only when new ones are given,
    updated_at = now(); -- and notes the time
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_save_progress(uuid, uuid, int[]) from public, anon; -- not for signed-out visitors
grant execute on function public.training_save_progress(uuid, uuid, int[]) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- The handbook's pay page: training is paid for its set time only (Carla,
-- 18 Nov 2026). Swaps one exact line, so other edits to the page are kept.
-- Running it again changes nothing (the old line is gone).
-- ---------------------------------------------------------------------------
update public.handbook_pages p -- changes a handbook page:
set body = replace(p.body, -- swaps one exact line:
  $t$- Compulsory training is paid for its set time once you finish it. It also counts towards your agreed weekly hours.$t$, -- the old line
  $t$- Compulsory training is paid for its set time once you finish it (for example 15 minutes), however long you take. It also counts towards your agreed weekly hours.
- You can save a module part way through and finish it another time. You can also do any module in your own time if you wish, but only the set time is paid.$t$) -- the new lines
where p.id = '7b000000-0000-4000-8000-000000000007'; -- the "Pay, hours and training" page
