-- To-do counts across the app (Carla, 11 Nov 2026): a number on every tab
-- or menu item where something needs doing, e.g. "Matching (4)".
--
-- One call returns every count for the person viewing, so the side menus,
-- the dashboard tabs at the top (Admin, Tutor, Parent, Student) and the top
-- bar (Sessions, Matching) always agree.
--
-- Each row is (area, section, n). Areas and sections:
--   admin     families    parent links to confirm, possible double-ups
--             matching    student subjects waiting for a tutor
--             tutors      tutor checks waiting to be confirmed
--             progress    term reviews to check, session notes 48 hr+ late
--             curriculum  curriculum files waiting to be confirmed
--             staff       staff invitations that ran out unused
--             records     records due for deletion in 30 days, open privacy
--                         requests, open data breaches
--   billing   families    families on hold for an overdue invoice
--             invoices    invoices waiting for approval
--             pay         staff hours waiting for approval
--   privacy   requests    open privacy requests
--             incidents   open data breaches
--   tutor     students    session notes to write, term reviews to write,
--                         new uploads from families
--             teaching    "What you teach" not filled in yet
--             checks      child safety checks missing, expiring or expired
--   parent    children    children whose details need finishing
--   student   learning    roadmap steps past their due date
--   family    billing     plan to choose, terms to agree, automatic payment
--                         to set up
--   sessions  bookings, notices, next-term, booking-length, libraries
--                         (the same numbers as the Sessions page menu)
-- Rows can be 0; the app shows no number then.
--
-- Runs as the person viewing (security invoker), so row level security
-- decides what is counted: nobody sees a number for data they can't open.
-- Every check that only some admins may see is also guarded here.
--
-- Needs 20261111600800_action_counts.sql. Safe to run more than once.

create or replace function public.to_do_counts()
returns table (area text, section text, n integer)
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_desk boolean := private.is_front_desk();
  v_admin boolean := private.is_admin();
  v_finance boolean := private.is_finance_admin();
  v_tutor boolean := private.has_role('tutor');
  v_parent boolean := private.has_role('parent');
  v_student boolean := private.has_role('student');
  v_sched jsonb;
  v_requests integer;
  v_incidents integer;
