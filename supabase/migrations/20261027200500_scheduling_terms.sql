-- Scheduling part 5 (module: scheduling): school terms and renewing each term.
--
-- * School term dates per state. South Australian government school dates
--   for 2026 to 2028 are added below (from education.sa.gov.au); admins can
--   add or correct terms.
-- * Two weeks before a term ends (four weeks before the end of terms 1 and
--   3, when sport seasons change), the family is asked about each booking
--   that ends this term:
--     - do they want sessions in the school holidays?
--     - do they want the same time and tutor next term?
--     - if not, what would they change (day and time, tutor, or both) and why
--     - any feedback, with a separate tick to let CLG use it as a testimonial
-- * "Same again" sends the tutor a request for next term at the same time.
--   The tutor accepts it like any other booking (48 hr), so the usual checks
--   run again (child safety checks still valid, no clash).
-- * A booking can skip the school holidays: no sessions are made on dates
--   between terms.
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- School terms
-- ---------------------------------------------------------------------------
create table if not exists public.school_terms (
  id uuid primary key default gen_random_uuid(),
  state public.au_state not null,
  year integer not null check (year between 2020 and 2100),
  term smallint not null check (term between 1 and 4),
  starts_on date not null,
  ends_on date not null,
  created_at timestamptz not null default now(),
  unique (state, year, term),
  check (ends_on > starts_on and extract(year from starts_on) = year)
);
alter table public.school_terms enable row level security;
revoke all on public.school_terms from anon;

drop policy if exists "signed in people see terms" on public.school_terms;
create policy "signed in people see terms" on public.school_terms
  for select to authenticated using (true);
drop policy if exists "admins manage terms" on public.school_terms;
create policy "admins manage terms" on public.school_terms
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- South Australian government school terms (education.sa.gov.au, checked
-- 28 Oct 2026). Existing rows are left alone, so an admin's correction stays.
insert into public.school_terms (state, year, term, starts_on, ends_on) values
  ('SA', 2026, 1, '2026-01-27', '2026-04-10'),
  ('SA', 2026, 2, '2026-04-27', '2026-07-03'),
  ('SA', 2026, 3, '2026-07-20', '2026-09-25'),
  ('SA', 2026, 4, '2026-10-12', '2026-12-11'),
  ('SA', 2027, 1, '2027-01-27', '2027-04-09'),
  ('SA', 2027, 2, '2027-04-26', '2027-07-02'),
  ('SA', 2027, 3, '2027-07-19', '2027-09-24'),
  ('SA', 2027, 4, '2027-10-11', '2027-12-10'),
  ('SA', 2028, 1, '2028-01-31', '2028-04-13'),
  ('SA', 2028, 2, '2028-05-01', '2028-07-07'),
  ('SA', 2028, 3, '2028-07-24', '2028-09-29'),
  ('SA', 2028, 4, '2028-10-16', '2028-12-15')
on conflict (state, year, term) do nothing;

-- Is this date in the school holidays for the state? Only when CLG has that
-- year's terms; otherwise we can't tell, and the answer is no.
create or replace function private.in_school_holidays(p_state public.au_state, p_date date)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.school_terms t
      where t.state = p_state and t.year = extract(year from p_date)::int
    )
    and not exists (
      select 1 from public.school_terms t
      where t.state = p_state and p_date between t.starts_on and t.ends_on
    )
$$;

-- ---------------------------------------------------------------------------
-- Bookings: skipping holidays, and which booking a renewal continues
-- ---------------------------------------------------------------------------
alter table public.bookings add column if not exists skip_holidays boolean not null default false;
alter table public.bookings add column if not exists renews_booking uuid references public.bookings (id) on delete set null;

-- No session is made in the holidays for a booking that skips them.
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
  if private.in_school_holidays(v_state, (new.starts_at at time zone private.state_timezone(v_state))::date) then
    return null;
  end if;
  return new;
end;
$$;
drop trigger if exists skip_holidays on public.sessions;
create trigger skip_holidays before insert on public.sessions
  for each row execute function private.skip_holiday_session();

-- ---------------------------------------------------------------------------
-- Renewal questions
-- ---------------------------------------------------------------------------
create table if not exists public.term_renewals (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  -- A term with renewal answers can't be deleted; correct its dates instead.
  term_id uuid not null references public.school_terms (id) on delete restrict,
  asked_at timestamptz not null default now(),
  answered_at timestamptz,
  answered_by uuid references public.accounts (id) on delete set null,
  holidays boolean,
  same_again boolean,
  change_what text check (change_what in ('time', 'tutor', 'both')),
  change_reason text check (char_length(change_reason) <= 1000),
  feedback text check (char_length(feedback) <= 2000),
  -- A separate, clear yes before CLG quotes the feedback anywhere.
  testimonial_ok boolean not null default false,
  -- The request sent to the tutor for next term, if they chose "same again".
  next_booking_id uuid references public.bookings (id) on delete set null,
  unique (booking_id, term_id)
);
create index if not exists term_renewals_student on public.term_renewals (student_id);

