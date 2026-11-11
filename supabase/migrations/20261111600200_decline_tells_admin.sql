-- Scheduling: CLG hears when a session time is declined (Carla, 11 Nov 2026).
--
-- * Whoever declines (the tutor, the family, or an admin for them) must
--   give a reason.
-- * Before this, a decline only told the other side (the family or the
--   tutor). Now CLG's owner and operations admins also get a notice under
--   Schedule, saying who declined, the reason, and that the student is back
--   in Matching. A separate trigger, so the existing notices are kept.
--
-- Changes respond_to_booking and approve_booking in place, so other edits
-- to them are kept. Safe to run more than once.

-- A reason is needed to decline.
do $$
declare
  v_def text;
  v_fn text;
  v_flag text;
begin
  foreach v_fn in array array['public.respond_to_booking(uuid, boolean, text)', 'public.approve_booking(uuid, boolean, text)'] loop
    v_flag := case when v_fn like '%respond%' then 'p_accept' else 'p_ok' end;
    v_def := pg_get_functiondef(v_fn::regprocedure);
    v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
    if strpos(v_def, 'Please give a reason for declining') > 0 then
      continue; -- already done
    end if;
    if strpos(v_def, E'  if not ' || v_flag || E' then\n') = 0 then
      raise exception '% has changed since this update was written. Ask for an updated file.', v_fn;
    end if;
    v_def := replace(v_def, E'  if not ' || v_flag || E' then\n',
      E'  if not ' || v_flag || E' and nullif(btrim(coalesce(p_note, '''')), '''') is null then\n'
      || E'    raise exception ''Please give a reason for declining'' using errcode = ''22023'';\n'
      || E'  end if;\n'
      || E'  if not ' || v_flag || E' then\n');
    execute v_def;
  end loop;
end;
$$;

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
