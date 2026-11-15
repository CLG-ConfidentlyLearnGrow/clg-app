-- Summary: clear the copied text on "No concern" flags after 12 months
-- (Carla, 15 Nov 2026).
--
-- When the app flags writing for child safety, it keeps its own copy of
-- what was written. For flags the Child Safety Officer or deputy marked
-- "No concern" (a false alarm), that copy is no longer needed once a year
-- has passed, so the app blanks it. Privacy law (APP 11.2) says personal
-- information should be deleted or de-identified once it isn't needed.
--
-- Kept: everything else on the flag (the words that matched, where and when
-- it was written, who wrote it, who decided "No concern", when and why), so
-- there is still a record that the check happened and was dealt with.
-- Never cleared: flags marked "Following up" or "Raised as a concern"
-- (child safety records, kept long term), or not yet reviewed.
-- The 12 months count from the latest decision.
--
-- Needs 20261114100100_safety_watch_words.sql. Safe to run more than once.

-- When the copied text was cleared (empty while it's still there).
alter table public.safety_word_flags add column if not exists text_cleared_at timestamptz; -- adds the column only if it isn't there yet

-- Blanks the copied text on "No concern" flags decided more than 12 months
-- ago, and gives back how many it cleared.
create or replace function private.clear_no_concern_flag_text() -- no inputs
returns integer -- gives back how many flags were cleared
language plpgsql security definer -- changes flags, which people can't change directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- the working values:
  v_count integer; -- how many were cleared
begin -- starts the code
  update public.safety_word_flags -- the flags:
  set text_copy = 'Cleared after 12 months: checked and no concern found.', -- replaces the copied text with a plain note
      text_cleared_at = now() -- and records when
  where status = 'no_concern' -- only "No concern" flags,
    and reviewed_at < now() - interval '12 months' -- decided more than 12 months ago,
    and text_cleared_at is null; -- and not already cleared
  get diagnostics v_count = row_count; -- how many rows changed
  if v_count > 0 then -- if any were cleared:
    perform private.log_event('clear_no_concern_flag_text', 'safety_word_flags', null, jsonb_build_object('cleared', v_count)); -- notes how many in the activity log (no words)
  end if; -- end of the check
  return v_count; -- hands back the number
end; -- ends the code
$$; -- end of the function
revoke all on function private.clear_no_concern_flag_text() from public; -- only the nightly job runs it

-- Runs it every night at 17:30 UTC (about 3 am in Adelaide), where the job
-- scheduler (pg_cron) is available. Supabase has it.
do $$ -- a small block of code
begin -- starts the block
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the job scheduler is available
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on if needed
    execute $job$ select cron.schedule('clg-clear-no-concern-flags', '30 17 * * *', 'select private.clear_no_concern_flag_text()') $job$; -- every night (re-running replaces the same named job)
  end if; -- end of the check
end; -- ends the block
$$; -- end of the code
