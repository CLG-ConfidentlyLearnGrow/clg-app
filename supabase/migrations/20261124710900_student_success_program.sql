-- Summary: the Student Success Program, with family requests, admin approval,
-- limited places and a $500 deposit (Carla, 22 Nov 2026).
--
-- Carla's first note: "need to have a space where can click or check off or
-- something if a student is part of the Student Success Program ... then it
-- sets up their student and/or family profile up accordingly." What it sets
-- up: "Study plan, term reviews, a program label, book till date range
-- (number of sessions) - these are top priority for matching, as they have
-- already paid the $500 deposit to secure their place."
--
-- Carla's second note (same day): the family can tick a box to ask about
-- it, "but ultimately an admin must qualify the student as being part of
-- the Student Success Program, because otherwise we may run out of spaces,
-- and need to ensure the $500 deposit has been received. Can the $500
-- deposit be sent through to the family, then once it is paid, they are
-- then classified as a student in the Student Success Program?"
--
-- How a student moves through the program (public.ssp_enrolments.status):
--   requested -> the family ticked the box to ask about it
--   approved  -> an owner or Operations admin offered a place; the place is
--                held (it counts against the spaces) and billing made the
--                $500 deposit invoice for the family to pay
--   enrolled  -> the deposit invoice is paid: the student is in the program
--                (study plan, term reviews included, label, first in Matching)
--   declined  -> CLG could not offer a place (the family can ask again later)
--   withdrawn -> the family cancelled their request, or CLG withdrew a place
--                before the deposit was paid (the deposit invoice is cancelled)
--   left      -> the student was in the program and has now left it
--
-- Modules: progress owns the program record, study plans and term reviews.
-- Billing owns prices and invoices. Progress asks billing to make the
-- deposit invoice through one billing function and never writes billing's
-- tables. A trigger on the invoice table tells progress when the deposit is
-- paid; it only writes progress's own table.
--
-- Safe to run more than once. Also safe to run after the earlier version
-- of this file (the admin-only tick box). Run after
-- 20261124710800_policy_versions_read_again.sql.

-- ===========================================================================
-- PART A. BILLING (module: billing)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A1. What an invoice is for: sessions (as before) or a deposit.
-- ---------------------------------------------------------------------------
alter table public.billing_invoices -- the invoices table
  add column if not exists kind text not null default 'sessions' -- what the invoice is for, "sessions" for every invoice so far
  check (kind in ('sessions', 'deposit')); -- only these two kinds

-- ---------------------------------------------------------------------------
-- A2. The deposit price item: $500, GST-free, charged once.
-- ---------------------------------------------------------------------------
-- GST: Carla treats curriculum tutoring as GST-free, and the deposit is a
-- payment towards that program, so the deposit is GST-free too. An Owner or
-- Finance admin can change the price or the GST setting under Billing, Prices and settings.
insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, active, description) -- the price list
values ('ssp_deposit', 'Student Success Program deposit', 'once', 50000, false, true, -- code, name, charged once, $500, GST-free, in use
  'The deposit that confirms a student''s place in the Student Success Program. The family is sent it when an admin approves their place, and the student is in the program once it is paid.') -- what it is, for admins
on conflict (code) do nothing; -- leaves it alone if it is already there (so a price already changed stays)

-- ---------------------------------------------------------------------------
-- A3. Making a deposit invoice. Only other database functions call this.
-- ---------------------------------------------------------------------------
-- The invoice is approved straight away (the admin's approval of the place
-- is the approval), so the family can pay it in Billing at once. It is paid
-- by the family choosing "Pay now"; it is never charged automatically to a
-- saved card or bank account, because asking about the program is not the
-- same as agreeing to be charged. Family credit is not used on it, and no
-- bank debit discount applies. An unpaid deposit never puts the family's
-- sessions on hold (see A4).
create or replace function private.billing_charge_deposit( -- the function's name
  p_family uuid, -- the family to bill
  p_student uuid, -- the student the deposit is for
  p_description text, -- the words on the invoice line
  p_due_on date -- the day it is due
)
returns uuid -- the new invoice's id
language plpgsql security definer -- runs with the database's own rights, as billing tables are locked down
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_account public.billing_accounts; -- the family's billing set-up
  v_price public.billing_price_items; -- the deposit price item
  v_family_name text; -- the family's name (copied onto the invoice)
  v_today date := private.billing_today(); -- today in Adelaide
  v_gst int; -- the GST part of the amount
  v_invoice uuid; -- the new invoice
