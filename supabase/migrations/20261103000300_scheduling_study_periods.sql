-- Study periods (module: scheduling). Carla, 2 Nov 2026.
--
-- Each student follows one study period:
--   * public  - the state's government school terms (the default)
--   * private - private school terms. In South Australia these match the
--               government terms except for an extra week of holidays
--               between Terms 2 and 3, so Term 2 ends a week early. They
--               are the same for every SA private school.
--   * own     - their own dates, for tertiary students (university and
--               TAFE dates differ by course and provider). The family,
--               student or an admin adds each study period.
-- A school student's last day of Term 4 changes from school to school and
-- year level to year level (Year 12s finish early), so it is confirmed for
-- each student. Until it is, the term's usual last day is used, and admins
-- see who still needs confirming.
--
-- Timing (all terms, no exceptions now):
--   * families are asked about next term 3 weeks before their study
--     period ends (was 2 weeks, or 4 for terms 1 and 3)
--   * tutors are asked to check their availability 4 weeks before the
--     term ends (was 3 weeks, or 5 for terms 1 and 3)
--
-- Holidays (for bookings that skip them) and the renewal question now
-- follow the student's own study period, not just their state.
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Term calendars: government and private
-- ---------------------------------------------------------------------------
alter table public.school_terms add column if not exists calendar text not null default 'public';
alter table public.school_terms drop constraint if exists school_terms_calendar_check;
alter table public.school_terms add constraint school_terms_calendar_check check (calendar in ('public', 'private'));
alter table public.school_terms drop constraint if exists school_terms_state_year_term_key;
create unique index if not exists school_terms_once on public.school_terms (state, calendar, year, term);

-- SA private schools: the government dates with Term 2 a week shorter.
-- Existing rows are left alone, so an admin's correction stays.
insert into public.school_terms (state, calendar, year, term, starts_on, ends_on)
select t.state, 'private', t.year, t.term, t.starts_on,
       case when t.term = 2 then t.ends_on - 7 else t.ends_on end
from public.school_terms t
where t.state = 'SA' and t.calendar = 'public'
on conflict (state, calendar, year, term) do nothing;

-- ---------------------------------------------------------------------------
-- Each student's study period
-- ---------------------------------------------------------------------------
create table if not exists public.student_study_periods (
  student_id uuid primary key references public.students (id) on delete cascade,
  calendar text not null default 'public' check (calendar in ('public', 'private', 'own')),
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Tertiary students' own study periods (semesters, trimesters, terms).
create table if not exists public.student_own_terms (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  label text check (char_length(label) <= 100),
  starts_on date not null,
  ends_on date not null,
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_on > starts_on and ends_on <= starts_on + 400)
);
create index if not exists student_own_terms_student on public.student_own_terms (student_id, starts_on);

-- A school student's last day of Term 4, per year.
create table if not exists public.student_term_ends (
  student_id uuid not null references public.students (id) on delete cascade,
  year integer not null check (year between 2020 and 2100),
  last_day date not null,
  confirmed_by uuid references public.accounts (id) on delete set null,
  confirmed_at timestamptz not null default now(),
  primary key (student_id, year),
  check (extract(year from last_day) = year)
);

alter table public.student_study_periods enable row level security;
alter table public.student_own_terms enable row level security;
alter table public.student_term_ends enable row level security;
revoke all on public.student_study_periods, public.student_own_terms, public.student_term_ends from anon;
-- Changed only through the functions below.
revoke insert, update, delete, truncate on public.student_study_periods, public.student_own_terms, public.student_term_ends from authenticated;

drop trigger if exists audit on public.student_study_periods;
create trigger audit after insert or update or delete on public.student_study_periods
  for each row execute function private.audit_change();
drop trigger if exists audit on public.student_own_terms;
create trigger audit after insert or update or delete on public.student_own_terms
  for each row execute function private.audit_change();
