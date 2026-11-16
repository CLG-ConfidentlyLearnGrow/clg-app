-- Training (module: training): admins who don't tutor don't do the
-- tutoring modules (Carla, 16 Nov 2026: "Admins who are not tutors do not
-- need to do the tutoring modules").
--
-- Modules made for "tutors" already only go to people with the tutor role.
-- Three of the safety modules were made for "everyone" but are about
-- tutoring, so they now go to tutors only:
--   4 Professional and honest (never writing a student's work)
--   5 Boundaries with students and families (session places, contact rules)
--   6 Safe online sessions
-- Child safety (1-3), privacy (7-8) and the yearly refresher (17) stay for
-- everyone, because every staff member who can see children's information
-- needs them (National Principles for Child Safe Organisations, Principle 7;
-- Privacy Act). Someone who is both an admin and a tutor still does all of
-- them, as a tutor.
--
-- Only draft modules change, so a module already published (and maybe
-- already done by admins) is left alone. Safe to run more than once.

update public.training_modules m -- changes modules:
set audience = 'tutor' -- to tutors only
where m.id in ('7a000000-0000-4000-8000-000000000004', '7a000000-0000-4000-8000-000000000005', '7a000000-0000-4000-8000-000000000006') -- modules 4, 5 and 6
  and m.audience = 'everyone' -- still made for everyone
  and m.status = 'draft'; -- and still a draft
