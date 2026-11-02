-- Emergency owner access starts after 24 hours (was 48), and the owner can
-- now approve it sooner as well as cancel it. Carla, 2 Nov 2026.
-- See docs/features/admin-levels.md. Safe to run more than once.

create or replace function public.request_emergency_owner_access(p_reason text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_id uuid;
begin
  if coalesce(private.my_saved_admin_level(), '') <> 'operations' then
    raise exception 'Only an Operations admin can ask for emergency owner access' using errcode = '42501';
  end if;
  if char_length(v_reason) < 10 then
    raise exception 'Please write why you need owner access (at least 10 characters)' using errcode = '22023';
  end if;
  if char_length(v_reason) > 1000 then
    raise exception 'Please keep the reason under 1000 characters' using errcode = '22023';
  end if;
  -- One request at a time, across everyone.
  lock table public.emergency_owner_access in share row exclusive mode;
  if exists (
    select 1 from public.emergency_owner_access
    where cancelled_at is null and ends_at > now()
  ) then
    raise exception 'There is already an emergency access request waiting or running' using errcode = '23505';
  end if;
  insert into public.emergency_owner_access (requested_by, reason, starts_at, ends_at)
  values (auth.uid(), v_reason, now() + interval '24 hours', now() + interval '24 hours' + interval '7 days')
  returning id into v_id;
  perform private.log_event('emergency_access_requested', 'emergency_owner_access', v_id::text,
    jsonb_build_object('reason', v_reason));
  return v_id;
end;
$$;
revoke execute on function public.request_emergency_owner_access(text) from public, anon;
grant execute on function public.request_emergency_owner_access(text) to authenticated;

-- The owner approves a waiting request: access starts now and still lasts
-- 7 days. Only the owner (never the person who asked).
create or replace function public.approve_emergency_owner_access(p_id uuid)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_row public.emergency_owner_access;
begin
  if coalesce(private.my_saved_admin_level(), '') <> 'owner' then
    raise exception 'Only the owner can approve emergency access' using errcode = '42501';
  end if;
  select * into v_row from public.emergency_owner_access
  where id = p_id and cancelled_at is null and starts_at > now()
  for update;
  if v_row.id is null then
    raise exception 'That request has already started, ended or been cancelled' using errcode = '22023';
  end if;
  update public.emergency_owner_access
  set starts_at = now(), ends_at = now() + interval '7 days'
  where id = v_row.id;
  perform private.log_event('emergency_access_approved', 'emergency_owner_access', v_row.id::text, '{}');
  return v_row.requested_by;
end;
$$;
revoke execute on function public.approve_emergency_owner_access(uuid) from public, anon;
grant execute on function public.approve_emergency_owner_access(uuid) to authenticated;
