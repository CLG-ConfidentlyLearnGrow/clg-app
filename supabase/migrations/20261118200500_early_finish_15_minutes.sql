-- Scheduling: a session only counts as finishing early when it ends more
-- than 15 minutes before the booked end (Carla, 16 Nov 2026).
--
-- Families are always charged the booked time. Before, any different
-- finish time the tutor recorded went to Times to check. Now:
--   * a tutor can't record a finish that's up to 15 minutes early: the app
--     says it counts as finishing on time, so there's nothing to record;
--   * Times to check leaves out any finish time recorded before this
--     change that is up to 15 minutes early (the booked time stands).
-- Finishing more than 15 minutes early, or running over, works as before.
--
-- Each function is edited in place (only the end-time rule), so anything
-- else changed in them later is kept. Safe to run more than once.

-- The tutor's "Finished at a different time?" form: refuse a finish up to
-- 15 minutes early, with a plain message.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  v_def := pg_catalog.pg_get_functiondef('public.record_end_time(uuid, timestamptz, text)'::regprocedure); -- reads its current code
  if strpos(v_def, 'counts as finishing on time') = 0 then -- not changed yet:
    v_def := replace(v_def, -- adds the 15-minute rule just before the "why" check:
      $old$  if nullif(trim(p_note), '') is null then$old$, -- the line it goes in front of
      $new$  -- Up to 15 minutes early counts as on time (Carla, 16 Nov 2026).
  if p_end < v_s.ends_at and p_end >= v_s.ends_at - interval '15 minutes' then
    raise exception 'Finishing up to 15 minutes early counts as finishing on time, so there''s nothing to record' using errcode = '22023';
  end if;
  if nullif(trim(p_note), '') is null then$new$); -- the new rule, then the original line
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- Times to check: a recorded finish only counts if it's more than 15
-- minutes early or after the booked end.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's current code
begin -- start
  v_def := pg_catalog.pg_get_functiondef('public.list_times_to_check()'::regprocedure); -- reads its current code
  if strpos(v_def, 'interval ''15 minutes''') = 0 then -- not changed yet:
    v_def := replace(v_def, 'when x.tutor_end_at is not null then', -- the reason shown
      'when x.tutor_end_at is not null and not (x.tutor_end_at < x.ends_at and x.tutor_end_at >= x.ends_at - interval ''15 minutes'') then'); -- only a real early finish or overrun
    v_def := replace(v_def, '      x.tutor_end_at is not null' || E'\n', -- which sessions are listed
      '      (x.tutor_end_at is not null and not (x.tutor_end_at < x.ends_at and x.tutor_end_at >= x.ends_at - interval ''15 minutes''))' || E'\n'); -- the same rule
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block
