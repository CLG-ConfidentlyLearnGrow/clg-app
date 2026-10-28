-- Scheduling: the one way to fill in a session's online meeting link.
--
-- sessions.meeting_url belongs to the scheduling module. Other modules
-- (the Teams links module) and admins set it only through this function,
-- never by writing the table. Families, students and tutors see the link
-- through list_sessions, as before.
--
-- Safe to run more than once.

create or replace function public.set_session_meeting_url(p_session uuid, p_url text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_url text := nullif(btrim(coalesce(p_url, '')), '');
  v_delivery public.session_delivery;
begin
  -- Only the server (scheduled jobs) and admins may set links.
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only CLG admins can change a session''s meeting link.' using errcode = '42501';
  end if;

  select delivery into v_delivery from public.sessions where id = p_session;
  if not found then
    raise exception 'That session no longer exists.' using errcode = 'P0002';
  end if;
  if v_url is not null then
    if v_delivery <> 'online' then
      raise exception 'Only online sessions have a meeting link.' using errcode = '22023';
    end if;
    if v_url !~ '^https://[^\s]+$' or char_length(v_url) > 2000 then
      raise exception 'The meeting link must be a full web address starting with https://' using errcode = '22023';
    end if;
  end if;

  update public.sessions set meeting_url = v_url where id = p_session;
end;
$$;
revoke all on function public.set_session_meeting_url(uuid, text) from public, anon;
grant execute on function public.set_session_meeting_url(uuid, text) to authenticated, service_role;
