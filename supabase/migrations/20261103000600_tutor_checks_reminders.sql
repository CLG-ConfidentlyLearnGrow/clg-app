-- Tutor checks (shared core). Carla, 2 Nov 2026.
--
-- * RRHAN-EC Fundamentals and Masterclass are required Australia-wide at
--   CLG, not only for South Australian students. A tutor needs both, in
--   date, for a student in any state.
-- * Tutors always upload the certificate (already required) and give the
--   date it was done or the date it expires, whichever the certificate
--   shows. For training with a set life, the app works out the expiry from
--   the date done: RRHAN-EC 3 years, first aid 3 years, police check
--   5 years. Cards with their own expiry (working with children checks)
--   still need the expiry date.
-- * Tutors are reminded to renew 6 weeks and 2 weeks before a check
--   expires (an app notice). At 2 weeks CLG's admins are told too.
--
-- See docs/features/tutor-checks.md. Safe to run more than once.

-- RRHAN-EC for students in every state.
insert into public.check_requirements (state, kind, basis)
select s::public.au_state, k::public.tutor_check_kind, 'student_state'
from unnest(array['SA', 'NSW', 'VIC', 'QLD', 'WA', 'TAS', 'ACT', 'NT']) s,
     unnest(array['rrhan_ec_fundamentals', 'rrhan_ec_masterclass']) k
on conflict do nothing;

-- How long a check lasts from the date done, where it has a set life.
create or replace function private.check_life(p_kind public.tutor_check_kind)
returns interval language sql immutable
set search_path = ''
as $$
  select case p_kind::text
    when 'police_check' then interval '5 years'
    when 'rrhan_ec_fundamentals' then interval '3 years'
    when 'rrhan_ec_masterclass' then interval '3 years'
    when 'first_aid' then interval '3 years'
  end
$$;

-- Fills in the expiry from the date done when only that is given. Runs
-- before the main check rules (triggers run in name order).
create or replace function private.fill_check_expiry()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if new.expires_on is null then
    if new.completed_on is null then
      raise exception 'Enter the date it was done or the date it expires' using errcode = '23514';
    end if;
    if private.check_life(new.kind) is null then
      raise exception 'Enter the expiry date shown on the card' using errcode = '23514';
    end if;
    new.expires_on := (new.completed_on + private.check_life(new.kind))::date;
  end if;
  return new;
end;
$$;
drop trigger if exists a_fill_expiry on public.tutor_checks;
create trigger a_fill_expiry before insert or update on public.tutor_checks
  for each row execute function private.fill_check_expiry();

-- Renewal reminders.
alter table public.tutor_checks add column if not exists reminded_6w_at timestamptz;
alter table public.tutor_checks add column if not exists reminded_2w_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'session_notices_kind_check'
      and pg_get_constraintdef(oid) like '%check_renewal%'
  ) then
    alter table public.session_notices drop constraint if exists session_notices_kind_check;
    alter table public.session_notices add constraint session_notices_kind_check check (kind in (
      'reminder_first', 'reminder_final',
      'booking_requested', 'booking_confirmed', 'booking_declined',
      'session_cancelled', 'renewal_due', 'availability_check',
      'offer_follow_up', 'tutor_away', 'request_update', 'staff_alert', 'check_renewal'
    ));
  end if;
end;
$$;

-- Runs daily. Only a tutor's latest verified check of each kind counts (a
-- renewed check stops reminders for the old one).
create or replace function private.queue_check_reminders()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
  v_name text;
begin
  for r in
    select c.*, a.full_name as tutor_name,
           (c.expires_on - current_date) as days_left
    from public.tutor_checks c
    join public.accounts a on a.id = c.tutor_id
    join public.tutor_profiles tp on tp.account_id = c.tutor_id and tp.active
    where c.verified_at is not null
      and c.expires_on >= current_date
      and c.expires_on <= current_date + 42
      and not exists (
        select 1 from public.tutor_checks n
        where n.tutor_id = c.tutor_id and n.kind = c.kind and n.id <> c.id
          and n.expires_on > c.expires_on and n.declined_at is null
      )
      and ((c.reminded_6w_at is null) or (c.expires_on <= current_date + 14 and c.reminded_2w_at is null))
    for update of c skip locked
  loop
    v_name := initcap(replace(replace(r.kind::text, 'rrhan_ec', 'RRHAN-EC'), '_', ' '));
    perform private.add_notice(r.tutor_id, null, null, 'check_renewal', 'Time to renew: ' || v_name,
      'Your ' || v_name || ' expires on ' || to_char(r.expires_on, 'FMDD FMMonth YYYY')
      || '. Please renew it and add the new certificate under Dashboard > Checks, so your sessions can carry on.',
      now());
    if r.expires_on <= current_date + 14 then
      perform private.notify_admins('Check expiring: ' || r.tutor_name,
        r.tutor_name || '''s ' || v_name || ' expires on ' || to_char(r.expires_on, 'FMDD Mon')
        || '. They have been reminded. Without a renewed check they can''t see or be matched with students who need it.');
      update public.tutor_checks
      set reminded_2w_at = now(), reminded_6w_at = coalesce(reminded_6w_at, now())
      where id = r.id;
    else
      update public.tutor_checks set reminded_6w_at = now() where id = r.id;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.queue_check_reminders() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    -- 9am Adelaide (22:30 UTC; 30 minutes later in daylight saving).
    execute $job$
      select cron.schedule('clg-check-reminders', '30 22 * * *', 'select private.queue_check_reminders()')
    $job$;
  end if;
end;
$$;
