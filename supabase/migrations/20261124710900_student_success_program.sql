-- Summary: the Student Success Program, with family requests, admin approval,
-- limited places, a program invoice paid by a $500 deposit and then in full,
-- monthly or weekly, and forfeiting a place when payments are missed (Carla,
-- 22 Nov 2026).
--
-- Carla's first note: "need to have a space where can click or check off or
-- something if a student is part of the Student Success Program ... then it
-- sets up their student and/or family profile up accordingly." What it sets
-- up: "Study plan, term reviews, a program label, book till date range
-- (number of sessions) - these are top priority for matching."
--
-- Carla's later answers (same day):
--   * The family ticks a box to ask; an admin must approve the student,
--     because places are limited.
--   * The $500 deposit comes off the Student Success Program invoice. The
--     admin types in the invoice total and chooses the payment plan: pay in
--     full, monthly or weekly. The instalment amount comes from the number of
--     months or weeks left until the finish payment date. Each monthly
--     payment has a $10 plan fee and each weekly payment a $5 plan fee.
--   * Paying the deposit secures the place, but the program's features only
--     switch on once everything is paid.
--   * The deposit is due within 72 hours; at 48 hours the person who pays is
--     reminded that the place will be forfeited if it is not paid. If it is
--     not paid in time, the place is forfeited and admins are told.
--   * Everyone is reminded 24 hours before a payment is taken. If a payment
--     is missed, the payer is warned that the place will be forfeited unless
--     they pay or agree a payment plan with CLG. Carla, 23 Nov 2026: 7 days
--     for all; and for a family paying weekly, sessions credited because of
--     non-payment two weeks in a row (with no plan agreed with CLG) also
--     forfeit the place. A forfeited place puts the family back on the
--     waiting list, and admins are told the place is open, why, and which
--     family it was for.
--   * All payments come off the family's saved card or bank account
--     automatically (they can still choose Pay now).
--
-- How a student moves through the program (public.ssp_enrolments.status):
--   requested -> the family ticked the box to ask about it
--   approved  -> an admin approved a place and billing made the program
--                invoices; the place is held while the deposit is paid
--   secured   -> the deposit is paid; the rest is still being paid
--   enrolled  -> every program invoice is paid: the student is in the
--                program (study plan, term reviews included, label, first
--                in Matching)
--   declined  -> CLG could not offer a place (the family can ask again)
--   withdrawn -> the family cancelled their request, or CLG withdrew a place
--                before the deposit was paid
--   forfeited -> (not used since 23 Nov 2026: a forfeited place goes back to
--                "requested", with the reason kept, so the family is back on
--                the waiting list)
--   left      -> the student had a place and has now left the program
--
-- Modules: progress owns the program record, study plans and term reviews.
-- Billing owns prices and invoices. Progress asks billing to make and cancel
-- invoices only through billing's functions and never writes billing's
-- tables. A trigger on the invoice table tells progress when a program
-- invoice is paid or cancelled; it only writes progress's own tables.
--
-- Safe to run more than once. Also safe to run after the earlier versions
-- of this file. Run after 20261124710800_policy_versions_read_again.sql.

-- ===========================================================================
-- PART A. BILLING (module: billing)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A1. What an invoice is for: sessions (as before), a program deposit, or a
--     program payment.
-- ---------------------------------------------------------------------------
alter table public.billing_invoices -- the invoices table
  add column if not exists kind text not null default 'sessions'; -- what the invoice is for, "sessions" for every invoice so far
alter table public.billing_invoices drop constraint if exists billing_invoices_kind_check; -- replaces the list of kinds if run again
alter table public.billing_invoices add constraint billing_invoices_kind_check -- the allowed kinds:
  check (kind in ('sessions', 'deposit', 'program')); -- sessions, a program deposit, or a program payment

-- ---------------------------------------------------------------------------
-- A2. Price items: the deposit, the program itself, and the plan fees.
-- ---------------------------------------------------------------------------
-- GST: Carla treats curriculum tutoring as GST-free, so these start as
-- GST-free. An Owner or Finance admin can change any price or its GST
-- setting under Billing, Prices and settings (worth checking the plan fees
-- with CLG's accountant).
insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, active, description) values -- the price list:
  ('ssp_deposit', 'Student Success Program deposit', 'once', 50000, false, true, -- the deposit: $500, GST-free, in use
   'The first payment on a Student Success Program invoice. It secures the student''s place and is taken off the program total.'), -- what it is, for admins
  ('ssp_program', 'Student Success Program', 'once', 0, false, false, -- the program itself: the admin types the total for each student
   'Used for the lines of Student Success Program invoices. The total is typed in by the admin for each student, so this price is not used.'), -- what it is, for admins
  ('plan_fee_monthly', 'Monthly payment plan fee', 'once', 1000, false, true, -- $10 on each monthly payment, in use
   'Added to each invoice on a monthly payment plan (family sessions and Student Success Program payments).'), -- what it is, for admins (shared with the normal billing update, so the words suit both)
  ('plan_fee_weekly', 'Weekly payment plan fee', 'once', 500, false, true, -- $5 on each weekly payment, in use
   'Added to each invoice on a weekly payment plan (family sessions and Student Success Program payments).') -- what it is, for admins (shared with the normal billing update, so the words suit both)
on conflict (code) do nothing; -- leaves any already there alone (so a price already changed stays)

-- ---------------------------------------------------------------------------
-- A3. Making a program invoice. Only other database functions call this.
-- ---------------------------------------------------------------------------
-- One invoice with one line for the amount, plus a line for a plan fee if
-- one applies. It is approved straight away (the admin's approval of the
-- place is the approval), so it can be paid at once, and the daily billing
-- run charges the family's saved card or bank account on its charge day.
-- Family credit is not used on it, and no bank debit discount applies.
-- A program invoice never puts the family's sessions on hold (see A4):
-- missed program payments lead to forfeiting the place instead.
drop function if exists private.billing_charge_deposit(uuid, uuid, text, date); -- removes the earlier version's deposit-only function
create or replace function private.billing_program_invoice( -- the function's name
  p_family uuid, -- the family to bill
  p_student uuid, -- the student it is for
  p_kind text, -- 'deposit' or 'program'
  p_price_code text, -- the price item for the main line ('ssp_deposit' or 'ssp_program')
  p_description text, -- the words on the main line
  p_amount_cents int, -- the main line's amount, including any GST
  p_fee_code text, -- the plan fee's price item ('plan_fee_monthly', 'plan_fee_weekly'), or nothing
  p_due_on date, -- the day it is due
  p_charge_on date -- the day the saved card or bank account is charged
)
returns uuid -- the new invoice's id
language plpgsql security definer -- runs with the database's own rights, as billing tables are locked down
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_account public.billing_accounts; -- the family's billing set-up
  v_price public.billing_price_items; -- the main line's price item
  v_fee public.billing_price_items; -- the plan fee's price item (if any)
  v_fee_cents int := 0; -- the plan fee amount
  v_family_name text; -- the family's name (copied onto the invoice)
  v_today date := private.billing_today(); -- today in Adelaide
  v_gst int; -- the GST part of the main line
  v_fee_gst int := 0; -- the GST part of the fee
  v_invoice uuid; -- the new invoice
