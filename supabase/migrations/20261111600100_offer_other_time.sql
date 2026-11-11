-- Matching (module: scheduling): CLG can offer another time or place
-- (Carla, 11 Nov 2026).
--
-- On the Matching card an admin can pick any of the tutor's other suitable
-- times, or "another time or place" that isn't in the tutor's availability.
-- Choosing anything but the suggestion records a reason (as before). The
-- tutor and the family still both approve before anything is booked.
--
-- For "another time or place" the app still checks that the tutor:
--   * is active, cleared for the student's state and teaches the subject
--     at the student's level, and isn't blocked from this student,
--   * has room under their weekly maximum hours,
--   * has no other booking at that time,
-- and that a library is active and confirmed by CLG.
--
-- request_booking is changed in place: the "time must be in the tutor's
-- availability" check is skipped only inside offer_other_time.
-- Safe to run more than once.

do $$
declare
  v_def text;
  v_old text := '  elsif not exists (
    select 1 from public.find_session_times(';
  v_new text := '  elsif not (private.is_front_desk() and coalesce(current_setting(''clg.offer_other_time'', true), '''') = ''on'')
    and not exists (
    select 1 from public.find_session_times(';
begin
  v_def := pg_get_functiondef('public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text)'::regprocedure);
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'clg.offer_other_time') > 0 then
    return; -- already done
  end if;
  if strpos(v_def, v_old) = 0 then
    raise exception 'request_booking has changed since this update was written. Ask for an updated file.';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$$;

create or replace function public.offer_other_time(
  p_student uuid,
  p_subject text,
  p_tutor uuid,
  p_weekday smallint,
  p_start time,
  p_minutes integer,
  p_delivery public.session_delivery,
  p_library uuid,
  p_first_date date,
  p_last_date date,
  p_note text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_level text;
  v_max numeric;
  v_booked integer;
  v_first date;
  v_id uuid;
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG admins can offer another time' using errcode = '42501';
  end if;
  if p_delivery not in ('online', 'library') then
    raise exception 'Choose online or a library' using errcode = '22023';
  end if;
  if p_weekday is null or p_weekday not between 1 and 7 or p_start is null then
    raise exception 'Choose a day and start time' using errcode = '22023';
  end if;
  if p_minutes is null or p_minutes < 60 or p_minutes > 240 then
    raise exception 'Sessions run for 1 to 4 hours' using errcode = '22023';
  end if;
  if p_delivery = 'library' and not exists (
    select 1 from public.libraries l where l.id = p_library and l.active and l.confirmed_at is not null
  ) then
    raise exception 'Choose a library CLG has confirmed' using errcode = '22023';
  end if;

  v_level := private.matching_level(p_student, p_subject);
  if not exists (select 1 from public.tutor_profiles t where t.account_id = p_tutor and t.active)
     or not private.tutor_cleared_for_student(p_tutor, p_student)
     or not private.tutor_teaches(p_tutor, p_subject, v_level)
     or private.blocked_pair(p_tutor, p_student) then
    raise exception 'This tutor can''t take this student for %', trim(p_subject) using errcode = '23514';
  end if;

  select w.max_weekly_hours into v_max from public.tutor_work_settings w where w.tutor_id = p_tutor;
  select coalesce(sum(b.minutes), 0) into v_booked
  from public.bookings b
  where b.tutor_id = p_tutor and private.booking_is_live(b.status, b.tutor_reply_by) and b.last_date >= current_date;
  if v_max is not null and v_booked + p_minutes > v_max * 60 then
    raise exception 'This would take the tutor past their weekly maximum of % hr', v_max using errcode = '23514';
  end if;

  v_first := p_first_date + ((p_weekday - extract(isodow from p_first_date)::int + 7) % 7);
  if exists (
    select 1 from public.bookings b
    where b.tutor_id = p_tutor and b.weekday = p_weekday
      and private.booking_is_live(b.status, b.tutor_reply_by)
      and b.first_date <= p_last_date and b.last_date >= v_first
      and b.start_time < p_start + make_interval(mins => p_minutes)
      and p_start < b.start_time + make_interval(mins => b.minutes)
  ) then
    raise exception 'The tutor already has a booking at that time' using errcode = '23514';
  end if;

  perform set_config('clg.offer_other_time', 'on', true);
  v_id := public.request_booking(p_student, p_subject, p_tutor, p_weekday, p_start, p_minutes,
                                 p_delivery, p_library, p_first_date, p_last_date, p_note);
  perform set_config('clg.offer_other_time', '', true);
  return v_id;
end;
$$;
revoke all on function public.offer_other_time(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text) from public, anon;
grant execute on function public.offer_other_time(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text) to authenticated;
