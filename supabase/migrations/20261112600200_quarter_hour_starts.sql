-- Scheduling: start times every 15 minutes, and summary time after each
-- tutor session (Carla, 12 Nov 2026).
--
-- Tutors are paid for 15 minutes after each session to write the session
-- summary, so a tutor's next session must not start inside that time.
--   * Times offered by "Book a session" and the Matching tab now start every
--     15 minutes (was every 30). Session lengths stay 1 to 4 hr in half-hour
--     steps.
--   * After each of a tutor's sessions, the summary time (15 min now) is
--     kept free before their next session. The same rule is used when a
--     time is offered, changed, confirmed, renewed for next term, or booked
--     as a one-off. A student's own sessions don't need the gap.
--   * Owner and operations admins can change the summary time (0 to 30
--     min), e.g. to 5 min later on.
--
-- Changes these functions in place (they were changed by later files, so
-- the old files must not be re-run): find_session_times, confirm_booking,
-- answer_renewal, offer_other_time, offer_one_off.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The setting
-- ---------------------------------------------------------------------------

-- One row of scheduling settings for the whole of CLG.
create table if not exists public.scheduling_settings (
  id boolean primary key default true check (id), -- only ever one row
  summary_minutes integer not null default 15 check (summary_minutes between 0 and 30), -- time after each session to write the summary
  updated_at timestamptz not null default now(), -- when it last changed
  updated_by uuid references public.accounts (id) on delete set null -- who changed it
);
insert into public.scheduling_settings (id) values (true) on conflict do nothing; -- make the one row (15 min)
alter table public.scheduling_settings enable row level security; -- access rules apply
revoke all on public.scheduling_settings from anon; -- signed-out visitors can't see it
drop policy if exists "signed-in people read scheduling settings" on public.scheduling_settings; -- replace the rule if re-run
create policy "signed-in people read scheduling settings" on public.scheduling_settings -- anyone signed in may read it
  for select to authenticated using (true); -- (it's one number, nothing personal); changes go through the function below

-- The summary time as a length of time. With "false" (a different tutor,
-- or only the student is shared) there's no gap.
create or replace function private.summary_gap(p_same_tutor boolean default true)
returns interval -- e.g. 15 minutes
language sql stable security definer -- reads the setting whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the value
  select case when coalesce(p_same_tutor, false) -- the same tutor:
              then make_interval(mins => coalesce((select s.summary_minutes from public.scheduling_settings s where s.id), 15)) -- the setting (15 if missing)
              else interval '0' end -- otherwise no gap
$$; -- end of the function
revoke all on function private.summary_gap(boolean) from public; -- only used inside other functions

-- Owner and operations admins change the summary time.
create or replace function public.set_summary_minutes(p_minutes integer)
returns void -- nothing back
language plpgsql security definer -- writes the setting after checking who's asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
begin -- start
  if not private.is_admin() then -- only owner and operations admins
    raise exception 'Only CLG''s owner or operations admins can change this' using errcode = '42501'; -- plain message
  end if; -- checked who
  if p_minutes is null or p_minutes < 0 or p_minutes > 30 then -- must be 0 to 30
    raise exception 'Summary time must be between 0 and 30 minutes' using errcode = '22023'; -- plain message
  end if; -- checked the number
  update public.scheduling_settings set summary_minutes = p_minutes, updated_at = now(), updated_by = auth.uid() where id; -- save it
end; -- finish
$$; -- end of the function
revoke all on function public.set_summary_minutes(integer) from public, anon; -- not for signed-out visitors
grant execute on function public.set_summary_minutes(integer) to authenticated; -- signed-in (the function checks for admins)

-- ---------------------------------------------------------------------------
-- 2. Change the booking functions in place
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- one function's full text
  v_new text; -- the changed text
begin -- start
  -- 2a. Finding times: every 15 minutes, and the tutor's summary time.
  v_def := replace(pg_get_functiondef('public.find_session_times(uuid,text,integer,boolean,uuid[],date,smallint[],time,time)'::regprocedure), chr(13), ''); -- current text, without Windows line ends
  if position('summary_gap' in v_def) = 0 then -- not changed yet
    v_new := replace(v_def, 'interval ''30 minutes'') g', 'interval ''15 minutes'') g'); -- start times every 15 min
    v_new := replace(v_new, -- "joins other sessions": straight after the summary time
      'b.end_time = o.st or b.start_time = o.st + make_interval(mins => p_minutes))', -- old
      'b.end_time + private.summary_gap(true) = o.st or b.start_time = o.st + make_interval(mins => p_minutes) + private.summary_gap(true))'); -- new
    v_new := regexp_replace(v_new, -- the tutor is free, including the summary time either side
      '(b\.tid = o\.tid and b\.weekday = o\.weekday\s+and b\.start_time < o\.st \+ make_interval\(mins => p_minutes\))(\s+and b\.end_time)( > o\.st)', -- old
      '\1 + private.summary_gap(true)\2 + private.summary_gap(true)\3'); -- new
    if v_new = v_def or position('15 minutes'') g' in v_new) = 0 or (length(v_new) - length(replace(v_new, 'summary_gap', ''))) / length('summary_gap') <> 4 then -- expect all three changes (4 gaps)
      raise exception 'find_session_times has changed since this was written; please ask for help'; -- stop rather than half-change it
    end if; -- checked
    execute v_new; -- save the changed function
  end if; -- 2a done

  -- 2b. Confirming a booking: no clash with the tutor's summary time.
  v_def := replace(pg_get_functiondef('private.confirm_booking(uuid)'::regprocedure), chr(13), ''); -- current text
  if position('summary_gap' in v_def) = 0 then -- not changed yet
    v_new := replace(v_def, 'o.start_time < v_b.start_time + make_interval(mins => v_b.minutes)', -- old: starts before this one ends
      'o.start_time < v_b.start_time + make_interval(mins => v_b.minutes) + private.summary_gap(o.tutor_id = v_b.tutor_id)'); -- new: or inside its summary time
    v_new := replace(v_new, 'o.start_time + make_interval(mins => o.minutes) > v_b.start_time', -- old: ends after this one starts
      'o.start_time + make_interval(mins => o.minutes) + private.summary_gap(o.tutor_id = v_b.tutor_id) > v_b.start_time'); -- new: or its summary time does
    if (length(v_new) - length(replace(v_new, 'summary_gap', ''))) / length('summary_gap') <> 2 then -- expect both changes
      raise exception 'confirm_booking has changed since this was written; please ask for help'; -- stop
    end if; -- checked
    execute v_new; -- save it
  end if; -- 2b done

  -- 2c. Renewing for next term: the same check.
  v_def := replace(pg_get_functiondef('public.answer_renewal(uuid,boolean,boolean,text,text,text,boolean)'::regprocedure), chr(13), ''); -- current text
  if position('summary_gap' in v_def) = 0 then -- not changed yet
    v_new := replace(v_def, 'o.start_time < v_b.start_time + make_interval(mins => v_b.minutes)', -- old
      'o.start_time < v_b.start_time + make_interval(mins => v_b.minutes) + private.summary_gap(o.tutor_id = v_b.tutor_id)'); -- new
    v_new := replace(v_new, 'o.start_time + make_interval(mins => o.minutes) > v_b.start_time', -- old
      'o.start_time + make_interval(mins => o.minutes) + private.summary_gap(o.tutor_id = v_b.tutor_id) > v_b.start_time'); -- new
    if (length(v_new) - length(replace(v_new, 'summary_gap', ''))) / length('summary_gap') <> 2 then -- expect both changes
      raise exception 'answer_renewal has changed since this was written; please ask for help'; -- stop
    end if; -- checked
    execute v_new; -- save it
  end if; -- 2c done

  -- 2d. Offering another time: the tutor's summary time.
  v_def := replace(pg_get_functiondef('public.offer_other_time(uuid,text,uuid,smallint,time,integer,public.session_delivery,uuid,date,date,text)'::regprocedure), chr(13), ''); -- current text
  if position('summary_gap' in v_def) = 0 then -- not changed yet
    v_new := replace(v_def, 'b.start_time < p_start + make_interval(mins => p_minutes)', -- old
      'b.start_time < p_start + make_interval(mins => p_minutes) + private.summary_gap(true)'); -- new
    v_new := replace(v_new, 'p_start < b.start_time + make_interval(mins => b.minutes)', -- old
      'p_start < b.start_time + make_interval(mins => b.minutes) + private.summary_gap(true)'); -- new
    if (length(v_new) - length(replace(v_new, 'summary_gap', ''))) / length('summary_gap') <> 2 then -- expect both changes
      raise exception 'offer_other_time has changed since this was written; please ask for help'; -- stop
    end if; -- checked
    execute v_new; -- save it
  end if; -- 2d done

  -- 2e. One-off sessions: the tutor's summary time, for sessions and bookings.
  v_def := replace(pg_get_functiondef('public.offer_one_off(uuid,uuid,date,time,integer,public.session_delivery,uuid,text)'::regprocedure), chr(13), ''); -- current text
  if position('summary_gap' in v_def) = 0 then -- not changed yet
    v_new := replace(v_def, 'x.starts_at < ((p_date + p_start + make_interval(mins => p_minutes)) at time zone private.state_timezone(v_student.state))', -- old
      'x.starts_at < ((p_date + p_start + make_interval(mins => p_minutes)) at time zone private.state_timezone(v_student.state)) + private.summary_gap(x.tutor_id = v_tutor)'); -- new
    v_new := replace(v_new, 'x.ends_at > ((p_date', 'x.ends_at + private.summary_gap(x.tutor_id = v_tutor) > ((p_date'); -- the other side
    v_new := replace(v_new, 'o.start_time < p_start + make_interval(mins => p_minutes)', -- old
      'o.start_time < p_start + make_interval(mins => p_minutes) + private.summary_gap(o.tutor_id = v_tutor)'); -- new
    v_new := replace(v_new, 'o.start_time + make_interval(mins => o.minutes) > p_start', -- old
      'o.start_time + make_interval(mins => o.minutes) + private.summary_gap(o.tutor_id = v_tutor) > p_start'); -- new
    if (length(v_new) - length(replace(v_new, 'summary_gap', ''))) / length('summary_gap') <> 4 then -- expect all four changes
      raise exception 'offer_one_off has changed since this was written; please ask for help'; -- stop
    end if; -- checked
    execute v_new; -- save it
  end if; -- 2e done
end; -- finish
$$; -- end of the block
