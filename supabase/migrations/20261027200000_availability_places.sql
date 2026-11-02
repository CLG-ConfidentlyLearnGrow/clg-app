-- Core: how a tutor can teach in each available time.
--
-- Each availability slot now says whether the tutor can teach in person
-- (at the libraries they ticked under "Where you teach"), online, or both.
-- The tutor sets this when adding a time in their dashboard. Booking
-- searches (scheduling module) only offer a way of teaching the slot allows.
--
-- Existing slots keep both, so nothing changes until a tutor edits them.
-- Dated just before the scheduling files, which read these columns.
-- Safe to run more than once.

alter table public.tutor_availability add column if not exists in_person boolean not null default true;
alter table public.tutor_availability add column if not exists online boolean not null default true;
alter table public.tutor_availability drop constraint if exists tutor_availability_some_place;
alter table public.tutor_availability add constraint tutor_availability_some_place
  check (in_person or online);
