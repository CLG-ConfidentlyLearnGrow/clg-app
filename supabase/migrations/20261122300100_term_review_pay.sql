-- Summary: tutors are paid for writing term reviews, and send one only once
-- their term review training is done (Carla, 19 Nov 2026).
--
-- Carla: term reviews are "paid at the tutor's rate (the tutor also needs to
-- have completed the corresponding modules)". A term review is expected to
-- take about 1 hour to write.
--
-- What changes:
--   * Billing: when CLG approves a term review, the tutor gets a "Term
--     review" pay line for 1 hour at their tutor rate (school or tertiary,
--     matching the level they teach the student), dated the day it was
--     approved. It is added when pay is worked out (the daily run, or Work
--     out pay), and each review is paid once. If the tutor has no rate
--     entered yet, it is added once a rate is entered.
--   * Progress: a tutor cannot send a term review to CLG until they have
--     finished the published modules needed before term reviews (24 and 25).
--     They can still save a draft. Admins are not stopped.
--
-- Billing module (billing_pay_lines). It reads term reviews and sessions but
-- never changes them. The progress part edits save_term_review in place (it
-- only reads training), so other changes stay.
-- Safe to run more than once. Run after 20261121300200_training_assign_order_jobs.sql.

-- ---------------------------------------------------------------------------
-- 1. A new kind of pay line, "term_review", linked to the review it pays.
-- ---------------------------------------------------------------------------
alter table public.billing_pay_lines drop constraint if exists billing_pay_lines_kind_check; -- removes the old list of kinds
alter table public.billing_pay_lines add constraint billing_pay_lines_kind_check -- adds the list back with "term_review" included
  check (kind in ('session', 'late_cancel', 'min_topup', 'admin', 'tutoring_work', 'guaranteed', 'summary', 'training', 'term_review')); -- every kind of pay line
alter table public.billing_pay_lines add column if not exists term_review_id uuid references public.term_reviews (id) on delete set null; -- which term review a line pays for (blank on other lines)
create unique index if not exists billing_pay_lines_term_review_once -- each term review is paid once
  on public.billing_pay_lines (term_review_id) where term_review_id is not null; -- (only lines that have one)

-- ---------------------------------------------------------------------------
-- 2. How long a term review is paid for: 1 hour (Carla, 19 Nov 2026).
-- ---------------------------------------------------------------------------
create or replace function private.billing_term_review_minutes() -- no inputs
returns int language sql immutable -- always gives the same answer
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the answer:
  select 60 -- 60 minutes (change this number if CLG changes the time)
$$; -- end of the function
revoke all on function private.billing_term_review_minutes() from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 3. Add term review pay for reviews CLG approved in a range of days.
-- Returns how many term review lines are waiting to go to Xero in the range.
-- ---------------------------------------------------------------------------
create or replace function public.billing_build_term_review_pay(p_from date, p_to date) -- the first and last day to look at
returns int language plpgsql security definer -- gives back a count; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  v_minutes int := private.billing_term_review_minutes(); -- the paid time for each review
  r record; -- one review at a time
  v_kind text; -- which tutor rate: school or tertiary
  v_rate int; -- the rate in cents on that day
  n int := 0; -- how many lines are waiting
