-- Billing (module: billing): tells tutors by email when a student's
-- sessions go on hold or come back on. No money details.
--
-- These notices aren't shown anywhere else, so they ignore the "email"
-- reminder setting: a tutor must hear about a pause. Quiet hours (8pm to
-- 8am Adelaide time) apply. Older than 3 days is not sent.
-- See docs/features/sending-emails.md. Safe to run more than once.

create or replace function public.billing_tutor_notice_emails_claim(p_limit integer default 50)
returns table (id uuid, email text, first_name text, subject text, body text, link text)
language sql security definer
set search_path = ''
as $$
  with due as (
    select n.id
    from public.billing_tutor_notices n
    join public.account_private ap on ap.account_id = n.tutor_id
    where n.sent_at is null
      and n.created_at > now() - interval '3 days'
      and private.outside_quiet_hours(n.created_at) <= now()
    order by n.created_at
    limit least(greatest(p_limit, 1), 100)
    for update of n skip locked
  )
  update public.billing_tutor_notices n
  set sent_at = now()
  from due, public.account_private ap, public.accounts a
  where n.id = due.id and ap.account_id = n.tutor_id and a.id = n.tutor_id
  returning n.id, ap.email, private.first_name(a.full_name),
    case n.kind
      when 'on_hold' then 'Sessions on hold: ' || coalesce((select private.first_name(s.full_name) from public.students s where s.id = n.student_id), 'a student')
      else 'Sessions back on: ' || coalesce((select private.first_name(s.full_name) from public.students s where s.id = n.student_id), 'a student')
    end,
    case n.kind
      when 'on_hold' then 'Sessions with ' || coalesce((select s.full_name from public.students s where s.id = n.student_id), 'this student')
        || ' are on hold for now. Please don''t run them until CLG tells you they are back on. Your schedule in the app shows what''s on.'
      else 'Sessions with ' || coalesce((select s.full_name from public.students s where s.id = n.student_id), 'this student')
        || ' are back on. Your schedule in the app shows the next session.'
    end,
    '/schedule'::text
$$;
revoke all on function public.billing_tutor_notice_emails_claim(integer) from public, anon, authenticated;
grant execute on function public.billing_tutor_notice_emails_claim(integer) to service_role;

create or replace function public.billing_tutor_notice_emails_release(p_ids uuid[])
returns void language sql security definer
set search_path = ''
as $$
  update public.billing_tutor_notices set sent_at = null
  where id = any (p_ids) and sent_at > now() - interval '1 hour'
$$;
revoke all on function public.billing_tutor_notice_emails_release(uuid[]) from public, anon, authenticated;
grant execute on function public.billing_tutor_notice_emails_release(uuid[]) to service_role;