begin -- start of the steps
  select * into v_account from public.billing_accounts where family_id = p_family; -- reads the family's billing set-up
  if not found or v_account.bill_payer_id is null then -- no billing set-up, or nobody named to pay:
    raise exception 'This family has not set up billing yet, so the deposit invoice cannot be made. Ask the family to open Billing in the app, choose a payment plan and accept the family terms, then approve the place again.' using errcode = '22023'; -- plain message
  end if; -- end of that check
  select * into v_price from public.billing_price_items where code = 'ssp_deposit'; -- reads the deposit price item
  if not found or not v_price.active or v_price.amount_cents <= 0 then -- missing, switched off or $0:
    raise exception 'The Student Success Program deposit price is not set. An Owner or Finance admin can set it under Billing, Prices and settings.' using errcode = '22023'; -- plain message
  end if; -- end of that check
  select name into v_family_name from public.families where id = p_family; -- reads the family's name
  v_gst := case when v_price.gst_applies then round(v_price.amount_cents / 11.0)::int else 0 end; -- GST is one eleventh of a GST-inclusive price (none when GST-free)

  insert into public.billing_invoices ( -- makes the invoice:
    family_id, family_name, plan, method, kind, -- who, their plan and method, and that it is a deposit
    period_start, period_end, first_session_on, send_on, due_on, charge_on, -- its dates
    status, subtotal_cents, gst_cents, discount_cents, credit_applied_cents, total_cents, -- approved, and the money
    approved_at, approved_by, created_by -- when and by whom
  ) values ( -- with these values:
    p_family, coalesce(v_family_name, 'Family'), v_account.plan, v_account.method, 'deposit', -- the family, plan, method, a deposit
    v_today, v_today, v_today, v_today, greatest(p_due_on, v_today), greatest(p_due_on, v_today), -- dated today, due on the day given (never in the past)
    'open', v_price.amount_cents, v_gst, 0, 0, v_price.amount_cents, -- ready to pay, the full price, no discount or credit
    now(), auth.uid(), auth.uid() -- approved now by the admin who approved the place
  ) -- end of the values
  returning id into v_invoice; -- keeps the new invoice's id

  -- The line counts as 60 minutes at the item's price, so Xero shows it as
  -- quantity 1 at that price (Xero's quantity is minutes divided by 60).
  insert into public.billing_invoice_lines ( -- adds the one line:
    invoice_id, student_id, price_item_id, line_date, description, -- which invoice, student, price, date and words
    minutes, billed_minutes, hourly_cents, amount_cents, gst_cents -- quantity and money
  ) values ( -- with these values:
    v_invoice, p_student, v_price.id, v_today, left(p_description, 300), -- the invoice, student, price item, today and the words (300 characters at most)
    60, 60, v_price.amount_cents, v_price.amount_cents, v_gst -- one unit at the deposit price
  ); -- end of the line
  return v_invoice; -- gives back the new invoice
end; -- end of the steps
$$; -- end of the function
revoke all on function private.billing_charge_deposit(uuid, uuid, text, date) from public; -- no one calls it directly; only database functions do

-- ---------------------------------------------------------------------------
-- A4. Deposit invoices do not count as session billing.
-- ---------------------------------------------------------------------------

-- A family is paused when a sent session invoice is not fully paid (or on
-- its way) and either its due date has passed or a payer's payment failed
-- and that payer has not paid since, and no override is in force. If part
-- of the invoice has been paid, the pause waits until the first session
-- that is not paid for. Same as 20261102230100_billing_partial_pause.sql,
-- except that a deposit invoice never pauses the family: an unpaid deposit
-- only means the program place is not confirmed.
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
        and i.kind = 'sessions' -- for sessions (never a deposit, Carla 22 Nov 2026)
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
-- exists, a plan change is booked for the next invoice. A deposit invoice
-- does not count, so paying a deposit never locks the payment plan.
create or replace function private.billing_has_invoice(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- reads invoices for the plan functions
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- true when
    select 1 from public.billing_invoices i -- an invoice
    where i.family_id = p_family and i.status <> 'void' and i.kind = 'sessions' -- for this family's sessions is not cancelled
  ) -- (end of the check)
$$; -- end of the function

-- Whether a family has been sent a session invoice (sent or paid). A
-- deposit invoice does not count, for the same reason.
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
-- B1. Settings: how many places there are, and how long families have to
--     pay the deposit. One row.
-- ---------------------------------------------------------------------------
create table if not exists public.ssp_settings ( -- the settings table
  id boolean primary key default true check (id), -- only ever one row
  spaces integer not null default 10 check (spaces between 0 and 1000), -- how many places the program has (change it in Families)
  deposit_due_days integer not null default 7 check (deposit_due_days between 1 and 60), -- days the family has to pay the deposit
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed it
  updated_at timestamptz not null default now() -- when
); -- end of the table
insert into public.ssp_settings (id) values (true) on conflict do nothing; -- makes the one row (leaves it if it is there)
alter table public.ssp_settings enable row level security; -- access rules apply
revoke all on public.ssp_settings from anon; -- signed-out visitors get nothing
revoke insert, update, delete, truncate on public.ssp_settings from authenticated; -- changes only through ssp_set_spaces
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
  decline_reason text check (char_length(decline_reason) <= 500), -- the reason given to the family when declined or withdrawn
  enrolled_by uuid references public.accounts (id) on delete set null, -- (from the first version: who ticked the box)
  enrolled_at timestamptz, -- when they joined the program (the deposit was paid)
  ended_at timestamptz, -- when they left the program
  ended_by uuid references public.accounts (id) on delete set null -- who took them out
); -- end of the table

