-- Scheduling: a booking process for home and school sessions (Carla,
-- 20 Nov 2026).
--
-- Home and school sessions are only arranged by CLG, in special
-- circumstances. The database already allowed them, but the Matching
-- offer form had no way to choose them for weekly sessions, and nothing
-- set a minimum length. Now:
--   * Home sessions are booked for at least 2 hours at a time, because the
--     tutor travels there (weekly bookings and one-off sessions).
--   * "Another time or place" on an offer (offer_other_time) can be at the
--     student's home or school. That path checks the tutor's weekly
--     maximum and other bookings, which a home or school booking otherwise
--     skipped.
--
-- Each function is edited in place, so anything else changed in them later
-- is kept. Safe to run more than once.

-- "Another time or place": allow home and school, and home needs 2 hours.
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.offer_other_time(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text)'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'at least 2 hours') = 0 then -- not changed yet:
    if strpos(v_def, 'if p_delivery not in (''online'', ''library'') then') = 0 then -- the expected code is not there:
      raise exception 'offer_other_time has changed since this was written; please ask for help'; -- stops, so nothing half-changes
    end if; -- end of the check
    v_def := replace(v_def, -- the place check:
      'if p_delivery not in (''online'', ''library'') then
    raise exception ''Choose online or a library''', -- old: online or a library only,
      'if p_delivery not in (''online'', ''library'', ''home'', ''school'') then
    raise exception ''Choose online, a library, the student''''s home or their school'''); -- new: home and school too,
    v_def := replace(v_def, -- after the length check, adds the home minimum:
      'raise exception ''Sessions run for 1 to 4 hours'' using errcode = ''22023'';
  end if;', -- the end of the length check,
      'raise exception ''Sessions run for 1 to 4 hours'' using errcode = ''22023'';
  end if;
  if p_delivery = ''home'' and p_minutes < 120 then
    raise exception ''Home sessions are booked for at least 2 hours at a time'' using errcode = ''22023'';
  end if;'); -- followed by the home minimum
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- Weekly bookings: home needs 2 hours (also covers any other way in).
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text)'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'at least 2 hours') = 0 then -- not changed yet:
    if strpos(v_def, 'if p_first_date is null or p_last_date is null then') = 0 then -- the expected code is not there:
      raise exception 'request_booking has changed since this was written; please ask for help'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, -- before the dates check, adds the home minimum:
      'if p_first_date is null or p_last_date is null then', -- the dates check,
      'if p_delivery = ''home'' and coalesce(p_minutes, 0) < 120 then
    raise exception ''Home sessions are booked for at least 2 hours at a time'' using errcode = ''22023'';
  end if;
  if p_first_date is null or p_last_date is null then'); -- with the home minimum before it
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- One-off sessions: home needs 2 hours.
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text)'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'at least 2 hours') = 0 then -- not changed yet:
    if strpos(v_def, 'if p_delivery in (''home'', ''school'') and v_by_tutor then') = 0 then -- the expected code is not there:
      raise exception 'offer_one_off has changed since this was written; please ask for help'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, -- before the "CLG only" check, adds the home minimum:
      'if p_delivery in (''home'', ''school'') and v_by_tutor then', -- the "CLG only" check,
      'if p_delivery = ''home'' and coalesce(p_minutes, 0) < 120 then
    raise exception ''Home sessions are booked for at least 2 hours at a time'' using errcode = ''22023'';
  end if;
  if p_delivery in (''home'', ''school'') and v_by_tutor then'); -- with the home minimum before it
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- Times to check: a home or school session has no place to check the
-- tutor's location against, so "no location" is expected there and is not
-- listed (a missing sign-on or a different finish time still is).
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.list_times_to_check()'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'or x.sign_on_check in (''not_at_library'', ''no_location'')') > 0 then -- not changed yet:
    v_def := replace(v_def, -- the location part of the filter:
      'or x.sign_on_check in (''not_at_library'', ''no_location'')', -- old: any missing location,
      'or x.sign_on_check = ''not_at_library''
      or (x.sign_on_check = ''no_location'' and x.delivery not in (''home'', ''school''))'); -- new: not for home or school sessions
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- Finding times: home times are only offered for sessions of 2 hours or
-- more, so an admin is never offered a home time that cannot be booked.
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time)'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'and p_minutes >= 120') = 0 then -- not changed yet:
    if strpos(v_def, 'where private.is_front_desk() and s.slot_home and v_home.travel_km is not null') = 0 then -- the expected code is not there:
      raise exception 'find_session_times has changed since this was written; please ask for help'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, -- the home times filter:
      'where private.is_front_desk() and s.slot_home and v_home.travel_km is not null', -- old,
      'where private.is_front_desk() and s.slot_home and v_home.travel_km is not null and p_minutes >= 120'); -- new: 2 hours or more
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block
