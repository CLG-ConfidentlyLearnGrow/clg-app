-- Billing part 9 (module: billing): tutoring work hours and guaranteed hours.
--
-- Carla (2026-11-05):
--   * Work tied to tutoring that isn't a session (making materials, lesson
--     prep, tutoring admin) is part of the tutor role, paid at the tutor's
--     rate. When staff log hours they choose "Tutoring work (not sessions)"
--     or "Office admin". Only people with the admin role can log office
--     admin. Every entry needs a short description.
--   * Part-time and full-time staff have agreed weekly hours. If sessions
--     plus logged hours fall short in a pay period (for example in the
--     school holidays), the app adds a "guaranteed hours" top-up for an
--     admin to approve before it goes to Xero.
--
-- Safe to run more than once. Run after 20261103000700_leaving_prices_hours.sql.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

-- What kind of hours: tutoring work (tutor rate) or office admin (admin rate).
alter table public.billing_hour_logs add column if not exists work_type text not null default 'admin';
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_work_type_check;
alter table public.billing_hour_logs add constraint billing_hour_logs_work_type_check check (work_type in ('tutoring', 'admin'));

-- staff: logged by the person. guaranteed: added by the app as a top-up.
alter table public.billing_hour_logs add column if not exists source text not null default 'staff';
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_source_check;
alter table public.billing_hour_logs add constraint billing_hour_logs_source_check check (source in ('staff', 'guaranteed'));
alter table public.billing_hour_logs add column if not exists period_start date;

-- A top-up can be longer than one day's work (a whole quiet pay week).
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_minutes_check;
alter table public.billing_hour_logs add constraint billing_hour_logs_minutes_check
  check (minutes > 0 and (source = 'guaranteed' or minutes between 15 and 720));