begin -- start of the steps
  if p_kind not in ('deposit', 'program') or coalesce(p_amount_cents, 0) <= 0 then -- not a program invoice, or nothing to charge:
    raise exception 'A program invoice needs an amount above $0' using errcode = '22023'; -- plain message
  end if; -- end of that check
  select * into v_account from public.billing_accounts where family_id = p_family; -- reads the family's billing set-up
  if not found or v_account.bill_payer_id is null then -- no billing set-up, or nobody named to pay:
    raise exception 'This family has not set up billing yet, so the program invoice cannot be made. Ask the family to open Billing in the app, choose a payment plan and accept the family terms, then approve the place again.' using errcode = '22023'; -- plain message
  end if; -- end of that check
  select * into v_price from public.billing_price_items where code = p_price_code; -- reads the main line's price item
  if p_fee_code is not null then -- a plan fee applies:
    select * into v_fee from public.billing_price_items where code = p_fee_code and active; -- reads it (only if in use)
    v_fee_cents := coalesce(v_fee.amount_cents, 0); -- its amount ($0 if switched off)
    v_fee_gst := case when v_fee.gst_applies then round(v_fee_cents / 11.0)::int else 0 end; -- its GST (one eleventh of a GST-inclusive price)
  end if; -- end of the fee
  select name into v_family_name from public.families where id = p_family; -- reads the family's name
  v_gst := case when v_price.gst_applies then round(p_amount_cents / 11.0)::int else 0 end; -- the main line's GST

  insert into public.billing_invoices ( -- makes the invoice:
    family_id, family_name, plan, method, kind, -- who, their plan and method, and what it is for
    period_start, period_end, first_session_on, send_on, due_on, charge_on, -- its dates
    status, subtotal_cents, gst_cents, discount_cents, credit_applied_cents, total_cents, -- approved, and the money
    approved_at, approved_by, created_by -- when and by whom
  ) values ( -- with these values:
    p_family, coalesce(v_family_name, 'Family'), v_account.plan, v_account.method, p_kind, -- the family, plan, method and kind
    v_today, greatest(p_due_on, v_today), greatest(p_due_on, v_today), v_today, greatest(p_due_on, v_today), greatest(p_charge_on, v_today), -- made today, due and charged on the days given (never in the past)
    'open', p_amount_cents + v_fee_cents, v_gst + v_fee_gst, 0, 0, p_amount_cents + v_fee_cents, -- ready to pay, the amount plus any fee, no discount or credit
    now(), auth.uid(), auth.uid() -- approved now by the admin who approved the place
  ) -- end of the values
  returning id into v_invoice; -- keeps the new invoice's id

  -- Each line counts as 60 minutes at its price, so Xero shows quantity 1
  -- at that price (Xero's quantity is minutes divided by 60).
  insert into public.billing_invoice_lines ( -- adds the main line:
    invoice_id, student_id, price_item_id, line_date, description, -- which invoice, student, price, date and words
    minutes, billed_minutes, hourly_cents, amount_cents, gst_cents -- quantity and money
  ) values ( -- with these values:
    v_invoice, p_student, v_price.id, greatest(p_due_on, v_today), left(p_description, 300), -- the invoice, student, price item, due day and words
    60, 60, p_amount_cents, p_amount_cents, v_gst -- one unit at the amount
  ); -- end of the main line
  if v_fee_cents > 0 then -- a plan fee applies:
    insert into public.billing_invoice_lines ( -- adds the fee line:
      invoice_id, student_id, price_item_id, line_date, description, -- which invoice, student, price, date and words
      minutes, billed_minutes, hourly_cents, amount_cents, gst_cents -- quantity and money
    ) values ( -- with these values:
      v_invoice, p_student, v_fee.id, greatest(p_due_on, v_today), v_fee.name, -- the invoice, student, fee item, due day and its name
      60, 60, v_fee_cents, v_fee_cents, v_fee_gst -- one unit at the fee
    ); -- end of the fee line
  end if; -- end of the fee step
  return v_invoice; -- gives back the new invoice
end; -- end of the steps
$$; -- end of the function
revoke all on function private.billing_program_invoice(uuid, uuid, text, text, text, int, text, date, date) from public; -- no one calls it directly; only database functions do

-- How much has been paid (or is on its way) on an invoice.
create or replace function private.billing_invoice_paid(p_invoice uuid) -- the invoice
returns int language sql stable security definer -- reads billing's payments for the database
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
  select coalesce(sum(p.amount_cents), 0)::int from public.billing_payments p -- adds up payments
  where p.invoice_id = p_invoice and p.status = 'succeeded'; -- on this invoice that succeeded
$$; -- end of the function
revoke all on function private.billing_invoice_paid(uuid) from public; -- only database functions use it

-- ---------------------------------------------------------------------------
-- A4. Program invoices do not count as session billing.
-- ---------------------------------------------------------------------------

-- A family is paused when a sent session invoice is not fully paid (or on
-- its way) and either its due date has passed or a payer's payment failed
-- and that payer has not paid since, and no override is in force. If part
-- of the invoice has been paid, the pause waits until the first session
-- that is not paid for. Same as 20261102230100_billing_partial_pause.sql,
-- except that program invoices never pause the family: a missed program
-- payment leads to the place being forfeited instead.
create or replace function private.billing_should_pause(p_family uuid, p_today date) -- takes the family and the day
returns boolean language sql stable security definer -- gives back yes or no; reads billing tables
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- true when there is
      select 1 -- an invoice
      from public.billing_invoices i -- from the invoices table
      cross join lateral ( -- with what has been paid on it:
        select coalesce(sum(p.amount_cents), 0) as paid -- the total paid or on its way
        from public.billing_payments p -- from the payments table
        where p.invoice_id = i.id and p.status in ('processing', 'succeeded') -- for this invoice, paid or on its way
      ) pay -- (named "pay")
      where i.family_id = p_family -- for this family
        and i.kind = 'sessions' -- for sessions (never a program invoice, Carla 22 Nov 2026)
        and i.status = 'open' -- sent and not paid
        and pay.paid < i.total_cents -- not fully covered
        and ( -- and either
          i.due_on < p_today -- its due date has passed
          or exists ( -- or a payment failed
            select 1 from public.billing_payments f -- a payment
            where f.invoice_id = i.id and f.status = 'failed' -- on this invoice that failed
              and not exists ( -- and that payer has not paid since
                select 1 from public.billing_payments g -- another payment
                where g.invoice_id = i.id and g.status in ('processing', 'succeeded') -- on this invoice, paid or on its way
                  and g.payer_id is not distinct from f.payer_id -- by the same payer
              ) -- end of "not paid since"
          ) -- end of the failed payment case
        ) -- end of "either"
        and ( -- and the pause applies now:
          pay.paid = 0 -- nothing paid at all
          or coalesce(private.billing_first_unpaid_day(i.id), p_today) <= p_today -- or the first session not paid for has come
        ) -- end of that part
    ) -- end of the invoice check
    and not exists ( -- and no override is in force
      select 1 from public.billing_pause_overrides o -- an override
      where o.family_id = p_family and o.ended_at is null and o.until_on >= p_today -- for this family, still running
    ) -- end of the override check
$$; -- end of the function

-- Whether a family has any session invoice that is not cancelled. Once one
-- exists, a plan change is booked for the next invoice. Program invoices
-- do not count, so they never lock the family's payment plan.
create or replace function private.billing_has_invoice(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- reads invoices for the plan functions
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- true when
    select 1 from public.billing_invoices i -- an invoice
    where i.family_id = p_family and i.status <> 'void' and i.kind = 'sessions' -- for this family's sessions is not cancelled
  ) -- (end of the check)
$$; -- end of the function

-- Whether a family has been sent a session invoice (sent or paid). Program
-- invoices do not count, for the same reason.
create or replace function private.billing_family_invoiced(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- reads invoices for the plan functions
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- true when
    select 1 from public.billing_invoices i -- an invoice
    where i.family_id = p_family and i.status in ('open', 'paid') and i.kind = 'sessions' -- for this family's sessions has been sent or paid
  ) -- (end of the check)
$$; -- end of the function

-- ===========================================================================
-- PART B. THE PROGRAM (module: progress)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- B1. Settings: places, the deposit deadline and reminder, and how long
--     after a missed payment the place is forfeited. One row.
-- ---------------------------------------------------------------------------
create table if not exists public.ssp_settings ( -- the settings table
  id boolean primary key default true check (id), -- only ever one row
  spaces integer not null default 10 check (spaces between 0 and 1000), -- how many places the program has (change it in Families)
  deposit_due_days integer not null default 7 check (deposit_due_days between 1 and 60), -- (from the first version: no longer used)
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed it
  updated_at timestamptz not null default now() -- when
); -- end of the table
alter table public.ssp_settings add column if not exists deposit_hours integer not null default 72 check (deposit_hours between 24 and 720); -- hours to pay the deposit (72, Carla 22 Nov 2026)
alter table public.ssp_settings add column if not exists reminder_hours integer not null default 48 check (reminder_hours between 1 and 719); -- hours after the offer when the payer is reminded (48)
alter table public.ssp_settings add column if not exists forfeit_days integer not null default 7 check (forfeit_days between 1 and 60); -- days after a missed payment before the place is forfeited (7 to start)
insert into public.ssp_settings (id) values (true) on conflict do nothing; -- makes the one row (leaves it if it is there)
alter table public.ssp_settings enable row level security; -- access rules apply
revoke all on public.ssp_settings from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.ssp_settings from authenticated; -- changes only through ssp_set_places
grant select on public.ssp_settings to authenticated; -- reading, limited by the rule below
drop policy if exists "admins see program settings" on public.ssp_settings; -- replaces the rule if run again
create policy "admins see program settings" on public.ssp_settings -- who can read it:
  for select to authenticated -- signed-in people
  using ((select private.is_front_desk())); -- front desk admins only (checked once per query, for speed)
drop trigger if exists audit on public.ssp_settings; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.ssp_settings -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log

