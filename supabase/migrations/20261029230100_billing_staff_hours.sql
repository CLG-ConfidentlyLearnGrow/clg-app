-- Billing part 6 (module: billing): staff log their own admin hours.
--
-- Carla (2026-10-29): admin staff log their hours in the app, so tutoring
-- and admin wages go to Xero Payroll together and are paid in one pay run.
--
--   * Anyone with an admin pay rate logs their own hours (day, hours, what
--     it was for) on their My pay page. Needs two-step login.
--   * An admin approves or declines each entry. Nobody approves their own
--     hours except the owner. (When admin levels arrive, approval will be
--     limited to the Owner and Finance levels.)
--   * An approved entry becomes an admin pay line, sent to Xero Payroll on
--     the same draft timesheet as the person's tutoring.
--
-- Safe to run more than once.

create table if not exists public.billing_hour_logs (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  work_date date not null,
  minutes int not null check (minutes between 15 and 720),
  note text not null check (char_length(trim(note)) between 3 and 300),
  status text not null default 'submitted' check (status in ('submitted', 'approved', 'declined')),
  review_note text check (char_length(review_note) <= 300),
  reviewed_by uuid references public.accounts (id) on delete set null,
  reviewed_at timestamptz,
  pay_line_id uuid references public.billing_pay_lines (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists billing_hour_logs_person on public.billing_hour_logs (account_id, work_date);
create index if not exists billing_hour_logs_waiting on public.billing_hour_logs (status) where status = 'submitted';

alter table public.billing_hour_logs enable row level security;
revoke all on public.billing_hour_logs from anon;

-- Staff see their own entries (with two-step login); admins see all.
-- Written only through the functions below.
drop policy if exists "own hour logs, admins all" on public.billing_hour_logs;
create policy "own hour logs, admins all" on public.billing_hour_logs
  for select to authenticated using (private.is_admin() or (account_id = auth.uid() and private.has_aal2()));
revoke insert, update, delete on public.billing_hour_logs from authenticated;

drop trigger if exists audit on public.billing_hour_logs;
create trigger audit after insert or update or delete on public.billing_hour_logs
  for each row execute function private.audit_change();

-- A staff member logs their own admin hours.
create or replace function public.billing_log_my_hours(p_day date, p_minutes int, p_note text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v uuid;
begin
  if auth.uid() is null or not private.has_aal2() then
    raise exception 'Please sign in with two-step login to log hours' using errcode = '42501';
  end if;
  if private.billing_pay_rate(auth.uid(), 'admin') is null then
    raise exception 'CLG hasn''t set an admin pay rate for you yet' using errcode = '42501';
  end if;
  if p_minutes is null or p_minutes < 15 or p_minutes > 720 then
    raise exception 'Hours must be between 15 minutes and 12 hours' using errcode = '22023';
  end if;
  if p_day is null or p_day > private.billing_today() then
    raise exception 'Hours are logged after they are worked' using errcode = '22023';
  end if;
  if p_day < private.billing_today() - 60 then
    raise exception 'Hours more than 60 days ago need to be added by CLG' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'Please say what the hours were for' using errcode = '22023';
  end if;
  insert into public.billing_hour_logs (account_id, work_date, minutes, note)
  values (auth.uid(), p_day, p_minutes, left(trim(p_note), 300))
  returning id into v;
  return v;
end;
$$;

-- A staff member takes back an entry that hasn't been looked at yet.
create or replace function public.billing_withdraw_my_hours(p_log uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not private.has_aal2() then
    raise exception 'Please sign in with two-step login' using errcode = '42501';
  end if;
  delete from public.billing_hour_logs
  where id = p_log and account_id = auth.uid() and status = 'submitted';
  if not found then
    raise exception 'Only hours still waiting for approval can be taken back' using errcode = '22023';
  end if;
end;
$$;

-- An admin approves (making an admin pay line) or declines logged hours.
create or replace function public.billing_review_hours(p_log uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v public.billing_hour_logs;
  v_rate int;
  v_line uuid;
begin
  if not private.is_admin() then
    raise exception 'Only admins can approve hours' using errcode = '42501';
  end if;
  select * into v from public.billing_hour_logs where id = p_log for update;
  if not found or v.status <> 'submitted' then
    raise exception 'These hours have already been dealt with' using errcode = '22023';
  end if;
  if v.account_id = auth.uid() and not private.is_owner() then
    raise exception 'Someone else needs to approve your own hours' using errcode = '42501';
  end if;
  if not p_approve then
    if char_length(trim(coalesce(p_note, ''))) < 3 then
      raise exception 'Please say why the hours are declined' using errcode = '22023';
    end if;
    update public.billing_hour_logs
    set status = 'declined', review_note = left(trim(p_note), 300), reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_log;
    return;
  end if;

  v_rate := private.billing_pay_rate(v.account_id, 'admin');
  if v_rate is null then
    raise exception 'Enter an admin pay rate for this person first' using errcode = '22023';
  end if;
  insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents, under_award, note, created_by)
  select v.account_id, a.full_name, v.work_date, 'admin', 'admin', v.minutes, v_rate,
         round(v_rate * v.minutes / 60.0)::int,
         private.billing_under_award(v.account_id, 'admin', v_rate, v.work_date),
         v.note, auth.uid()
  from public.accounts a where a.id = v.account_id
  returning id into v_line;
  update public.billing_hour_logs
  set status = 'approved', review_note = nullif(left(trim(coalesce(p_note, '')), 300), ''),
      reviewed_by = auth.uid(), reviewed_at = now(), pay_line_id = v_line
  where id = p_log;
end;
$$;

revoke all on function public.billing_log_my_hours(date, int, text) from public, anon;
revoke all on function public.billing_withdraw_my_hours(uuid) from public, anon;
revoke all on function public.billing_review_hours(uuid, boolean, text) from public, anon;
grant execute on function public.billing_log_my_hours(date, int, text) to authenticated;
grant execute on function public.billing_withdraw_my_hours(uuid) to authenticated;
grant execute on function public.billing_review_hours(uuid, boolean, text) to authenticated;
