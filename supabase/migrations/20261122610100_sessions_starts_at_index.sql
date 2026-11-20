-- Summary: makes admin views of sessions faster (Carla, 20 Nov 2026, Home
-- overview dashboards).
--
-- Each dashboard now opens on an Overview. The admin Overview counts the
-- sessions today and in the coming week across all of CLG, using
-- public.list_sessions. For an admin, that looks up sessions by start time
-- only (not by tutor or student), and sessions had no index on start time,
-- so the database read every session ever booked. This index lets it go
-- straight to the dates asked for. The Sessions page and the calendars use
-- the same lookup, so they get faster too.
--
-- Nothing about who can see what changes: no access rules are touched.
-- Scheduling module (sessions). Safe to run more than once.
-- Run after 20261122560200_libraries_closed_public_holidays.sql.

create index if not exists sessions_starts_at_idx on public.sessions (starts_at); -- finds sessions by start time quickly, for any tutor or student
