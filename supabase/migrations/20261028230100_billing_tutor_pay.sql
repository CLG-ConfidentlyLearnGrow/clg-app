-- Billing part 2 (module: billing): tutor and staff pay.
--
-- Turns the sessions tutors worked (as confirmed by scheduling's sign on and
-- sign off) into pay lines, one per session, plus admin hours. Each week's
-- lines go to Xero Payroll as a draft timesheet for Carla to approve.
--
-- Carla's rules (2026-10-26):
--   * Up to three hourly rates per person: school tutoring, tertiary and
--     other tutoring, admin. Admins enter them.
--   * Paid for time worked (scheduling's worked_from and worked_to). Student
--     late: paid in full. Tutor late without making it up: time worked.
--   * Family (or CLG) cancels late (24 hr or less) or the student doesn't show, before the tutor
--     has signed on: 50% of the session or 1 hr, whichever is less.
--     After the tutor has signed on: the time they had to be there.
--   * Tutor cancels: no pay for that session.
--   * Casual staff: at least 2 hr pay for each day they attend work, online
--     too (Miscellaneous Award cl 11.2, Post-Secondary Award cl 11.4). The
--     app tops up a short day; paid admin time counts towards it.
--   * Award minimum rates are settings, updated each 1 July; any rate under
--     them is flagged for the owner. Seeded from the 1 July 2026 figures; an
--     employment adviser should confirm the levels.
--
-- Billing reads sessions and never writes them. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Pay settings per person
-- ---------------------------------------------------------------------------
create table if not exists public.billing_staff_pay (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  employment text not null default 'casual' check (employment in ('casual', 'part_time', 'full_time')),
  school_rate_cents int check (school_rate_cents is null or school_rate_cents between 0 and 100000),
  tertiary_rate_cents int check (tertiary_rate_cents is null or tertiary_rate_cents between 0 and 100000),
  admin_rate_cents int check (admin_rate_cents is null or admin_rate_cents between 0 and 100000),
  -- Xero Payroll references: the employee and an earnings rate for each kind.
  xero_employee_id text,
  xero_school_rate_id text,
  xero_tertiary_rate_id text,
  xero_admin_rate_id text,
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Award minimum hourly rates (adult), by kind of work and employment type.
create table if not exists public.billing_award_rates (
  work_kind text not null check (work_kind in ('school', 'tertiary', 'admin')),
  employment text not null check (employment in ('casual', 'part_time', 'full_time')),
  min_rate_cents int not null check (min_rate_cents >= 0),
  award text not null check (char_length(award) <= 200),
  effective_from date not null,
  primary key (work_kind, employment, effective_from)
);
insert into public.billing_award_rates (work_kind, employment, min_rate_cents, award, effective_from) values
  ('school', 'casual', 3218, 'Miscellaneous Award MA000104, Level 1 casual', '2026-07-01'),
  ('school', 'part_time', 2574, 'Miscellaneous Award MA000104, Level 1', '2026-07-01'),
  ('school', 'full_time', 2574, 'Miscellaneous Award MA000104, Level 1', '2026-07-01'),
  ('tertiary', 'casual', 6288, 'Post-Secondary Award MA000075, tutor/instructor casual', '2026-07-01'),
  ('tertiary', 'part_time', 3312, 'Post-Secondary Award MA000075, tutor/instructor', '2026-07-01'),
  ('tertiary', 'full_time', 3312, 'Post-Secondary Award MA000075, tutor/instructor', '2026-07-01'),
  ('admin', 'casual', 3371, 'Clerks Award MA000002, Level 1 Year 1 casual', '2026-07-01'),
  ('admin', 'part_time', 2697, 'Clerks Award MA000002, Level 1 Year 1', '2026-07-01'),
  ('admin', 'full_time', 2697, 'Clerks Award MA000002, Level 1 Year 1', '2026-07-01')
on conflict do nothing;

-- Pay rules that may change.
alter table public.billing_settings add column if not exists casual_min_minutes int not null default 120;
alter table public.billing_settings add column if not exists late_cancel_pay_share numeric(4, 3) not null default 0.5;
alter table public.billing_settings add column if not exists late_cancel_pay_cap_minutes int not null default 60;
-- CLG's pay period in Xero Payroll: its length and any day it starts on.
-- Must match the payroll calendar in Xero (weekly from a Monday by default).
alter table public.billing_settings add column if not exists pay_period_days int not null default 7
  check (pay_period_days in (7, 14));
alter table public.billing_settings add column if not exists pay_period_anchor date not null default '2026-09-07';

-- The pay period a day falls in.
create or replace function public.billing_pay_period(p_day date, out period_start date, out period_end date)
language sql stable
set search_path = ''
as $$
  select p_day - (((p_day - s.pay_period_anchor) % s.pay_period_days + s.pay_period_days) % s.pay_period_days),
         p_day - (((p_day - s.pay_period_anchor) % s.pay_period_days + s.pay_period_days) % s.pay_period_days) + s.pay_period_days - 1
  from public.billing_settings s
$$;

-- ---------------------------------------------------------------------------
-- Pay lines
-- ---------------------------------------------------------------------------
create table if not exists public.billing_pay_lines (
  id uuid primary key default gen_random_uuid(),
  account_id uuid references public.accounts (id) on delete set null,
  staff_name text not null,
  work_date date not null,
  -- session: time worked. late_cancel: CLG's late cancel or no-show pay.
  -- min_topup: casual 2 hr minimum. admin: admin hours.
  kind text not null check (kind in ('session', 'late_cancel', 'min_topup', 'admin')),
  work_kind text not null check (work_kind in ('school', 'tertiary', 'admin')),
  session_id uuid references public.sessions (id) on delete set null,
  minutes int not null check (minutes > 0),
  rate_cents int not null check (rate_cents >= 0),
  amount_cents int not null check (amount_cents >= 0),
  -- Rate below the award minimum for this person's employment type.
  under_award boolean not null default false,
  note text check (char_length(note) <= 300),
  -- pending: worked out, not yet in Xero. sent: in a draft Xero timesheet.
  status text not null default 'pending' check (status in ('pending', 'sent')),
  xero_timesheet_id text,
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists billing_pay_lines_person on public.billing_pay_lines (account_id, work_date);
create unique index if not exists billing_pay_lines_session_once
  on public.billing_pay_lines (session_id, kind) where session_id is not null;
create unique index if not exists billing_pay_lines_topup_once
  on public.billing_pay_lines (account_id, work_date) where kind = 'min_topup';

-- Days with a confirmed time problem that payroll waits on, for admins to
-- sort out (for example a rate not entered yet).
create or replace view public.billing_pay_problems
with (security_invoker = true) as
select se.id as session_id, se.tutor_id as account_id, a.full_name,
       (se.starts_at at time zone 'Australia/Adelaide')::date as work_date,
       'No ' || se.level_kind || ' pay rate entered yet' as problem
from public.sessions se
join public.accounts a on a.id = se.tutor_id
left join public.billing_staff_pay p on p.account_id = se.tutor_id
where se.status::text in ('completed', 'no_show', 'cancelled')
  and se.starts_at > now() - interval '60 days'
  and (case se.level_kind when 'tertiary' then p.tertiary_rate_cents else p.school_rate_cents end) is null;

alter table public.billing_staff_pay enable row level security;
alter table public.billing_award_rates enable row level security;
alter table public.billing_pay_lines enable row level security;
revoke all on public.billing_staff_pay, public.billing_award_rates, public.billing_pay_lines from anon;
revoke all on public.billing_pay_problems from anon;

-- Staff see their own pay; admins see and set everyone's.
drop policy if exists "own pay settings, admins all" on public.billing_staff_pay;
create policy "own pay settings, admins all" on public.billing_staff_pay
  for select to authenticated using (private.is_admin() or (account_id = auth.uid() and private.has_aal2()));
drop policy if exists "admins set pay" on public.billing_staff_pay;
create policy "admins set pay" on public.billing_staff_pay
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists "admins read award rates" on public.billing_award_rates;
create policy "admins read award rates" on public.billing_award_rates
  for select to authenticated using (private.is_admin());
drop policy if exists "owner sets award rates" on public.billing_award_rates;
create policy "owner sets award rates" on public.billing_award_rates
  for all to authenticated using (private.is_owner()) with check (private.is_owner());

drop policy if exists "own pay lines, admins all" on public.billing_pay_lines;
create policy "own pay lines, admins all" on public.billing_pay_lines
  for select to authenticated using (private.is_admin() or (account_id = auth.uid() and private.has_aal2()));
revoke insert, update, delete on public.billing_pay_lines from authenticated;

drop trigger if exists audit on public.billing_staff_pay;
create trigger audit after insert or update or delete on public.billing_staff_pay
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_award_rates;
create trigger audit after insert or update or delete on public.billing_award_rates
  for each row execute function private.audit_change();

create or replace function private.stamp_staff_pay()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists stamp on public.billing_staff_pay;
create trigger stamp before insert or update on public.billing_staff_pay
  for each row execute function private.stamp_staff_pay();

-- ---------------------------------------------------------------------------
-- Pay rules
-- ---------------------------------------------------------------------------

-- A person's rate for a kind of work, or null if not entered.
create or replace function private.billing_pay_rate(p_account uuid, p_kind text)
returns int language sql stable security definer
set search_path = ''
as $$
  select case p_kind
    when 'tertiary' then tertiary_rate_cents
    when 'admin' then admin_rate_cents
    else school_rate_cents end
  from public.billing_staff_pay where account_id = p_account
$$;

-- Is this rate under the award minimum in force on that day?
create or replace function private.billing_under_award(p_account uuid, p_kind text, p_rate int, p_day date)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select coalesce(p_rate < (
    select r.min_rate_cents from public.billing_award_rates r
    where r.work_kind = p_kind
      and r.employment = coalesce((select employment from public.billing_staff_pay where account_id = p_account), 'casual')
      and r.effective_from <= p_day
    order by r.effective_from desc limit 1
  ), false)
$$;

-- Adds one pay line, with its rate and award check. Skips quietly if the
-- person has no rate for that kind of work yet (billing_pay_problems lists
-- those) or the line is already there.
create or replace function private.billing_add_pay_line(
  p_account uuid, p_day date, p_kind text, p_work_kind text, p_session uuid, p_minutes int, p_note text
)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_rate int := private.billing_pay_rate(p_account, p_work_kind);
begin
  if v_rate is null or p_minutes <= 0 then
    return;
  end if;
  insert into public.billing_pay_lines (
    account_id, staff_name, work_date, kind, work_kind, session_id, minutes, rate_cents, amount_cents, under_award, note, created_by
  )
  select p_account, a.full_name, p_day, p_kind, p_work_kind, p_session, p_minutes, v_rate,
         round(v_rate * p_minutes / 60.0)::int,
         private.billing_under_award(p_account, p_work_kind, v_rate, p_day),
         left(p_note, 300), auth.uid()
  from public.accounts a where a.id = p_account
  on conflict do nothing;
end;
$$;
revoke all on function private.billing_add_pay_line(uuid, date, text, text, uuid, int, text) from public;

-- Works out pay lines for sessions between two days (Adelaide), then tops
-- up short days for casual staff. Lines already sent to Xero are never
-- changed; pending lines in the dates are rebuilt, so re-running after a
-- correction is safe. Returns the number of lines made.
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

  -- Casual 2 hr minimum for each day worked (sessions and admin hours).
  -- Late-cancel pay alone isn't a day at work.
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
    having sum(l.minutes) < s.casual_min_minutes
  loop
    perform private.billing_add_pay_line(r.account_id, r.work_date, 'min_topup', r.main_kind, null,
      s.casual_min_minutes - r.worked, 'Top-up to the 2 hr minimum for a casual day');
  end loop;

  select count(*) into n from public.billing_pay_lines
  where status = 'pending' and work_date between p_from and p_to;
  return n;
end;
$$;

-- An admin records admin hours for a staff member (for example Lauren's
-- admin time, or paid prep that fills a short day).
create or replace function public.billing_add_admin_time(p_account uuid, p_day date, p_minutes int, p_note text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v uuid;
begin
  if not private.is_admin() then
    raise exception 'Only admins can record admin hours' using errcode = '42501';
  end if;
  if p_minutes is null or p_minutes < 15 or p_minutes > 720 then
    raise exception 'Hours must be between 15 minutes and 12 hours' using errcode = '22023';
  end if;
  if p_day is null or p_day > private.billing_today() then
    raise exception 'Admin hours are recorded after they are worked' using errcode = '22023';
  end if;
  if private.billing_pay_rate(p_account, 'admin') is null then
    raise exception 'Enter an admin pay rate for this person first' using errcode = '22023';
  end if;
  insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents, under_award, note, created_by)
  select p_account, a.full_name, p_day, 'admin', 'admin', p_minutes, private.billing_pay_rate(p_account, 'admin'),
         round(private.billing_pay_rate(p_account, 'admin') * p_minutes / 60.0)::int,
         private.billing_under_award(p_account, 'admin', private.billing_pay_rate(p_account, 'admin'), p_day),
         nullif(left(trim(p_note), 300), ''), auth.uid()
  from public.accounts a where a.id = p_account
  returning id into v;
  if v is null then
    raise exception 'Unknown staff member' using errcode = '22023';
  end if;
  return v;
end;
$$;

-- Removes admin hours that haven't gone to Xero yet.
create or replace function public.billing_remove_pay_line(p_line uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  delete from public.billing_pay_lines where id = p_line and status = 'pending' and kind = 'admin';
  if not found then
    raise exception 'Only admin hours not yet sent to Xero can be removed' using errcode = '22023';
  end if;
end;
$$;

-- The server marks lines as sent once Xero has the timesheet.
create or replace function public.billing_mark_pay_sent(p_lines uuid[], p_timesheet text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_backend() then
    raise exception 'Only the server can do this' using errcode = '42501';
  end if;
  update public.billing_pay_lines set status = 'sent', xero_timesheet_id = p_timesheet
  where id = any(p_lines) and status = 'pending';
end;
$$;

revoke all on function public.billing_build_pay(date, date) from public, anon;
revoke all on function public.billing_add_admin_time(uuid, date, int, text) from public, anon;
revoke all on function public.billing_remove_pay_line(uuid) from public, anon;
revoke all on function public.billing_mark_pay_sent(uuid[], text) from public, anon, authenticated;
grant execute on function public.billing_build_pay(date, date) to authenticated, service_role;
grant execute on function public.billing_add_admin_time(uuid, date, int, text) to authenticated;
grant execute on function public.billing_remove_pay_line(uuid) to authenticated;
grant execute on function public.billing_mark_pay_sent(uuid[], text) to service_role;