begin
  if v_me is null then
    return;
  end if;

  -- Scheduling counts from the scheduling module, read once.
  select coalesce(jsonb_object_agg(c.key, c.n), '{}'::jsonb)
    into v_sched
  from public.scheduling_counts() c;

  -- Admin: Families and Matching (front desk: owner, operations, support).
  if v_desk then
    area := 'admin'; section := 'families';
    n := (select count(*) from public.parent_student_links where verified_at is null)
       + (select count(*) from public.admin_possible_duplicate_children());
    return next;
    area := 'admin'; section := 'matching'; n := coalesce((v_sched ->> 'matching')::integer, 0);
    return next;
  end if;

  -- Admin: the rest of the admin menu (owner and operations).
  if v_admin then
    area := 'admin'; section := 'tutors';
    n := (select count(*) from public.tutor_checks where verified_at is null and declined_at is null);
    return next;

    area := 'admin'; section := 'progress';
    n := (select count(*) from public.term_reviews where status = 'submitted')
       + (select count(*) from public.list_notes_due() d where d.hours_since_end >= 48);
    return next;

    area := 'admin'; section := 'curriculum';
    n := (select count(*) from public.curriculum_frameworks where active and confirmed_at is null);
    return next;

    area := 'admin'; section := 'staff';
    n := (select count(*) from public.invitations where accepted_at is null and expires_at < now());
    return next;

    v_requests := (select count(*) from public.privacy_requests where closed_at is null);
    v_incidents := (select count(*) from public.privacy_incidents where closed_at is null);
    area := 'privacy'; section := 'requests'; n := v_requests;
    return next;
    area := 'privacy'; section := 'incidents'; n := v_incidents;
    return next;
    area := 'admin'; section := 'records';
    n := (select count(*) from public.upcoming_deletions(30)) + v_requests + v_incidents;
    return next;
  end if;

  -- Billing (owner, operations and finance).
  if v_finance then
    area := 'billing'; section := 'families';
    n := (select count(*) from public.billing_accounts where paused);
    return next;
    area := 'billing'; section := 'invoices';
    n := (select count(*) from public.billing_invoices where status in ('draft', 'awaiting_approval'));
    return next;
    area := 'billing'; section := 'pay';
    n := (select count(*) from public.billing_hour_logs where status = 'submitted');
    return next;
  end if;

  -- Tutor dashboard: only the tutor's own work.
  if v_tutor then
    area := 'tutor'; section := 'students';
    n := (select count(*) from public.list_notes_due() d where d.tutor_id = v_me)
       + (select count(*) from public.term_reviews r
          where r.tutor_id = v_me and r.status in ('draft', 'returned'))
       + (select count(*) from public.progress_notices p
          where p.account_id = v_me and p.kind = 'evidence_added' and p.read_at is null);
    return next;
    area := 'tutor'; section := 'teaching';
    n := case when exists (select 1 from public.tutor_teaching where tutor_id = v_me) then 0 else 1 end;
    return next;
    area := 'tutor'; section := 'checks';
    n := (select count(*) from public.tutor_check_status where tutor_id = v_me and status <> 'current');
    return next;
  end if;

  -- Parent dashboard: their own children with details still to give
  -- (the same list as "Please finish ... details" on the dashboard).
  if v_parent then
    area := 'parent'; section := 'children';
    n := (select count(*) from public.students s
          where private.is_parent_of(s.id)
            and (s.date_of_birth is null or s.state is null or s.year_level is null
                 or s.school is null or s.goals is null
                 or not exists (select 1 from public.student_subjects ss where ss.student_id = s.id)));
    return next;
  end if;

  -- Student dashboard: their own roadmap steps that are overdue.
  if v_student then
    area := 'student'; section := 'learning';
    n := (select count(*) from public.roadmap_steps rs
          join public.students s on s.id = rs.student_id
          where s.account_id = v_me and rs.done_at is null
            and rs.due_on < (now() at time zone 'Australia/Adelaide')::date);
    return next;
  end if;

  -- Family billing, for whoever pays for a family (parent or adult learner).
  area := 'family'; section := 'billing';
  n := (select count(*) from public.billing_my_plan_choices() c where not c.chosen and c.can_change)
     + (select count(*) from public.billing_accounts b
        where private.is_family_payer(b.family_id) and b.terms_accepted_at is null)
     + (select count(*) from public.billing_accounts b
        where private.is_family_payer(b.family_id)
          and not coalesce(
            (select p.payment_ready from public.billing_payers p
             where p.family_id = b.family_id and p.account_id = v_me),
            b.payment_ready));
  return next;

  -- Sessions page menu (the same rules as the page itself).
  area := 'sessions'; section := 'bookings';
  n := (select count(*) from public.list_bookings() lb
        join public.bookings b on b.id = lb.id
        where lb.status = 'requested' and not lb.expired
          and ((lb.tutor_id = v_me and b.tutor_ok_at is null)
               or (not v_desk and b.needs_family_ok and b.family_ok_at is null and lb.tutor_id <> v_me)));
  return next;
  area := 'sessions'; section := 'notices';
  n := (select count(*) from public.session_notices
        where account_id = v_me and read_at is null and deliver_at <= now());
  return next;
  if v_desk or v_parent or v_student then
    area := 'sessions'; section := 'next-term';
    n := (select count(*) from public.term_renewals where answered_at is null);
    return next;
    area := 'sessions'; section := 'booking-length';
    n := coalesce((v_sched ->> 'booking-length')::integer, 0);
    return next;
  end if;
  if v_admin then
    area := 'sessions'; section := 'libraries';
    n := coalesce((v_sched ->> 'libraries')::integer, 0);
    return next;
  end if;
end;
$$;
revoke all on function public.to_do_counts() from public, anon;
grant execute on function public.to_do_counts() to authenticated;
