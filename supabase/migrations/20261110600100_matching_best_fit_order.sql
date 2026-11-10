-- Matching (module: scheduling): new "best fit" order for the tutor
-- shortlist (Carla, 10 Nov 2026).
--
-- Only tutors who teach the subject at the level the student is working at
-- are listed (as before). Among them:
--   1. a tutor who already teaches a sibling
--   2. spare hours: tutors with room for this session before tutors at
--      their weekly maximum
--   3. place that suits: the tutor goes to one of the student's libraries,
--      or teaches online when the student is happy with online
--   4. time that suits: has times that fit, preferred times first
--   then most spare hours, then name.
--
-- Changes the ranking inside matching_shortlist in place, so later edits to
-- the rest of that function are kept. Needs
-- 20261103600200_scheduling_matching_tab.sql. Safe to run more than once.

do $$
declare
  v_def text;
  v_old text := 'order by s.teaches_sibling desc,
                     (s.times > 0) desc,
                     (s.preferred_times > 0) desc,
                     (s.in_person_times > 0 and cardinality(v_libs) > 0) desc,
                     coalesce(s.max_weekly_hours * 60 - s.booked_minutes, 100000) desc,
                     s.full_name';
  v_new text := 'order by s.teaches_sibling desc,
                     (not s.at_max) desc,
                     (exists (select 1 from public.tutor_places tp
                              where tp.tutor_id = s.tid and tp.library_id = any (v_libs))
                      or (v_online and exists (select 1 from public.tutor_availability av
                                               where av.tutor_id = s.tid and av.online))) desc,
                     (s.times > 0) desc,
                     (s.preferred_times > 0) desc,
                     coalesce(s.max_weekly_hours * 60 - s.booked_minutes, 100000) desc,
                     s.full_name';
begin
  if to_regprocedure('public.matching_shortlist(uuid, text, integer)') is null then
    raise exception 'Run 20261103600200_scheduling_matching_tab.sql first';
  end if;
  v_def := pg_get_functiondef('public.matching_shortlist(uuid, text, integer)'::regprocedure);
  if strpos(v_def, v_new) > 0 then
    return; -- already done
  end if;
  if strpos(v_def, v_old) = 0 then
    raise exception 'The matching shortlist has changed since this update was written. Ask for an updated file.';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$$;
