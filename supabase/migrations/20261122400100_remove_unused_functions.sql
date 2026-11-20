-- Summary: removes five database functions that nothing uses any more
-- (Carla, 20 Nov 2026: "delete code that is no longer being used").
--
-- Each one was checked against the app code, every other migration, every
-- scheduled job and every trigger. None of them is called by the app, by
-- another function, by a trigger or by a scheduled job:
--   * public.list_matching and public.matching_pipeline: the first version
--     of the Matching page. The page now uses matching_queue,
--     matching_stage_counts and the other matching_ functions instead.
--   * public.count_booking_sessions: an early "how many sessions will this
--     booking make" helper. The booking screens no longer ask for it; the
--     away dates are still skipped when sessions are made.
--   * private.queue_monthly_summaries: monthly summaries stopped on
--     12 Nov 2026 (paid term reviews only). It was left behind as an empty
--     stand-in that always answers 0, and its nightly job was already
--     removed.
--   * private.monthly_summary_text: wrote the text of those monthly
--     summaries; only the old version of queue_monthly_summaries used it.
--
-- Nothing is stored in these functions, so no information is lost. Tables
-- and saved records are not touched. If any of them is wanted again, it can
-- be copied back from its original migration.
-- Shared core and scheduling and progress modules (functions only).
-- Safe to run more than once. Run after 20261122300100_term_review_pay.sql.

-- ---------------------------------------------------------------------------
-- 1. The old Matching page functions.
-- ---------------------------------------------------------------------------
drop function if exists public.list_matching(text, text, integer, integer); -- removes the old Matching list (replaced by matching_queue)
drop function if exists public.matching_pipeline(); -- removes the old Matching stage counts (replaced by matching_stage_counts)

-- ---------------------------------------------------------------------------
-- 2. The old booking session counter.
-- ---------------------------------------------------------------------------
drop function if exists public.count_booking_sessions(uuid, uuid, smallint, date, date); -- removes the unused "sessions this booking would make" helper

-- ---------------------------------------------------------------------------
-- 3. The leftovers of monthly summaries (stopped 12 Nov 2026).
-- ---------------------------------------------------------------------------
drop function if exists private.queue_monthly_summaries(date); -- removes the empty stand-in that always answered 0
drop function if exists private.monthly_summary_text(uuid, date, date); -- removes the text writer only the old monthly summaries used

-- ---------------------------------------------------------------------------
-- 4. Makes sure no old monthly summary job is still scheduled (it was
--    removed on 12 Nov 2026; this only tidies up if it somehow came back).
-- ---------------------------------------------------------------------------
do $$ -- a one-off block:
begin -- start
  if to_regclass('cron.job') is not null then -- if the scheduler is installed:
    perform cron.unschedule(jobid) from cron.job where jobname = 'clg-monthly-summaries'; -- removes the old job, if it is there
  end if; -- end of the check
end -- end of the block
$$; -- (end of the block's text)
