-- Billing part 4 (module: billing): casual 2 hr top-up switched off for now.
--
-- Carla (2026-10-28): remove the casual 2 hr minimum for now, and reinstate
-- it next year. Instead of deleting the rule, it becomes an owner setting
-- that starts switched off. While it is off, short casual days are paid only
-- for the time worked, and the pay screen warns that the awards (Miscellaneous
-- Award cl 11.2, Post-Secondary Award cl 11.4) require at least 2 hr pay for
-- each day a casual attends work. The owner turns it back on under
-- Billing > Pay > Pay period and casual minimum.
--
-- Replaces billing_build_pay so the top-up only happens when switched on.
-- Safe to run more than once.

alter table public.billing_settings add column if not exists casual_min_enabled boolean not null default false;

-- Works out pay lines for sessions between two days (Adelaide), then tops
-- up short days for casual staff when switched on. Lines already sent to
-- Xero are never changed; pending lines in the dates are rebuilt, so
-- re-running after a correction is safe. Returns the number of lines made.
create or replace function public.billing_build_pay(p_from date, p_to date)
returns int language plpgsql security definer
set search_path = ''
as $$
declare
  s public.billing_settings;
  r record;
  n int;
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can work out pay' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 62 then
    raise exception 'Choose up to about two months at a time' using errcode = '22023';
  end if;
  select * into s from public.billing_settings;

  delete from public.billing_pay_lines
  where status = 'pending' and kind in ('session', 'late_cancel', 'min_topup')
    and work_date between p_from and p_to;

  for r in
    select se.*, (se.starts_at at time zone 'Australia/Adelaide')::date as day,
           round(extract(epoch from se.ends_at - se.starts_at) / 60)::int as booked_minutes,
           left(to_char(se.starts_at at time zone 'Australia/Adelaide', 'FMHH12:MIam') || ' '
                || split_part(trim(st.full_name), ' ', 1) || ', ' || se.subject, 200) as label
    from public.sessions se
    join public.students st on st.id = se.student_id
    where (se.starts_at at time zone 'Australia/Adelaide')::date between p_from and p_to
      and not exists (
        select 1 from public.billing_pay_lines l where l.session_id = se.id and l.status = 'sent'
      )
  loop
    if r.status::text = 'completed' and r.worked_from is not null and r.worked_to is not null then
      -- Time worked, as confirmed by sign on and sign off.
      perform private.billing_add_pay_line(r.tutor_id, r.day, 'session', r.level_kind, r.id,
        round(extract(epoch from r.worked_to - r.worked_from) / 60)::int, r.label);
    elsif r.status::text in ('no_show', 'cancelled') and r.signed_on_at is not null
          and coalesce(r.cancelled_by_role, 'family') <> 'tutor' then
      -- The tutor was already at work: paid for the time they had to be there.
      perform private.billing_add_pay_line(r.tutor_id, r.day, 'session', r.level_kind, r.id,
        coalesce(round(extract(epoch from r.worked_to - r.worked_from) / 60)::int, r.booked_minutes),
        r.label || ' (student didn''t come)');
    elsif r.status::text = 'no_show'
          or (r.status::text = 'cancelled' and r.cancelled_by_role in ('family', 'admin')
              and r.starts_at - r.cancelled_at <= make_interval(hours => s.full_credit_hours)) then
      -- Late cancel or no-show before the tutor signed on: CLG's own rule.
      perform private.billing_add_pay_line(r.tutor_id, r.day, 'late_cancel', r.level_kind, r.id,
        least(round(r.booked_minutes * s.late_cancel_pay_share)::int, s.late_cancel_pay_cap_minutes),
        r.label || ' (late cancel)');
    end if;
  end loop;

  -- Casual 2 hr minimum for each day worked (sessions and admin hours),
  -- when switched on. Late-cancel pay alone isn't a day at work.
  for r in
    select l.account_id, l.work_date, sum(l.minutes)::int as worked,
           (array_agg(l.work_kind order by l.minutes desc))[1] as main_kind
    from public.billing_pay_lines l
    join public.billing_staff_pay p on p.account_id = l.account_id and p.employment = 'casual'
    where l.work_date between p_from and p_to
      and l.kind in ('session', 'admin')
      and not exists (
        select 1 from public.billing_pay_lines t
        where t.account_id = l.account_id and t.work_date = l.work_date and t.kind = 'min_topup'
      )
    group by l.account_id, l.work_date
    having s.casual_min_enabled and sum(l.minutes) < s.casual_min_minutes
  loop
    perform private.billing_add_pay_line(r.account_id, r.work_date, 'min_topup', r.main_kind, null,
      s.casual_min_minutes - r.worked, 'Top-up to the 2 hr minimum for a casual day');
  end loop;

  select count(*) into n from public.billing_pay_lines
  where status = 'pending' and work_date between p_from and p_to;
  return n;
end;
$$;
revoke all on function public.billing_build_pay(date, date) from public, anon;
grant execute on function public.billing_build_pay(date, date) to authenticated, service_role;

-- Whether the casual 2 hr top-up is on, for staff to see on their pay page
-- (they can't read billing settings).
create or replace function public.billing_casual_min_on()
returns boolean language sql stable security definer
set search_path = ''
as $$ select casual_min_enabled from public.billing_settings $$;
revoke all on function public.billing_casual_min_on() from public, anon;
grant execute on function public.billing_casual_min_on() to authenticated;