begin -- start of the steps
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can work out pay' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of that check
  if p_to < p_from or p_to - p_from > 62 then -- same limit as working out session pay
    raise exception 'Choose up to about two months at a time' using errcode = '22023'; -- plain message
  end if; -- end of that check
  for r in -- each approved review in the range not yet paid:
    select tr.id, tr.tutor_id, tr.student_id, tr.term_label, -- the review, its tutor, the student and the term
           (tr.approved_at at time zone 'Australia/Adelaide')::date as day, -- the day CLG approved it (Adelaide time)
           private.first_name(st.full_name) as first_name -- the student's first name, for the note
    from public.term_reviews tr -- term reviews belong to progress; billing only reads them
    join public.students st on st.id = tr.student_id -- for the student's first name
    where tr.status = 'approved' and tr.tutor_id is not null and tr.approved_at is not null -- approved, with a tutor
      and (tr.approved_at at time zone 'Australia/Adelaide')::date between p_from and p_to -- approved in the days asked for
      and not exists (select 1 from public.billing_pay_lines l where l.term_review_id = tr.id) -- not paid already
  loop -- for each one:
    v_kind := coalesce( -- the rate kind:
      (select se.level_kind from public.sessions se -- the level of the tutor's latest session with this student,
        where se.tutor_id = r.tutor_id and se.student_id = r.student_id -- (same tutor and student)
        order by se.starts_at desc limit 1), -- (the latest one)
      private.billing_tutoring_kind(r.tutor_id)); -- or the tutor's usual tutoring rate
    v_rate := case when v_kind is null then null else private.billing_pay_rate_on(r.tutor_id, v_kind, r.day) end; -- the rate on that day (if entered)
    if v_rate is null then -- no rate entered yet:
      continue; -- skips it for now (it is added once a rate is entered)
    end if; -- end of that check
    insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, term_review_id, minutes, rate_cents, amount_cents, under_award, note, created_by) -- adds the pay line
    select r.tutor_id, a.full_name, r.day, 'term_review', v_kind, r.id, v_minutes, v_rate, -- who, when, what kind, which rate, which review, how long and the rate
           round(v_rate * v_minutes / 60.0)::int, -- the pay, in cents
           private.billing_under_award(r.tutor_id, v_kind, v_rate, r.day), -- flag if under the award on that day
           left(coalesce(r.first_name, 'Student') || ', ' || r.term_label || ' (writing the term review)', 300), auth.uid() -- what it is for, and who worked it out
    from public.accounts a where a.id = r.tutor_id -- the tutor's name
    on conflict do nothing; -- already there: leave it
  end loop; -- end of the reviews
  select count(*) into n from public.billing_pay_lines -- counts what is waiting
  where status = 'pending' and kind = 'term_review' and work_date between p_from and p_to; -- term review lines in the range not yet sent
  return n; -- tells the caller
end; -- end of the steps
$$; -- end of the function
revoke all on function public.billing_build_term_review_pay(date, date) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_build_term_review_pay(date, date) to authenticated, service_role; -- signed-in admins (checked inside) and the daily run

-- ---------------------------------------------------------------------------
-- 4. Progress: a tutor sends a term review only once the modules needed
--    before term reviews are finished. save_term_review is edited in place.
-- ---------------------------------------------------------------------------
do $$ -- a small block of code
declare -- working values:
  v_def text; -- the function's current code
  v_anchor text := E'  if p_submit and (nullif(btrim(p_summary), '''') is null'; -- the line the new check goes before
  v_new text := E'  if p_submit and v_r.tutor_id = auth.uid() and exists (select 1 from private.training_job_missing(v_r.tutor_id, ''term_review'')) then -- the tutor is sending it but has term review training still to do (Carla, 19 Nov 2026):\n'
             || E'    raise exception ''Please finish your term review training first: %. You can save your draft now and send it once the modules are done'', -- refuses, in plain words\n'
             || E'      (select string_agg(x.title, '', '') from private.training_job_missing(v_r.tutor_id, ''term_review'') x) using errcode = ''22023''; -- naming the modules\n'
             || E'  end if; -- end of the term review training check\n'; -- the new check
begin -- start
  if to_regprocedure('private.training_job_missing(uuid, text)') is null then -- the training change is not there
    raise exception 'Run 20261121300200_training_assign_order_jobs.sql first.'; -- plain message
  end if; -- end of the check
  v_def := replace(pg_get_functiondef('public.save_term_review(uuid, text, text, text, text, boolean)'::regprocedure), chr(13), ''); -- reads its code (without Windows line endings from pasting)
  if strpos(v_def, 'end of the term review training check') > 0 then -- already done:
    return; -- nothing to change
  end if; -- end of the check
  if strpos(v_def, v_anchor) = 0 then -- the code has changed since this was written:
    raise exception 'public.save_term_review has changed since this update was written. Ask for an updated file.'; -- plain message
  end if; -- end of the check
  execute replace(v_def, v_anchor, v_new || v_anchor); -- saves the code with the new check
end; -- finish
$$; -- end of the block
