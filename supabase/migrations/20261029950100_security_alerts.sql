-- Security alerts (shared core): emails CLG's owner when something
-- security-related happens, so a problem is noticed in minutes, not weeks.
--
-- Alerts are raised for:
--   * an account locked after 5 wrong passwords in 15 minutes;
--   * 30 or more wrong passwords across all accounts within 1 hr (a sign
--     someone is trying a list of stolen passwords); at most once every 6 hr;
--   * someone given tutor or admin access;
--   * someone's admin access removed.
--
-- The alerts only tell the owner. They never block or approve anything:
-- giving access still happens in the app as before. Each email links to the
-- admin page so the owner can check, and undo the change if it looks wrong.
--
-- Alerts are gathered into one email per run of the email sender (every
-- 5 minutes at most), so a burst of events sends one email, not hundreds.
-- They ignore quiet hours: a security problem can't wait until 8am.
-- Unsent alerts older than 7 days are not sent (they stay in the table and
-- the activity log).
--
-- Guidance: OAIC Guide to securing personal information (monitor and log
-- access, detect incidents early); OWASP ASVS 4.0 V7 (security logging and
-- alerting); ACSC Essential Eight (restrict admin privileges).
-- Safe to run more than once.

create table if not exists public.security_alerts (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('account_locked', 'many_failed_logins', 'role_given', 'role_removed')),
  created_at timestamptz not null default now(),
  -- Who it is about: an account (role changes) or an email (locks).
  account_id uuid references public.accounts (id) on delete set null,
  email text,
  role public.app_role,
  -- Who made the change, when someone did.
  by_account_id uuid references public.accounts (id) on delete set null,
  failed_count integer,
  sent_at timestamptz,
  -- Which email run took it, so a failed send can put it back.
  batch_id uuid
);
create index if not exists security_alerts_unsent on public.security_alerts (created_at) where sent_at is null;
create index if not exists security_alerts_batch on public.security_alerts (batch_id) where batch_id is not null;

alter table public.security_alerts enable row level security;

-- Only the owner can read alerts. Nobody writes them directly: the triggers
-- below add them, and the email sender marks them sent.
drop policy if exists "owner reads security alerts" on public.security_alerts;
create policy "owner reads security alerts" on public.security_alerts
  for select to authenticated using (private.is_owner());
revoke insert, update, delete, truncate on public.security_alerts from anon, authenticated;

-- Counting recent failed sign-ins across all accounts needs this.
create index if not exists login_attempts_at on private.login_attempts (attempted_at);

-- ---------------------------------------------------------------------------
-- What raises an alert
-- ---------------------------------------------------------------------------

-- An account was locked (new lock, or a lock that had ended and came back).
create or replace function private.alert_account_locked()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.locked_at is distinct from old.locked_at then
    insert into public.security_alerts (kind, email) values ('account_locked', new.email);
  end if;
  return new;
end;
$$;
revoke all on function private.alert_account_locked() from public;

drop trigger if exists security_alert on private.account_locks;
create trigger security_alert after insert or update on private.account_locks
  for each row execute function private.alert_account_locked();

-- Many wrong passwords across all accounts in the last hour.
create or replace function private.alert_many_failed_logins()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if new.succeeded then
    return new;
  end if;
  -- Already told the owner recently? Then stay quiet.
  if exists (
    select 1 from public.security_alerts
    where kind = 'many_failed_logins' and created_at > now() - interval '6 hours'
  ) then
    return new;
  end if;
  select count(*) into v_count from private.login_attempts
  where not succeeded and attempted_at > now() - interval '1 hour';
  if v_count >= 30 then
    insert into public.security_alerts (kind, failed_count) values ('many_failed_logins', v_count);
  end if;
  return new;
end;
$$;
revoke all on function private.alert_many_failed_logins() from public;

drop trigger if exists security_alert on private.login_attempts;
create trigger security_alert after insert on private.login_attempts
  for each row execute function private.alert_many_failed_logins();

-- Tutor or admin access given, or admin access removed.
create or replace function private.alert_role_change()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.role in ('admin', 'tutor') then
    insert into public.security_alerts (kind, account_id, role, by_account_id)
    values ('role_given', new.account_id, new.role, coalesce(new.granted_by, auth.uid()));
  elsif tg_op = 'DELETE' and old.role = 'admin' then
    insert into public.security_alerts (kind, account_id, role, by_account_id)
    values ('role_removed', old.account_id, old.role, auth.uid());
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function private.alert_role_change() from public;

drop trigger if exists security_alert on public.account_roles;
create trigger security_alert after insert or delete on public.account_roles
  for each row execute function private.alert_role_change();

-- ---------------------------------------------------------------------------
-- Sending the alerts (see docs/features/sending-emails.md)
-- ---------------------------------------------------------------------------

-- Any alert waiting to be emailed?
create or replace function private.security_alerts_waiting()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.security_alerts
    where sent_at is null and created_at > now() - interval '7 days'
  )
$$;
revoke all on function private.security_alerts_waiting() from public;

