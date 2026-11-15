-- Billing part 11 (module: billing): pay for compulsory training.
--
-- Carla (16 Nov 2026):
--   * Each compulsory training module has a set time. When someone finishes
--     one, it becomes a "Training" hours entry waiting for approval, like
--     other logged hours.
--   * It counts towards agreed weekly hours, so in a short week it fills the
--     guaranteed-hours top-up first.
--   * It's paid at the rate of the job the training is for: tutor training
--     at the tutor rate, admin training at the admin rate. Training for
--     everyone is paid at the tutor rate for someone who tutors (their main
--     job, and the safer choice), otherwise at the admin rate.
--   * Optional modules aren't paid automatically.
--
-- Billing only reads training completions; it never changes them.
-- Safe to run more than once. Run after 20261116300100_training.sql.

-- ---------------------------------------------------------------------------
-- Columns and rules
-- ---------------------------------------------------------------------------

-- A third kind of hours entry: "training", added by the app from a completion.
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_source_check; -- removes the old list of kinds
alter table public.billing_hour_logs add constraint billing_hour_logs_source_check check (source in ('staff', 'guaranteed', 'training')); -- adds the list back with training

-- Training can be shorter than 15 minutes (a module's set time can be 5 minutes).
alter table public.billing_hour_logs drop constraint if exists billing_hour_logs_minutes_check; -- removes the old rule
alter table public.billing_hour_logs add constraint billing_hour_logs_minutes_check -- adds it back:
  check (minutes > 0 and (source in ('guaranteed', 'training') or minutes between 15 and 720)); -- staff entries stay 15 min to 12 hr

-- Which training completion an entry pays for (each one is paid once).
alter table public.billing_hour_logs add column if not exists training_completion_id uuid references public.training_completions (id) on delete set null; -- the completion
create unique index if not exists billing_hour_logs_training_once -- each completion only once
  on public.billing_hour_logs (training_completion_id) where training_completion_id is not null; -- (only rows that have one)

-- A new kind of pay line: training.
alter table public.billing_pay_lines drop constraint if exists billing_pay_lines_kind_check; -- removes the old list of kinds
alter table public.billing_pay_lines add constraint billing_pay_lines_kind_check -- adds the list back with "training" included
  check (kind in ('session', 'late_cancel', 'min_topup', 'admin', 'tutoring_work', 'guaranteed', 'summary', 'training')); -- every kind of pay line

-- ---------------------------------------------------------------------------
-- Which rate pays a person's training: 'tutoring' or 'admin'.
-- ---------------------------------------------------------------------------
create or replace function private.billing_training_work_type(p_account uuid, p_audience text) -- takes the person and who the module was for
returns text language sql stable security definer -- gives back the kind of hours; reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the choice:
  select case -- choose:
    when p_audience = 'admin' then 'admin' -- admin training: admin rate
    when p_audience = 'tutor' then 'tutoring' -- tutor training: tutor rate
    when private.account_has_role(p_account, 'tutor') and private.billing_tutoring_kind(p_account) is not null then 'tutoring' -- training for everyone, for a tutor with a tutoring rate: tutor rate
    when private.account_has_role(p_account, 'admin') then 'admin' -- otherwise, for admin staff: admin rate
    else 'tutoring' -- otherwise the tutor rate (CLG enters it before approving)
  end -- end of the choice
$$; -- end of the function
revoke all on function private.billing_training_work_type(uuid, text) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- Add training hours for completions in a range of days.
-- Each paid completion becomes one entry waiting for approval. Already
-- added completions are skipped. Returns how many were added.
-- ---------------------------------------------------------------------------
create or replace function public.billing_build_training_hours(p_from date, p_to date) -- the first and last day to look at
returns int language plpgsql security definer -- gives back a count; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  r record; -- one completion at a time
  v_id uuid; -- the new entry's id
  n int := 0; -- how many were added
begin -- start of the steps
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can work out pay' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of that check
  if p_to < p_from or p_to - p_from > 62 then -- same limit as working out session pay
    raise exception 'Choose up to about two months at a time' using errcode = '22023'; -- plain message
  end if; -- end of that check
  for r in -- each paid completion in the range not yet added:
    select c.id, c.account_id, c.completed_on, c.minutes, c.module_title, c.audience -- its details
    from public.training_completions c -- training completions belong to training; billing only reads them
    where c.paid and c.completed_on between p_from and p_to -- paid ones, in the days asked for
      and not exists (select 1 from public.billing_hour_logs h where h.training_completion_id = c.id) -- not added already
  loop -- for each one:
    v_id := null; -- no entry yet
    insert into public.billing_hour_logs (account_id, work_date, minutes, note, work_type, source, training_completion_id) -- adds an hours entry
    values (r.account_id, r.completed_on, r.minutes, left(r.module_title, 300), -- who, the day, the set time, and which module (shown beside the "Training" label)
            private.billing_training_work_type(r.account_id, r.audience), 'training', r.id) -- at the right rate, marked as training, for this completion
    on conflict do nothing -- (already there: nothing happens)
    returning id into v_id; -- keeps the new entry's id
    if v_id is not null then -- it was added:
      update public.billing_hour_logs set logged_late = false where id = v_id; -- the app added it, so it's never "late"
      n := n + 1; -- counts it
    end if; -- end of that case
  end loop; -- end of the completions
  return n; -- how many were added
end; -- end of the steps
$$; -- end of the function
revoke all on function public.billing_build_training_hours(date, date) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_build_training_hours(date, date) to authenticated, service_role; -- signed-in admins (checked inside) and the daily run

-- ---------------------------------------------------------------------------
-- Approving hours (owner or Finance admin). Same as before, plus training
-- entries become "training" pay lines.
-- ---------------------------------------------------------------------------
create or replace function public.billing_review_hours(p_log uuid, p_approve boolean, p_note text default null) -- the entry, approve or decline, and a note
returns void language plpgsql security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  v public.billing_hour_logs; -- the entry
  v_kind text; -- which rate: school, tertiary or admin
  v_line_kind text; -- which kind of pay line
  v_rate int; -- the rate in cents
  v_line uuid; -- the new pay line's id
begin -- start of the steps
  if not private.is_pay_admin() then -- not the owner or Finance:
    raise exception 'Only the owner or a Finance admin can approve hours' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select * into v from public.billing_hour_logs where id = p_log for update; -- reads the entry (and holds it while working)
  if not found or v.status <> 'submitted' then -- missing or already dealt with:
    raise exception 'These hours have already been dealt with' using errcode = '22023'; -- says so
  end if; -- end of that check
  if v.account_id = auth.uid() and not private.is_owner() then -- their own hours, and not the owner:
    raise exception 'Someone else needs to approve your own hours' using errcode = '42501'; -- refuses
  end if; -- end of that check
  if not p_approve then -- declining:
    if char_length(trim(coalesce(p_note, ''))) < 3 then -- no reason given:
      raise exception 'Please say why the hours are declined' using errcode = '22023'; -- asks for one
    end if; -- end of that check
    update public.billing_hour_logs -- marks the entry:
    set status = 'declined', review_note = left(trim(p_note), 300), reviewed_by = auth.uid(), reviewed_at = now() -- declined, with the reason, who and when
    where id = p_log; -- this entry
    return; -- finished
  end if; -- end of declining

  v_kind := case when v.work_type = 'tutoring' then private.billing_tutoring_kind(v.account_id) else 'admin' end; -- the rate: their tutoring rate, or admin
  v_line_kind := case when v.source = 'guaranteed' then 'guaranteed' -- a top-up line,
                      when v.source = 'training' then 'training' -- a training line,
                      when v.work_type = 'tutoring' then 'tutoring_work' -- a tutoring work line,
                      else 'admin' end; -- or an office admin line
  v_rate := case when v_kind is null then null else private.billing_pay_rate(v.account_id, v_kind) end; -- the rate in cents (if entered)
  if v_rate is null then -- no rate entered:
    raise exception 'Enter a % pay rate for this person first', case when v.work_type = 'tutoring' then 'tutoring' else 'admin' end -- asks for it
      using errcode = '22023'; -- (plain message code)
  end if; -- end of that check
  insert into public.billing_pay_lines (account_id, staff_name, work_date, kind, work_kind, minutes, rate_cents, amount_cents, under_award, note, created_by) -- adds the pay line
  select v.account_id, a.full_name, v.work_date, v_line_kind, v_kind, v.minutes, v_rate, -- who, when, what kind, which rate, how long and the rate
         round(v_rate * v.minutes / 60.0)::int, -- the pay, in cents
         private.billing_under_award(v.account_id, v_kind, v_rate, v.work_date), -- flag if under the award
         v.note, auth.uid() -- the note, and who approved it
  from public.accounts a where a.id = v.account_id -- the person's name
  returning id into v_line; -- keeps the new line's id
  update public.billing_hour_logs -- marks the entry:
  set status = 'approved', review_note = nullif(left(trim(coalesce(p_note, '')), 300), ''), -- approved, with any note
      reviewed_by = auth.uid(), reviewed_at = now(), pay_line_id = v_line -- who, when, and its pay line
  where id = p_log; -- this entry
end; -- end of the steps
$$; -- end of the function
revoke all on function public.billing_review_hours(uuid, boolean, text) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_review_hours(uuid, boolean, text) to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- Guaranteed hours top-ups. Same as before, plus training entries still
-- waiting for approval count as hours worked, so training fills the
-- top-up first.
-- ---------------------------------------------------------------------------
create or replace function public.billing_check_guaranteed_hours(p_day date) -- a day in the pay period to check
returns int language plpgsql security definer -- gives back how many top-ups were added; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  v_start date; -- the pay period's first day
  v_end date; -- its last day
  r record; -- one person at a time
  v_expected int; -- the agreed minutes for the period
  v_worked int; -- the minutes worked or logged
  v_id uuid; -- a new top-up's id
  n int := 0; -- how many were added
begin -- start of the steps
  if not (private.is_backend() or private.is_pay_admin()) then -- only the daily run, the owner or Finance
    raise exception 'Only the owner or a Finance admin can do this' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of that check
  select period_start, period_end into v_start, v_end from public.billing_pay_period(p_day); -- the pay period's first and last day
  if v_end >= private.billing_today() then -- the pay period hasn't finished yet:
    return 0; -- nothing to check yet
  end if; -- end of that check

  for r in -- each part-time or full-time person with agreed hours and no top-up yet this period:
    select sp.account_id, sp.guaranteed_weekly_minutes -- who, and their agreed weekly minutes
    from public.billing_staff_pay sp -- from pay details
    where sp.guaranteed_weekly_minutes is not null -- with agreed hours
      and sp.employment in ('part_time', 'full_time') -- part-time or full-time
      and not exists ( -- and no top-up
        select 1 from public.billing_hour_logs h -- entry
        where h.account_id = sp.account_id and h.source = 'guaranteed' and h.period_start = v_start -- for them, this period
      ) -- end of that test
  loop -- for each one:
    v_expected := round(r.guaranteed_weekly_minutes * (v_end - v_start + 1) / 7.0)::int; -- the agreed minutes for the period's length
    v_worked := coalesce(( -- the minutes worked:
        select sum(l.minutes) from public.billing_pay_lines l -- pay lines
        where l.account_id = r.account_id and l.work_date between v_start and v_end -- for them, in the period
      ), 0) + coalesce(( -- plus
        select sum(h.minutes) from public.billing_hour_logs h -- hours entries
        where h.account_id = r.account_id and h.work_date between v_start and v_end -- for them, in the period
          and h.status = 'submitted' and h.source in ('staff', 'training') -- still waiting for approval, logged by them or from training
      ), 0); -- (none counts as 0)
    v_id := null; -- no top-up added yet for this person
    if v_expected - v_worked >= 15 then -- at least 15 minutes short:
      insert into public.billing_hour_logs (account_id, work_date, minutes, note, work_type, source, period_start) -- adds a top-up entry
      values ( -- with:
        r.account_id, v_end, v_expected - v_worked, -- who, the last day of the period, and the minutes short
        format('Guaranteed hours top-up: agreed %s hr, worked or logged %s hr this pay period', -- a note explaining it
               round(v_expected / 60.0, 2), round(v_worked / 60.0, 2)), -- (agreed and worked hours)
        case when private.account_has_role(r.account_id, 'tutor') and private.billing_tutoring_kind(r.account_id) is not null -- a tutor with a tutoring rate:
             then 'tutoring' else 'admin' end, -- tutor rate, otherwise admin rate
        'guaranteed', v_start -- marked as a top-up for this period
      ) -- end of the values
      on conflict do nothing -- (already there: nothing happens)
      returning id into v_id; -- keeps the new entry's id
      if v_id is not null then -- it was added:
        update public.billing_hour_logs set logged_late = false where id = v_id; -- the app added it, so it's never "late"
        n := n + 1; -- counts it
      end if; -- end of that case
    end if; -- end of the short case
  end loop; -- end of the people
  return n; -- how many were added
end; -- end of the steps
$$; -- end of the function
revoke all on function public.billing_check_guaranteed_hours(date) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_check_guaranteed_hours(date) to authenticated, service_role; -- signed-in admins (checked inside) and the daily run
