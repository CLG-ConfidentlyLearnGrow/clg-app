-- Scheduling part 4 (module: scheduling): reminders and notices.
--
-- Everyone involved in a session (the tutor, the student's parents, and
-- the student if they have their own login) gets:
--   * a first reminder before each session (48 hr by default; each person
--     can change it), then a final reminder 1 hr before
--   * a notice when a booking is requested, confirmed or declined, and when
--     a session is cancelled
-- Nothing is delivered between 8pm and 8am Adelaide time: it waits until
-- 8am. A final reminder that would land in those hours, or after the
-- session starts, goes at 7:30pm the evening before instead.
--
-- Notices show in the app. Email and text sending read the same rows
-- (email_sent_at, sms_sent_at) and come in a later step, once CLG's email
-- sending and text provider are set up.
--
-- See docs/features/scheduling.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Each person's settings
-- ---------------------------------------------------------------------------
create table if not exists public.notice_settings (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  first_reminder_hours integer not null default 48 check (first_reminder_hours between 2 and 168),
  by_email boolean not null default true,
  by_text boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.notice_settings enable row level security;
revoke all on public.notice_settings from anon;
drop trigger if exists touch on public.notice_settings;
create trigger touch before update on public.notice_settings
  for each row execute function private.touch_updated_at();

drop policy if exists "own notice settings" on public.notice_settings;
create policy "own notice settings" on public.notice_settings
  for all to authenticated
  using (account_id = auth.uid() or private.is_admin())
  with check (account_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Notices
-- ---------------------------------------------------------------------------
create table if not exists public.session_notices (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  session_id uuid references public.sessions (id) on delete cascade,
  booking_id uuid references public.bookings (id) on delete cascade,
  kind text not null check (kind in (
    'reminder_first', 'reminder_final',
    'booking_requested', 'booking_confirmed', 'booking_declined',
    'session_cancelled'
  )),
  title text not null check (char_length(title) <= 200),
  body text not null check (char_length(body) <= 1000),
  deliver_at timestamptz not null,
  read_at timestamptz,
  email_sent_at timestamptz,
  sms_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists session_notices_account on public.session_notices (account_id, deliver_at desc);
-- Each reminder once per person per session.
create unique index if not exists session_notices_reminder_once
  on public.session_notices (account_id, session_id, kind)
  where kind in ('reminder_first', 'reminder_final');

alter table public.session_notices enable row level security;
revoke all on public.session_notices from anon;
revoke insert, update, delete, truncate on public.session_notices from authenticated;

drop policy if exists "own delivered notices" on public.session_notices;
create policy "own delivered notices" on public.session_notices
  for select to authenticated using (account_id = auth.uid() and deliver_at <= now());

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Moves a time out of quiet hours (8pm to 8am Adelaide time) to 8am.
create or replace function private.outside_quiet_hours(p_at timestamptz)
returns timestamptz language sql stable
set search_path = ''
as $$
  with l as (select (p_at at time zone 'Australia/Adelaide') as t)
  select case
    when t::time >= time '20:00' then ((t::date + 1) + time '08:00') at time zone 'Australia/Adelaide'
    when t::time < time '08:00' then (t::date + time '08:00') at time zone 'Australia/Adelaide'
    else p_at
  end
  from l
$$;

-- Everyone who hears about a student's session: the tutor, the student's
-- parents, and the student's own login if they have one.
create or replace function private.session_people(p_student uuid, p_tutor uuid)
returns table (account_id uuid, is_tutor boolean)
language sql stable security definer
set search_path = ''
as $$
  select p_tutor, true
  union
  select l.parent_id, false from public.parent_student_links l where l.student_id = p_student
  union
  select s.account_id, false from public.students s where s.id = p_student and s.account_id is not null
$$;

-- "Mon 3 Nov, 4:00pm" in Adelaide time.
create or replace function private.when_text(p_at timestamptz)
returns text language sql stable
set search_path = ''
as $$
  select trim(to_char(p_at at time zone 'Australia/Adelaide', 'Dy FMDD Mon, FMHH12:MI'))
      || lower(to_char(p_at at time zone 'Australia/Adelaide', 'am'))
$$;

create or replace function private.add_notice(
  p_account uuid, p_session uuid, p_booking uuid, p_kind text, p_title text, p_body text, p_at timestamptz
)
returns void language sql security definer
set search_path = ''
as $$
  insert into public.session_notices (account_id, session_id, booking_id, kind, title, body, deliver_at)
  values (p_account, p_session, p_booking, p_kind, left(p_title, 200), left(p_body, 1000), private.outside_quiet_hours(p_at))
  on conflict do nothing
$$;

-- ---------------------------------------------------------------------------
-- Reminders: queued every 15 minutes for sessions in the next 8 days
-- ---------------------------------------------------------------------------
create or replace function private.queue_reminders()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  -- Reminders for sessions that were cancelled are withdrawn if not yet due.
  delete from public.session_notices n
  using public.sessions x
  where x.id = n.session_id
    and n.kind in ('reminder_first', 'reminder_final')
    and n.deliver_at > now()
    and x.status <> 'scheduled';

  with upcoming as (
    select x.id, x.student_id, x.tutor_id, x.subject, x.starts_at, x.delivery,
           st.full_name as student_name, tu.full_name as tutor_name, l.name as library_name
    from public.sessions x
    join public.students st on st.id = x.student_id
    join public.accounts tu on tu.id = x.tutor_id
    left join public.libraries l on l.id = x.library_id
    where x.status = 'scheduled'
      and x.starts_at > now()
      and x.starts_at <= now() + interval '8 days'
  ),
  wanted as (
    select u.*, p.account_id, p.is_tutor,
           coalesce(ns.first_reminder_hours, 48) as hours
    from upcoming u
    cross join lateral private.session_people(u.student_id, u.tutor_id) p
    left join public.notice_settings ns on ns.account_id = p.account_id
  ),
  rows as (
    select w.account_id, w.id as session_id, 'reminder_first' as kind,
           w.starts_at - make_interval(hours => w.hours) as at, w
    from wanted w
    -- Skip the first reminder when it would be within 2 hr of the final one.
    where w.hours > 3
    union all
    select w.account_id, w.id, 'reminder_final',
           w.starts_at - interval '1 hour', w
    from wanted w
  )
  insert into public.session_notices (account_id, session_id, kind, title, body, deliver_at)
  select r.account_id, r.session_id, r.kind,
         case when r.kind = 'reminder_final' then 'Session in 1 hour' else 'Upcoming session' end,
         left(
           case when (r.w).is_tutor
                then (r.w).subject || ' with ' || (r.w).student_name
                else (r.w).student_name || ': ' || (r.w).subject || ' with ' || (r.w).tutor_name end
           || ', ' || private.when_text((r.w).starts_at) || ', '
           || case (r.w).delivery when 'online' then 'online' when 'home' then 'at home'
                   else coalesce((r.w).library_name, 'library') end
           || '.', 1000),
         -- Quiet hours apply; a final reminder that would then land after
         -- the start goes at 7:30pm the evening before.
         case
           when r.kind = 'reminder_final'
                and private.outside_quiet_hours(r.at) > (r.w).starts_at - interval '15 minutes'
           then ((((r.w).starts_at at time zone 'Australia/Adelaide')::date - 1) + time '19:30') at time zone 'Australia/Adelaide'
           else private.outside_quiet_hours(greatest(r.at, now()))
         end
  from rows r
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.queue_reminders() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-queue-reminders', '*/15 * * * *', 'select private.queue_reminders()')
    $job$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Notices when bookings and sessions change
-- ---------------------------------------------------------------------------
create or replace function private.notice_on_booking()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_student text;
  v_tutor text;
  v_when text;
  p record;
begin
  select full_name into v_student from public.students where id = new.student_id;
  select full_name into v_tutor from public.accounts where id = new.tutor_id;
  v_when := (array['Mondays','Tuesdays','Wednesdays','Thursdays','Fridays','Saturdays','Sundays'])[new.weekday]
            || ' at ' || lower(trim(to_char(timestamp '2000-01-01' + new.start_time, 'FMHH12:MIam')));

  if tg_op = 'INSERT' and new.status = 'requested' then
    perform private.add_notice(new.tutor_id, null, new.id, 'booking_requested', 'New booking request',
      split_part(v_student, ' ', 1) || ' (' || new.subject || '), ' || v_when
      || '. Please accept or decline within 48 hours.', now());
  elsif tg_op = 'UPDATE' and old.status = 'requested' and new.status in ('confirmed', 'declined') then
    for p in select * from private.session_people(new.student_id, new.tutor_id) where not is_tutor loop
      perform private.add_notice(p.account_id, null, new.id,
        case when new.status = 'confirmed' then 'booking_confirmed' else 'booking_declined' end,
        case when new.status = 'confirmed' then 'Booking confirmed' else 'Booking declined' end,
        case when new.status = 'confirmed'
             then v_tutor || ' confirmed ' || new.subject || ' for ' || v_student || ', ' || v_when || '.'
             else v_tutor || ' can''t take ' || new.subject || ' for ' || v_student || ', ' || v_when
                  || '. Please choose another time, or CLG will be in touch.' end,
        now());
    end loop;
  end if;
  return new;
end;
$$;
drop trigger if exists notices on public.bookings;
create trigger notices after insert or update of status on public.bookings
  for each row execute function private.notice_on_booking();

-- When a future session is cancelled, everyone else involved hears about it.
create or replace function private.notice_on_cancel()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_student text;
  v_tutor text;
  p record;
begin
  if not (old.status = 'scheduled' and new.status = 'cancelled' and new.starts_at > now()) then
    return new;
  end if;
  select full_name into v_student from public.students where id = new.student_id;
  select full_name into v_tutor from public.accounts where id = new.tutor_id;
  for p in
    select * from private.session_people(new.student_id, new.tutor_id)
    where account_id is distinct from new.cancelled_by
  loop
    perform private.add_notice(p.account_id, new.id, new.booking_id, 'session_cancelled', 'Session cancelled',
      v_student || ': ' || new.subject || ' with ' || v_tutor || ', ' || private.when_text(new.starts_at)
      || ', is cancelled' || coalesce(' (' || new.cancel_reason || ')', '') || '.',
      now());
  end loop;
  return new;
end;
$$;
drop trigger if exists notices on public.sessions;
create trigger notices after update of status on public.sessions
  for each row execute function private.notice_on_cancel();

-- ---------------------------------------------------------------------------
-- For the screens
-- ---------------------------------------------------------------------------
create or replace function public.mark_notices_read()
returns void language sql security definer
set search_path = ''
as $$
  update public.session_notices set read_at = now()
  where account_id = auth.uid() and read_at is null and deliver_at <= now()
$$;
revoke all on function public.mark_notices_read() from public, anon;
grant execute on function public.mark_notices_read() to authenticated;