-- One top-up per person per pay period (a declined one isn't made again).
create unique index if not exists billing_hour_logs_one_top_up
  on public.billing_hour_logs (account_id, period_start) where source = 'guaranteed';

-- Agreed hours per week for part-time and full-time staff.
alter table public.billing_staff_pay add column if not exists guaranteed_weekly_minutes int;
alter table public.billing_staff_pay drop constraint if exists billing_staff_pay_guaranteed_check;
alter table public.billing_staff_pay add constraint billing_staff_pay_guaranteed_check
  check (guaranteed_weekly_minutes is null or guaranteed_weekly_minutes between 15 and 3600);
grant insert (guaranteed_weekly_minutes) on public.billing_staff_pay to authenticated;
grant update (guaranteed_weekly_minutes) on public.billing_staff_pay to authenticated;

-- Pay lines for the two new kinds of hours.
alter table public.billing_pay_lines drop constraint if exists billing_pay_lines_kind_check;
alter table public.billing_pay_lines add constraint billing_pay_lines_kind_check
  check (kind in ('session', 'late_cancel', 'min_topup', 'admin', 'tutoring_work', 'guaranteed'));

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.account_has_role(p_account uuid, p_role text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.account_roles r where r.account_id = p_account and r.role::text = p_role)
$$;
revoke all on function private.account_has_role(uuid, text) from public, anon, authenticated;

-- The tutor rate for tutoring work: the school rate, or the tertiary rate
-- for someone who only tutors tertiary.
create or replace function private.billing_tutoring_kind(p_account uuid)
returns text language sql stable security definer
set search_path = ''
as $$
  select case
    when private.billing_pay_rate(p_account, 'school') is not null then 'school'
    when private.billing_pay_rate(p_account, 'tertiary') is not null then 'tertiary'
  end
$$;
revoke all on function private.billing_tutoring_kind(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Logging hours
-- ---------------------------------------------------------------------------

-- The old three-part version is replaced by one that says the kind of hours.
drop function if exists public.billing_log_my_hours(date, int, text);

create or replace function public.billing_log_my_hours(p_day date, p_minutes int, p_note text, p_type text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v uuid;
begin
  if auth.uid() is null or not private.has_aal2() then
    raise exception 'Please sign in with two-step login to log hours' using errcode = '42501';
  end if;
  if p_type = 'admin' then
    if not private.account_has_role(auth.uid(), 'admin') then
      raise exception 'Only CLG admin staff can log office admin hours. Choose tutoring work instead' using errcode = '42501';
    end if;
    if private.billing_pay_rate(auth.uid(), 'admin') is null then
      raise exception 'CLG hasn''t set an admin pay rate for you yet' using errcode = '42501';
    end if;
  elsif p_type = 'tutoring' then
    if not private.account_has_role(auth.uid(), 'tutor') then
      raise exception 'Only tutors can log tutoring work' using errcode = '42501';
    end if;
    if private.billing_tutoring_kind(auth.uid()) is null then
      raise exception 'CLG hasn''t set a tutoring pay rate for you yet' using errcode = '42501';
    end if;
  else
    raise exception 'Choose tutoring work or office admin' using errcode = '22023';
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
    raise exception 'Please write a short description of what you did' using errcode = '22023';
  end if;
  insert into public.billing_hour_logs (account_id, work_date, minutes, note, work_type)
  values (auth.uid(), p_day, p_minutes, left(trim(p_note), 300), p_type)
  returning id into v;
  return v;
end;
$$;

-- Staff can take back their own entries, but not an app-made top-up.
create or replace function public.billing_withdraw_my_hours(p_log uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not private.has_aal2() then
    raise exception 'Please sign in with two-step login' using errcode = '42501';
  end if;
  delete from public.billing_hour_logs
  where id = p_log and account_id = auth.uid() and status = 'submitted' and source = 'staff';
  if not found then
    raise exception 'Only hours still waiting for approval can be taken back' using errcode = '22023';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Approving hours (owner or Finance admin)
-- ---------------------------------------------------------------------------

create or replace function public.billing_review_hours(p_log uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v public.billing_hour_logs;
  v_kind text;
  v_line_kind text;
  v_rate int;
  v_line uuid;
begin
  if not private.is_pay_admin() then
    raise exception 'Only the owner or a Finance admin can approve hours' using errcode = '42501';
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

  v_kind := case when v.work_type = 'tutoring' then private.billing_tutoring_kind(v.account_id) else 'admin' end;
  v_line_kind := case when v.source = 'guaranteed' then 'guaranteed'
                      when v.work_type = 'tutoring' then 'tutoring_work'
                      else 'admin' end;
  v_rate := case when v_kind is null then null else private.billing_pay_rate(v.account_id, v_kind) end;
  if v_rate is null then
    raise exception 'Enter a % pay rate for this person first', case when v.work_type = 'tutoring' then 'tutoring' else 'admin' end
      using errcode = '22023';
  end if;
  insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents, under_award, note, created_by)
  select v.account_id, a.full_name, v.work_date, v_line_kind, v_kind, v.minutes, v_rate,
         round(v_rate * v.minutes / 60.0)::int,
         private.billing_under_award(v.account_id, v_kind, v_rate, v.work_date),
         v.note, auth.uid()
  from public.accounts a where a.id = v.account_id
  returning id into v_line;
  update public.billing_hour_logs
  set status = 'approved', review_note = nullif(left(trim(coalesce(p_note, '')), 300), ''),
      reviewed_by = auth.uid(), reviewed_at = now(), pay_line_id = v_line
  where id = p_log;
end;
$$;

-- ---------------------------------------------------------------------------
-- Guaranteed hours top-ups
-- ---------------------------------------------------------------------------

-- For the pay period containing p_day (once it has ended): each part-time
-- or full-time person with agreed weekly hours who worked less gets a
-- top-up entry waiting for approval. Counts pay lines plus hours still
-- waiting for approval. Returns how many top-ups were added.
create or replace function public.billing_check_guaranteed_hours(p_day date)
returns int language plpgsql security definer
set search_path = ''
as $$
declare
  v_start date;
  v_end date;
  r record;
  v_expected int;
  v_worked int;
  v_id uuid;
  n int := 0;
begin
  if not (private.is_backend() or private.is_pay_admin()) then
    raise exception 'Only the owner or a Finance admin can do this' using errcode = '42501';
  end if;
  select period_start, period_end into v_start, v_end from public.billing_pay_period(p_day);
  if v_end >= private.billing_today() then
    return 0; -- the pay period hasn't finished yet
  end if;

  for r in
    select sp.account_id, sp.guaranteed_weekly_minutes
    from public.billing_staff_pay sp
    where sp.guaranteed_weekly_minutes is not null
      and sp.employment in ('part_time', 'full_time')
      and not exists (
        select 1 from public.billing_hour_logs h
        where h.account_id = sp.account_id and h.source = 'guaranteed' and h.period_start = v_start
      )
  loop
    v_expected := round(r.guaranteed_weekly_minutes * (v_end - v_start + 1) / 7.0)::int;
    v_worked := coalesce((
        select sum(l.minutes) from public.billing_pay_lines l
        where l.account_id = r.account_id and l.work_date between v_start and v_end
      ), 0) + coalesce((
        select sum(h.minutes) from public.billing_hour_logs h
        where h.account_id = r.account_id and h.work_date between v_start and v_end
          and h.status = 'submitted' and h.source = 'staff'
      ), 0);
    if v_expected - v_worked >= 15 then
      insert into public.billing_hour_logs (account_id, work_date, minutes, note, work_type, source, period_start)
      values (
        r.account_id, v_end, v_expected - v_worked,
        format('Guaranteed hours top-up: agreed %s hr, worked or logged %s hr this pay period',
               round(v_expected / 60.0, 2), round(v_worked / 60.0, 2)),
        case when private.account_has_role(r.account_id, 'tutor') and private.billing_tutoring_kind(r.account_id) is not null
             then 'tutoring' else 'admin' end,
        'guaranteed', v_start
      )
      on conflict do nothing
      returning id into v_id;
      if v_id is not null then
        update public.billing_hour_logs set logged_late = false where id = v_id;
        n := n + 1;
      end if;
    end if;
  end loop;
  return n;
end;
$$;

revoke all on function public.billing_log_my_hours(date, int, text, text) from public, anon;
revoke all on function public.billing_withdraw_my_hours(uuid) from public, anon;
revoke all on function public.billing_review_hours(uuid, boolean, text) from public, anon;
revoke all on function public.billing_check_guaranteed_hours(date) from public, anon;
grant execute on function public.billing_log_my_hours(date, int, text, text) to authenticated;
grant execute on function public.billing_withdraw_my_hours(uuid) to authenticated;
grant execute on function public.billing_review_hours(uuid, boolean, text) to authenticated;
grant execute on function public.billing_check_guaranteed_hours(date) to authenticated, service_role;
