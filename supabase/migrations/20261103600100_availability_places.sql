-- How a tutor can teach in each available time (core column, read by the
-- scheduling module). Carla, 2 Nov 2026.
--
-- Each availability slot says whether the tutor can teach in person (at
-- the libraries they ticked under "Where you teach"), online, or both. The
-- tutor ticks this when adding a time in their dashboard. Existing times
-- keep both, so nothing changes until a tutor edits them.
--
-- Booking searches only offer a way of teaching the time allows, and the
-- term availability check counts bookings that no longer fit.
--
-- This file edits the current find_session_times in place (other files
-- change it too), so it is safe to run more than once and in any order
-- after the earlier scheduling files.

-- ---------------------------------------------------------------------------
-- Core: in person, online or both for each available time
-- ---------------------------------------------------------------------------
alter table public.tutor_availability add column if not exists in_person boolean not null default true;
alter table public.tutor_availability add column if not exists online boolean not null default true;
alter table public.tutor_availability drop constraint if exists tutor_availability_some_place;
alter table public.tutor_availability add constraint tutor_availability_some_place
  check (in_person or online);

-- ---------------------------------------------------------------------------
-- Finding times: only the ways of teaching each available time allows
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text;
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.find_session_times(uuid, text, integer, boolean, uuid[], date, smallint[], time, time)'::regprocedure);
  if strpos(v_def, 'slot_online') = 0 then
    v_def := replace(v_def,
      'g::time as st
    from tutors tu',
      'g::time as st,
           av.online as slot_online, av.in_person as slot_in_person
    from tutors tu');
    v_def := replace(v_def,
      'where p_online and tu.can_online',
      'where p_online and tu.can_online and s.slot_online');
    v_def := replace(v_def,
      'where tu.can_in_person and tp.library_id',
      'where tu.can_in_person and s.slot_in_person and tp.library_id');
    if strpos(v_def, 'as slot_online') = 0 or strpos(v_def, 's.slot_online') = 0
       or strpos(v_def, 's.slot_in_person') = 0 then
      raise exception 'find_session_times has changed; update this migration';
    end if;
    execute v_def;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Term availability check: a booking no longer fits if its time no longer
-- allows the way it's taught
-- ---------------------------------------------------------------------------
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
                and av.ends_at >= b.start_time + make_interval(mins => b.minutes)
                -- and the time still allows this way of teaching
                and (case when b.delivery = 'online' then av.online else av.in_person end)))
  from latest l
  join public.accounts a on a.id = l.tutor_id
  join public.school_terms t on t.id = l.term_id
  order by l.confirmed_at is not null, a.full_name
$$;
revoke all on function public.list_availability_checks() from public, anon;
grant execute on function public.list_availability_checks() to authenticated;
