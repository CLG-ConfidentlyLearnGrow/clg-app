-- Scheduling part 6 (module: scheduling): tutors check their availability
-- each term.
--
-- A week before families are asked about next term (3 weeks before a term
-- ends; 5 weeks for terms 1 and 3), each active tutor is asked: "Is your
-- availability right for next term?" They tap "No changes", or update it
-- (on their dashboard) and then confirm. Admins see who hasn't answered,
-- weekly times a tutor has removed since last term, and booked times that
-- now fall outside their availability. Nobody is hidden from bookings for
-- a missed answer, and changes never touch booked sessions.
--
-- This module only reads availability (tutor_availability belongs to the
-- core). At each confirmation it keeps a copy, so the next term's changes
-- can be shown.
--
-- See docs/features/scheduling.md. Safe to run more than once.

create table if not exists public.availability_checks (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  term_id uuid not null references public.school_terms (id) on delete restrict,
  asked_at timestamptz not null default now(),
  confirmed_at timestamptz,
  -- Whether the tutor said they changed something.
  changed boolean,
  -- Availability and weekly limit at confirmation:
  -- {"slots": [{"weekday": 1, "starts_at": "15:00", "ends_at": "18:00"}], "max_weekly_hours": 10}
  snapshot jsonb,
  unique (tutor_id, term_id)
);
create index if not exists availability_checks_tutor on public.availability_checks (tutor_id, asked_at desc);

alter table public.availability_checks enable row level security;
revoke all on public.availability_checks from anon;
revoke insert, update, delete, truncate on public.availability_checks from authenticated;

drop policy if exists "tutor and admins see availability checks" on public.availability_checks;
create policy "tutor and admins see availability checks" on public.availability_checks
  for select to authenticated using (
    private.is_admin() or (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
  );

-- A new notice kind for tutors.
-- Only widened when this kind isn't allowed yet, so running this file again
-- never narrows a list a later file has widened.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'session_notices_kind_check'
      and pg_get_constraintdef(oid) like '%availability_check%'
  ) then
    alter table public.session_notices drop constraint if exists session_notices_kind_check;
    alter table public.session_notices add constraint session_notices_kind_check check (kind in (
      'reminder_first', 'reminder_final',
      'booking_requested', 'booking_confirmed', 'booking_declined',
      'session_cancelled', 'renewal_due', 'availability_check'
    ));
  end if;
end;
$$;

-- A tutor's current availability and weekly limit, as stored in a check.
create or replace function private.availability_snapshot(p_tutor uuid)
returns jsonb language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'slots', coalesce((
      select jsonb_agg(jsonb_build_object(
               'weekday', a.weekday,
               'starts_at', to_char(a.starts_at, 'HH24:MI'),
               'ends_at', to_char(a.ends_at, 'HH24:MI'))
             order by a.weekday, a.starts_at)
      from public.tutor_availability a where a.tutor_id = p_tutor), '[]'::jsonb),
    'max_weekly_hours', (select w.max_weekly_hours from public.tutor_work_settings w where w.tutor_id = p_tutor)
  )
$$;

-- Runs daily. Asks each active tutor once per term, when it's due. Terms
-- follow the tutor's work state (South Australia if not set).
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
     and current_date between t.starts_on and t.ends_on
    where tp.active
      and exists (select 1 from public.account_roles ar where ar.account_id = tp.account_id and ar.role = 'tutor')
      and current_date >= t.ends_on - case when t.term in (1, 3) then 35 else 21 end
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

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-queue-availability-checks', '0 23 * * *', 'select private.queue_availability_checks()')
    $job$;
  end if;
end;
$$;

-- The tutor confirms (p_changed = false: "No changes"; true: "I've updated
-- it"). They can confirm again after more changes; the latest copy is kept.
create or replace function public.confirm_availability(p_check uuid, p_changed boolean)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_c public.availability_checks;
begin
  select * into v_c from public.availability_checks where id = p_check for update;
  if v_c.id is null or not (
    private.is_admin() or (v_c.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
  ) then
    raise exception 'Availability check not found' using errcode = 'P0002';
  end if;
  update public.availability_checks
  set confirmed_at = now(),
      changed = coalesce(changed, false) or coalesce(p_changed, false),
      snapshot = private.availability_snapshot(v_c.tutor_id)
  where id = p_check;
end;
$$;
revoke all on function public.confirm_availability(uuid, boolean) from public, anon;
grant execute on function public.confirm_availability(uuid, boolean) to authenticated;

-- For the screens: the latest check for each tutor (their own, or all for
-- admins), with:
--   removed_slots: weekly times in last term's confirmed copy that aren't
--     in their availability now
--   bookings_outside: live bookings still running that now fall outside
--     their availability (to talk through with the tutor)
create or replace function public.list_availability_checks()
returns table (
  id uuid, tutor_id uuid, tutor_name text, term_label text, term_ends_on date,
  asked_at timestamptz, confirmed_at timestamptz, changed boolean,
  removed_slots text[], bookings_outside bigint
)
language sql stable security definer
set search_path = ''
as $$
  with latest as (
    select distinct on (c.tutor_id) c.*
    from public.availability_checks c
    where private.is_admin() or (c.tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2())
    order by c.tutor_id, c.asked_at desc
  )
  select l.id, l.tutor_id, a.full_name, 'Term ' || t.term || ' ' || t.year, t.ends_on,
         l.asked_at, l.confirmed_at, l.changed,
         array(
           select (array['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])[(s->>'weekday')::int]
                  || ' ' || (s->>'starts_at') || '-' || (s->>'ends_at')
           from public.availability_checks prev
           cross join lateral jsonb_array_elements(prev.snapshot->'slots') s
           where prev.id = (
               select p.id from public.availability_checks p
               where p.tutor_id = l.tutor_id and p.asked_at < l.asked_at and p.snapshot is not null
               order by p.asked_at desc limit 1)
             and not exists (
               select 1 from public.tutor_availability av
               where av.tutor_id = l.tutor_id and av.weekday = (s->>'weekday')::int
                 and av.starts_at <= (s->>'starts_at')::time and av.ends_at >= (s->>'ends_at')::time)
           order by (s->>'weekday')::int, s->>'starts_at'
         ),
         (select count(*) from public.bookings b
          where b.tutor_id = l.tutor_id
            and private.booking_is_live(b.status, b.tutor_reply_by)
            and b.last_date >= current_date
            and not exists (
              select 1 from public.tutor_availability av
              where av.tutor_id = b.tutor_id and av.weekday = b.weekday
                and av.starts_at <= b.start_time
                and av.ends_at >= b.start_time + make_interval(mins => b.minutes)))
  from latest l
  join public.accounts a on a.id = l.tutor_id
  join public.school_terms t on t.id = l.term_id
  order by l.confirmed_at is not null, a.full_name
$$;
revoke all on function public.list_availability_checks() from public, anon;
grant execute on function public.list_availability_checks() to authenticated;
