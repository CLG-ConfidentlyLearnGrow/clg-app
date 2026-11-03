-- Leaving reasons (shared core), drafting prices and admin hours due date
-- (module: billing). Carla, 2 Nov 2026.
--
-- * When a family or a tutor leaves CLG, an admin records why, so CLG can
--   see patterns over time. For a family leaving happy, the record notes
--   whether they were asked for a testimonial or Google review.
-- * Assessment drafting: $90 per hour for school students and $110 per
--   hour for tertiary students, both GST-free. (Session prices stay $95
--   school and $115 tertiary, confirmed.) Drafting is invoiced separately
--   from ongoing tutoring, so these prices aren't tied to sessions.
-- * Admin hours for a pay week are due by the day after the pay week ends.
--   Late entries can still be logged (people must be paid for time worked)
--   but are flagged for the admin who approves them.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Leaving reasons
-- ---------------------------------------------------------------------------
create table if not exists public.leaving_records (
  id uuid primary key default gen_random_uuid(),
  who text not null check (who in ('family', 'tutor')),
  family_id uuid references public.families (id) on delete cascade,
  tutor_id uuid references public.tutor_profiles (account_id) on delete cascade,
  left_on date not null,
  reason text not null check (reason in (
    'goals_met', 'finished_study', 'cost', 'timing', 'tutor_fit', 'other_provider', 'moved',
    'own_study_or_work', 'pay', 'hours', 'workload', 'personal', 'other'
  )),
  details text check (char_length(details) <= 2000),
  left_happy boolean,
  review_asked boolean not null default false,
  recorded_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  check ((who = 'family') = (family_id is not null) and (who = 'tutor') = (tutor_id is not null))
);
create index if not exists leaving_records_left on public.leaving_records (left_on desc);

alter table public.leaving_records enable row level security;
revoke all on public.leaving_records from anon;
revoke insert, update, delete, truncate on public.leaving_records from authenticated;
drop trigger if exists audit on public.leaving_records;
create trigger audit after insert or update or delete on public.leaving_records
  for each row execute function private.audit_change();

drop policy if exists "admins see leaving records" on public.leaving_records;
create policy "admins see leaving records" on public.leaving_records
  for select to authenticated using (private.is_admin());

create or replace function public.record_leaving(
  p_who text,
  p_family uuid,
  p_tutor uuid,
  p_left_on date,
  p_reason text,
  p_details text default null,
  p_left_happy boolean default null,
  p_review_asked boolean default false
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.is_admin() then
    raise exception 'Only CLG admins record why someone left' using errcode = '42501';
  end if;
  if p_who not in ('family', 'tutor') then
    raise exception 'Choose a family or a tutor' using errcode = '22023';
  end if;
  if (p_who = 'family' and p_family is null) or (p_who = 'tutor' and p_tutor is null) then
    raise exception 'Choose who left' using errcode = '22023';
  end if;
  if p_left_on is null then
    raise exception 'Enter the date they left' using errcode = '22023';
  end if;
  insert into public.leaving_records (who, family_id, tutor_id, left_on, reason, details, left_happy, review_asked, recorded_by)
  values (p_who, case when p_who = 'family' then p_family end, case when p_who = 'tutor' then p_tutor end,
          p_left_on, p_reason, nullif(left(trim(p_details), 2000), ''), p_left_happy, coalesce(p_review_asked, false), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.record_leaving(text, uuid, uuid, date, text, text, boolean, boolean) from public, anon;
grant execute on function public.record_leaving(text, uuid, uuid, date, text, text, boolean, boolean) to authenticated;

create or replace function public.list_leaving_records()
returns table (id uuid, who text, name text, left_on date, reason text, details text, left_happy boolean, review_asked boolean)
language sql stable security definer
set search_path = ''
as $$
  select r.id, r.who,
         coalesce(f.name, a.full_name, 'Removed'),
         r.left_on, r.reason, r.details, r.left_happy, r.review_asked
  from public.leaving_records r
  left join public.families f on f.id = r.family_id
  left join public.accounts a on a.id = r.tutor_id
  where private.is_admin()
  order by r.left_on desc, r.created_at desc
$$;
revoke all on function public.list_leaving_records() from public, anon;
grant execute on function public.list_leaving_records() to authenticated;

-- ---------------------------------------------------------------------------
-- Assessment drafting prices
-- ---------------------------------------------------------------------------
insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, description) values
  ('drafting_school', 'Assessment drafting (school)', 'hour', 9000, false,
   'Feedback on a school student''s assessment draft. GST-free. Invoiced separately from ongoing tutoring.'),
  ('drafting_tertiary', 'Assessment drafting (tertiary)', 'hour', 11000, false,
   'Feedback on a TAFE or university assessment draft. GST-free. Invoiced separately from ongoing tutoring.')
on conflict (code) do update set amount_cents = excluded.amount_cents, gst_applies = false;

-- ---------------------------------------------------------------------------
-- Admin hours: due the day after the pay week ends
-- ---------------------------------------------------------------------------
alter table public.billing_hour_logs add column if not exists logged_late boolean not null default false;

-- The last day to log hours worked on a day: the day after its pay period ends.
create or replace function public.billing_hours_due_by(p_day date)
returns date language sql stable security definer
set search_path = ''
as $$
  select (select period_end from public.billing_pay_period(p_day)) + 1
$$;
revoke all on function public.billing_hours_due_by(date) from public, anon;
grant execute on function public.billing_hours_due_by(date) to authenticated;

create or replace function private.flag_late_hours()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  new.logged_late := private.billing_today() > public.billing_hours_due_by(new.work_date);
  return new;
end;
$$;
drop trigger if exists flag_late on public.billing_hour_logs;
create trigger flag_late before insert on public.billing_hour_logs
  for each row execute function private.flag_late_hours();
