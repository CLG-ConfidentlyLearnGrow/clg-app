-- Scheduling: booking end dates (Carla, 11 Nov 2026).
--
-- * Families say how long they want to book for, as its own step (not part
--   of preferred times): a "book until" date, and whether sessions go ahead
--   in school holidays and on public holidays. They can change it later,
--   and CLG admins can change it for them. When CLG offers a time, the date
--   is the last date and the holiday choices are copied onto the booking.
--   The app no longer guesses an end date.
-- * Anyone booking sees the student's term dates (from their school
--   calendar, private calendar or own study periods) to pick an end from.
--
-- Needs 20261103000300_scheduling_study_periods.sql and
-- 20261103000400_scheduling_requests_and_holidays.sql. Safe to run more than
-- once.

alter table public.student_places add column if not exists book_until date;
-- Blank until the family answers.
alter table public.student_places add column if not exists include_school_holidays boolean;
alter table public.student_places add column if not exists include_public_holidays boolean;

-- The date must be from today and no more than a year ahead (bookings run
-- up to a year). Checked only when it changes, so an old date doesn't block
-- other edits.
create or replace function private.check_book_until()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.book_until is not null
     and (tg_op = 'INSERT' or new.book_until is distinct from old.book_until)
     and (new.book_until < current_date or new.book_until > current_date + 366) then
    raise exception 'The "book until" date must be from today and within a year' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists check_book_until on public.student_places;
create trigger check_book_until before insert or update on public.student_places
  for each row execute function private.check_book_until();

-- The family (or a CLG admin) sets how long to book for. All three answers
-- are needed.
create or replace function public.set_booking_length(
  p_student uuid, p_until date, p_school_holidays boolean, p_public_holidays boolean
)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not (private.can_book_for(p_student) or private.is_front_desk()) then
    raise exception 'You can only do this for your own children' using errcode = '42501';
  end if;
  if p_until is null or p_school_holidays is null or p_public_holidays is null then
    raise exception 'Please give the last date and answer both holiday questions' using errcode = '22023';
  end if;
  insert into public.student_places (student_id, book_until, include_school_holidays, include_public_holidays)
  values (p_student, p_until, p_school_holidays, p_public_holidays)
  on conflict (student_id) do update
    set book_until = excluded.book_until,
        include_school_holidays = excluded.include_school_holidays,
        include_public_holidays = excluded.include_public_holidays;
end;
$$;
revoke all on function public.set_booking_length(uuid, date, boolean, boolean) from public, anon;
grant execute on function public.set_booking_length(uuid, date, boolean, boolean) to authenticated;

-- A new booking (not a renewal, which keeps its own choice) follows the
-- family's holiday answers.
create or replace function private.booking_holiday_choices()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_sp public.student_places;
begin
  if new.renews_booking is not null then
    return new;
  end if;
  select * into v_sp from public.student_places where student_id = new.student_id;
  if v_sp.include_school_holidays is not null then
    new.skip_holidays := not v_sp.include_school_holidays;
  end if;
  if v_sp.include_public_holidays is not null then
    new.skip_public_holidays := not v_sp.include_public_holidays;
  end if;
  return new;
end;
$$;
revoke all on function private.booking_holiday_choices() from public;
drop trigger if exists holiday_choices on public.bookings;
create trigger holiday_choices before insert on public.bookings
  for each row execute function private.booking_holiday_choices();

-- The student's terms or study periods that haven't finished yet, for
-- picking an end date. For the family (and the student) and CLG admins.
create or replace function public.student_term_dates(p_student uuid)
returns table (label text, starts_on date, ends_on date)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not (private.can_book_for(p_student) or private.is_front_desk()) then
    raise exception 'You can only see term dates for your own children' using errcode = '42501';
  end if;
  return query
  select t.label, t.starts_on, t.ends_on
  from private.student_terms(p_student) t
  where t.ends_on >= current_date
  order by t.starts_on
  limit 8;
end;
$$;
revoke all on function public.student_term_dates(uuid) from public, anon;
grant execute on function public.student_term_dates(uuid) to authenticated;