drop trigger if exists audit on public.student_term_ends;
create trigger audit after insert or update or delete on public.student_term_ends
  for each row execute function private.audit_change();

-- The family, the student, their tutors (to plan) and admins.
drop policy if exists "see study period" on public.student_study_periods;
create policy "see study period" on public.student_study_periods
  for select to authenticated using (private.is_admin() or private.can_view_student(student_id));
drop policy if exists "see own terms" on public.student_own_terms;
create policy "see own terms" on public.student_own_terms
  for select to authenticated using (private.is_admin() or private.can_view_student(student_id));
drop policy if exists "see term ends" on public.student_term_ends;
create policy "see term ends" on public.student_term_ends
  for select to authenticated using (private.is_admin() or private.can_view_student(student_id));

-- Sets which study period a student follows (family, the student, or an
-- admin).
create or replace function public.set_study_period(p_student uuid, p_calendar text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only set the study period for your own children' using errcode = '42501';
  end if;
  if p_calendar is null or p_calendar not in ('public', 'private', 'own') then
    raise exception 'Choose government school terms, private school terms, or your own dates' using errcode = '22023';
  end if;
  insert into public.student_study_periods (student_id, calendar, updated_by, updated_at)
  values (p_student, p_calendar, auth.uid(), now())
  on conflict (student_id) do update
    set calendar = excluded.calendar, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.set_study_period(uuid, text) from public, anon;
grant execute on function public.set_study_period(uuid, text) to authenticated;

-- Adds one of a tertiary student's own study periods.
create or replace function public.add_own_term(p_student uuid, p_starts date, p_ends date, p_label text default null)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only add dates for your own children' using errcode = '42501';
  end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then
    raise exception 'Choose a first and last day, in order' using errcode = '22023';
  end if;
  if p_ends > p_starts + 400 then
    raise exception 'A study period can be up to about a year' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.student_own_terms o
    where o.student_id = p_student and o.starts_on <= p_ends and o.ends_on >= p_starts
  ) then
    raise exception 'Those dates overlap another study period. Remove that one first.' using errcode = '23505';
  end if;
  insert into public.student_own_terms (student_id, label, starts_on, ends_on, created_by)
  values (p_student, nullif(left(trim(p_label), 100), ''), p_starts, p_ends, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.add_own_term(uuid, date, date, text) from public, anon;
grant execute on function public.add_own_term(uuid, date, date, text) to authenticated;

create or replace function public.remove_own_term(p_id uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_o public.student_own_terms;
begin
  select * into v_o from public.student_own_terms where id = p_id;
  if v_o.id is null or not private.can_book_for(v_o.student_id) then
    raise exception 'Study period not found' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.term_renewals r where r.own_term_id = p_id) then
    raise exception 'Next-term answers use this study period, so it can''t be removed. Correct its dates by adding the right ones and asking CLG.' using errcode = '23503';
  end if;
  delete from public.student_own_terms where id = p_id;
end;
$$;
revoke all on function public.remove_own_term(uuid) from public, anon;
grant execute on function public.remove_own_term(uuid) to authenticated;

-- Confirms a school student's last day of Term 4 for that year.
create or replace function public.set_term4_last_day(p_student uuid, p_last_day date)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_t4 public.school_terms;
  v_state public.au_state;
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only set this for your own children' using errcode = '42501';
  end if;
  if p_last_day is null then
    raise exception 'Choose the last day of Term 4' using errcode = '22023';
  end if;
  select s.state into v_state from public.students s where s.id = p_student;
  select * into v_t4 from public.school_terms t
  where t.state = v_state and t.calendar = 'public' and t.year = extract(year from p_last_day)::int and t.term = 4;
  if v_t4.id is not null and (p_last_day < v_t4.starts_on or p_last_day > v_t4.ends_on + 7) then
    raise exception 'That date isn''t in Term 4 (% to %)', to_char(v_t4.starts_on, 'FMDD Mon'), to_char(v_t4.ends_on, 'FMDD Mon')
      using errcode = '22023';
  end if;
  insert into public.student_term_ends (student_id, year, last_day, confirmed_by, confirmed_at)
  values (p_student, extract(year from p_last_day)::int, p_last_day, auth.uid(), now())
  on conflict (student_id, year) do update
    set last_day = excluded.last_day, confirmed_by = excluded.confirmed_by, confirmed_at = excluded.confirmed_at;
end;
$$;
revoke all on function public.set_term4_last_day(uuid, date) from public, anon;
grant execute on function public.set_term4_last_day(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- A student's study periods, whichever kind they follow
-- ---------------------------------------------------------------------------
-- One row per term or study period: the school term it comes from (or the
-- student's own period), a label, and the student's real first and last
-- day. Private falls back to government dates where CLG hasn't loaded
-- private dates for that state and year.
create or replace function private.student_terms(p_student uuid)
returns table (school_term_id uuid, own_term_id uuid, label text, term smallint, starts_on date, ends_on date)
language sql stable security definer
set search_path = ''
as $$
  with s as (
    select st.id, st.state, coalesce(sp.calendar, 'public') as calendar
    from public.students st
    left join public.student_study_periods sp on sp.student_id = st.id
    where st.id = p_student
  )
  select t.id, null::uuid,
         'Term ' || t.term || ' ' || t.year || case when t.calendar = 'private' then ' (private schools)' else '' end,
         t.term, t.starts_on,
         case when t.term = 4 then coalesce(e.last_day, t.ends_on) else t.ends_on end
  from s
  join public.school_terms t on t.state = s.state
  left join public.student_term_ends e on e.student_id = s.id and e.year = t.year
  where s.calendar <> 'own'
    and t.calendar = case
      when s.calendar = 'private' and exists (
        select 1 from public.school_terms p
        where p.state = s.state and p.calendar = 'private' and p.year = t.year
      ) then 'private'
      else 'public' end
  union all
  select null::uuid, o.id, coalesce(o.label, 'Study period'), null::smallint, o.starts_on, o.ends_on
  from s
  join public.student_own_terms o on o.student_id = s.id
  where s.calendar = 'own'
$$;
revoke all on function private.student_terms(uuid) from public;

-- The study period a date falls in, or the one just before it (if it is in
-- the holidays).
create or replace function private.student_term_for(p_student uuid, p_date date)
returns table (school_term_id uuid, own_term_id uuid, label text, term smallint, starts_on date, ends_on date)
language sql stable security definer
set search_path = ''
as $$
  select * from private.student_terms(p_student) t
  where t.starts_on <= p_date
  order by t.starts_on desc limit 1
$$;
revoke all on function private.student_term_for(uuid, date) from public;

-- Is this date in the student's holidays? Only when CLG knows a study
-- period before and after it; otherwise we can't tell, and the answer is no.
create or replace function private.student_in_holidays(p_student uuid, p_date date)
returns boolean language sql stable security definer
set search_path = ''
as $$
  with t as (select * from private.student_terms(p_student))
  select exists (select 1 from t where t.starts_on <= p_date)
     and exists (select 1 from t where t.ends_on >= p_date)
     and not exists (select 1 from t where p_date between t.starts_on and t.ends_on)
$$;
revoke all on function private.student_in_holidays(uuid, date) from public;

-- Bookings that skip the holidays now follow the student's own study period.
create or replace function private.skip_holiday_session()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_state public.au_state;
begin
  if new.booking_id is null
     or not exists (select 1 from public.bookings b where b.id = new.booking_id and b.skip_holidays) then
    return new;
  end if;
  select s.state into v_state from public.students s where s.id = new.student_id;
  if private.student_in_holidays(new.student_id, (new.starts_at at time zone private.state_timezone(v_state))::date) then
    return null;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Renewal questions follow the student's study period
-- ---------------------------------------------------------------------------
alter table public.term_renewals alter column term_id drop not null;
alter table public.term_renewals add column if not exists own_term_id uuid references public.student_own_terms (id) on delete restrict;
alter table public.term_renewals drop constraint if exists term_renewals_one_term;
alter table public.term_renewals add constraint term_renewals_one_term check ((term_id is null) <> (own_term_id is null));
create unique index if not exists term_renewals_own_once on public.term_renewals (booking_id, own_term_id) where own_term_id is not null;

-- Runs daily. Asks the family about each confirmed booking that ends this
-- study period (or in the holidays after it), 3 weeks before it ends.
create or replace function private.queue_renewals()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  r record;
  p record;
  v_count integer := 0;
  v_id uuid;
begin
  for r in
    select b.id as booking_id, b.student_id, b.tutor_id, b.subject,
           t.school_term_id, t.own_term_id, t.ends_on, s.full_name as student_name
    from public.bookings b
    join public.students s on s.id = b.student_id
    cross join lateral private.student_term_for(b.student_id, b.last_date) t
    where b.status = 'confirmed'
      and b.last_date >= current_date
      and current_date >= t.ends_on - 21
      -- Not already renewed some other way.
      and not exists (
        select 1 from public.bookings n
        where n.renews_booking = b.id and private.booking_is_live(n.status, n.tutor_reply_by)
      )
  loop
    v_id := null;
    if r.school_term_id is not null then
      insert into public.term_renewals (booking_id, student_id, term_id)
      values (r.booking_id, r.student_id, r.school_term_id)
      on conflict (booking_id, term_id) do nothing
      returning id into v_id;
    elsif not exists (
      select 1 from public.term_renewals x where x.booking_id = r.booking_id and x.own_term_id = r.own_term_id
    ) then
      insert into public.term_renewals (booking_id, student_id, own_term_id)
      values (r.booking_id, r.student_id, r.own_term_id)
      returning id into v_id;
    end if;
    if v_id is not null then
      v_count := v_count + 1;
      for p in select * from private.session_people(r.student_id, r.tutor_id) where not is_tutor loop
        perform private.add_notice(p.account_id, null, r.booking_id, 'renewal_due', 'Next term',
          split_part(r.student_name, ' ', 1) || '''s ' || r.subject
          || ' sessions finish with this study period. Would you like the same again next term, or sessions in the holidays? Please answer under Sessions.',
          now());
      end loop;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.queue_renewals() from public;

-- The family's answer. "Same again" sends the tutor a request for the next
-- study period at the same time, place and length.
create or replace function public.answer_renewal(
  p_renewal uuid,
  p_same_again boolean,
  p_holidays boolean,
  p_change_what text default null,
  p_change_reason text default null,
  p_feedback text default null,
  p_testimonial_ok boolean default false
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_r public.term_renewals;
  v_b public.bookings;
  v_this_start date;
  v_next record;
  v_first date;
  v_last date;
  v_new uuid;
begin
  select * into v_r from public.term_renewals where id = p_renewal for update;
  if v_r.id is null or not private.can_book_for(v_r.student_id) then
    raise exception 'Renewal not found' using errcode = 'P0002';
  end if;
  if v_r.answered_at is not null then
    raise exception 'This has already been answered. Please contact CLG to change it.' using errcode = '22023';
  end if;
  if p_same_again is null or p_holidays is null then
    raise exception 'Please answer both questions' using errcode = '22023';
  end if;
  if not p_same_again and p_change_what is null then
    raise exception 'Please say what you would like to change' using errcode = '22023';
  end if;
  if p_change_what is not null and p_change_what not in ('time', 'tutor', 'both') then
    raise exception 'What to change must be time, tutor or both' using errcode = '22023';
  end if;

  select * into v_b from public.bookings where id = v_r.booking_id;

  if p_same_again then
    if private.family_paused(v_b.family_id) then
      raise exception 'This family''s bookings are paused for an overdue payment. CLG will be in touch.' using errcode = '23514';
    end if;
    v_this_start := coalesce(
      (select t.starts_on from public.school_terms t where t.id = v_r.term_id),
      (select o.starts_on from public.student_own_terms o where o.id = v_r.own_term_id));
    select * into v_next from private.student_terms(v_r.student_id) t
    where t.starts_on > v_this_start
    order by t.starts_on limit 1;
    if v_next.starts_on is null then
      raise exception 'CLG doesn''t have the next study period''s dates yet. Please add them under Session places, or contact CLG.' using errcode = '22023';
    end if;
    -- With holidays, sessions carry straight on; without, they start with
    -- the next study period.
    v_first := case when p_holidays then v_b.last_date + 1 else greatest(v_b.last_date + 1, v_next.starts_on) end;
    v_first := v_first + ((v_b.weekday - extract(isodow from v_first)::int + 7) % 7);
    v_last := v_next.ends_on;
    if v_first > v_last then
      raise exception 'This booking already runs into next term' using errcode = '22023';
    end if;
    if exists (
      select 1 from public.bookings o
      where o.id <> v_b.id and private.booking_is_live(o.status, o.tutor_reply_by)
        and (o.tutor_id = v_b.tutor_id or o.student_id = v_b.student_id)
        and o.weekday = v_b.weekday
        and o.first_date <= v_last and o.last_date >= v_first
        and o.start_time < v_b.start_time + make_interval(mins => v_b.minutes)
        and o.start_time + make_interval(mins => o.minutes) > v_b.start_time
    ) then
      raise exception 'That time is no longer available next term. Please choose "something different" and CLG will find another time.' using errcode = '23514';
    end if;

    insert into public.bookings (
      student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, library_id,
      first_date, last_date, family_note, requested_by, skip_holidays, renews_booking
    ) values (
      v_b.student_id, v_b.tutor_id, v_b.family_id, v_b.subject, v_b.weekday, v_b.start_time, v_b.minutes,
      v_b.delivery, v_b.library_id, v_first, v_last,
      'Same again next term' || case when p_holidays then ', with holiday sessions' else '' end || '.',
      auth.uid(), not p_holidays, v_b.id
    )
    returning id into v_new;
  end if;

  update public.term_renewals
  set answered_at = now(), answered_by = auth.uid(),
      same_again = p_same_again, holidays = p_holidays,
      change_what = case when p_same_again then null else p_change_what end,
      change_reason = nullif(left(trim(p_change_reason), 1000), ''),
      feedback = nullif(left(trim(p_feedback), 2000), ''),
      testimonial_ok = coalesce(p_testimonial_ok, false) and nullif(trim(p_feedback), '') is not null,
      next_booking_id = v_new
  where id = p_renewal;
  return v_new;
end;
$$;
revoke all on function public.answer_renewal(uuid, boolean, boolean, text, text, text, boolean) from public, anon;
grant execute on function public.answer_renewal(uuid, boolean, boolean, text, text, text, boolean) to authenticated;

-- For the screens: renewal questions with names, the booking's time, and
-- the student's own last day of the study period.
create or replace function public.list_renewals()
returns table (
  id uuid, booking_id uuid, student_name text, subject text, tutor_name text,
  weekday smallint, start_time time, minutes integer, last_date date,
  term_label text, term_ends_on date, asked_at timestamptz, answered_at timestamptz,
  same_again boolean, holidays boolean, change_what text, change_reason text,
  feedback text, testimonial_ok boolean, next_status public.booking_status
)
language sql stable security definer
set search_path = ''
as $$
  select r.id, r.booking_id, s.full_name, b.subject, a.full_name,
         b.weekday, b.start_time, b.minutes, b.last_date,
         st.label, st.ends_on, r.asked_at, r.answered_at,
         r.same_again, r.holidays, r.change_what, r.change_reason,
         r.feedback, r.testimonial_ok, n.status
  from public.term_renewals r
  join public.bookings b on b.id = r.booking_id
  join public.students s on s.id = r.student_id
  left join lateral (
    select t.label, t.ends_on from private.student_terms(r.student_id) t
    where t.school_term_id is not distinct from r.term_id and t.own_term_id is not distinct from r.own_term_id
    limit 1
  ) st on true
  left join public.accounts a on a.id = b.tutor_id
  left join public.bookings n on n.id = r.next_booking_id
  where private.is_admin() or private.can_book_for(r.student_id)
  order by r.answered_at is not null, st.ends_on, s.full_name
$$;
revoke all on function public.list_renewals() from public, anon;
grant execute on function public.list_renewals() to authenticated;

-- ---------------------------------------------------------------------------
-- Tutors check their availability 4 weeks before every term ends
-- ---------------------------------------------------------------------------
create or replace function private.queue_availability_checks()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  r record;
  v_id uuid;
  v_count integer := 0;
begin
  for r in
    select tp.account_id as tutor_id, t.id as term_id
    from public.tutor_profiles tp
    left join public.tutor_work_settings w on w.tutor_id = tp.account_id
    join public.school_terms t
      on t.state = coalesce(w.work_state, 'SA')
     and t.calendar = 'public'
     and current_date between t.starts_on and t.ends_on
    where tp.active
      and exists (select 1 from public.account_roles ar where ar.account_id = tp.account_id and ar.role = 'tutor')
      and current_date >= t.ends_on - 28
  loop
    insert into public.availability_checks (tutor_id, term_id)
    values (r.tutor_id, r.term_id)
    on conflict (tutor_id, term_id) do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      perform private.add_notice(r.tutor_id, null, null, 'availability_check', 'Your availability for next term',
        'Is your weekly availability right for next term? Families will soon be booking. Please check it, '
        || 'then tap "No changes" or "I''ve updated it" under Sessions.', now());
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.queue_availability_checks() from public;

-- ---------------------------------------------------------------------------
-- Admins: study dates that still need checking
-- ---------------------------------------------------------------------------
-- Students with a booking who:
--   * follow their own dates but have no study period loaded from today on
--   * are school students whose Term 4 last day isn't confirmed, once
--     Term 4 of the current year is within 8 weeks
create or replace function public.list_study_dates_to_check()
returns table (student_id uuid, student_name text, calendar text, problem text)
language sql stable security definer
set search_path = ''
as $$
  with active as (
    select distinct b.student_id
    from public.bookings b
    where b.status in ('confirmed', 'requested') and b.last_date >= current_date
  )
  select s.id, s.full_name, coalesce(sp.calendar, 'public'),
         case
           when coalesce(sp.calendar, 'public') = 'own' then 'No study dates loaded from today on'
           else 'Last day of Term 4 not confirmed'
         end
  from active x
  join public.students s on s.id = x.student_id
  left join public.student_study_periods sp on sp.student_id = s.id
  where private.is_admin()
    and (
      (coalesce(sp.calendar, 'public') = 'own'
        and not exists (select 1 from public.student_own_terms o where o.student_id = s.id and o.ends_on >= current_date))
      or (coalesce(sp.calendar, 'public') <> 'own'
        and coalesce(s.year_level, '') not in ('University or TAFE', 'Adult learner')
        and exists (
          select 1 from public.school_terms t
          where t.state = s.state and t.calendar = 'public' and t.term = 4
            and t.year = extract(year from current_date)::int
            and current_date >= t.starts_on - 56 and current_date <= t.ends_on
        )
        and not exists (
          select 1 from public.student_term_ends e
          where e.student_id = s.id and e.year = extract(year from current_date)::int
        ))
    )
  order by s.full_name
$$;
revoke all on function public.list_study_dates_to_check() from public, anon;
grant execute on function public.list_study_dates_to_check() to authenticated;