alter table public.term_renewals enable row level security;
revoke all on public.term_renewals from anon;
revoke insert, update, delete, truncate on public.term_renewals from authenticated;

-- The family and CLG. Tutors don't see it: families can say why they want a
-- change of tutor.
drop policy if exists "family and admins see renewals" on public.term_renewals;
create policy "family and admins see renewals" on public.term_renewals
  for select to authenticated using (private.is_admin() or private.can_book_for(student_id));

-- Two new notice kinds: the renewal question, for the family.
-- Only widened when this kind isn't allowed yet, so running this file again
-- never narrows a list a later file has widened.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'session_notices_kind_check'
      and pg_get_constraintdef(oid) like '%renewal_due%'
  ) then
    alter table public.session_notices drop constraint if exists session_notices_kind_check;
    alter table public.session_notices add constraint session_notices_kind_check check (kind in (
      'reminder_first', 'reminder_final',
      'booking_requested', 'booking_confirmed', 'booking_declined',
      'session_cancelled', 'renewal_due'
    ));
  end if;
end;
$$;

-- The term a date falls in, or the term just before it (if it is in the
-- holidays).
create or replace function private.term_for(p_state public.au_state, p_date date)
returns public.school_terms language sql stable security definer
set search_path = ''
as $$
  select t.* from public.school_terms t
  where t.state = p_state and t.starts_on <= p_date
  order by t.starts_on desc limit 1
$$;

-- Runs daily. Asks the family about each confirmed booking that ends this
-- term (or in the holidays after it), once the question is due.
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
    select b.id as booking_id, b.student_id, b.tutor_id, b.subject, t.id as term_id, t.term, t.ends_on,
           s.full_name as student_name
    from public.bookings b
    join public.students s on s.id = b.student_id
    cross join lateral private.term_for(s.state, b.last_date) t
    where b.status = 'confirmed'
      and b.last_date >= current_date
      and t.id is not null
      -- From 2 weeks before the term ends (4 weeks for terms 1 and 3).
      and current_date >= t.ends_on - case when t.term in (1, 3) then 28 else 14 end
      -- Not already renewed some other way.
      and not exists (
        select 1 from public.bookings n
        where n.renews_booking = b.id and private.booking_is_live(n.status, n.tutor_reply_by)
      )
  loop
    insert into public.term_renewals (booking_id, student_id, term_id)
    values (r.booking_id, r.student_id, r.term_id)
    on conflict (booking_id, term_id) do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      for p in select * from private.session_people(r.student_id, r.tutor_id) where not is_tutor loop
        perform private.add_notice(p.account_id, null, r.booking_id, 'renewal_due', 'Next term',
          split_part(r.student_name, ' ', 1) || '''s ' || r.subject
          || ' sessions finish with the term. Would you like the same again next term, or sessions in the holidays? Please answer under Sessions.',
          now());
      end loop;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.queue_renewals() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    -- 9:30am Adelaide (23:00 UTC; 30 minutes later in daylight saving).
    execute $job$
      select cron.schedule('clg-queue-renewals', '0 23 * * *', 'select private.queue_renewals()')
    $job$;
  end if;
end;
$$;

-- The family's answer. "Same again" sends the tutor a request for next term
-- at the same time, place and length.
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
  v_state public.au_state;
  v_this public.school_terms;
  v_next public.school_terms;
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
    select s.state into v_state from public.students s where s.id = v_r.student_id;
    select * into v_this from public.school_terms where id = v_r.term_id;
    select * into v_next from public.school_terms t
    where t.state = v_state and t.starts_on > v_this.starts_on
    order by t.starts_on limit 1;
    if v_next.id is null then
      raise exception 'CLG hasn''t added next term''s dates yet. Please contact CLG.' using errcode = '22023';
    end if;
    -- With holidays, sessions carry straight on; without, they start with
    -- next term.
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
      raise exception 'That time is no longer free next term. Please choose "something different" and CLG will find another time.' using errcode = '23514';
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

-- For the screens: renewal questions with names and the booking's time.
-- Families see their own; admins see all.
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
         'Term ' || t.term || ' ' || t.year, t.ends_on, r.asked_at, r.answered_at,
         r.same_again, r.holidays, r.change_what, r.change_reason,
         r.feedback, r.testimonial_ok, n.status
  from public.term_renewals r
  join public.bookings b on b.id = r.booking_id
  join public.students s on s.id = r.student_id
  join public.school_terms t on t.id = r.term_id
  left join public.accounts a on a.id = b.tutor_id
  left join public.bookings n on n.id = r.next_booking_id
  where private.is_admin() or private.can_book_for(r.student_id)
  order by r.answered_at is not null, t.ends_on, s.full_name
$$;
revoke all on function public.list_renewals() from public, anon;
grant execute on function public.list_renewals() to authenticated;
