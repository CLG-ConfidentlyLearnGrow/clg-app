-- Matching: a declined or expired offer doesn't restart the wait
-- (Carla, 11 Nov 2026).
--
-- A student who still needs a tutor has been waiting since their subject
-- was added, or since their last tutor's sessions finished. Before this, a
-- tutor or family declining an offer (or an offer running out) restarted
-- the count, though the student was never taken on. Now only bookings that
-- were confirmed count.
--
-- Changes private.matching_rows in place, so other edits to it are kept.
-- Safe to run more than once.

do $$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('private.matching_rows()'::regprocedure);
  v_def := replace(v_def, chr(13), ''); -- line endings from pasting on Windows
  if strpos(v_def, 'b.confirmed_at is not null -- only sessions that went ahead') > 0 then
    return; -- already done
  end if;
  if strpos(v_def, '  ) past on true') = 0 then
    raise exception 'matching_rows has changed since this update was written. Ask for an updated file.';
  end if;
  v_def := replace(v_def,
    E'    where b.student_id = ss.student_id and lower(b.subject) = lower(ss.subject)\n  ) past on true',
    E'    where b.student_id = ss.student_id and lower(b.subject) = lower(ss.subject)\n      and b.confirmed_at is not null -- only sessions that went ahead\n  ) past on true');
  if strpos(v_def, 'only sessions that went ahead') = 0 then
    raise exception 'matching_rows has changed since this update was written. Ask for an updated file.';
  end if;
  execute v_def;
end;
$$;
