-- Scheduling: when each booking was asked for, so the Bookings list can
-- show the most recent at the top (Carla, 12 Nov 2026).
--
-- Returns the id and request time of every booking the viewer can already
-- see in list_bookings(), and nothing else, so it shares the same access
-- rules. Safe to run more than once.

create or replace function public.booking_request_times()
returns table (id uuid, requested_at timestamptz) -- each booking and when it was asked for
language sql stable security definer -- reads bookings, limited below to what the viewer may see
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select b.id, b.requested_at -- the booking and its request time
  from public.bookings b -- every booking
  join public.list_bookings() lb on lb.id = b.id -- only those the viewer can see (list_bookings checks who's asking)
$$; -- end of the function
revoke all on function public.booking_request_times() from public, anon; -- not for signed-out visitors
grant execute on function public.booking_request_times() to authenticated; -- signed-in people (each sees only their own bookings)
