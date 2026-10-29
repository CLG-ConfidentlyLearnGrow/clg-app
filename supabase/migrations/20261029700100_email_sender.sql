-- Sending emails (shared core): wakes the app's email sender.
--
-- Each module keeps its own notices (scheduling: session_notices; progress:
-- progress_notices; billing: billing_tutor_notices) and offers two
-- server-only functions: one that hands over the notices due by email and
-- marks them sent, and one that puts them back if sending failed. The app's
-- sender (src/app/api/email/cron) calls those and sends through Resend.
--
-- Vercel's free plan only runs a job once a day, which is too slow for a
-- "session in 1 hour" reminder. So the database wakes the sender every
-- 5 minutes, but only when an email is waiting. It needs two values saved
-- once in Supabase's Vault (Project Settings > Vault, or the SQL below):
--   select vault.create_secret('https://clg-app-chi.vercel.app', 'clg_app_url');
--   select vault.create_secret('<the same text as CRON_SECRET in Vercel>', 'clg_cron_secret');
-- Until both are saved, this does nothing and the app works as before.
--
-- See docs/features/sending-emails.md. Safe to run more than once.

-- Is any email waiting? Reads each module's notices; changes nothing.
create or replace function private.emails_waiting()
returns boolean language sql stable security definer
set search_path = ''
as $$
  -- Same rules as the modules' claim functions.
  select exists (
    select 1 from public.session_notices n
    left join public.notice_settings ns on ns.account_id = n.account_id
    left join public.sessions x on x.id = n.session_id
    where n.email_sent_at is null and n.deliver_at <= now() and n.deliver_at > now() - interval '12 hours'
      and coalesce(ns.by_email, true)
      and (n.kind not in ('reminder_first', 'reminder_final') or (x.status = 'scheduled' and x.starts_at > now()))
  ) or exists (
    select 1 from public.progress_notices n
    left join public.notice_settings ns on ns.account_id = n.account_id
    where n.email_sent_at is null and n.deliver_at <= now() and n.deliver_at > now() - interval '12 hours'
      and coalesce(ns.by_email, true)
  ) or exists (
    select 1 from public.billing_tutor_notices n
    where n.sent_at is null and n.created_at > now() - interval '3 days'
      and private.outside_quiet_hours(n.created_at) <= now()
  )
$$;
revoke all on function private.emails_waiting() from public;

-- Calls the app's sender. Uses pg_net and Vault, which Supabase provides;
-- does nothing where they (or the two saved values) are missing.
create or replace function private.wake_email_sender()
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if to_regnamespace('net') is null or to_regclass('vault.decrypted_secrets') is null then
    return false;
  end if;
  if not private.emails_waiting() then
    return false;
  end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'clg_app_url' limit 1$q$ into v_url;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'clg_cron_secret' limit 1$q$ into v_secret;
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then
    return false;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 30000)'
    using rtrim(v_url, '/') || '/api/email/cron',
          '{}'::jsonb,
          jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json');
  return true;
end;
$$;
revoke all on function private.wake_email_sender() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    execute 'create extension if not exists pg_net';
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-send-emails', '*/5 * * * *', 'select private.wake_email_sender()')
    $job$;
  end if;
end;
$$;
