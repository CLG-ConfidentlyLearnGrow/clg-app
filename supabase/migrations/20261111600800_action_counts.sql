-- Scheduling: numbers on tabs that need action, e.g. "Matching (4)"
-- (Carla, 11 Nov 2026).
--
-- One call returns the counts for the person viewing:
--   matching        CLG admins: student subjects waiting for a tutor
--   libraries       owner and operations admins: libraries on the to-do list
--   booking-length  families: children whose "How long to book" isn't filled in
-- Other counts (offers to answer, unread notices, next term) are worked out
-- on the page from data it already loads.
--
-- Needs 20261111600500_booking_end_dates.sql and
-- 20261111600700_library_checks.sql. Safe to run more than once.

create or replace function public.scheduling_counts()
returns table (key text, n integer)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if private.is_front_desk() then
    return query
    select 'matching'::text, count(*)::integer
    from private.matching_rows() r
    where r.stage = 'needs_tutor';
  end if;
  if private.is_admin() then
    return query
    select 'libraries'::text, count(*)::integer from public.library_checks();
  end if;
  return query
  select 'booking-length'::text, count(*)::integer
  from public.students s
  left join public.student_places sp on sp.student_id = s.id
  where (private.can_manage_student(s.id) or private.is_student_self(s.id))
    and exists (select 1 from public.student_subjects ss where ss.student_id = s.id)
    and (sp.book_until is null or sp.include_school_holidays is null or sp.include_public_holidays is null);
end;
$$;
revoke all on function public.scheduling_counts() from public, anon;
grant execute on function public.scheduling_counts() to authenticated;
