-- Scheduling: booking end dates (Carla, 11 Nov 2026).
--
-- * Families say how long they want to book for: a "book until" date in
--   each child's session places. When CLG offers a time, that date is the
--   last date. The app no longer guesses an end date.
-- * Anyone booking sees the student's term dates (from their school
--   calendar, private calendar or own study periods) to pick an end from.
--
-- Needs 20261103000300_scheduling_study_periods.sql. Safe to run more than
-- once.

alter table public.student_places add column if not exists book_until date;

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
