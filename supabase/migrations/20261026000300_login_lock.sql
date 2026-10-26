-- Account lock after repeated failed sign-ins.
--
-- 5 failed attempts within 15 minutes locks the email address for 30
-- minutes. The person can unlock it early by resetting their password, or
-- an admin can unlock it.
--
-- Called only by the app's server (service key), never from a browser.

create function public.login_lock_status(p_email text)
returns timestamptz language sql stable security definer
set search_path = ''
as $$
  select locked_until from private.account_locks
  where email = lower(trim(p_email)) and locked_until > now()
$$;

-- Records an attempt. Returns the lock expiry if this attempt caused or
-- extended a lock, otherwise null.
create function public.record_login_attempt(p_email text, p_succeeded boolean)
returns timestamptz language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_failures integer;
  v_until timestamptz;
begin
  insert into private.login_attempts (email, succeeded) values (v_email, p_succeeded);

  if p_succeeded then
    return null;
  end if;

  select count(*) into v_failures
  from private.login_attempts
  where email = v_email
    and not succeeded
    and attempted_at > now() - interval '15 minutes'
    and attempted_at > coalesce(
      (select max(attempted_at) from private.login_attempts
       where email = v_email and succeeded),
      '-infinity'
    )
    and attempted_at > coalesce(
      (select locked_at from private.account_locks where email = v_email),
      '-infinity'
    );

  if v_failures >= 5 then
    v_until := now() + interval '30 minutes';
    insert into private.account_locks (email, locked_until, locked_at)
    values (v_email, v_until, now())
    on conflict (email) do update
      set locked_until = excluded.locked_until, locked_at = excluded.locked_at;
    return v_until;
  end if;

  return null;
end;
$$;

-- After a successful password reset. The lock row is kept (ended now) so
-- failures from before the reset do not count towards a new lock.
create function public.clear_login_lock(p_email text)
returns void language sql security definer
set search_path = ''
as $$
  update private.account_locks
  set locked_until = now(), locked_at = now()
  where email = lower(trim(p_email))
$$;

-- An admin unlocks someone from the admin screens.
create function public.admin_unlock_account(p_account uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare v_email text;
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  select email into v_email from public.account_private where account_id = p_account;
  update private.account_locks
  set locked_until = now(), locked_at = now()
  where email = v_email;
  perform private.log_event('unlock', 'accounts', p_account::text);
end;
$$;

-- Old attempts are only needed for the lock window; keep 90 days for
-- security review, then delete.
create function private.purge_login_attempts()
returns void language sql security definer
set search_path = ''
as $$
  delete from private.login_attempts where attempted_at < now() - interval '90 days';
  delete from private.account_locks where locked_until < now() - interval '1 day';
$$;

revoke execute on function public.login_lock_status(text) from public, anon, authenticated;
revoke execute on function public.record_login_attempt(text, boolean) from public, anon, authenticated;
revoke execute on function public.clear_login_lock(text) from public, anon, authenticated;
revoke execute on function private.purge_login_attempts() from public;
grant execute on function public.login_lock_status(text) to service_role;
grant execute on function public.record_login_attempt(text, boolean) to service_role;
grant execute on function public.clear_login_lock(text) to service_role;

revoke execute on function public.admin_unlock_account(uuid) from public, anon;
grant execute on function public.admin_unlock_account(uuid) to authenticated;
