-- Progress (module: progress): family updates and tutor reminders by email.
--
-- Same rules as scheduling's notice emails: once, when due, to the login
-- email, unless the person turned email off in their reminder settings;
-- more than 12 hr overdue stays in the app only. The email carries the same
-- short text as the app and a link to the student's progress page.
-- See docs/features/sending-emails.md. Safe to run more than once.

create or replace function public.progress_notice_emails_claim(p_limit integer default 50)
returns table (id uuid, email text, first_name text, subject text, body text, link text)
language sql security definer
set search_path = ''
as $$
  with due as (
    select n.id
    from public.progress_notices n
    join public.account_private ap on ap.account_id = n.account_id
    left join public.notice_settings ns on ns.account_id = n.account_id
    where n.email_sent_at is null
      and n.deliver_at <= now()
      and n.deliver_at > now() - interval '12 hours'
      and coalesce(ns.by_email, true)
    order by n.deliver_at
    limit least(greatest(p_limit, 1), 100)
    for update of n skip locked
  )
  update public.progress_notices n
  set email_sent_at = now()
  from due, public.account_private ap, public.accounts a
  where n.id = due.id and ap.account_id = n.account_id and a.id = n.account_id
  returning n.id, ap.email, private.first_name(a.full_name), n.title, n.body,
            '/students/' || n.student_id::text || '/progress'
$$;
revoke all on function public.progress_notice_emails_claim(integer) from public, anon, authenticated;
grant execute on function public.progress_notice_emails_claim(integer) to service_role;

create or replace function public.progress_notice_emails_release(p_ids uuid[])
returns void language sql security definer
set search_path = ''
as $$
  update public.progress_notices set email_sent_at = null
  where id = any (p_ids) and email_sent_at > now() - interval '1 hour'
$$;
revoke all on function public.progress_notice_emails_release(uuid[]) from public, anon, authenticated;
grant execute on function public.progress_notice_emails_release(uuid[]) to service_role;