-- Brings a table made by the first version of this file up to date.
alter table public.ssp_enrolments add column if not exists status text; -- where they are up to
alter table public.ssp_enrolments add column if not exists request_note text check (char_length(request_note) <= 500); -- the family's message
alter table public.ssp_enrolments add column if not exists requested_by uuid references public.accounts (id) on delete set null; -- who asked
alter table public.ssp_enrolments add column if not exists requested_at timestamptz default now(); -- when they asked
alter table public.ssp_enrolments add column if not exists deposit_invoice_id uuid references public.billing_invoices (id) on delete set null; -- the deposit invoice
alter table public.ssp_enrolments add column if not exists decided_by uuid references public.accounts (id) on delete set null; -- who decided
alter table public.ssp_enrolments add column if not exists decided_at timestamptz; -- when
alter table public.ssp_enrolments add column if not exists decline_reason text check (char_length(decline_reason) <= 500); -- the reason given to the family
alter table public.ssp_enrolments alter column enrolled_at drop not null; -- joining time is now blank until the deposit is paid
alter table public.ssp_enrolments alter column enrolled_at drop default; -- and is not filled in automatically
update public.ssp_enrolments -- students ticked in by the first version:
  set status = case when ended_at is null then 'enrolled' else 'left' end -- are in the program (or left it)
  where status is null; -- only rows with no status yet
alter table public.ssp_enrolments alter column status set default 'requested'; -- new rows start as a request
alter table public.ssp_enrolments alter column status set not null; -- every row has a status
alter table public.ssp_enrolments drop constraint if exists ssp_enrolments_status_check; -- replaces the list of statuses if run again
alter table public.ssp_enrolments add constraint ssp_enrolments_status_check -- the allowed statuses:
  check (status in ('requested', 'approved', 'enrolled', 'declined', 'withdrawn', 'left')); -- (see the list at the top)

-- Fast look-ups: places in use, and finding the row for a deposit invoice.
create index if not exists ssp_enrolments_places on public.ssp_enrolments (status) -- by status
  where status in ('requested', 'approved', 'enrolled'); -- only the ones the admin page and place count need
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
  using ((select private.is_front_desk())); -- front desk admins only. Families read their own status through ssp_family_status, which leaves out CLG's own note.

-- ---------------------------------------------------------------------------
-- B3. Small helpers.
-- ---------------------------------------------------------------------------

-- Is this student in the program now (deposit paid, not left)?
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

