-- Scheduling changes from Carla's 2 Nov 2026 notes (module: scheduling).
--
-- 1. Preferred times of day. Families pick preferred days and parts of the
--    day (morning, midday, afternoon, evening) for each child. They are a
--    preference CLG tries to meet, never a promise.
-- 2. Offer follow-ups at 48 hours. When CLG offers a time and both sides
--    must approve, anyone who hasn't answered after 48 hours gets a
--    reminder, and anyone who has answered is told it is waiting on the
--    other side. The offer then stays open one more day (72 hours in all)
--    before it returns to the Matching tab.
-- 3. Tutor away dates take effect 2 hours after they are entered, so a
--    mistake can be fixed (or removed) before any session is cancelled.
--    The tutor can offer other times while entering them. Each family
--    affected and the admins are then told, politely, and the family can
--    ask for a different time or a different tutor. A family's own away
--    dates still apply straight away.
-- 4. Requests from families (the "Requests" list):
--      * extra      - an extra one-off session before a big event (a test,
--                     an exam), with the event's date
--      * public_holiday - a one-off at another time in a week the child
--                     misses because of a public holiday
--      * away_cover - a different time or tutor when their tutor is away
--    The student's tutor or an admin offers a one-off session (before the
--    event, for extras), and the family approves it as usual.
-- 5. Public holidays. CLG keeps each state's public holidays (SA 2026 to
--    2028 loaded from SafeWork SA). Families see upcoming sessions that
--    fall on one and can choose to skip public holidays for a booking, then
--    ask for a one-off at another time that week.
-- 6. Sessions at home or at school are arranged only by CLG (an admin), in
--    special circumstances.
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- New notice kinds
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'session_notices_kind_check'
      and pg_get_constraintdef(oid) like '%offer_follow_up%'
  ) then
    alter table public.session_notices drop constraint if exists session_notices_kind_check;
    alter table public.session_notices add constraint session_notices_kind_check check (kind in (
      'reminder_first', 'reminder_final',
      'booking_requested', 'booking_confirmed', 'booking_declined',
      'session_cancelled', 'renewal_due', 'availability_check',
      'offer_follow_up', 'tutor_away', 'request_update', 'staff_alert'
    ));
  end if;
end;
$$;