-- ---------------------------------------------------------------------------
-- B2. The program record: one row per student who asked or was added.
-- ---------------------------------------------------------------------------
create table if not exists public.ssp_enrolments ( -- one row per student
  student_id uuid primary key references public.students (id) on delete cascade, -- the student (removed with their records)
  status text not null default 'requested', -- where they are up to (see the list at the top)
  request_note text check (char_length(request_note) <= 500), -- the family's message when asking (optional)
  requested_by uuid references public.accounts (id) on delete set null, -- who asked
  requested_at timestamptz default now(), -- when they asked
  sessions_planned integer check (sessions_planned between 1 and 200), -- how many sessions the program covers (if known)
  book_until date, -- the last date sessions are booked to
  deposit_invoice_id uuid references public.billing_invoices (id) on delete set null, -- the deposit invoice (billing's table, only read here)
  deposit_paid_on date, -- when the deposit was paid
  note text check (char_length(note) <= 500), -- CLG's own note (admins only)
  decided_by uuid references public.accounts (id) on delete set null, -- the admin who approved, declined or withdrew
  decided_at timestamptz, -- when
  decline_reason text check (char_length(decline_reason) <= 500), -- the reason given to the family when declined, withdrawn or forfeited
  enrolled_by uuid references public.accounts (id) on delete set null, -- (from the first version: who ticked the box)
  enrolled_at timestamptz, -- when everything was paid and the program switched on
  ended_at timestamptz, -- when they left the program or forfeited the place
  ended_by uuid references public.accounts (id) on delete set null -- who took them out (blank when the app forfeited it)
); -- end of the table

-- Brings a table made by an earlier version of this file up to date.
alter table public.ssp_enrolments add column if not exists status text; -- where they are up to
alter table public.ssp_enrolments add column if not exists request_note text check (char_length(request_note) <= 500); -- the family's message
alter table public.ssp_enrolments add column if not exists requested_by uuid references public.accounts (id) on delete set null; -- who asked
alter table public.ssp_enrolments add column if not exists requested_at timestamptz default now(); -- when they asked
alter table public.ssp_enrolments add column if not exists deposit_invoice_id uuid references public.billing_invoices (id) on delete set null; -- the deposit invoice
alter table public.ssp_enrolments add column if not exists decided_by uuid references public.accounts (id) on delete set null; -- who decided
alter table public.ssp_enrolments add column if not exists decided_at timestamptz; -- when
alter table public.ssp_enrolments add column if not exists decline_reason text check (char_length(decline_reason) <= 500); -- the reason given to the family
alter table public.ssp_enrolments add column if not exists program_total_cents integer check (program_total_cents between 1 and 10000000); -- the program total the admin typed in (deposit included, plan fees not)
alter table public.ssp_enrolments add column if not exists plan text check (plan in ('full', 'monthly', 'weekly')); -- the payment plan the admin chose
alter table public.ssp_enrolments add column if not exists finish_on date; -- the date the last payment is due by
alter table public.ssp_enrolments add column if not exists deposit_deadline timestamptz; -- when the place is forfeited if the deposit is not paid
alter table public.ssp_enrolments add column if not exists deposit_reminded_at timestamptz; -- when the payer was reminded about the deposit
alter table public.ssp_enrolments add column if not exists agreement_until date; -- a payment agreement with CLG: no forfeiting until this date
alter table public.ssp_enrolments add column if not exists agreement_note text check (char_length(agreement_note) <= 500); -- what was agreed (admins only)
alter table public.ssp_enrolments alter column enrolled_at drop not null; -- joining time is blank until everything is paid
alter table public.ssp_enrolments alter column enrolled_at drop default; -- and is not filled in automatically
update public.ssp_enrolments -- students ticked in by the first version:
  set status = case when ended_at is null then 'enrolled' else 'left' end -- are in the program (or left it)
  where status is null; -- only rows with no status yet
alter table public.ssp_enrolments alter column status set default 'requested'; -- new rows start as a request
alter table public.ssp_enrolments alter column status set not null; -- every row has a status
alter table public.ssp_enrolments drop constraint if exists ssp_enrolments_status_check; -- replaces the list of statuses if run again
alter table public.ssp_enrolments add constraint ssp_enrolments_status_check -- the allowed statuses:
  check (status in ('requested', 'approved', 'secured', 'enrolled', 'declined', 'withdrawn', 'forfeited', 'left')); -- (see the list at the top)

-- Fast look-ups: the admin list and place count, and the deposit.
drop index if exists public.ssp_enrolments_places; -- replaces the index if run again (its list changed)
create index ssp_enrolments_places on public.ssp_enrolments (status) -- by status
  where status in ('requested', 'approved', 'secured', 'enrolled'); -- only the ones the admin page, place count and hourly job need
create unique index if not exists ssp_enrolments_deposit on public.ssp_enrolments (deposit_invoice_id) -- by deposit invoice
  where deposit_invoice_id is not null; -- only rows with one

alter table public.ssp_enrolments enable row level security; -- access rules apply
revoke all on public.ssp_enrolments from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.ssp_enrolments from authenticated; -- changes only through the functions below
grant select on public.ssp_enrolments to authenticated; -- reading, limited by the rule below
drop trigger if exists audit on public.ssp_enrolments; -- replaces the change log trigger if run again
create trigger audit after insert or update or delete on public.ssp_enrolments -- logs every change
  for each row execute function private.audit_change(); -- in the shared change log
drop policy if exists "see program students" on public.ssp_enrolments; -- removes the first version's rule
drop policy if exists "admins see the program list" on public.ssp_enrolments; -- replaces this rule if run again
create policy "admins see the program list" on public.ssp_enrolments -- who can read the table directly:
  for select to authenticated -- signed-in people
  using ((select private.is_front_desk())); -- front desk admins only. Families read their own status through ssp_family_status, which leaves out CLG's own notes.

-- ---------------------------------------------------------------------------
-- B3. The program's invoices (deposit first, then the rest), and reminders
--     already sent, so none goes twice.
-- ---------------------------------------------------------------------------
create table if not exists public.ssp_invoices ( -- one row per program invoice
  invoice_id uuid primary key references public.billing_invoices (id) on delete cascade, -- the invoice (billing's table, only read here)
  student_id uuid not null references public.students (id) on delete cascade, -- the student
  payment_no integer not null check (payment_no between 1 and 200), -- 1 is the deposit, then 2, 3 and so on
  created_at timestamptz not null default now() -- when it was made
); -- end of the table
create index if not exists ssp_invoices_student on public.ssp_invoices (student_id, payment_no); -- finds a student's invoices in order
alter table public.ssp_invoices enable row level security; -- access rules apply
revoke all on public.ssp_invoices from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.ssp_invoices from authenticated; -- changes only through the functions below
grant select on public.ssp_invoices to authenticated; -- reading, limited by the rule below
drop policy if exists "admins see program invoices" on public.ssp_invoices; -- replaces the rule if run again
create policy "admins see program invoices" on public.ssp_invoices -- who can read it:
  for select to authenticated -- signed-in people
  using ((select private.is_front_desk())); -- front desk admins only (families see the invoices themselves in Billing)

create table if not exists public.ssp_reminders_sent ( -- one row per reminder sent
  invoice_id uuid not null references public.billing_invoices (id) on delete cascade, -- the invoice it was about
  kind text not null check (kind in ('day_before', 'missed', 'final_warning')), -- 24 hours before, missed, or the final warning
  sent_at timestamptz not null default now(), -- when
  primary key (invoice_id, kind) -- each reminder once per invoice
); -- end of the table
alter table public.ssp_reminders_sent enable row level security; -- access rules apply (no one reads it directly)
revoke all on public.ssp_reminders_sent from anon, authenticated; -- only the database's own functions use it

-- ---------------------------------------------------------------------------
-- B4. Small helpers.
-- ---------------------------------------------------------------------------

-- Is this student in the program now (everything paid, not left)?
create or replace function private.ssp_member(p_student uuid) -- the student
returns boolean language sql stable security definer -- reads the program list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select exists (select 1 from public.ssp_enrolments e where e.student_id = p_student and e.status = 'enrolled'); -- in the program
$$; -- end of the function
revoke all on function private.ssp_member(uuid) from public; -- inside use only
grant execute on function private.ssp_member(uuid) to authenticated, service_role; -- (matching runs as the caller, so it needs this)

-- May the signed-in person ask about the program for this student? The
-- parent or guardian who manages them, or an adult learner who manages
-- their own account (no parent manages them).
create or replace function private.ssp_can_ask(p_student uuid) -- the student
returns boolean language sql stable security definer -- reads family links for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select private.can_manage_student(p_student) -- a parent or guardian who manages them
    or (private.is_student_self(p_student) and not private.has_managing_parent(p_student)); -- or the learner themselves, when no parent manages them
$$; -- end of the function
revoke all on function private.ssp_can_ask(uuid) from public; -- inside use only
grant execute on function private.ssp_can_ask(uuid) to authenticated, service_role; -- used by the functions below

-- Adds "ssp_update" to the allowed kinds of progress notice, keeping every
-- kind already allowed.
do $$ -- a one-off block
declare -- working values
  v_def text; -- the current rule
begin -- start
  select pg_get_constraintdef(c.oid) into v_def -- reads the current rule
  from pg_constraint c -- from the list of rules
  where c.conrelid = 'public.progress_notices'::regclass and c.conname = 'progress_notices_kind_check'; -- the kinds rule on progress notices
  if v_def is null then -- no rule found:
    raise exception 'The progress notice kinds rule is missing. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  if strpos(v_def, '''ssp_update''') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, 'ARRAY[') = 0 then -- the rule is in an unexpected shape:
    raise exception 'The progress notice kinds rule has changed shape. Ask for an updated file.'; -- stops
  end if; -- end of the check
  execute 'alter table public.progress_notices drop constraint progress_notices_kind_check'; -- removes the old rule
  execute 'alter table public.progress_notices add constraint progress_notices_kind_check ' -- adds it back
    || replace(v_def, 'ARRAY[', 'ARRAY[''ssp_update''::text, '); -- with "ssp_update" first in the list
end; -- finish
$$; -- end of the block

-- Tells the student's family about a change (an app notice, also emailed
-- by the usual progress notice emails): each person who manages the
-- student, or the learner themselves when no parent manages them, and each
-- person who pays for the family (once each, even if they are both).
create or replace function private.ssp_tell_family(p_student uuid, p_title text, p_body text) -- the student, the title and the words
returns void language sql security definer -- writes progress notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) -- a notice:
  select w.account_id, p_student, 'ssp_update', left(p_title, 200), left(p_body, 1000), now() -- to each person, about this student, now
  from ( -- the people to tell:
    select f.account_id from private.term_review_family(p_student) f -- the people who answer for the student
    union -- and (without repeats)
    select p.payer from public.students s cross join lateral private.billing_family_payer_ids(s.family_id) as p(payer) where s.id = p_student -- the people who pay for their family
  ) w -- (named "w")
  where w.account_id is not null; -- real people only
$$; -- end of the function
revoke all on function private.ssp_tell_family(uuid, text, text) from public; -- inside use only

-- Tells only the people who pay for the student's family (payment details
-- are for payers only, Carla 16 Nov 2026).
create or replace function private.ssp_tell_payers(p_student uuid, p_title text, p_body text) -- the student, the title and the words
returns void language sql security definer -- writes progress notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) -- a notice:
  select p.payer, p_student, 'ssp_update', left(p_title, 200), left(p_body, 1000), now() -- to each payer, about this student, now
  from public.students s -- the student
  cross join lateral private.billing_family_payer_ids(s.family_id) as p(payer) -- each person who pays for their family (billing's own function)
  where s.id = p_student and p.payer is not null; -- this student, real payers only
$$; -- end of the function
revoke all on function private.ssp_tell_payers(uuid, text, text) from public; -- inside use only

-- A student's first name, for notices.
create or replace function private.ssp_first_name(p_student uuid) -- the student
returns text language sql stable security definer -- reads the student's name
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select coalesce(private.first_name(s.full_name), 'your child') from public.students s where s.id = p_student; -- their first name
$$; -- end of the function
revoke all on function private.ssp_first_name(uuid) from public; -- inside use only

-- Money as "$1,234.50", for notices.
create or replace function private.ssp_money(p_cents integer) -- an amount in cents
returns text language sql immutable -- the same answer every time
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select '$' || to_char(p_cents / 100.0, 'FM999,999,990.00'); -- dollars and cents
$$; -- end of the function
revoke all on function private.ssp_money(integer) from public; -- inside use only

-- Cancels every unpaid program invoice for a student (through billing's own
-- function). Invoices with a payment on them are left for CLG to sort out.
create or replace function private.ssp_void_unpaid(p_student uuid, p_reason text) -- the student and the reason
returns void language plpgsql security definer -- asks billing to cancel invoices
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  r record; -- each invoice
begin -- start
  for r in -- for each program invoice
    select si.invoice_id from public.ssp_invoices si -- of this student
    join public.billing_invoices i on i.id = si.invoice_id -- (billing's table, only read here)
    where si.student_id = p_student and i.status in ('draft', 'awaiting_approval', 'open') -- not paid or cancelled yet
      and not exists (select 1 from public.billing_payments p where p.invoice_id = i.id and p.status in ('processing', 'succeeded')) -- with nothing paid or on its way
  loop -- go through them
    perform public.billing_void_invoice(r.invoice_id, left(p_reason, 500)); -- asks billing to cancel it
  end loop; -- end of the list
end; -- end of the code
$$; -- end of the function
revoke all on function private.ssp_void_unpaid(uuid, text) from public; -- inside use only

-- Works out where a student with a place is up to from their invoices:
-- deposit not paid (approved), deposit paid (secured), or everything paid
-- (enrolled, which switches the program on). Called whenever a program
-- invoice is paid or cancelled.
create or replace function private.ssp_refresh(p_student uuid) -- the student
returns void language plpgsql security definer -- writes the program list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_row public.ssp_enrolments; -- the student's program row
  v_deposit text; -- the deposit invoice's status
  v_left integer; -- program invoices still to pay
  v_name text; -- the student's first name
begin -- start
  select * into v_row from public.ssp_enrolments where student_id = p_student for update; -- reads the row (and holds it)
  if not found or v_row.status not in ('approved', 'secured') then return; end if; -- only places being paid for change here
  select status::text into v_deposit from public.billing_invoices where id = v_row.deposit_invoice_id; -- the deposit's status (billing's table, only read here)
  if v_deposit = 'void' and v_row.status = 'approved' then -- the deposit invoice was cancelled before it was paid:
    update public.ssp_enrolments set status = 'requested', deposit_invoice_id = null, decided_by = null, decided_at = null, deposit_deadline = null, deposit_reminded_at = null -- back to a request for an admin to decide again
    where student_id = p_student; -- for this student
    perform private.ssp_void_unpaid(p_student, 'Student Success Program deposit invoice cancelled'); -- cancels the rest of the program invoices
    return; -- done
  end if; -- end of that case
  if v_deposit is distinct from 'paid' then return; end if; -- deposit not paid yet: nothing changes
  select count(*) into v_left -- counts invoices still to pay:
  from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id -- the student's program invoices
  where si.student_id = p_student and i.status not in ('paid', 'void'); -- not paid and not cancelled
  v_name := private.ssp_first_name(p_student); -- the student's first name
  if v_left = 0 then -- everything is paid:
    update public.ssp_enrolments set status = 'enrolled', enrolled_at = now(), deposit_paid_on = coalesce(deposit_paid_on, private.billing_today()) -- the program switches on
    where student_id = p_student; -- for this student
    -- The study plan add-on (shared core): given from today, open-ended.
    insert into public.add_on_members (add_on, student_id, note, created_by) -- gives the add-on:
    select 'study_plans', p_student, 'Student Success Program', null -- study plans, for this student, noting why
    where exists (select 1 from public.add_ons where code = 'study_plans') -- if the add-on exists
    on conflict (add_on, student_id) do update set ends_on = null; -- already given: keeps it open-ended
    perform private.ssp_tell_family(p_student, -- tells the family:
      v_name || ' is in the Student Success Program', -- the title
      'Thank you, everything is paid. ' || v_name || ' is now in the Student Success Program. This includes a study plan, each term review at no charge, and priority when CLG finds a tutor.'); -- what it means
  elsif v_row.status = 'approved' then -- the deposit has just been paid, with more to pay:
    update public.ssp_enrolments set status = 'secured', deposit_paid_on = private.billing_today() -- the place is secured
    where student_id = p_student; -- for this student
    perform private.ssp_tell_family(p_student, -- tells the family:
      'Student Success Program place secured for ' || v_name, -- the title
      'Thank you, the deposit has been received and ' || v_name || '''s place is secured. The program switches on once the rest of the program invoice is paid. Each payment is taken from your saved card or bank account on its due date, and you are reminded the day before.'); -- what happens next
  end if; -- end of the cases
end; -- end of the code
$$; -- end of the function
revoke all on function private.ssp_refresh(uuid) from public; -- inside use only

-- Forfeits a place: cancels unpaid program invoices, switches off anything
-- the program gave, puts the student back on the waiting list (as a new
-- request, at the back of the queue), and tells the family and the owner and
-- Operations admins (which student and family, and why the place opened,
-- Carla, 23 Nov 2026). Paid invoices stay paid; any refund follows CLG's
-- terms and is done in Billing.
create or replace function private.ssp_forfeit(p_student uuid, p_reason text) -- the student and the reason
returns void language plpgsql security definer -- writes the program list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_name text := private.ssp_first_name(p_student); -- the student's first name
  v_full text; -- the student's full name (for admins)
  v_family text; -- the family's name (for admins)
begin -- start
  update public.ssp_enrolments set -- puts the student back on the waiting list:
    status = 'requested', requested_at = now(), -- a request again, at the back of the queue
    decline_reason = left('Place forfeited because ' || p_reason, 500), -- why the last place was lost (the family and admins see it)
    ended_at = now(), ended_by = auth.uid(), -- when the place was lost, and by whom (blank when the app did it)
    deposit_invoice_id = null, decided_by = null, decided_at = null, deposit_deadline = null, deposit_reminded_at = null, -- the old offer cleared
    agreement_until = null, agreement_note = null, enrolled_at = null -- and the old agreement and joining date cleared
  where student_id = p_student and status in ('approved', 'secured', 'enrolled'); -- only a place that was held
  if not found then return; end if; -- nothing held: nothing to do
  perform private.ssp_void_unpaid(p_student, 'Student Success Program place forfeited'); -- cancels unpaid program invoices
  update public.add_on_members set ends_on = greatest(starts_on, private.billing_today()) -- ends the program's study plan today
  where add_on = 'study_plans' and student_id = p_student and note = 'Student Success Program' and ends_on is null; -- only the program's one
  perform private.ssp_tell_family(p_student, -- tells the family:
    'Student Success Program place forfeited for ' || v_name, -- the title
    'The place in the Student Success Program for ' || v_name || ' has been forfeited because ' || p_reason -- what happened and why,
      || ' Any unpaid program invoices have been cancelled, and ' || v_name || ' is back on the waiting list for a place. Please contact CLG if you have any questions.'); -- what it means
  select s.full_name, f.name into v_full, v_family from public.students s left join public.families f on f.id = s.family_id where s.id = p_student; -- the names, for admins
  perform private.notify_admins( -- tells the owner and Operations admins:
    'Student Success Program place open', -- the title
    left('A Student Success Program place is open. It was for ' || coalesce(v_full, 'a student') || coalesce(' (' || v_family || ' family)', '') -- who it was for,
      || ' and was forfeited because ' || p_reason || ' They are back on the waiting list.', 1000)); -- why, and where they are now
end; -- end of the code
$$; -- end of the function
revoke all on function private.ssp_forfeit(uuid, text) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- B5. Places: how many there are, used and left (front desk admins).
-- ---------------------------------------------------------------------------
-- A place is "used" from approval until it is withdrawn, forfeited or ended.
drop function if exists public.ssp_places(); -- replaces the function if run again (so a change to its columns always applies)
create or replace function public.ssp_places() -- no inputs
returns table (spaces integer, used integer, places_left integer, waiting integer, deposit_hours integer, reminder_hours integer, forfeit_days integer) -- the numbers
language sql stable security definer -- reads the program list for front desk admins
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select s.spaces, -- places in total
         u.used, -- places used
         greatest(s.spaces - u.used, 0), -- places left (never below zero)
         u.waiting, -- requests waiting for a decision
         s.deposit_hours, s.reminder_hours, s.forfeit_days -- the deadlines
  from public.ssp_settings s -- the settings
  cross join lateral ( -- with the counts:
    select count(*) filter (where e.status in ('approved', 'secured', 'enrolled'))::int as used, -- held, secured or in the program
           count(*) filter (where e.status = 'requested')::int as waiting -- asked, not yet decided
    from public.ssp_enrolments e -- from the program list
    where e.status in ('requested', 'approved', 'secured', 'enrolled') -- (uses the index)
  ) u -- (named "u")
  where (select private.is_front_desk()); -- front desk admins only (others get nothing)
$$; -- end of the function
revoke all on function public.ssp_places() from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_places() to authenticated; -- signed-in people (the check is inside)

-- Changes the number of places and the days before a missed payment
-- forfeits the place (owner and Operations).
drop function if exists public.ssp_set_places(integer, integer); -- replaces the function if run again
create or replace function public.ssp_set_places(p_spaces integer, p_forfeit_days integer) -- the new numbers
returns void language plpgsql security definer -- writes the settings for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_spaces is null or p_spaces < 0 or p_spaces > 1000 then -- an odd number of places
    raise exception 'The number of places must be between 0 and 1000' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_forfeit_days is null or p_forfeit_days < 1 or p_forfeit_days > 60 then -- an odd number of days
    raise exception 'The days before a missed payment forfeits the place must be between 1 and 60' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.ssp_settings set spaces = p_spaces, forfeit_days = p_forfeit_days, updated_by = auth.uid(), updated_at = now(); -- saves them
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_set_places(integer, integer) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_set_places(integer, integer) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- B6. The family's side: asking, cancelling, and seeing where it is up to.
-- ---------------------------------------------------------------------------

-- The family ticks the box to ask about the program.
create or replace function public.ssp_request(p_student uuid, p_note text default null) -- the student and an optional message
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_status text; -- where the student is up to now (if anywhere)
begin -- start
  if not private.ssp_can_ask(p_student) then -- not their child (or themselves):
    raise exception 'Only the student''s parent or guardian can ask about the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  select status into v_status from public.ssp_enrolments where student_id = p_student for update; -- reads where they are up to (and holds the row)
  if v_status in ('approved', 'secured', 'enrolled') then -- already has a place:
    raise exception 'This student already has a place in the Student Success Program' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.ssp_enrolments (student_id, status, request_note, requested_by, requested_at) -- adds the request:
  values (p_student, 'requested', nullif(left(btrim(coalesce(p_note, '')), 500), ''), auth.uid(), now()) -- with the message (if any), who asked and when
  on conflict (student_id) do update set -- or, if there is a row already:
    status = 'requested', request_note = excluded.request_note, -- a request again, with the new message
    requested_by = excluded.requested_by, -- who asked,
    requested_at = case when public.ssp_enrolments.status = 'requested' then public.ssp_enrolments.requested_at else now() end, -- when (kept if they are only changing the message),
    deposit_invoice_id = null, decided_by = null, decided_at = null, decline_reason = null, -- with the last decision cleared
    deposit_deadline = null, deposit_reminded_at = null, agreement_until = null, agreement_note = null, -- and the last place's dates cleared
    ended_at = null, ended_by = null; -- and not marked as ended
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_request(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_request(uuid, text) to authenticated; -- signed-in people (the check is inside)

-- The family cancels their request (only before CLG decides).
create or replace function public.ssp_cancel_request(p_student uuid) -- the student
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.ssp_can_ask(p_student) then -- not their child (or themselves):
    raise exception 'Only the student''s parent or guardian can change this request' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set status = 'withdrawn', decided_by = auth.uid(), decided_at = now() -- marks it as cancelled
  where student_id = p_student and status = 'requested'; -- only a request still waiting
  if not found then -- nothing waiting:
    raise exception 'There is no request waiting to cancel. If a place has been offered, please contact CLG.' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_cancel_request(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_cancel_request(uuid) to authenticated; -- signed-in people (the check is inside)

-- Where a student is up to, for their family. Gives one row for a student
-- the person may see as family (status blank if they have never asked).
-- Leaves out CLG's own notes. Money details (total, paid, next payment and
-- the deposit deadline) are only given to the people who pay (billing
-- information is for payers only, Carla 16 Nov 2026).
drop function if exists public.ssp_family_status(uuid); -- replaces the function if run again (so a change to its columns always applies)
create or replace function public.ssp_family_status(p_student uuid) -- the student
returns table ( -- what the family sees:
  status text, can_ask boolean, requested_at timestamptz, request_note text, decline_reason text, enrolled_at timestamptz, -- where they are up to
  is_payer boolean, plan text, total_cents integer, paid_cents integer, deposit_deadline timestamptz, next_due_on date, next_amount_cents integer -- payment details (payers only)
) -- (end of the columns)
language sql stable security definer -- reads the program list and invoices for them
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select e.status, -- where they are up to (blank if never asked)
         private.ssp_can_ask(s.id), -- whether this person can ask or cancel (a student whose parent manages them can only look)
         e.requested_at, e.request_note, e.decline_reason, e.enrolled_at, -- when they asked, their message, any reason given, when they joined
         pay.is_payer, -- whether this person pays for the family
         case when pay.is_payer then e.plan end, -- the payment plan (payers only)
         case when pay.is_payer then m.total end, -- the total of the program invoices, with fees (payers only)
         case when pay.is_payer then m.paid end, -- how much is paid (payers only)
         case when pay.is_payer then e.deposit_deadline end, -- when the deposit must be paid by (payers only)
         case when pay.is_payer then m.next_due end, -- the next payment's due date (payers only)
         case when pay.is_payer then m.next_amount end -- and its amount (payers only)
  from public.students s -- the student
  cross join lateral (select private.is_family_payer(s.family_id) as is_payer) pay -- whether this person pays (worked out once)
  left join public.ssp_enrolments e on e.student_id = s.id -- with their program row (if any)
  left join lateral ( -- with their program invoices added up:
    select sum(i.total_cents)::int as total, -- the total
           sum(private.billing_invoice_paid(i.id))::int as paid, -- what is paid
           min(i.due_on) filter (where i.status = 'open') as next_due, -- the next unpaid due date
           (array_agg(i.total_cents - private.billing_invoice_paid(i.id) order by i.due_on) filter (where i.status = 'open'))[1] as next_amount -- and what is left on it
    from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id -- (billing's table, only read here)
    where si.student_id = s.id and i.status <> 'void' -- this student's invoices that are not cancelled
  ) m on e.status in ('approved', 'secured', 'enrolled') -- only while they have a place
  where s.id = p_student -- this student
    and (private.ssp_can_ask(s.id) or private.is_student_self(s.id)); -- only for their family (or the student themselves)
$$; -- end of the function
revoke all on function public.ssp_family_status(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_family_status(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- B7. The admin's side (owner and Operations admins).
-- ---------------------------------------------------------------------------
drop function if exists public.ssp_enrol(uuid, integer, date, date, text); -- removes the first version's tick box
drop function if exists public.ssp_approve(uuid, integer, date, text); -- removes the second version's approve (new inputs below)

-- Approves a place: checks there is a place left, holds it, and asks
-- billing to make the program invoices: the deposit (due within the set
-- hours, charged straight away from the saved card or bank account), then
-- the rest, paid in full by the finish date, or in equal monthly or weekly
-- payments until then, each with its plan fee. Gives back a plain summary.
create or replace function public.ssp_approve( -- approves a place:
  p_student uuid, -- the student
  p_total_cents integer, -- the program total, deposit included (plan fees are added on top)
  p_plan text, -- 'full', 'monthly' or 'weekly'
  p_finish_on date, -- the date the last payment is due by
  p_sessions integer default null, -- sessions planned
  p_book_until date default null, -- the book-till date
  p_note text default null -- CLG's own note
)
returns text -- a plain summary of the payments
language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_family uuid; -- the student's family
  v_settings public.ssp_settings; -- places and deadlines
  v_status text; -- where the student is up to now
  v_used integer; -- places already used
  v_deposit public.billing_price_items; -- the deposit price item
  v_today date := private.billing_today(); -- today in Adelaide
  v_deadline timestamptz := now(); -- when the deposit must be paid by (set below)
  v_balance integer; -- the total less the deposit
  v_count integer := 0; -- how many payments after the deposit
  v_each integer; -- each payment (before its fee)
  v_due date; -- each payment's due date
  v_fee_code text; -- the plan fee's price item
  v_fee integer := 0; -- the plan fee amount
  v_invoice uuid; -- each invoice made
  v_name text; -- the student's first name
  v_summary text; -- the plain summary
  i integer; -- a counter
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  select family_id into v_family from public.students where id = p_student; -- reads the student's family
  if not found then -- no such student
    raise exception 'That student could not be found' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  if v_family is null then -- no family to bill
    raise exception 'This student is not linked to a family, so there is no one to send the program invoice to' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_sessions is not null and (p_sessions < 1 or p_sessions > 200) then -- an odd number of sessions
    raise exception 'The number of sessions must be between 1 and 200' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_plan is null or p_plan not in ('full', 'monthly', 'weekly') then -- no plan chosen
    raise exception 'Please choose a payment plan: pay in full, monthly or weekly' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_finish_on is null or p_finish_on < v_today then -- no finish date, or one in the past
    raise exception 'Please choose the date the last payment is due by (today or later)' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into v_deposit from public.billing_price_items where code = 'ssp_deposit'; -- the deposit price item
  if not found or not v_deposit.active or v_deposit.amount_cents <= 0 then -- missing, switched off or $0:
    raise exception 'The Student Success Program deposit price is not set. An Owner or Finance admin can set it under Billing, Prices and settings.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_total_cents is null or p_total_cents < v_deposit.amount_cents then -- a total below the deposit
    raise exception 'The program total must be at least the deposit (%)', private.ssp_money(v_deposit.amount_cents) using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_balance := p_total_cents - v_deposit.amount_cents; -- what is left after the deposit
  if v_balance > 0 then -- something left to pay after the deposit:
    if p_plan = 'full' then -- in full:
      v_count := 1; -- one payment, on the finish date
    elsif p_plan = 'monthly' then -- monthly:
      while (v_today + make_interval(months => v_count + 1))::date <= p_finish_on loop v_count := v_count + 1; end loop; -- counts whole months until the finish date
      v_fee_code := 'plan_fee_monthly'; -- with the monthly plan fee
    else -- weekly:
      v_count := (p_finish_on - v_today) / 7; -- counts whole weeks until the finish date
      v_fee_code := 'plan_fee_weekly'; -- with the weekly plan fee
    end if; -- end of the plans
    if v_count < 1 then -- not even one month or week left:
      raise exception 'The finish date is too soon for a % plan. Choose a later date, or Pay in full.', p_plan using errcode = '22023'; -- plain message
    end if; -- end of the check
    if v_count > 199 then v_count := 199; end if; -- never more than 199 payments (a safety limit)
  end if; -- end of the balance

  select * into v_settings from public.ssp_settings for update; -- reads the settings and holds them, so two admins cannot give away the last place at once
  select status into v_status from public.ssp_enrolments where student_id = p_student for update; -- where the student is up to (and holds the row)
  if v_status in ('approved', 'secured', 'enrolled') then -- already has a place:
    raise exception 'This student already has a place in the Student Success Program' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select count(*) into v_used from public.ssp_enrolments where status in ('approved', 'secured', 'enrolled'); -- places already used
  if v_used >= v_settings.spaces then -- none left:
    raise exception 'All % places in the Student Success Program are taken. Add more places, or wait until a place is free.', v_settings.spaces using errcode = '22023'; -- plain message
  end if; -- end of the check
  v_deadline := now() + make_interval(hours => v_settings.deposit_hours); -- the deposit deadline (72 hours to start)
  insert into public.ssp_enrolments (student_id, status, sessions_planned, book_until, note, decided_by, decided_at, requested_at, program_total_cents, plan, finish_on, deposit_deadline) -- holds the place:
  values (p_student, 'approved', p_sessions, p_book_until, nullif(left(btrim(coalesce(p_note, '')), 500), ''), auth.uid(), now(), now(), p_total_cents, p_plan, p_finish_on, v_deadline) -- with the details given
  on conflict (student_id) do update set -- or, if there is a row already:
    status = 'approved', sessions_planned = excluded.sessions_planned, book_until = excluded.book_until, -- approved, with the sessions and date,
    note = excluded.note, decided_by = excluded.decided_by, decided_at = excluded.decided_at, -- the note, and who approved and when,
    program_total_cents = excluded.program_total_cents, plan = excluded.plan, finish_on = excluded.finish_on, deposit_deadline = excluded.deposit_deadline, -- the money and dates,
    decline_reason = null, deposit_paid_on = null, deposit_reminded_at = null, agreement_until = null, agreement_note = null, -- with anything from before cleared
    enrolled_at = null, ended_at = null, ended_by = null; -- (and not ended)
  v_name := private.ssp_first_name(p_student); -- the student's first name

  -- Payment 1: the deposit, charged straight away and due by the deadline.
  v_invoice := private.billing_program_invoice(v_family, p_student, 'deposit', 'ssp_deposit', -- asks billing for the deposit invoice:
    'Student Success Program for ' || v_name || ': deposit (payment 1 of ' || (v_count + 1) || ')', -- its words,
    v_deposit.amount_cents, null, (v_deadline at time zone 'Australia/Adelaide')::date, v_today); -- the deposit amount, no fee, due by the deadline, charged today
  update public.ssp_enrolments set deposit_invoice_id = v_invoice where student_id = p_student; -- links it to the place
  insert into public.ssp_invoices (invoice_id, student_id, payment_no) values (v_invoice, p_student, 1); -- and lists it as payment 1

  -- The rest: one payment in full, or equal monthly or weekly payments
  -- (any odd cents go on the last one), each with its plan fee.
  v_each := case when v_count > 0 then v_balance / v_count else 0 end; -- each payment (whole cents)
  for i in 1 .. v_count loop -- for each payment after the deposit:
    v_due := case p_plan -- its due date:
      when 'full' then p_finish_on -- in full: the finish date
      when 'monthly' then (v_today + make_interval(months => i))::date -- monthly: one month apart
      else v_today + 7 * i end; -- weekly: one week apart
    v_invoice := private.billing_program_invoice(v_family, p_student, 'program', 'ssp_program', -- asks billing for the invoice:
      'Student Success Program for ' || v_name || ': payment ' || (i + 1) || ' of ' || (v_count + 1), -- its words,
      case when i = v_count then v_balance - v_each * (v_count - 1) else v_each end, -- the amount (the last one takes any odd cents)
      v_fee_code, v_due, v_due); -- the plan fee (if any), due and charged on the day
    insert into public.ssp_invoices (invoice_id, student_id, payment_no) values (v_invoice, p_student, i + 1); -- lists it
  end loop; -- end of the payments

  select coalesce(amount_cents, 0) into v_fee from public.billing_price_items where code = v_fee_code and active; -- the plan fee amount (for the summary)
  v_summary := private.ssp_money(v_deposit.amount_cents) || ' deposit now' -- the plain summary: the deposit,
    || case -- then the rest:
         when v_count = 0 then ', and nothing more to pay' -- nothing more,
         when p_plan = 'full' then ', then ' || private.ssp_money(v_balance) || ' on ' || to_char(p_finish_on, 'FMDD FMMonth YYYY') -- in full by the finish date,
         else ', then ' || v_count || ' ' || p_plan || ' payments of about ' || private.ssp_money(v_each) -- or the instalments,
              || case when coalesce(v_fee, 0) > 0 then ' plus a ' || private.ssp_money(v_fee) || ' plan fee each' else '' end -- with their fee,
              || ', the last on ' || to_char(v_due, 'FMDD FMMonth YYYY') end -- and the last date
    || '. Total ' || private.ssp_money(p_total_cents + coalesce(v_fee, 0) * case when p_plan = 'full' then 0 else v_count end) || '.'; -- and the full total including fees

  perform private.ssp_tell_family(p_student, -- tells the family:
    'A place in the Student Success Program for ' || v_name, -- the title
    'CLG has offered ' || v_name || ' a place in the Student Success Program. The deposit secures the place and needs to be paid by ' -- the offer,
      || to_char(v_deadline at time zone 'Australia/Adelaide', 'FMHH12:MI am "on" FMDD FMMonth') || ', or the place will be forfeited. ' -- the deadline,
      || 'The person who pays for your family''s sessions can see the payments in Billing. Payments are taken from your saved card or bank account. ' -- where to see and how it is paid,
      || 'The program switches on once everything is paid.'); -- what happens then
  return v_summary; -- gives back the summary
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_approve(uuid, integer, text, date, integer, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_approve(uuid, integer, text, date, integer, date, text) to authenticated; -- signed-in people (the check is inside)

-- Changes the details of a place (sessions, book-till date and note). The
-- money and payments stay as they are.
create or replace function public.ssp_save_details( -- saves the details:
  p_student uuid, -- the student
  p_sessions integer default null, -- sessions planned
  p_book_until date default null, -- the book-till date
  p_note text default null -- CLG's own note
)
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_sessions is not null and (p_sessions < 1 or p_sessions > 200) then -- an odd number of sessions
    raise exception 'The number of sessions must be between 1 and 200' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments -- saves:
  set sessions_planned = p_sessions, book_until = p_book_until, note = nullif(left(btrim(coalesce(p_note, '')), 500), '') -- the sessions, date and note
  where student_id = p_student and status in ('approved', 'secured', 'enrolled'); -- only for a place that is held
  if not found then -- no place:
    raise exception 'This student does not have a place in the Student Success Program' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_save_details(uuid, integer, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_save_details(uuid, integer, date, text) to authenticated; -- signed-in people (the check is inside)

-- Records a payment agreement with CLG: no forfeiting until the date given
-- (a blank date ends the agreement).
create or replace function public.ssp_set_agreement(p_student uuid, p_until date, p_note text default null) -- the student, the date and what was agreed
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if p_until is not null and (p_until < private.billing_today() or p_until > private.billing_today() + 365) then -- a date in the past or over a year away
    raise exception 'The agreement date must be from today and within a year' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set agreement_until = p_until, agreement_note = nullif(left(btrim(coalesce(p_note, '')), 500), '') -- saves the agreement
  where student_id = p_student and status in ('approved', 'secured'); -- only for a place still being paid for
  if not found then -- no such place:
    raise exception 'This student does not have a place still being paid for' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_set_agreement(uuid, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_set_agreement(uuid, date, text) to authenticated; -- signed-in people (the check is inside)

-- Declines a request, with an optional reason that the family sees.
create or replace function public.ssp_decline(p_student uuid, p_reason text default null) -- the student and the reason
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 500), ''); -- the reason, tidied (or nothing)
  v_name text; -- the student's first name
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set status = 'declined', decline_reason = v_reason, decided_by = auth.uid(), decided_at = now() -- marks it as declined
  where student_id = p_student and status = 'requested'; -- only a request still waiting
  if not found then -- nothing waiting:
    raise exception 'There is no request waiting for this student' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  v_name := private.ssp_first_name(p_student); -- the student's first name
  perform private.ssp_tell_family(p_student, -- tells the family:
    'Student Success Program request for ' || v_name, -- the title
    'Thank you for asking about the Student Success Program for ' || v_name || '. CLG is not able to offer a place at the moment.' -- the answer
      || coalesce(' ' || v_reason, '') || ' You are welcome to ask again later, or to contact CLG with any questions.'); -- the reason (if any) and what they can do
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_decline(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_decline(uuid, text) to authenticated; -- signed-in people (the check is inside)

-- Withdraws a place before the deposit is paid. Billing cancels the program
-- invoices (through billing's own function), and the place is free again.
create or replace function public.ssp_withdraw(p_student uuid, p_reason text) -- the student and the reason
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 500), ''); -- the reason, tidied (or nothing)
  v_invoice uuid; -- the deposit invoice
  v_name text; -- the student's first name
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if v_reason is null or char_length(v_reason) < 5 then -- no proper reason:
    raise exception 'Please give a reason for withdrawing the place' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select deposit_invoice_id into v_invoice from public.ssp_enrolments where student_id = p_student and status = 'approved' for update; -- the place waiting for its deposit (held)
  if not found then -- no place waiting:
    raise exception 'This student does not have a place waiting for its deposit. To take a student out of the program, use Remove from the program.' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  if exists (select 1 from public.billing_payments where invoice_id = v_invoice and status in ('processing', 'succeeded')) then -- the deposit is paid or on its way:
    raise exception 'The deposit has been paid or is on its way, so the place cannot be withdrawn. Use Remove from the program instead, and follow CLG''s terms for any refund.' using errcode = '22023'; -- plain message (nothing is changed)
  end if; -- end of the check
  update public.ssp_enrolments set status = 'withdrawn', decline_reason = v_reason, decided_by = auth.uid(), decided_at = now() -- marks the place as withdrawn first (so cancelling the invoices does not reopen the request)
  where student_id = p_student; -- for this student
  perform private.ssp_void_unpaid(p_student, 'Student Success Program place withdrawn: ' || v_reason); -- asks billing to cancel the program invoices
  v_name := private.ssp_first_name(p_student); -- the student's first name
  perform private.ssp_tell_family(p_student, -- tells the family:
    'Student Success Program place for ' || v_name, -- the title
    'The place offered to ' || v_name || ' in the Student Success Program has been withdrawn, and the program invoices have been cancelled. ' || v_reason -- what happened and why
      || ' Please contact CLG if you have any questions.'); -- what they can do
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_withdraw(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_withdraw(uuid, text) to authenticated; -- signed-in people (the check is inside)

-- Takes a student out of the program (after the deposit was paid). Unpaid
-- program invoices are cancelled. Any refund follows CLG's terms and is
-- done in Billing, not here.
create or replace function public.ssp_leave(p_student uuid) -- the student
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set status = 'left', ended_at = now(), ended_by = auth.uid() -- marks them as left
  where student_id = p_student and status in ('secured', 'enrolled'); -- only someone whose place is secured or in use
  if not found then raise exception 'That student is not in the Student Success Program' using errcode = 'P0002'; end if; -- not in it
  perform private.ssp_void_unpaid(p_student, 'Student Success Program: student left the program'); -- cancels unpaid program invoices
  -- The study plan add-on given for the program ends today (one given for another reason is left alone).
  update public.add_on_members set ends_on = greatest(starts_on, (now() at time zone 'Australia/Adelaide')::date) -- ends it today
  where add_on = 'study_plans' and student_id = p_student and note = 'Student Success Program' and ends_on is null; -- only the program's one
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_leave(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_leave(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- B8. When a program invoice is paid or cancelled.
-- ---------------------------------------------------------------------------
-- Billing marks the invoice paid however it was paid: automatically from
-- the saved card or bank account, Pay now, or a payment entered in Xero.
-- This trigger then works out where the student is up to (ssp_refresh). It
-- only writes progress's own tables and the shared add-ons list; it never
-- changes the invoice.
create or replace function private.ssp_invoice_changed() -- runs after an invoice's status changes
returns trigger language plpgsql security definer -- writes the program list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_student uuid; -- the student whose invoice it is
begin -- start
  select student_id into v_student from public.ssp_invoices where invoice_id = new.id; -- finds the student
  if v_student is null then -- not listed (for example a deposit from the first version):
    select student_id into v_student from public.ssp_enrolments where deposit_invoice_id = new.id; -- looks for it as a deposit
  end if; -- end of that look-up
  if v_student is not null then perform private.ssp_refresh(v_student); end if; -- works out where they are up to
  return null; -- (an "after" trigger gives nothing back)
end; -- end of the code
$$; -- end of the function
revoke all on function private.ssp_invoice_changed() from public; -- inside use only
drop trigger if exists ssp_deposit_changed on public.billing_invoices; -- removes the earlier version's trigger
drop function if exists private.ssp_deposit_changed(); -- and its function
drop trigger if exists ssp_invoice_changed on public.billing_invoices; -- replaces the trigger if run again
create trigger ssp_invoice_changed after update of status on public.billing_invoices -- after an invoice's status changes
  for each row -- for each invoice
  when (new.kind in ('deposit', 'program') and old.status is distinct from new.status and new.status in ('paid', 'void')) -- only program invoices that are paid or cancelled (so other invoices cost nothing)
  execute function private.ssp_invoice_changed(); -- runs the function above

-- ---------------------------------------------------------------------------
-- B9. The hourly job: reminders, missed payments and forfeiting.
-- ---------------------------------------------------------------------------
-- Run every hour by the app's scheduler (/api/ssp/cron), as the server.
--   1. Deposit not paid by the reminder time (48 hours): the payer is
--      reminded that the place will be forfeited at the deadline.
--   2. Deposit not paid by the deadline (72 hours): the place is forfeited
--      (unless an admin recorded a payment agreement still running).
--   3. 24 hours before a program payment is taken: the payer is reminded.
--   4. A program payment missed (its due day has passed and it is unpaid):
--      the payer is warned, again 2 days before the forfeit day, and the
--      place is forfeited the set number of days after the due day (7 to
--      start), unless a payment agreement is running.
--   5. A weekly-paying family whose sessions are credited two weeks in a row
--      because the weekly invoice was not paid: the place is forfeited,
--      unless a payment agreement is running.
-- A forfeited place puts the student back on the waiting list, and the
-- family and admins are told. Gives back how many things it did.
create or replace function public.ssp_run_deadlines() -- no inputs
returns integer language plpgsql security definer -- reads and writes the program list as the server
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_settings public.ssp_settings; -- the deadlines
  v_today date := private.billing_today(); -- today in Adelaide
  v_done integer := 0; -- how many things were done
  r record; -- each row being looked at
  v_name text; -- a student's first name
begin -- start
  if not private.is_backend() then -- only the server
    raise exception 'Only the server can run the program deadlines' using errcode = '42501'; -- plain message
  end if; -- end of the check
  select * into v_settings from public.ssp_settings; -- reads the deadlines

  -- 1. The deposit reminder.
  for r in -- for each place waiting for its deposit, past the reminder time, not yet reminded:
    select e.student_id, e.deposit_deadline from public.ssp_enrolments e -- from the program list
    where e.status = 'approved' and e.deposit_reminded_at is null -- waiting, not reminded
      and e.decided_at + make_interval(hours => v_settings.reminder_hours) <= now() -- reminder time reached
      and e.deposit_deadline > now() -- deadline not yet passed
  loop -- go through them
    v_name := private.ssp_first_name(r.student_id); -- the first name
    perform private.ssp_tell_payers(r.student_id, -- tells the people who pay:
      'Reminder: Student Success Program deposit for ' || v_name, -- the title
      'The deposit for ' || v_name || '''s place in the Student Success Program has not been received. Please pay it in Billing by ' -- what is missing,
        || to_char(r.deposit_deadline at time zone 'Australia/Adelaide', 'FMHH12:MI am "on" FMDD FMMonth') -- the deadline,
        || ', or the place will be forfeited. If your saved card or bank account did not work, you can update it in Billing or choose Pay now.'); -- and what they can do
    update public.ssp_enrolments set deposit_reminded_at = now() where student_id = r.student_id; -- notes it was sent
    v_done := v_done + 1; -- counts it
  end loop; -- end of the reminders

  -- 2. The deposit deadline.
  for r in -- for each place still waiting for its deposit after the deadline, with no agreement running:
    select e.student_id from public.ssp_enrolments e -- from the program list
    where e.status = 'approved' and e.deposit_deadline <= now() -- deadline passed
      and (e.agreement_until is null or e.agreement_until < v_today) -- no payment agreement running
      and not exists (select 1 from public.billing_payments p where p.invoice_id = e.deposit_invoice_id and p.status = 'processing') -- no payment on its way
  loop -- go through them
    perform private.ssp_forfeit(r.student_id, 'the deposit was not paid by the deadline.'); -- forfeits the place
    v_done := v_done + 1; -- counts it
  end loop; -- end of the deadlines

  -- 3. 24 hours before a payment is taken (the day before its charge day).
  for r in -- for each unpaid program payment charged tomorrow, not yet reminded:
    select si.student_id, si.invoice_id, i.total_cents - private.billing_invoice_paid(i.id) as owing, i.charge_on -- the student, invoice, what is owed and the day
    from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id -- (billing's table, only read here)
    join public.ssp_enrolments e on e.student_id = si.student_id -- with the place
    where i.status = 'open' and i.charge_on = v_today + 1 -- unpaid, charged tomorrow
      and e.status in ('approved', 'secured') -- for a place still being paid for
      and not exists (select 1 from public.ssp_reminders_sent s where s.invoice_id = si.invoice_id and s.kind = 'day_before') -- not yet reminded
  loop -- go through them
    v_name := private.ssp_first_name(r.student_id); -- the first name
    perform private.ssp_tell_payers(r.student_id, -- tells the people who pay:
      'Student Success Program payment tomorrow for ' || v_name, -- the title
      'A Student Success Program payment of ' || private.ssp_money(r.owing) || ' for ' || v_name || ' will be taken from your saved card or bank account tomorrow (' -- the amount,
        || to_char(r.charge_on, 'FMDD FMMonth') || '). Please make sure your payment details in Billing are up to date.'); -- the day and what to check
    insert into public.ssp_reminders_sent (invoice_id, kind) values (r.invoice_id, 'day_before'); -- notes it was sent
    v_done := v_done + 1; -- counts it
  end loop; -- end of the day-before reminders

  -- 4. Missed program payments (after the deposit).
  for r in -- for each unpaid program payment whose due day has passed, for a secured place:
    select distinct on (si.student_id) si.student_id, si.invoice_id, i.due_on, -- the student, the oldest missed invoice and its due day
           i.total_cents - private.billing_invoice_paid(i.id) as owing, e.agreement_until -- what is owed and any agreement
    from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id -- (billing's table, only read here)
    join public.ssp_enrolments e on e.student_id = si.student_id -- with the place
    where e.status = 'secured' and i.kind = 'program' and i.status = 'open' and i.due_on < v_today -- missed
      and not exists (select 1 from public.billing_payments p where p.invoice_id = i.id and p.status = 'processing') -- no payment on its way
    order by si.student_id, i.due_on -- the oldest missed one for each student
  loop -- go through them
    v_name := private.ssp_first_name(r.student_id); -- the first name
    if r.agreement_until is not null and r.agreement_until >= v_today then continue; end if; -- a payment agreement is running: nothing happens
    if v_today >= r.due_on + v_settings.forfeit_days then -- the forfeit day has come:
      perform private.ssp_forfeit(r.student_id, 'a program payment was not made, and no payment plan was agreed with CLG.'); -- forfeits the place
      v_done := v_done + 1; -- counts it
    elsif v_today >= r.due_on + greatest(v_settings.forfeit_days - 2, 1) -- 2 days before the forfeit day:
          and not exists (select 1 from public.ssp_reminders_sent s where s.invoice_id = r.invoice_id and s.kind = 'final_warning') then -- not yet warned:
      perform private.ssp_tell_payers(r.student_id, -- tells the people who pay:
        'Final reminder: Student Success Program payment for ' || v_name, -- the title
        'The Student Success Program payment of ' || private.ssp_money(r.owing) || ' for ' || v_name || ' is still unpaid. ' -- what is owed,
          || v_name || '''s place will be forfeited on ' || to_char(r.due_on + v_settings.forfeit_days, 'FMDD FMMonth') -- when the place goes,
          || ' unless it is paid in Billing, or a payment plan is agreed with CLG before then.'); -- and how to keep it
      insert into public.ssp_reminders_sent (invoice_id, kind) values (r.invoice_id, 'final_warning') on conflict do nothing; -- notes it was sent
      v_done := v_done + 1; -- counts it
    elsif not exists (select 1 from public.ssp_reminders_sent s where s.invoice_id = r.invoice_id and s.kind = 'missed') then -- first warning not yet sent:
      perform private.ssp_tell_payers(r.student_id, -- tells the people who pay:
        'Student Success Program payment missed for ' || v_name, -- the title
        'The Student Success Program payment of ' || private.ssp_money(r.owing) || ' for ' || v_name || ' due on ' || to_char(r.due_on, 'FMDD FMMonth') || ' was not received. ' -- what was missed,
          || 'Please pay it in Billing, or contact CLG to agree a payment plan. If neither happens by ' || to_char(r.due_on + v_settings.forfeit_days, 'FMDD FMMonth') -- what to do and by when,
          || ', ' || v_name || '''s place in the program will be forfeited.'); -- and what happens otherwise
      insert into public.ssp_reminders_sent (invoice_id, kind) values (r.invoice_id, 'missed') on conflict do nothing; -- notes it was sent
      v_done := v_done + 1; -- counts it
    end if; -- end of the cases
  end loop; -- end of the missed payments

  -- 5. Weekly payers (Carla, 23 Nov 2026): if the family pays weekly and a
  --    session was credited because it was missed while the family was on
  --    hold for not paying, two weeks in a row, the place is forfeited
  --    (unless a payment agreement with CLG is running). Only sessions
  --    credited since the place was approved count. Billing's credits and
  --    the sessions are only read here.
  for r in -- for each place held by a weekly-paying family with 2 weeks in a row of credited sessions:
    select e.student_id from public.ssp_enrolments e -- from the program list
    join public.students s on s.id = e.student_id -- with the student's family
    join public.billing_accounts b on b.family_id = s.family_id and b.plan = 'weekly' -- paying weekly (billing's table, only read here)
    where e.status in ('approved', 'secured', 'enrolled') -- a place that is held
      and (e.agreement_until is null or e.agreement_until < v_today) -- no payment agreement running
      and exists ( -- a credited session one week, and another the week after:
        select 1 -- (any pair)
        from public.billing_credits c1 join public.sessions x1 on x1.id = c1.session_id -- a credit and its session
        join public.sessions x2 on x2.student_id = x1.student_id -- another session of the same student
          and date_trunc('week', x2.starts_at at time zone 'Australia/Adelaide') = date_trunc('week', x1.starts_at at time zone 'Australia/Adelaide') + interval '7 days' -- in the next week
        join public.billing_credits c2 on c2.session_id = x2.id and c2.kind = 'missed_in_pause' -- also credited for being on hold
        where c1.kind = 'missed_in_pause' and x1.student_id = e.student_id -- for this student
          and c1.created_at >= e.decided_at and c2.created_at >= e.decided_at -- both since the place was approved
      ) -- end of the pair
  loop -- go through them
    perform private.ssp_forfeit(r.student_id, 'sessions were missed two weeks in a row because the weekly invoice was not paid, and no plan was agreed with CLG.'); -- forfeits the place
    v_done := v_done + 1; -- counts it
  end loop; -- end of the weekly check
  return v_done; -- gives back how many things were done
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_run_deadlines() from public, anon, authenticated; -- not for people in the app
grant execute on function public.ssp_run_deadlines() to service_role; -- only the server's scheduled job

-- ---------------------------------------------------------------------------
-- B10. Term reviews are included: each offer is accepted at no charge
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- the function's code
  v_old text := '      if v_offer is not null then -- a new offer:'; -- the line where a new offer is handled
begin -- start
  v_def := replace(pg_get_functiondef('private.queue_term_reviews()'::regprocedure), chr(13), ''); -- reads its current code
  if strpos(v_def, 'ssp_member') > 0 then return; end if; -- already added: nothing to do
  if strpos(v_def, v_old) = 0 then -- the place has changed:
    raise exception 'queue_term_reviews has changed since this update was written. Ask for an updated file.'; -- stops, so nothing half-changes
  end if; -- end of the check
  v_def := replace(v_def, v_old, -- a Student Success Program student first:
    E'      if v_offer is not null and private.ssp_member(r.student_id) then -- a new offer for a Student Success Program student (Carla, 22 Nov 2026):\n'
    || E'        v_count := v_count + 1; -- counts it\n'
    || E'        update public.term_review_offers set answer = ''yes'', no_charge = true, answered_at = now() where id = v_offer; -- accepted at no charge (included in the program)\n'
    || E'        perform private.make_term_review_draft(v_offer); -- makes the tutor''s draft\n'
    || E'        insert into public.progress_notices (account_id, student_id, offer_id, kind, title, body, deliver_at) -- tells the family\n'
    || E'        select f.account_id, r.student_id, v_offer, ''review_booked'', left(''Term review for '' || private.first_name(r.full_name), 200), -- a notice to each person who answers\n'
    || E'               left(''A written term review from '' || private.first_name(r.full_name) || ''''''s tutor is included in the Student Success Program, so there is nothing to pay. CLG checks it before you see it.'', 1000), now() -- that it is included\n'
    || E'        from private.term_review_family(r.student_id) f on conflict do nothing; -- never twice\n'
    || E'      elsif v_offer is not null then -- a new offer:'); -- otherwise the usual offer, as before
  execute v_def; -- saves the changed function
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- B11. Matching: program students first
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_def text; -- a function's code
begin -- start
  v_def := replace(pg_get_functiondef('public.matching_queue(text, text, text, text, integer, integer)'::regprocedure), chr(13), ''); -- the queue's code
  if strpos(v_def, 'ssp_member') = 0 then -- not yet changed:
    if strpos(v_def, 'order by r.since, r.student_name, r.subject') = 0 then -- the order line has changed:
      raise exception 'matching_queue has changed since this update was written. Ask for an updated file.'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, 'order by r.since, r.student_name, r.subject', 'order by private.ssp_member(r.student_id) desc, r.since, r.student_name, r.subject'); -- program students first, then as before
    execute v_def; -- saves it
  end if; -- end of the queue
  v_def := replace(pg_get_functiondef('public.matching_tutor_fill(uuid)'::regprocedure), chr(13), ''); -- "Fill a tutor's times"
  if strpos(v_def, 'ssp_member') = 0 then -- not yet changed:
    if strpos(v_def, 'order by m.since, m.student_name, m.subject') = 0 then -- the order line has changed:
      raise exception 'matching_tutor_fill has changed since this update was written. Ask for an updated file.'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, 'order by m.since, m.student_name, m.subject', 'order by private.ssp_member(m.student_id) desc, m.since, m.student_name, m.subject'); -- program students first, then as before
    execute v_def; -- saves it
  end if; -- end of the fill list
end; -- finish
$$; -- end of the block