-- Tells the student's family about a change (an app notice, also emailed
-- by the usual progress notice emails). Goes to each person who manages the
-- student, or to the learner themselves when no parent manages them.
do $$ -- a one-off block: adds "ssp_update" to the allowed kinds of progress notice, keeping every kind already allowed
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

create or replace function private.ssp_tell_family(p_student uuid, p_title text, p_body text) -- the student, the title and the words
returns void language sql security definer -- writes progress notices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  insert into public.progress_notices (account_id, student_id, kind, title, body, deliver_at) -- a notice:
  select f.account_id, p_student, 'ssp_update', left(p_title, 200), left(p_body, 1000), now() -- to each family member, about this student, now
  from private.term_review_family(p_student) f; -- the people who answer for the student
$$; -- end of the function
revoke all on function private.ssp_tell_family(uuid, text, text) from public; -- inside use only

-- A student's first name, for notices.
create or replace function private.ssp_first_name(p_student uuid) -- the student
returns text language sql stable security definer -- reads the student's name
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select coalesce(private.first_name(s.full_name), 'your child') from public.students s where s.id = p_student; -- their first name
$$; -- end of the function
revoke all on function private.ssp_first_name(uuid) from public; -- inside use only

-- ---------------------------------------------------------------------------
-- B4. Places: how many there are, used and left (front desk admins).
-- ---------------------------------------------------------------------------
-- A place is "used" once it is approved (held while the deposit is paid)
-- or the student is in the program.
create or replace function public.ssp_places() -- no inputs
returns table (spaces integer, used integer, places_left integer, waiting integer, deposit_due_days integer) -- the numbers
language sql stable security definer -- reads the program list for front desk admins
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select s.spaces, -- places in total
         u.used, -- places used
         greatest(s.spaces - u.used, 0), -- places left (never below zero)
         u.waiting, -- requests waiting for a decision
         s.deposit_due_days -- days to pay the deposit
  from public.ssp_settings s -- the settings
  cross join lateral ( -- with the counts:
    select count(*) filter (where e.status in ('approved', 'enrolled'))::int as used, -- held or in the program
           count(*) filter (where e.status = 'requested')::int as waiting -- asked, not yet decided
    from public.ssp_enrolments e -- from the program list
    where e.status in ('requested', 'approved', 'enrolled') -- (uses the index)
  ) u -- (named "u")
  where (select private.is_front_desk()); -- front desk admins only (others get nothing)
$$; -- end of the function
revoke all on function public.ssp_places() from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_places() to authenticated; -- signed-in people (the check is inside)