-- Tells CLG's owner and operations admins (each gets an app notice).
create or replace function private.notify_admins(p_title text, p_body text, p_booking uuid default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  a record;
begin
  for a in
    select distinct ar.account_id
    from public.account_roles ar
    left join public.admin_profiles ap on ap.account_id = ar.account_id
    where ar.role = 'admin' and coalesce(ap.level, 'owner') in ('owner', 'operations')
  loop
    perform private.add_notice(a.account_id, null, p_booking, 'staff_alert', p_title, p_body, now());
  end loop;
end;
$$;
revoke all on function private.notify_admins(text, text, uuid) from public;

-- ---------------------------------------------------------------------------
-- 1. Preferred parts of the day
-- ---------------------------------------------------------------------------
alter table public.student_places add column if not exists preferred_parts text[];
alter table public.student_places drop constraint if exists student_places_preferred_parts;
alter table public.student_places add constraint student_places_preferred_parts
  check (preferred_parts is null or preferred_parts <@ array['morning', 'midday', 'afternoon', 'evening']::text[]);

-- Which part of the day a start time is in: morning before 11am, midday
-- 11am to 2pm, afternoon 2pm to 5pm, evening from 5pm.
create or replace function private.part_of_day(p_time time)
returns text language sql immutable
set search_path = ''
as $$
  select case
    when p_time < time '11:00' then 'morning'
    when p_time < time '14:00' then 'midday'
    when p_time < time '17:00' then 'afternoon'
    else 'evening'
  end
$$;

-- Free times with the family's preferred days and parts of the day first.
-- (Older saved preferences, a from/to time or school hours, still count.)
create or replace function public.offer_options(
  p_student uuid,
  p_subject text,
  p_minutes integer,
  p_online boolean,
  p_libraries uuid[] default '{}',
  p_first_date date default null,
  p_weekdays smallint[] default null,
  p_earliest time default null,
  p_latest time default null
)
returns table (
  tutor_id uuid, tutor_name text, weekday smallint, start_time time, end_time time,
  delivery public.session_delivery, library_id uuid, library_name text,
  joins_other_sessions boolean, learning_support boolean, preferred boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_p public.student_places;
begin
  select * into v_p from public.student_places where student_id = p_student;
  return query
    select f.tutor_id, f.tutor_name, f.weekday, f.start_time, f.end_time, f.delivery, f.library_id,
           f.library_name, f.joins_other_sessions, f.learning_support,
           coalesce(
             ((v_p.preferred_days is not null or v_p.preferred_parts is not null
               or v_p.preferred_from is not null or v_p.preferred_to is not null)
              and (v_p.preferred_days is null or f.weekday = any (v_p.preferred_days))
              and (v_p.preferred_parts is null or private.part_of_day(f.start_time) = any (v_p.preferred_parts))
              and (v_p.preferred_from is null or f.start_time >= v_p.preferred_from)
              and (v_p.preferred_to is null or f.end_time <= v_p.preferred_to))
             or (v_p.preferred_school_hours and f.weekday between 1 and 5
                 and f.start_time >= time '09:00' and f.end_time <= time '15:00'),
             false) as preferred
    from public.find_session_times(p_student, p_subject, p_minutes, p_online, p_libraries,
                                   p_first_date, p_weekdays, p_earliest, p_latest)
         with ordinality as f
    order by 11 desc, f.ordinality;
end;
$$;
revoke all on function public.offer_options(uuid, text, integer, boolean, uuid[], date, smallint[], time, time) from public, anon;
grant execute on function public.offer_options(uuid, text, integer, boolean, uuid[], date, smallint[], time, time) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Offers: follow-up at 48 hours, open for 72
-- ---------------------------------------------------------------------------
alter table public.bookings add column if not exists follow_up_sent_at timestamptz;

-- A time CLG offers (both sides approve) stays open 72 hours. Requests a
-- family sends a tutor keep 48.
create or replace function private.offer_reply_window()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.needs_family_ok and new.status = 'requested' then
    new.tutor_reply_by := new.requested_at + interval '72 hours';
  end if;
  return new;
end;
$$;
drop trigger if exists offer_reply_window on public.bookings;
create trigger offer_reply_window before insert on public.bookings
  for each row execute function private.offer_reply_window();

-- Every 15 minutes: offers 48 hours old that both sides haven't approved.
create or replace function private.queue_offer_follow_ups()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  b record;
  p record;
  v_count integer := 0;
  v_what text;
  v_until text;
begin
  for b in
    select x.*, s.full_name as student_name, a.full_name as tutor_name
    from public.bookings x
    join public.students s on s.id = x.student_id
    join public.accounts a on a.id = x.tutor_id
    where x.status = 'requested' and x.needs_family_ok
      and x.follow_up_sent_at is null
      and x.requested_at <= now() - interval '48 hours'
      and x.tutor_reply_by > now()
      and (x.tutor_ok_at is null or x.family_ok_at is null)
    for update of x skip locked
  loop
    v_what := split_part(b.student_name, ' ', 1) || ' (' || b.subject || '), '
      || (array['Mondays','Tuesdays','Wednesdays','Thursdays','Fridays','Saturdays','Sundays'])[b.weekday]
      || ' at ' || lower(trim(to_char(timestamp '2000-01-01' + b.start_time, 'FMHH12:MIam')));
    v_until := private.when_text(b.tutor_reply_by);

    -- The tutor.
    perform private.add_notice(b.tutor_id, null, b.id, 'offer_follow_up',
      case when b.tutor_ok_at is null then 'Reminder: session offer to approve' else 'Waiting for the family' end,
      case when b.tutor_ok_at is null
        then 'CLG offered you ' || v_what || '. Please approve or decline under Sessions by ' || v_until || '.'
        else 'Thanks for approving ' || v_what || '. We''re waiting for the family to approve it too, and will let you know.' end,
      now());
    -- The family.
    for p in select * from private.session_people(b.student_id, b.tutor_id) where not is_tutor loop
      perform private.add_notice(p.account_id, null, b.id, 'offer_follow_up',
        case when b.family_ok_at is null then 'Reminder: session time to approve' else 'Waiting for the tutor' end,
        case when b.family_ok_at is null
          then 'CLG found ' || b.tutor_name || ' for ' || v_what || '. Please approve or decline under Sessions by ' || v_until || '.'
          else 'Thanks for approving ' || v_what || '. We''re waiting for ' || b.tutor_name || ' to approve it too, and will let you know.' end,
        now());
    end loop;
    update public.bookings set follow_up_sent_at = now() where id = b.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.queue_offer_follow_ups() from public;

-- ---------------------------------------------------------------------------
-- 3. Tutor away dates: 2 hours to fix a mistake
-- ---------------------------------------------------------------------------
alter table public.away_dates add column if not exists applies_at timestamptz;
alter table public.away_dates add column if not exists applied_at timestamptz;
-- Other times the tutor can offer instead, shown to the families affected.
alter table public.away_dates add column if not exists tutor_offer text check (char_length(tutor_offer) <= 500);
-- Away dates entered before this change have already been applied.
update public.away_dates set applies_at = created_at, applied_at = created_at where applies_at is null;
alter table public.away_dates alter column applies_at set default now();
alter table public.away_dates alter column applies_at set not null;
create index if not exists away_dates_to_apply on public.away_dates (applies_at) where applied_at is null;

-- Cancels the sessions an away entry covers. Recorded as cancelled when the
-- dates were entered, so early notice still gets the full credit.
create or replace function private.apply_away_entry(p_id uuid)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_a public.away_dates;
  v_count integer;
  v_tutor text;
  f record;
  v_list text;
  v_ids uuid[];
begin
  select * into v_a from public.away_dates where id = p_id for update;
  if v_a.id is null or v_a.applied_at is not null then
    return 0;
  end if;

  with c as (
    update public.sessions x
    set status = 'cancelled', cancelled_at = v_a.created_at, cancelled_by = v_a.created_by,
        cancelled_by_role = case when v_a.tutor_id is not null then 'tutor' else 'family' end,
        cancel_reason = left(case
          when v_a.tutor_id is not null then 'Your tutor isn''t available that day. You can ask for another time or tutor under Sessions > Requests'
          else coalesce('Away: ' || nullif(trim(v_a.reason), ''), 'Away') end, 500)
    from public.students s
    where s.id = x.student_id
      and x.status = 'scheduled'
      and x.starts_at > now()
      and (x.tutor_id = v_a.tutor_id or x.student_id = v_a.student_id)
      and (x.starts_at at time zone private.state_timezone(s.state))::date between v_a.from_date and v_a.to_date
    returning x.id
  )
  select coalesce(array_agg(c.id), '{}') into v_ids from c;
  v_count := cardinality(v_ids);

  update public.away_dates set applied_at = now() where id = p_id;

  -- A tutor's dates: each family affected and CLG's admins hear about it.
  if v_a.tutor_id is not null and v_count > 0 then
    select full_name into v_tutor from public.accounts where id = v_a.tutor_id;
    for f in
      select c.student_id, s.full_name as student_name,
             string_agg(private.when_text(c.starts_at), '; ' order by c.starts_at) as times
      from public.sessions c join public.students s on s.id = c.student_id
      where c.id = any (v_ids)
      group by c.student_id, s.full_name
    loop
      perform private.add_notice(p.account_id, null, null, 'tutor_away', 'Your tutor is away',
        'We''re sorry: ' || v_tutor || ' isn''t available for ' || split_part(f.student_name, ' ', 1) || '''s session'
        || case when position(';' in f.times) > 0 then 's' else '' end || ' (' || f.times || '), so '
        || case when position(';' in f.times) > 0 then 'they are' else 'it is' end || ' cancelled and you won''t be charged.'
        || coalesce(' ' || split_part(v_tutor, ' ', 1) || ' can offer instead: ' || nullif(trim(v_a.tutor_offer), '') || '.', '')
        || ' If you''d like another time or a different tutor, please ask under Sessions > Requests.',
        now())
      from private.session_people(f.student_id, v_a.tutor_id) p
      where not p.is_tutor;
    end loop;
    select string_agg(distinct s.full_name, ', ') into v_list
    from public.sessions c join public.students s on s.id = c.student_id
    where c.id = any (v_ids);
    perform private.notify_admins('Tutor away: ' || coalesce(v_tutor, 'a tutor'),
      coalesce(v_tutor, 'A tutor') || ' is away ' || to_char(v_a.from_date, 'FMDD Mon')
      || case when v_a.to_date <> v_a.from_date then ' to ' || to_char(v_a.to_date, 'FMDD Mon') else '' end
      || '. ' || v_count || ' session' || case when v_count = 1 then ' was' else 's were' end || ' cancelled ('
      || coalesce(v_list, '') || '). Families have been told and can ask for another time or tutor.'
      || coalesce(' Tutor offered: ' || nullif(trim(v_a.tutor_offer), '') || '.', ''));
  end if;
  return v_count;
end;
$$;
revoke all on function private.apply_away_entry(uuid) from public;

-- Every 5 minutes: tutor away dates whose 2 hours are up.
create or replace function private.apply_due_away_dates()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in select id from public.away_dates where applied_at is null and applies_at <= now() order by applies_at loop
    v_count := v_count + private.apply_away_entry(r.id);
  end loop;
  return v_count;
end;
$$;
revoke all on function private.apply_due_away_dates() from public;

-- Old five-argument version: replaced by the one below with the tutor's offer.
drop function if exists public.add_away_dates(uuid, uuid, date, date, text);

-- Add away dates for a tutor (p_student null) or a student (p_tutor null).
-- A family's dates cancel sessions straight away and the function returns
-- how many. A tutor's dates wait 2 hours (returns 0); until then the tutor
-- can remove them, and nothing is cancelled or sent.
create or replace function public.add_away_dates(
  p_tutor uuid,
  p_student uuid,
  p_from date,
  p_to date,
  p_reason text default null,
  p_tutor_offer text default null
)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if (p_tutor is null) = (p_student is null) then
    raise exception 'Choose a tutor or a student' using errcode = '22023';
  end if;
  if p_tutor is not null and not (
    private.is_admin() or (p_tutor = auth.uid() and private.has_role('tutor') and private.has_aal2())
  ) then
    raise exception 'You can only add your own away dates' using errcode = '42501';
  end if;
  if p_student is not null and not private.can_book_for(p_student) then
    raise exception 'You can only add away dates for your own children' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Choose a first and last date, in order' using errcode = '22023';
  end if;
  if p_to < current_date then
    raise exception 'Those dates have passed' using errcode = '22023';
  end if;
  if p_to > p_from + 366 then
    raise exception 'Away dates can cover up to a year' using errcode = '22023';
  end if;

  insert into public.away_dates (tutor_id, student_id, from_date, to_date, reason, tutor_offer, created_by, applies_at)
  values (p_tutor, p_student, greatest(p_from, current_date), p_to, nullif(left(trim(p_reason), 300), ''),
          case when p_tutor is not null then nullif(left(trim(p_tutor_offer), 500), '') end,
          auth.uid(),
          case when p_tutor is not null then now() + interval '2 hours' else now() end)
  returning id into v_id;

  if p_student is not null then
    return private.apply_away_entry(v_id);
  end if;
  return 0;
end;
$$;
revoke all on function public.add_away_dates(uuid, uuid, date, date, text, text) from public, anon;
grant execute on function public.add_away_dates(uuid, uuid, date, date, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Sessions at home or at school: CLG only
-- ---------------------------------------------------------------------------
alter type public.session_delivery add value if not exists 'school';

-- ---------------------------------------------------------------------------
-- 5. Public holidays
-- ---------------------------------------------------------------------------
create table if not exists public.public_holidays (
  id uuid primary key default gen_random_uuid(),
  state public.au_state not null,
  holiday_on date not null,
  name text not null check (char_length(name) between 1 and 100),
  created_at timestamptz not null default now(),
  unique (state, holiday_on)
);
alter table public.public_holidays enable row level security;
revoke all on public.public_holidays from anon;
drop policy if exists "signed in people see public holidays" on public.public_holidays;
create policy "signed in people see public holidays" on public.public_holidays
  for select to authenticated using (true);
drop policy if exists "admins manage public holidays" on public.public_holidays;
create policy "admins manage public holidays" on public.public_holidays
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- South Australian public holidays, from SafeWork SA's "Public Holidays
-- 2025-2028" (checked 2 Nov 2026). Full days only: Christmas Eve and New
-- Year's Eve are only public holidays from 7pm. Existing rows are left
-- alone, so an admin's correction stays.
insert into public.public_holidays (state, holiday_on, name) values
  ('SA', '2026-01-01', 'New Year''s Day'), ('SA', '2026-01-26', 'Australia Day'),
  ('SA', '2026-03-09', 'Adelaide Cup Day'), ('SA', '2026-04-03', 'Good Friday'),
  ('SA', '2026-04-04', 'Easter Saturday'), ('SA', '2026-04-05', 'Easter Sunday'),
  ('SA', '2026-04-06', 'Easter Monday'), ('SA', '2026-04-25', 'ANZAC Day'),
  ('SA', '2026-06-08', 'King''s Birthday'), ('SA', '2026-10-05', 'Labour Day'),
  ('SA', '2026-12-25', 'Christmas Day'), ('SA', '2026-12-26', 'Proclamation Day'),
  ('SA', '2026-12-28', 'Proclamation Day (additional day)'),
  ('SA', '2027-01-01', 'New Year''s Day'), ('SA', '2027-01-26', 'Australia Day'),
  ('SA', '2027-03-08', 'Adelaide Cup Day'), ('SA', '2027-03-26', 'Good Friday'),
  ('SA', '2027-03-27', 'Easter Saturday'), ('SA', '2027-03-28', 'Easter Sunday'),
  ('SA', '2027-03-29', 'Easter Monday'), ('SA', '2027-04-25', 'ANZAC Day'),
  ('SA', '2027-06-14', 'King''s Birthday'), ('SA', '2027-10-04', 'Labour Day'),
  ('SA', '2027-12-25', 'Christmas Day'), ('SA', '2027-12-26', 'Proclamation Day'),
  ('SA', '2027-12-27', 'Christmas Day (additional day)'), ('SA', '2027-12-28', 'Proclamation Day (additional day)'),
  ('SA', '2028-01-01', 'New Year''s Day'), ('SA', '2028-01-03', 'New Year''s Day (additional day)'),
  ('SA', '2028-01-26', 'Australia Day'), ('SA', '2028-03-13', 'Adelaide Cup Day'),
  ('SA', '2028-04-14', 'Good Friday'), ('SA', '2028-04-15', 'Easter Saturday'),
  ('SA', '2028-04-16', 'Easter Sunday'), ('SA', '2028-04-17', 'Easter Monday'),
  ('SA', '2028-04-25', 'ANZAC Day'), ('SA', '2028-06-12', 'King''s Birthday'),
  ('SA', '2028-10-02', 'Labour Day'), ('SA', '2028-12-25', 'Christmas Day'),
  ('SA', '2028-12-26', 'Proclamation Day')
on conflict (state, holiday_on) do nothing;

-- A family can skip public holidays for a booking.
alter table public.bookings add column if not exists skip_public_holidays boolean not null default false;

-- No session is made on a public holiday for a booking that skips them.
create or replace function private.skip_public_holiday_session()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_state public.au_state;
begin
  if new.booking_id is null
     or not exists (select 1 from public.bookings b where b.id = new.booking_id and b.skip_public_holidays) then
    return new;
  end if;
  select s.state into v_state from public.students s where s.id = new.student_id;
  if exists (
    select 1 from public.public_holidays h
    where h.state = v_state and h.holiday_on = (new.starts_at at time zone private.state_timezone(v_state))::date
  ) then
    return null;
  end if;
  return new;
end;
$$;
drop trigger if exists skip_public_holidays on public.sessions;
create trigger skip_public_holidays before insert on public.sessions
  for each row execute function private.skip_public_holiday_session();

-- The family turns public holidays off (or back on) for a booking. Turning
-- them off cancels booked sessions on public holidays, as a family
-- cancellation made now (so early notice gets the full credit).
create or replace function public.set_skip_public_holidays(p_booking uuid, p_skip boolean)
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_b public.bookings;
  v_count integer := 0;
begin
  select * into v_b from public.bookings where id = p_booking for update;
  if v_b.id is null or not private.can_book_for(v_b.student_id) then
    raise exception 'Booking not found' using errcode = 'P0002';
  end if;
  update public.bookings set skip_public_holidays = coalesce(p_skip, false) where id = p_booking;
  if coalesce(p_skip, false) then
    update public.sessions x
    set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
        cancelled_by_role = private.cancel_role(x.student_id, x.tutor_id, case when private.is_admin() then 'family' end),
        cancel_reason = 'Public holiday'
    from public.students s, public.public_holidays h
    where x.booking_id = p_booking and s.id = x.student_id
      and x.status = 'scheduled' and x.starts_at > now()
      and h.state = s.state and h.holiday_on = (x.starts_at at time zone private.state_timezone(s.state))::date;
    get diagnostics v_count = row_count;
  else
    -- Sessions already cancelled stay cancelled; future ones are made again.
    perform private.make_sessions(p_booking);
  end if;
  return v_count;
end;
$$;
revoke all on function public.set_skip_public_holidays(uuid, boolean) from public, anon;
grant execute on function public.set_skip_public_holidays(uuid, boolean) to authenticated;

-- Upcoming sessions (next 120 days) on a public holiday, and weeks a
-- booking that skips public holidays misses one. Families see their own;
-- admins see all.
create or replace function public.list_public_holiday_weeks()
returns table (
  booking_id uuid, student_id uuid, student_name text, subject text, holiday_on date, holiday_name text,
  skipping boolean, session_id uuid
)
language sql stable security definer
set search_path = ''
as $$
  select b.id, b.student_id, s.full_name, b.subject, h.holiday_on, h.name, b.skip_public_holidays,
         (select x.id from public.sessions x
          where x.booking_id = b.id and x.status = 'scheduled'
            and (x.starts_at at time zone private.state_timezone(s.state))::date = h.holiday_on
          limit 1)
  from public.bookings b
  join public.students s on s.id = b.student_id
  join public.public_holidays h
    on h.state = s.state
   and h.holiday_on between greatest(b.first_date, current_date) and least(b.last_date, current_date + 120)
   and extract(isodow from h.holiday_on)::int = b.weekday
  where b.status = 'confirmed'
    and (private.is_admin() or private.can_book_for(b.student_id))
  order by h.holiday_on, s.full_name
$$;
revoke all on function public.list_public_holiday_weeks() from public, anon;
grant execute on function public.list_public_holiday_weeks() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Requests: extra sessions, public holiday one-offs, cover when away
-- ---------------------------------------------------------------------------
create table if not exists public.session_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  kind text not null check (kind in ('extra', 'public_holiday', 'away_cover')),
  subject text not null check (char_length(subject) between 1 and 100),
  -- The tutor the student has for that subject, if any.
  tutor_id uuid references public.tutor_profiles (account_id) on delete set null,
  -- extra: the date of the test or event. public_holiday: the holiday.
  -- away_cover: the date of the cancelled session.
  event_on date,
  event_label text check (char_length(event_label) <= 200),
  -- away_cover: a different time, a different tutor, or either.
  wants text check (wants in ('time', 'tutor', 'either')),
  note text check (char_length(note) <= 1000),
  status text not null default 'open' check (status in ('open', 'offered', 'done', 'declined', 'withdrawn')),
  offered_booking_id uuid references public.bookings (id) on delete set null,
  staff_note text check (char_length(staff_note) <= 1000),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check (kind <> 'extra' or event_on is not null)
);
create index if not exists session_requests_open on public.session_requests (created_at) where status in ('open', 'offered');
create index if not exists session_requests_student on public.session_requests (student_id);

alter table public.session_requests enable row level security;
revoke all on public.session_requests from anon;
revoke insert, update, delete, truncate on public.session_requests from authenticated;
drop trigger if exists audit on public.session_requests;
create trigger audit after insert or update or delete on public.session_requests
  for each row execute function private.audit_change();

-- The family, the student's tutor for that request (so they can offer a
-- time), and admins.
drop policy if exists "see session requests" on public.session_requests;
create policy "see session requests" on public.session_requests
  for select to authenticated using (
    private.is_admin()
    or private.can_book_for(student_id)
    or (tutor_id = auth.uid() and private.is_tutor_of(student_id))
  );

-- The family asks. Returns the request's id.
create or replace function public.make_session_request(
  p_student uuid,
  p_kind text,
  p_subject text,
  p_event_on date default null,
  p_event_label text default null,
  p_wants text default null,
  p_note text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_tutor uuid;
  v_id uuid;
  v_student text;
begin
  if not private.can_book_for(p_student) then
    raise exception 'You can only ask for your own children' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('extra', 'public_holiday', 'away_cover') then
    raise exception 'Choose what the request is for' using errcode = '22023';
  end if;
  if nullif(trim(p_subject), '') is null then
    raise exception 'Choose the subject' using errcode = '22023';
  end if;
  if p_kind = 'extra' and (p_event_on is null or p_event_on <= current_date) then
    raise exception 'Give the date of the test or event (in the future)' using errcode = '22023';
  end if;
  if p_wants is not null and p_wants not in ('time', 'tutor', 'either') then
    raise exception 'Choose a different time, a different tutor, or either' using errcode = '22023';
  end if;
  select a.tutor_id into v_tutor
  from public.tutor_assignments a
  where a.student_id = p_student and lower(a.subject) = lower(trim(p_subject))
    and private.assignment_is_current(a.starts_on, a.ends_on)
  order by a.starts_on desc limit 1;

  insert into public.session_requests (student_id, kind, subject, tutor_id, event_on, event_label, wants, note, created_by)
  values (p_student, p_kind, trim(p_subject), v_tutor, p_event_on, nullif(left(trim(p_event_label), 200), ''),
          case when p_kind = 'away_cover' then coalesce(p_wants, 'either') end,
          nullif(left(trim(p_note), 1000), ''), auth.uid())
  returning id into v_id;

  select full_name into v_student from public.students where id = p_student;
  perform private.notify_admins(
    case p_kind when 'extra' then 'Extra session asked for' when 'public_holiday' then 'Public holiday one-off asked for'
                else 'Cover asked for (tutor away)' end,
    v_student || ', ' || trim(p_subject)
    || coalesce(case when p_kind = 'extra' then ': ' || coalesce(nullif(trim(p_event_label), ''), 'event') || ' on ' || to_char(p_event_on, 'FMDD Mon') end, '')
    || '. See Schedule > Requests.');
  if v_tutor is not null and p_kind in ('extra', 'public_holiday') then
    perform private.add_notice(v_tutor, null, null, 'request_update',
      case when p_kind = 'extra' then 'Extra session asked for' else 'One-off session asked for' end,
      split_part(v_student, ' ', 1) || '''s family would like '
      || case when p_kind = 'extra'
              then 'an extra ' || trim(p_subject) || ' session before ' || coalesce(nullif(trim(p_event_label), ''), 'an event')
                   || ' on ' || to_char(p_event_on, 'FMDD Mon')
              else 'a one-off ' || trim(p_subject) || ' session at another time in a public holiday week' end
      || '. If you can, offer a time under Sessions > Requests.', now());
  end if;
  return v_id;
end;
$$;
revoke all on function public.make_session_request(uuid, text, text, date, text, text, text) from public, anon;
grant execute on function public.make_session_request(uuid, text, text, date, text, text, text) to authenticated;

-- The family withdraws, or an admin closes (done or declined, with a note
-- the family sees).
create or replace function public.close_session_request(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_r public.session_requests;
  p record;
begin
  select * into v_r from public.session_requests where id = p_id for update;
  if v_r.id is null or not (private.is_admin() or private.can_book_for(v_r.student_id)) then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if p_status = 'withdrawn' then
    if not private.can_book_for(v_r.student_id) then
      raise exception 'Only the family can withdraw a request' using errcode = '42501';
    end if;
  elsif p_status in ('done', 'declined') then
    if not private.is_admin() then
      raise exception 'Only CLG can close a request' using errcode = '42501';
    end if;
  else
    raise exception 'Choose done, declined or withdrawn' using errcode = '22023';
  end if;
  update public.session_requests
  set status = p_status, closed_at = now(), staff_note = coalesce(nullif(left(trim(p_note), 1000), ''), staff_note)
  where id = p_id;
  if p_status = 'declined' then
    for p in select * from private.session_people(v_r.student_id, v_r.tutor_id) where not is_tutor loop
      perform private.add_notice(p.account_id, null, null, 'request_update', 'About your request',
        'Sorry, we couldn''t find a time for the ' || v_r.subject || ' session you asked for.'
        || coalesce(' ' || nullif(trim(p_note), ''), ''), now());
    end loop;
  end if;
end;
$$;
revoke all on function public.close_session_request(uuid, text, text) from public, anon;
grant execute on function public.close_session_request(uuid, text, text) to authenticated;

-- The student's tutor or an admin offers a one-off session for a request.
-- It is a booking with one session, which the family approves as usual (and
-- the tutor too, if an admin offers it with another tutor). An extra
-- session must come before the event.
create or replace function public.offer_one_off(
  p_request uuid,
  p_tutor uuid,
  p_date date,
  p_start time,
  p_minutes integer,
  p_delivery public.session_delivery,
  p_library uuid default null,
  p_note text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_r public.session_requests;
  v_student public.students;
  v_tutor uuid := coalesce(p_tutor, auth.uid());
  v_by_tutor boolean;
  v_weekday smallint;
  v_id uuid;
begin
  select * into v_r from public.session_requests where id = p_request for update;
  if v_r.id is null then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  v_by_tutor := not private.is_admin();
  if v_by_tutor and not (
    v_r.tutor_id = auth.uid() and v_tutor = auth.uid()
    and private.has_role('tutor') and private.has_aal2() and private.is_tutor_of(v_r.student_id)
  ) then
    raise exception 'Only the student''s tutor or CLG can offer a time' using errcode = '42501';
  end if;
  if v_r.status not in ('open', 'offered') then
    raise exception 'This request is closed' using errcode = '22023';
  end if;
  if p_date is null or p_date <= current_date then
    raise exception 'Choose a date from tomorrow on' using errcode = '22023';
  end if;
  if v_r.kind = 'extra' and p_date >= v_r.event_on then
    raise exception 'An extra session needs to be before the event (%)', to_char(v_r.event_on, 'FMDD Mon') using errcode = '22023';
  end if;
  if p_minutes is null or p_minutes < 60 or p_minutes > 240 or p_minutes % 30 <> 0 then
    raise exception 'Sessions are 1 to 4 hours, in half-hour steps' using errcode = '22023';
  end if;
  if p_delivery in ('home', 'school') and v_by_tutor then
    raise exception 'Sessions at home or at school are arranged by CLG only' using errcode = '42501';
  end if;
  if (p_delivery = 'library') <> (p_library is not null) then
    raise exception 'Choose a library for a library session (and only then)' using errcode = '22023';
  end if;

  select * into v_student from public.students where id = v_r.student_id;
  if private.family_paused(v_student.family_id) then
    raise exception 'This family''s bookings are paused for an overdue payment.' using errcode = '23514';
  end if;
  if not (private.tutor_cleared_for_student(v_tutor, v_r.student_id)
          and private.tutor_teaches(v_tutor, v_r.subject, private.matching_level(v_r.student_id, v_r.subject))) then
    raise exception 'This tutor can''t take this student for %', v_r.subject using errcode = '23514';
  end if;
  if private.blocked_pair(v_tutor, v_r.student_id) then
    raise exception 'This tutor can''t be matched with this student. Please choose another.' using errcode = '23514';
  end if;
  if exists (select 1 from public.away_dates a
             where (a.tutor_id = v_tutor or a.student_id = v_r.student_id) and p_date between a.from_date and a.to_date) then
    raise exception 'The tutor or student is away that day' using errcode = '23514';
  end if;
  if p_delivery = 'library' and not private.library_open(p_library, p_date, p_start, p_minutes) then
    raise exception 'The library isn''t open then. Please choose a time inside its opening hours.' using errcode = '23514';
  end if;

  v_weekday := extract(isodow from p_date)::smallint;
  -- No clash with the tutor's or student's other sessions that day.
  if exists (
    select 1 from public.sessions x
    where (x.tutor_id = v_tutor or x.student_id = v_r.student_id)
      and x.status = 'scheduled'
      and x.starts_at < ((p_date + p_start + make_interval(mins => p_minutes)) at time zone private.state_timezone(v_student.state))
      and x.ends_at > ((p_date + p_start) at time zone private.state_timezone(v_student.state))
  ) or exists (
    select 1 from public.bookings o
    where private.booking_is_live(o.status, o.tutor_reply_by) and o.status = 'requested'
      and (o.tutor_id = v_tutor or o.student_id = v_r.student_id)
      and o.weekday = v_weekday and p_date between o.first_date and o.last_date
      and o.start_time < p_start + make_interval(mins => p_minutes)
      and o.start_time + make_interval(mins => o.minutes) > p_start
  ) then
    raise exception 'That time clashes with another session' using errcode = '23514';
  end if;

  insert into public.bookings (
    student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, library_id,
    first_date, last_date, family_note, requested_by, needs_family_ok, tutor_ok_at
  ) values (
    v_r.student_id, v_tutor, v_student.family_id, v_r.subject, v_weekday, p_start, p_minutes,
    p_delivery, p_library, p_date, p_date,
    left(case v_r.kind when 'extra' then 'Extra session before ' || coalesce(v_r.event_label, 'an event')
                       when 'public_holiday' then 'One-off session for a public holiday week'
                       else 'One-off session while the usual tutor is away' end
         || coalesce('. ' || nullif(trim(p_note), ''), '') || '.', 1000),
    auth.uid(), true,
    -- A tutor offering their own time has already said yes.
    case when v_by_tutor then now() end
  )
  returning id into v_id;

  update public.session_requests set status = 'offered', offered_booking_id = v_id where id = p_request;
  return v_id;
end;
$$;
revoke all on function public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text) from public, anon;
grant execute on function public.offer_one_off(uuid, uuid, date, time, integer, public.session_delivery, uuid, text) to authenticated;

-- A request is done once its one-off booking is confirmed.
create or replace function private.close_request_on_confirm()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if old.status = 'requested' and new.status = 'confirmed' then
    update public.session_requests set status = 'done', closed_at = now()
    where offered_booking_id = new.id and status = 'offered';
  elsif old.status = 'requested' and new.status = 'declined' then
    update public.session_requests set status = 'open'
    where offered_booking_id = new.id and status = 'offered';
  end if;
  return new;
end;
$$;
drop trigger if exists close_request on public.bookings;
create trigger close_request after update of status on public.bookings
  for each row execute function private.close_request_on_confirm();

-- For the screens: requests with names. Families see their own; tutors
-- the ones for their students; admins all. Open ones first, oldest first.
create or replace function public.list_session_requests()
returns table (
  id uuid, student_id uuid, student_name text, kind text, subject text, tutor_id uuid, tutor_name text,
  event_on date, event_label text, wants text, note text, status text, staff_note text,
  created_at timestamptz, offered_booking_id uuid, offered_status public.booking_status
)
language sql stable security definer
set search_path = ''
as $$
  select r.id, r.student_id, s.full_name, r.kind, r.subject, r.tutor_id, a.full_name,
         r.event_on, r.event_label, r.wants, r.note, r.status, r.staff_note,
         r.created_at, r.offered_booking_id, b.status
  from public.session_requests r
  join public.students s on s.id = r.student_id
  left join public.accounts a on a.id = r.tutor_id
  left join public.bookings b on b.id = r.offered_booking_id
  where private.is_admin()
     or private.can_book_for(r.student_id)
     or (r.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2() and private.is_tutor_of(r.student_id))
  order by r.status not in ('open', 'offered'), r.created_at
$$;
revoke all on function public.list_session_requests() from public, anon;
grant execute on function public.list_session_requests() to authenticated;

-- ---------------------------------------------------------------------------
-- Jobs
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-offer-follow-ups', '*/15 * * * *', 'select private.queue_offer_follow_ups()')
    $job$;
    execute $job$
      select cron.schedule('clg-apply-away-dates', '*/5 * * * *', 'select private.apply_due_away_dates()')
    $job$;
  end if;
end;
$$;
