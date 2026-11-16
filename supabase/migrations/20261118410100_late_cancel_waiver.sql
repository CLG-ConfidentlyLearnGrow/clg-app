-- Summary: once-a-year waiver of the late-cancellation rule (Carla, 16 Nov 2026).
--
-- Carla: the late-cancellation rule can be waived (learner suddenly unwell,
-- a family emergency or a similar good reason) "only once per year, more
-- than this and proof is required - further explanation to the CLG Team
-- (NOT the tutor - at this stage either Lauren or myself)".
--
-- How it works:
--   * Only Owner and Operations admins (today Carla and Lauren) can waive,
--     with two-step sign-in. Tutors never see waivers or the reasons.
--   * A waiver is for one session the family cancelled, or a no-show. It
--     gives the family a full credit for that session.
--   * Each learner gets one waiver each calendar year (Adelaide time, by the
--     session's date) on a short reason. After that, the admin must tick
--     that they have seen proof, and explain why.
--   * We record only that proof was seen, never a copy of it: proof is
--     often a medical certificate, which is health information (Privacy Act
--     1988, APP 3: collect only what is needed).
--   * Tutor pay doesn't change: a tutor paid 50% for a cancel under 2 hr
--     keeps it.
--   * If the session's credit was already given, the rest of the full
--     credit is added as a goodwill credit, linked to the session.
--
-- Billing module: reads sessions, writes only billing tables.
-- Needs 20261118100300_makeup_cancel_pay_rules.sql first. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. The waivers table
-- ---------------------------------------------------------------------------
-- One row for each waived session.
create table if not exists public.billing_cancel_waivers ( -- the waivers:
  id uuid primary key default gen_random_uuid(), -- its own id
  session_id uuid not null unique references public.sessions (id) on delete cascade, -- the waived session (once each); goes if the session is deleted
  student_id uuid not null references public.students (id) on delete cascade, -- the learner, for the once-a-year count
  family_id uuid references public.families (id) on delete set null, -- the family the credit goes to
  waiver_year int not null, -- the calendar year it counts against (from the session's date in Adelaide)
  proof_seen boolean not null default false, -- whether the admin saw proof (needed after the first waiver in a year)
  reason text not null check (char_length(trim(reason)) between 5 and 500), -- why it was waived, in a few words
  waived_by uuid references public.accounts (id) on delete set null, -- the admin who waived it
  created_at timestamptz not null default now() -- when
); -- (end of the table)
create index if not exists billing_cancel_waivers_student_year on public.billing_cancel_waivers (student_id, waiver_year); -- quick count of a learner's waivers in a year

alter table public.billing_cancel_waivers enable row level security; -- access rules on: nobody sees a row unless a rule below allows it
revoke all on public.billing_cancel_waivers from anon; -- signed-out visitors see nothing
revoke insert, update, delete, truncate on public.billing_cancel_waivers from authenticated; -- changes only through the function below

drop trigger if exists audit on public.billing_cancel_waivers; -- replaces the audit trigger if this is run again
create trigger audit after insert or update or delete on public.billing_cancel_waivers -- every change is written to the audit log
  for each row execute function private.audit_change(); -- (the shared audit step)

drop policy if exists "owner and operations see waivers" on public.billing_cancel_waivers; -- removes the old rule first, so this can be run again
create policy "owner and operations see waivers" on public.billing_cancel_waivers for select to authenticated -- who can read waivers:
  using (private.is_admin()); -- only Owner and Operations admins (not tutors, families, Support or Finance)

-- ---------------------------------------------------------------------------
-- 2. The credit rule knows about waivers (replaces the 100300 version whole)
-- ---------------------------------------------------------------------------
-- Hands back the percentage of the session's charge to give back as credit,
-- or nothing while make-up times are still waiting for an answer.
create or replace function private.billing_session_credit_percent(p_session uuid) -- takes the session
returns int -- the credit percentage (0, 50 or 100), or nothing while waiting
language sql stable security definer -- reads sessions, offers and waivers whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the rule
  select case -- in order:
    when exists (select 1 from public.billing_cancel_waivers w where w.session_id = se.id) -- the late-cancel rule was waived:
      then 100 -- full credit
    when exists (select 1 from public.session_makeup_offers o -- make-up times
                 where o.session_id = se.id and o.status in ('waiting', 'confirming')) -- still waiting for an answer:
      then null -- wait before giving any credit
    when se.status::text = 'cancelled' and se.cancelled_by_role = 'family' -- the family cancelled,
         and exists (select 1 from public.session_makeup_offers o -- and a make-up
                     where o.session_id = se.id and o.status = 'picked') -- was booked:
      then case when se.starts_at - se.cancelled_at < make_interval(hours => s.half_credit_hours) -- under 2 hr notice:
                then 50 -- half credit (they pay half the cancelled session),
                else 100 end -- otherwise full credit (they pay only for the make-up)
    else private.billing_cancel_credit_percent(se.starts_at, se.cancelled_at, se.cancelled_by_role::text, se.status::text) -- otherwise the usual rules
  end -- (end of the rule)
  from public.sessions se -- the session
  cross join public.billing_settings s -- with the notice settings (2 hr is half_credit_hours)
  where se.id = p_session -- this session
$$; -- end of the function
revoke all on function private.billing_session_credit_percent(uuid) from public, anon, authenticated; -- only used inside the database

-- ---------------------------------------------------------------------------
-- 3. Waive the late-cancellation rule for one session
-- ---------------------------------------------------------------------------
-- Owner or Operations admin only. Gives back nothing; a plain message explains any refusal.
create or replace function public.billing_waive_late_cancel(p_session uuid, p_reason text, p_proof_seen boolean default false) -- takes the session, the reason, and whether proof was seen
returns void -- gives nothing back
language plpgsql security definer -- runs with full rights; the checks below decide who may
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values:
  v_s public.sessions; -- the session
  v_year int; -- the calendar year it counts against
  v_used int; -- waivers the learner already had that year
  v_line record; -- the invoice line that charged for the session (if any)
  v_given int; -- credit already given for the session (in cents)
begin -- start
  if not (private.is_admin() and private.has_aal2()) then -- not an Owner or Operations admin with two-step sign-in:
    raise exception 'Only Owner and Operations admins can waive a late cancellation' using errcode = '42501'; -- plain refusal
  end if; -- (end of that check)
  select * into v_s from public.sessions where id = p_session; -- finds the session
  if v_s.id is null then -- no such session:
    raise exception 'Session not found' using errcode = 'P0002'; -- plain refusal
  end if; -- (end of that check)
  if not (v_s.status::text = 'no_show' or (v_s.status::text = 'cancelled' and v_s.cancelled_by_role = 'family')) then -- not a family cancel or a no-show:
    raise exception 'Only a session the family cancelled, or a no-show, can be waived' using errcode = '22023'; -- plain refusal
  end if; -- (end of that check)
  if exists (select 1 from public.billing_cancel_waivers where session_id = p_session) then -- already waived:
    raise exception 'This session has already been waived' using errcode = '22023'; -- plain refusal
  end if; -- (end of that check)
  if private.billing_session_credit_percent(p_session) = 100 then -- the family already gets a full credit:
    raise exception 'This session already gets a full credit, so there is nothing to waive' using errcode = '22023'; -- plain refusal
  end if; -- (end of that check)
  if char_length(trim(coalesce(p_reason, ''))) < 5 then -- no real reason given:
    raise exception 'Please say briefly why (no health details needed)' using errcode = '22023'; -- plain refusal
  end if; -- (end of that check)
  v_year := extract(year from v_s.starts_at at time zone 'Australia/Adelaide')::int; -- the session's year in Adelaide
  select count(*) into v_used from public.billing_cancel_waivers -- counts the learner's waivers
  where student_id = v_s.student_id and waiver_year = v_year; -- in that year
  if v_used >= 1 and not coalesce(p_proof_seen, false) then -- the yearly waiver is used and no proof was seen:
    raise exception 'This learner has already had their waiver for %. To waive again, see proof, explain why, and tick "Proof seen".', v_year using errcode = '22023'; -- plain refusal
  end if; -- (end of that check)
  insert into public.billing_cancel_waivers (session_id, student_id, family_id, waiver_year, proof_seen, reason, waived_by) -- records the waiver:
  values (p_session, v_s.student_id, v_s.family_id, v_year, coalesce(p_proof_seen, false), trim(p_reason), auth.uid()); -- for this session, learner and family, by this admin

  -- If the credit for this session was already given, add the rest of the full credit now.
  select coalesce(sum(c.amount_cents), 0) into v_given from public.billing_credits c -- credit already given
  where c.session_id = p_session and c.kind in ('cancellation', 'goodwill'); -- for this session
  select l.amount_cents, l.description, i.id as invoice_id, i.family_id into v_line -- the charge for the session:
  from public.billing_invoice_lines l join public.billing_invoices i on i.id = l.invoice_id -- from its invoice line
  where l.session_id = p_session and l.active and i.status in ('open', 'paid') -- that still stands
  limit 1; -- (one line per session)
  if v_line.invoice_id is not null -- it was charged,
     and exists (select 1 from public.billing_credits c where c.session_id = p_session and c.kind = 'cancellation') -- the credit run already dealt with it,
     and v_line.amount_cents - v_given > 0 then -- and some of the charge is still not credited:
    insert into public.billing_credits (family_id, kind, amount_cents, session_id, invoice_id, note, created_by) -- adds the rest as credit:
    values (v_line.family_id, 'goodwill', v_line.amount_cents - v_given, p_session, v_line.invoice_id, -- for the family, the missing amount, linked to the session and invoice,
            left('Late-cancel waiver: rest of the credit for ' || v_line.description, 500), auth.uid()); -- with a plain note, by this admin
  end if; -- (if not yet credited, the daily credit run gives the full credit because of the waiver)
end; -- finish
$$; -- end of the function
revoke all on function public.billing_waive_late_cancel(uuid, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.billing_waive_late_cancel(uuid, text, boolean) to authenticated; -- signed-in people (the checks above decide)

-- ---------------------------------------------------------------------------
-- 4. Sessions an admin could waive, for the Billing page
-- ---------------------------------------------------------------------------
-- Family cancels and no-shows from the last 60 days and the next 14, newest first,
-- with the credit they get and how many waivers the learner has had that year.
create or replace function public.billing_waiver_list() -- takes nothing
returns table ( -- gives back rows of:
  session_id uuid, -- the session
  student_name text, -- the learner's name
  family_name text, -- the family's name
  starts_at timestamptz, -- when it was booked for
  cancelled_at timestamptz, -- when it was cancelled (nothing for a no-show)
  status text, -- cancelled or no_show
  credit_percent int, -- the credit it gets now (nothing while make-up times wait)
  used_this_year int, -- the learner's waivers in that session's year
  waived boolean -- whether this session is waived
) -- (end of the row shape)
language sql stable security definer -- reads across tables; the check below limits who
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select se.id, -- the session,
         st.full_name, -- the learner,
         f.name, -- the family,
         se.starts_at, -- when,
         se.cancelled_at, -- when cancelled,
         se.status::text, -- cancelled or no-show,
         private.billing_session_credit_percent(se.id), -- the credit now,
         (select count(*)::int from public.billing_cancel_waivers w -- the learner's waivers
          where w.student_id = se.student_id -- for this learner
            and w.waiver_year = extract(year from se.starts_at at time zone 'Australia/Adelaide')::int), -- in that year,
         exists (select 1 from public.billing_cancel_waivers w where w.session_id = se.id) -- and whether it's waived
  from public.sessions se -- from sessions
  join public.students st on st.id = se.student_id -- with their learner
  left join public.families f on f.id = se.family_id -- and family (if set)
  where private.is_admin() -- only for Owner and Operations admins (others get nothing)
    and (se.status::text = 'no_show' or (se.status::text = 'cancelled' and se.cancelled_by_role = 'family')) -- family cancels and no-shows
    and se.starts_at between now() - interval '60 days' and now() + interval '14 days' -- recent and coming up
  order by se.starts_at desc -- newest first
  limit 100 -- up to 100
$$; -- end of the function
revoke all on function public.billing_waiver_list() from public, anon; -- not for signed-out visitors
grant execute on function public.billing_waiver_list() to authenticated; -- signed-in people (only admins get rows)