-- Changes the number of places and the days to pay (owner and Operations).
create or replace function public.ssp_set_places(p_spaces integer, p_due_days integer) -- the new numbers
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
  if p_due_days is null or p_due_days < 1 or p_due_days > 60 then -- an odd number of days
    raise exception 'The days to pay the deposit must be between 1 and 60' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.ssp_settings set spaces = p_spaces, deposit_due_days = p_due_days, updated_by = auth.uid(), updated_at = now(); -- saves them
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_set_places(integer, integer) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_set_places(integer, integer) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- B5. The family's side: asking, cancelling, and seeing where it is up to.
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
  if v_status in ('approved', 'enrolled') then -- already has a place:
    raise exception 'This student already has a place in the Student Success Program' using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.ssp_enrolments (student_id, status, request_note, requested_by, requested_at) -- adds the request:
  values (p_student, 'requested', nullif(left(btrim(coalesce(p_note, '')), 500), ''), auth.uid(), now()) -- with the message (if any), who asked and when
  on conflict (student_id) do update set -- or, if there is a row already:
    status = 'requested', request_note = excluded.request_note, -- a request again, with the new message
    requested_by = excluded.requested_by, -- who asked,
    requested_at = case when public.ssp_enrolments.status = 'requested' then public.ssp_enrolments.requested_at else now() end, -- when (kept if they are only changing the message),
    deposit_invoice_id = null, decided_by = null, decided_at = null, decline_reason = null, -- with the last decision cleared
    ended_at = null, ended_by = null; -- and not marked as left
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
-- Leaves out CLG's own note. The deposit's due date is only given to the
-- people who pay (billing information is for payers only, Carla 16 Nov 2026).
drop function if exists public.ssp_family_status(uuid); -- replaces the function if run again (so a change to its columns always applies)
create or replace function public.ssp_family_status(p_student uuid) -- the student
returns table (status text, can_ask boolean, requested_at timestamptz, request_note text, decline_reason text, enrolled_at timestamptz, is_payer boolean, deposit_due_on date) -- what the family sees
language sql stable security definer -- reads the program list and the deposit invoice for them
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select e.status, -- where they are up to (blank if never asked)
         private.ssp_can_ask(s.id), -- whether this person can ask or cancel (a student whose parent manages them can only look)
         e.requested_at, e.request_note, e.decline_reason, e.enrolled_at, -- when they asked, their message, any reason given, when they joined
         private.is_family_payer(s.family_id), -- whether this person pays for the family
         case when private.is_family_payer(s.family_id) then i.due_on end -- the deposit's due date (payers only)
  from public.students s -- the student
  left join public.ssp_enrolments e on e.student_id = s.id -- with their program row (if any)
  left join public.billing_invoices i on i.id = e.deposit_invoice_id -- and the deposit invoice (billing's table, only read here)
  where s.id = p_student -- this student
    and (private.ssp_can_ask(s.id) or private.is_student_self(s.id)); -- only for their family (or the student themselves)
$$; -- end of the function
revoke all on function public.ssp_family_status(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_family_status(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- B6. The admin's side (owner and Operations admins).
-- ---------------------------------------------------------------------------
drop function if exists public.ssp_enrol(uuid, integer, date, date, text); -- removes the first version's tick box (replaced by approve below)

-- Approves a place: checks there is a place left, holds it, and asks
-- billing to make the deposit invoice. Works for a family's request, or for
-- a student CLG adds directly (for example after a phone call).
create or replace function public.ssp_approve( -- approves a place:
  p_student uuid, -- the student
  p_sessions integer default null, -- sessions planned
  p_book_until date default null, -- the book-till date
  p_note text default null -- CLG's own note
)
returns uuid -- the deposit invoice
language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_family uuid; -- the student's family
  v_settings public.ssp_settings; -- the number of places and days to pay
  v_status text; -- where the student is up to now
  v_used integer; -- places already used
  v_invoice uuid; -- the deposit invoice
  v_due date; -- when the deposit is due
  v_total integer; -- the deposit amount, in cents
  v_name text; -- the student's first name
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  select family_id into v_family from public.students where id = p_student; -- reads the student's family
  if not found then -- no such student
    raise exception 'That student could not be found' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  if v_family is null then -- no family to bill
    raise exception 'This student is not linked to a family, so there is no one to send the deposit to' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_sessions is not null and (p_sessions < 1 or p_sessions > 200) then -- an odd number of sessions
    raise exception 'The number of sessions must be between 1 and 200' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select * into v_settings from public.ssp_settings for update; -- reads the settings and holds them, so two admins cannot give away the last place at once
  select status into v_status from public.ssp_enrolments where student_id = p_student for update; -- where the student is up to (and holds the row)
  if v_status in ('approved', 'enrolled') then -- already has a place:
    raise exception 'This student already has a place in the Student Success Program' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select count(*) into v_used from public.ssp_enrolments where status in ('approved', 'enrolled'); -- places already used
  if v_used >= v_settings.spaces then -- none left:
    raise exception 'All % places in the Student Success Program are taken. Add more places, or wait until a place is free.', v_settings.spaces using errcode = '22023'; -- plain message
  end if; -- end of the check
  insert into public.ssp_enrolments (student_id, status, sessions_planned, book_until, note, decided_by, decided_at, requested_at) -- holds the place:
  values (p_student, 'approved', p_sessions, p_book_until, nullif(left(btrim(coalesce(p_note, '')), 500), ''), auth.uid(), now(), now()) -- with the details given
  on conflict (student_id) do update set -- or, if there is a row already:
    status = 'approved', sessions_planned = excluded.sessions_planned, book_until = excluded.book_until, -- approved, with the sessions and date,
    note = excluded.note, decided_by = excluded.decided_by, decided_at = excluded.decided_at, -- the note, and who approved and when,
    decline_reason = null, deposit_paid_on = null, enrolled_at = null, ended_at = null, ended_by = null; -- with anything from before cleared
  v_name := private.ssp_first_name(p_student); -- the student's first name
  v_invoice := private.billing_charge_deposit( -- asks billing to make the deposit invoice:
    v_family, p_student, -- for this family and student,
    'Student Success Program deposit for ' || v_name, -- with these words on the line,
    private.billing_today() + v_settings.deposit_due_days); -- due in the set number of days
  update public.ssp_enrolments set deposit_invoice_id = v_invoice where student_id = p_student; -- links the invoice to the place
  select total_cents, due_on into v_total, v_due from public.billing_invoices where id = v_invoice; -- reads the amount and due date (billing's table, only read here)
  perform private.ssp_tell_family(p_student, -- tells the family:
    'A place in the Student Success Program for ' || v_name, -- the title
    'CLG has offered ' || v_name || ' a place in the Student Success Program. To confirm the place, the $' || to_char(v_total / 100.0, 'FM999990.00') -- the offer and amount
      || ' deposit needs to be paid by ' || to_char(v_due, 'FMDD FMMonth YYYY') || '. The person who pays for your family''s sessions can pay it in Billing in the CLG app. ' -- the due date and where to pay
      || v_name || ' is in the program once the deposit is paid.'); -- what happens then
  return v_invoice; -- gives back the invoice
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_approve(uuid, integer, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_approve(uuid, integer, date, text) to authenticated; -- signed-in people (the check is inside)

-- Changes the details of a place that is approved or in the program.
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
  where student_id = p_student and status in ('approved', 'enrolled'); -- only for a place that is held or in use
  if not found then -- no place:
    raise exception 'This student does not have a place in the Student Success Program' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_save_details(uuid, integer, date, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_save_details(uuid, integer, date, text) to authenticated; -- signed-in people (the check is inside)

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

-- Withdraws a place before the deposit is paid. Billing cancels the deposit
-- invoice (through billing's own function), and the place is free again.
create or replace function public.ssp_withdraw(p_student uuid, p_reason text) -- the student and the reason
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 500), ''); -- the reason, tidied (or nothing)
  v_invoice uuid; -- the deposit invoice
  v_inv_status text; -- the invoice's status
  v_name text; -- the student's first name
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if v_reason is null or char_length(v_reason) < 5 then -- no proper reason:
    raise exception 'Please give a reason for withdrawing the place' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set status = 'withdrawn', decline_reason = v_reason, decided_by = auth.uid(), decided_at = now() -- marks the place as withdrawn first (so the invoice step below does not reopen the request)
  where student_id = p_student and status = 'approved' -- only a place waiting for its deposit
  returning deposit_invoice_id into v_invoice; -- and notes the deposit invoice
  if not found then -- no place waiting:
    raise exception 'This student does not have a place waiting for its deposit. To take a student out of the program, use Remove from the program.' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  select status::text into v_inv_status from public.billing_invoices where id = v_invoice; -- reads the invoice's status (billing's table, only read here)
  if v_inv_status = 'paid' then -- paid in the meantime:
    raise exception 'The deposit has already been paid, so the place cannot be withdrawn. Use Remove from the program instead, and follow CLG''s terms for any refund.' using errcode = '22023'; -- plain message (nothing is changed)
  end if; -- end of the check
  if v_inv_status is not null and v_inv_status <> 'void' then -- an unpaid invoice:
    perform public.billing_void_invoice(v_invoice, 'Student Success Program place withdrawn: ' || v_reason); -- asks billing to cancel it (billing refuses if a payment is on its way)
  end if; -- end of the invoice step
  v_name := private.ssp_first_name(p_student); -- the student's first name
  perform private.ssp_tell_family(p_student, -- tells the family:
    'Student Success Program place for ' || v_name, -- the title
    'The place offered to ' || v_name || ' in the Student Success Program has been withdrawn, and the deposit invoice has been cancelled. ' || v_reason -- what happened and why
      || ' Please contact CLG if you have any questions.'); -- what they can do
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_withdraw(uuid, text) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_withdraw(uuid, text) to authenticated; -- signed-in people (the check is inside)

-- Takes a student out of the program (after the deposit was paid). Any
-- refund follows CLG's terms and is done in Billing, not here.
create or replace function public.ssp_leave(p_student uuid) -- the student
returns void language plpgsql security definer -- writes the program list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG''s owner or Operations admins can change the Student Success Program' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.ssp_enrolments set status = 'left', ended_at = now(), ended_by = auth.uid() -- marks them as left
  where student_id = p_student and status = 'enrolled'; -- only someone in the program
  if not found then raise exception 'That student is not in the Student Success Program' using errcode = 'P0002'; end if; -- not in it
  -- The study plan add-on given for the program ends today (one given for another reason is left alone).
  update public.add_on_members set ends_on = greatest(starts_on, (now() at time zone 'Australia/Adelaide')::date) -- ends it today
  where add_on = 'study_plans' and student_id = p_student and note = 'Student Success Program' and ends_on is null; -- only the program's one
end; -- end of the code
$$; -- end of the function
revoke all on function public.ssp_leave(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.ssp_leave(uuid) to authenticated; -- signed-in people (the check is inside)

-- ---------------------------------------------------------------------------
-- B7. When the deposit is paid (or its invoice is cancelled).
-- ---------------------------------------------------------------------------
-- Billing marks the invoice paid however it was paid: Pay now in the app
-- (Stripe), or a payment entered in Xero. This trigger then puts the
-- student in the program: it gives the study plan add-on and tells the
-- family. If the deposit invoice is cancelled (for example in Xero) while
-- the place is waiting, the place is released and the request goes back to
-- the admin's list. It only writes progress's own table and the shared
-- add-ons list; it never changes the invoice.
create or replace function private.ssp_deposit_changed() -- runs after an invoice's status changes
returns trigger language plpgsql security definer -- writes the program list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_student uuid; -- the student whose deposit it is
  v_name text; -- their first name
begin -- start
  if new.status = 'paid' then -- the deposit is paid:
    update public.ssp_enrolments -- puts the student in the program:
    set status = 'enrolled', enrolled_at = now(), deposit_paid_on = private.billing_today() -- in, from now, paid today
    where deposit_invoice_id = new.id and status = 'approved' -- the place this deposit holds
    returning student_id into v_student; -- notes the student
    if v_student is null then return null; end if; -- no place waiting (for example withdrawn): nothing more to do
    -- The study plan add-on (shared core): given from today, open-ended.
    insert into public.add_on_members (add_on, student_id, note, created_by) -- gives the add-on:
    select 'study_plans', v_student, 'Student Success Program', null -- study plans, for this student, noting why
    where exists (select 1 from public.add_ons where code = 'study_plans') -- if the add-on exists
    on conflict (add_on, student_id) do update set ends_on = null; -- already given: keeps it open-ended
    v_name := private.ssp_first_name(v_student); -- the student's first name
    perform private.ssp_tell_family(v_student, -- tells the family:
      v_name || ' is in the Student Success Program', -- the title
      'Thank you, the deposit has been received. ' || v_name || ' is now in the Student Success Program. This includes a study plan, each term review at no charge, and priority when CLG finds a tutor.'); -- what it means
  elsif new.status = 'void' then -- the deposit invoice was cancelled:
    update public.ssp_enrolments -- releases the place:
    set status = 'requested', deposit_invoice_id = null, decided_by = null, decided_at = null -- back to a request for the admin to decide again
    where deposit_invoice_id = new.id and status = 'approved'; -- only a place still waiting for this deposit
  end if; -- end of the cases
  return null; -- (an "after" trigger gives nothing back)
end; -- end of the code
$$; -- end of the function
revoke all on function private.ssp_deposit_changed() from public; -- inside use only
drop trigger if exists ssp_deposit_changed on public.billing_invoices; -- replaces the trigger if run again
create trigger ssp_deposit_changed after update of status on public.billing_invoices -- after an invoice's status changes
  for each row -- for each invoice
  when (new.kind = 'deposit' and old.status is distinct from new.status and new.status in ('paid', 'void')) -- only deposits that are paid or cancelled (so other invoices cost nothing)
  execute function private.ssp_deposit_changed(); -- runs the function above

-- ---------------------------------------------------------------------------
-- B8. Term reviews are included: each offer is accepted at no charge
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
-- B9. Matching: program students first
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