-- One plain sentence for each alert.
create or replace function private.security_alert_line(a public.security_alerts)
returns text language sql stable security definer
set search_path = ''
as $$
  select to_char(a.created_at at time zone 'Australia/Adelaide', 'FMDy FMDD FMMon, FMHH12:MI am') || ': '
    || case a.kind
      when 'account_locked' then
        'the account for ' || coalesce(a.email, 'an email address')
        || ' was locked for 30 minutes after 5 wrong passwords.'
      when 'many_failed_logins' then
        a.failed_count || ' wrong-password sign-ins across all accounts in the last hr.'
        || ' This can mean someone is trying a list of stolen passwords.'
      when 'role_given' then
        coalesce(acc.full_name, 'An account') || coalesce(' (' || ap.email || ')', '')
        || ' was given ' || a.role::text || ' access'
        || case
             when a.by_account_id is null or a.by_account_id = a.account_id then ' (through an invite link or sign-up).'
             else ' by ' || coalesce(byacc.full_name, 'an admin') || '.'
           end
      when 'role_removed' then
        coalesce(acc.full_name, 'An account') || coalesce(' (' || ap.email || ')', '')
        || ' no longer has admin access'
        || case when a.by_account_id is null then '.' else ' (removed by ' || coalesce(byacc.full_name, 'an admin') || ').' end
    end
  from (select 1) one
  left join public.accounts acc on acc.id = a.account_id
  left join public.account_private ap on ap.account_id = a.account_id
  left join public.accounts byacc on byacc.id = a.by_account_id
$$;
revoke all on function private.security_alert_line(public.security_alerts) from public;

-- Hands the waiting alerts to the email sender as one email to each owner,
-- and marks them sent. Returns nothing if there is no owner to tell.
create or replace function public.security_alert_emails_claim(p_limit integer default 50)
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text)
language plpgsql security definer
set search_path = ''
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_lines text;
  v_count integer;
begin
  if not exists (select 1 from public.admin_profiles where level = 'owner') then
    return;
  end if;

  with due as (
    select s.id from public.security_alerts s
    where s.sent_at is null and s.created_at > now() - interval '7 days'
    order by s.created_at
    limit least(greatest(p_limit, 1), 100)
    for update skip locked
  )
  update public.security_alerts s
  set sent_at = now(), batch_id = v_batch
  from due where s.id = due.id;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return;
  end if;

  select string_agg('- ' || private.security_alert_line(s), E'\n' order by s.created_at)
  into v_lines
  from public.security_alerts s where s.batch_id = v_batch;

  return query
  select v_batch, ap.email, private.first_name(acc.full_name),
    case when v_count = 1 then 'CLG app security alert' else 'CLG app security alerts (' || v_count || ')' end,
    'This happened in the CLG app (Adelaide time):' || E'\n\n' || v_lines || E'\n\n'
      || 'If you don''t recognise a change, open the admin page and undo it, then ask the person to reset their password. '
      || 'The activity log has the full record. Nothing needs doing if you expected this.',
    '/admin'::text,
    'Open the admin page'::text,
    'You get this email because you are the owner of CLG''s app account. Security alerts can''t be turned off.'::text
  from public.admin_profiles p
  join public.accounts acc on acc.id = p.account_id
  join public.account_private ap on ap.account_id = p.account_id
  where p.level = 'owner';
end;
$$;
revoke all on function public.security_alert_emails_claim(integer) from public, anon, authenticated;
grant execute on function public.security_alert_emails_claim(integer) to service_role;

-- Puts alerts back if sending failed (only ones taken in the last hour).
create or replace function public.security_alert_emails_release(p_ids uuid[])
returns void language sql security definer
set search_path = ''
as $$
  update public.security_alerts set sent_at = null, batch_id = null
  where batch_id = any (p_ids) and sent_at > now() - interval '1 hour'
$$;
revoke all on function public.security_alert_emails_release(uuid[]) from public, anon, authenticated;
grant execute on function public.security_alert_emails_release(uuid[]) to service_role;

-- Wake the email sender for alerts too. The shared check is extended rather
-- than copied, so changes other modules make to it are kept.
do $$
declare
  v_def text;
begin
  if to_regprocedure('private.emails_waiting()') is null then
    return;
  end if;
  v_def := pg_catalog.pg_get_functiondef('private.emails_waiting()'::regprocedure);
  if strpos(v_def, 'private.security_alerts_waiting()') = 0 then
    v_def := regexp_replace(v_def, '\s*\$function\$\s*$', E'\n  or private.security_alerts_waiting()\n$function$\n');
    execute v_def;
  end if;
end;
$$;

-- Old alerts are cleared after the same time as the activity log (7 years).
create or replace function private.clear_old_security_alerts()
returns void language sql security definer
set search_path = ''
as $$
  delete from public.security_alerts where created_at < now() - private.keep_for('activity_log')
$$;
revoke all on function private.clear_old_security_alerts() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-clear-security-alerts', '15 3 * * *', 'select private.clear_old_security_alerts()')
    $job$;
  end if;
end;
$$;
