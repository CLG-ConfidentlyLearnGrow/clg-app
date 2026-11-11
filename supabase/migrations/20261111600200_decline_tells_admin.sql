-- Scheduling: CLG hears when a session time is declined (Carla, 11 Nov 2026).
--
-- Before this, a decline only told the other side (the family or the
-- tutor). Now CLG's owner and operations admins also get a notice under
-- Schedule, saying who declined, any reason given, and that the student is
-- back in Matching. A separate trigger, so the existing notices are kept.
-- Safe to run more than once.

create or replace function private.notice_admins_on_decline()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_student text;
  v_tutor text;
  v_who text;
  v_note text;
begin
  if not (old.status = 'requested' and new.status = 'declined') then
    return new;
  end if;
  select full_name into v_student from public.students where id = new.student_id;
  select full_name into v_tutor from public.accounts where id = new.tutor_id;
  v_who := case new.declined_by_role when 'family' then split_part(coalesce(v_student, 'The student'), ' ', 1) || '''s family'
                                     else coalesce(v_tutor, 'The tutor') end;
  v_note := case new.declined_by_role when 'family' then new.family_note else new.tutor_note end;
  perform private.notify_admins('Session declined',
    v_who || ' declined ' || new.subject || ' for ' || coalesce(v_student, 'a student') || ' with '
    || coalesce(v_tutor, 'the tutor') || ', '
    || (array['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])[new.weekday] || ' '
    || trim(to_char(new.start_time, 'FMHH12:MIam')) || '.'
    || coalesce(' Reason: ' || nullif(btrim(v_note), '') || '.', '')
    || ' Please find another time or tutor under Matching.',
    new.id);
  return new;
end;
$$;
revoke all on function private.notice_admins_on_decline() from public;
drop trigger if exists admins_on_decline on public.bookings;
create trigger admins_on_decline after update of status on public.bookings
  for each row execute function private.notice_admins_on_decline();
