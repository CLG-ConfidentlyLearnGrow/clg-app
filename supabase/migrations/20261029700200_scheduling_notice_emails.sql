-- Scheduling (module: scheduling): reminders and booking notices by email.
--
-- The app's email sender calls these with the server key. A notice is
-- emailed once, when it is due, to the person's login email, unless they
-- turned email off in their reminder settings. Notices more than 12 hr
-- overdue (for example from before email was set up) stay in the app only,
-- and a reminder is never emailed once its session has started or been
-- cancelled. See docs/features/sending-emails.md. Safe to run more than once.

create or replace function public.session_notice_emails_claim(p_limit integer default 50)
returns table (id uuid, email text, first_name text, subject text, body text, link text)
language sql security definer
set search_path = ''
as $$
  with due as (
    select n.id
    from public.session_notices n
    join public.account_private ap on ap.account_id = n.account_id
    left join public.notice_settings ns on ns.account_id = n.account_id
    left join public.sessions x on x.id = n.session_id
    where n.email_sent_at is null
      and n.deliver_at <= now()
      and n.deliver_at > now() - interval '12 hours'
      and coalesce(ns.by_email, true)
      and (n.kind not in ('reminder_first', 'reminder_final')
           or (x.status = 'scheduled' and x.starts_at > now()))
    order by n.deliver_at
    limit least(greatest(p_limit, 1), 100)
    for update of n skip locked
  )
  update public.session_notices n
  set email_sent_at = now()
  from due, public.account_private ap, public.accounts a
  where n.id = due.id and ap.account_id = n.account_id and a.id = n.account_id
  returning n.id, ap.email, private.first_name(a.full_name), n.title, n.body, '/schedule'::text
$$;
revoke all on function public.session_notice_emails_claim(integer) from public, anon, authenticated;
grant execute on function public.session_notice_emails_claim(integer) to service_role;

-- Sending failed: put them back so the next run tries again.
create or replace function public.session_notice_emails_release(p_ids uuid[])
returns void language sql security definer
set search_path = ''
as $$
  update public.session_notices set email_sent_at = null
  where id = any (p_ids) and email_sent_at > now() - interval '1 hour'
$$;
revoke all on function public.session_notice_emails_release(uuid[]) from public, anon, authenticated;
grant execute on function public.session_notice_emails_release(uuid[]) to service_role;
