-- Billing module: prices, family billing accounts, invoices built from
-- sessions, payments, credits, and automatic pauses for overdue families.
-- See docs/features/billing.md.
--
-- How it fits together:
--   * The app decides what each family owes and when. Xero is the official
--     accounts; Stripe only moves the money.
--   * Billing reads sessions (owned by the scheduling module) and never
--     writes them. Scheduling asks billing whether a family is paused
--     through private.billing_family_paused().
--   * Card and bank details never reach CLG: families type them into
--     Stripe's own pages and the app keeps only Stripe's reference.
--   * Money results (payments, Xero ids) are written only by the server,
--     never from a browser.
--
-- Needs the scheduling migration (public.sessions) to have run first.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.billing_plan as enum ('weekly', 'monthly', 'term', 'upfront');
exception when duplicate_object then null; end $$;

-- How a family pays. 'none' means they haven't saved a card or bank debit
-- yet, so they pay each invoice by link.
do $$ begin
  create type public.billing_method as enum ('none', 'card', 'bank_debit');
exception when duplicate_object then null; end $$;

-- draft: built in the app, not yet in Xero.
-- awaiting_approval: in Xero, waiting for Carla to approve (pilot).
-- open: approved and sent to the family, waiting for payment.
-- paid / void: finished.
do $$ begin
  create type public.billing_invoice_status as enum ('draft', 'awaiting_approval', 'open', 'paid', 'void');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.billing_payment_status as enum ('processing', 'succeeded', 'failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.billing_credit_kind as enum (
    'cancellation',      -- family or CLG cancelled a paid session
    'missed_in_pause',   -- paid session missed while the family was paused
    'tutor_day_off',     -- tutor's one-off day off
    'goodwill',          -- added by an admin, with a note
    'applied',           -- used on an invoice (a negative amount)
    'returned'           -- put back when an invoice is voided
  );
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Today in Adelaide, which is where CLG's billing days are counted.
create or replace function private.billing_today()
returns date language sql stable
set search_path = ''
as $$ select (now() at time zone 'Australia/Adelaide')::date $$;

-- A date some business days (Monday to Friday) before another. Public
-- holidays aren't counted yet, so allow a day's margin around them.
create or replace function private.business_days_before(p_day date, p_days int)
returns date language plpgsql immutable
set search_path = ''
as $$
declare
  v date := p_day;
  n int := 0;
begin
  while n < p_days loop
    v := v - 1;
    if extract(isodow from v) < 6 then
      n := n + 1;
    end if;
  end loop;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settings: one row. Fees, notice periods and timings in one place, so a
-- change in Stripe's prices or CLG's rules is an edit, not a rebuild.
-- ---------------------------------------------------------------------------
create table if not exists public.billing_settings (
  id boolean primary key default true check (id),
  -- Stripe fees (GST included), used to work out the bank-debit discount.
  card_fee_percent numeric(5, 3) not null default 1.65,
  card_fee_fixed_cents int not null default 30,
  debit_fee_percent numeric(5, 3) not null default 1.0,
  debit_fee_fixed_cents int not null default 30,
  debit_fee_cap_cents int not null default 350,
  -- Share of the saving passed to families paying by bank debit.
  debit_discount_share numeric(4, 3) not null default 0.5 check (debit_discount_share between 0 and 1),
  -- Booking steps and minimum charge per session.
  step_minutes int not null default 30 check (step_minutes > 0),
  minimum_minutes int not null default 60 check (minimum_minutes >= 0),
  -- Cancellation credit: more than full_credit_hours = 100%; between
  -- half_credit_hours and full_credit_hours = 50%; less = none.
  full_credit_hours int not null default 24,
  half_credit_hours int not null default 2,
  -- When payment is due, counted back from the first session on the invoice.
  short_plan_due_days int not null default 4,   -- weekly and monthly
  long_plan_due_days int not null default 7,    -- per term and upfront
  -- When the invoice goes out, counted back from the due date.
  short_plan_send_days int not null default 7,
  long_plan_send_days int not null default 14,
  -- A bank debit can take 3 business days to clear, plus one spare.
  debit_clear_business_days int not null default 4,
  -- 'awaiting_approval': invoices wait in Xero for approval (pilot).
  -- 'send': invoices are approved and emailed automatically.
  invoice_mode text not null default 'awaiting_approval' check (invoice_mode in ('awaiting_approval', 'send')),
  -- Who may lift a pause without payment: the owner only, or any admin.
  override_by text not null default 'owner' check (override_by in ('owner', 'admin')),
  show_tutor_on_invoice boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.billing_settings (id) values (true) on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Price list. Each price carries its own GST setting.
--
-- Built for later too: a price can be for self-signup (families buying
-- support in the app without staff) and can carry a free or paid trial.
-- Those prices are decided later; for now everything is set up by admins.
-- ---------------------------------------------------------------------------
create table if not exists public.billing_price_items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_]{2,40}$'),
  name text not null check (char_length(name) between 1 and 200),
  description text check (char_length(description) <= 1000),
  -- 'hour' prices are charged per session hour; 'week', 'month' and 'term'
  -- are flat fees for a period (for example a self-service program later).
  unit text not null default 'hour' check (unit in ('hour', 'week', 'month', 'term', 'once')),
  amount_cents int not null check (amount_cents >= 0),
  -- Prices include GST where it applies (consumer prices in Australia).
  gst_applies boolean not null default false,
  -- The session level this price is used for ('school' or 'tertiary').
  -- Blank for prices not tied to sessions.
  session_level text check (session_level in ('school', 'tertiary')),
  self_signup boolean not null default false,
  trial_days int check (trial_days is null or trial_days between 1 and 365),
  trial_sessions int check (trial_sessions is null or trial_sessions between 1 and 52),
  trial_amount_cents int check (trial_amount_cents is null or trial_amount_cents >= 0),
  program_id uuid references public.programs (id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- One active session price per level, so there's never doubt which applies.
create unique index if not exists billing_price_items_one_per_level
  on public.billing_price_items (session_level) where active and session_level is not null;

insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, session_level, description) values
  ('school_tutoring', 'School tutoring', 'hour', 9500, false, 'school', 'Curriculum tutoring for school students, online or in person. GST-free.'),
  ('tertiary_tutoring', 'Tertiary tutoring', 'hour', 11500, false, 'tertiary', 'Curriculum tutoring for TAFE and university students. GST-free.')
on conflict (code) do nothing;
insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, active, description) values
  ('other_support', 'Other educational support', 'hour', 9500, true, false, 'Non-curriculum support. GST applies. Set the price before turning it on.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- School terms and holidays, for per-term billing. Entered by admins.
-- ---------------------------------------------------------------------------
create table if not exists public.billing_school_periods (
  id uuid primary key default gen_random_uuid(),
  state public.au_state not null default 'SA',
  name text not null check (char_length(name) between 1 and 100),
  kind text not null check (kind in ('term', 'holidays')),
  starts_on date not null,
  ends_on date not null,
  check (ends_on >= starts_on)
);
create unique index if not exists billing_school_periods_once
  on public.billing_school_periods (state, starts_on);

-- ---------------------------------------------------------------------------
-- A family's billing account.
-- ---------------------------------------------------------------------------
create table if not exists public.billing_accounts (
  family_id uuid primary key references public.families (id) on delete cascade,
  bill_payer_id uuid references public.accounts (id) on delete set null,
  plan public.billing_plan not null default 'weekly',
  method public.billing_method not null default 'none',
  -- Stripe and Xero references. Not card or bank numbers.
  stripe_customer_id text,
  stripe_payment_method_id text,
  stripe_mandate_id text,
  xero_contact_id text,
  -- Family terms accepted in the app.
  terms_version text check (char_length(terms_version) <= 40),
  terms_accepted_at timestamptz,
  terms_accepted_by uuid references public.accounts (id) on delete set null,
  -- Kept up to date by private.billing_refresh_pause(). Never set by hand.
  paused boolean not null default false,
  paused_since timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Weekly families pay by card (bank debit is too slow for weekly).
  constraint billing_accounts_weekly_card check (not (plan = 'weekly' and method = 'bank_debit'))
);
alter table public.billing_accounts
  add column if not exists payment_ready boolean generated always as (stripe_payment_method_id is not null) stored;

-- Existing families keep their old hourly rate (a quiet thank-you).
create table if not exists public.billing_family_rates (
  family_id uuid not null references public.families (id) on delete cascade,
  price_item_id uuid not null references public.billing_price_items (id) on delete cascade,
  amount_cents int not null check (amount_cents >= 0),
  note text check (char_length(note) <= 500),
  set_by uuid references public.accounts (id) on delete set null,
  set_at timestamptz not null default now(),
  primary key (family_id, price_item_id)
);

-- ---------------------------------------------------------------------------
-- Invoices and their lines. Kept for tax records (7 years) even after a
-- family's learning records are deleted, so names are copied onto them and
-- links to families, students and sessions fall away to blank.
-- ---------------------------------------------------------------------------
create sequence if not exists public.billing_invoice_number_seq start 1001;

create table if not exists public.billing_invoices (
  id uuid primary key default gen_random_uuid(),
  number text not null unique default ('CLG-' || lpad(nextval('public.billing_invoice_number_seq')::text, 5, '0')),
  family_id uuid references public.families (id) on delete set null,
  family_name text not null,
  plan public.billing_plan not null,
  method public.billing_method not null,
  period_start date not null,
  period_end date not null,
  first_session_on date not null,
  send_on date not null,
  due_on date not null,
  -- The day the saved card or bank debit is charged.
  charge_on date not null,
  status public.billing_invoice_status not null default 'draft',
  subtotal_cents int not null default 0,
  gst_cents int not null default 0,
  discount_cents int not null default 0,
  credit_applied_cents int not null default 0,
  total_cents int not null default 0,
  -- One key per invoice so a retry can never bill or charge twice.
  idempotency_key uuid not null default gen_random_uuid(),
  xero_invoice_id text,
  auto_charge_attempted_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references public.accounts (id) on delete set null,
  voided_at timestamptz,
  void_reason text check (char_length(void_reason) <= 500),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end >= period_start),
  check (total_cents >= 0)
);
create index if not exists billing_invoices_family on public.billing_invoices (family_id, status);
create index if not exists billing_invoices_due on public.billing_invoices (status, due_on);

create table if not exists public.billing_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoices (id) on delete cascade,
  session_id uuid references public.sessions (id) on delete set null,
  student_id uuid references public.students (id) on delete set null,
  price_item_id uuid references public.billing_price_items (id) on delete set null,
  line_date date not null,
  -- Day, date, time, student's first name and subject.
  description text not null check (char_length(description) <= 300),
  minutes int not null check (minutes > 0),
  billed_minutes int not null check (billed_minutes > 0),
  hourly_cents int not null check (hourly_cents >= 0),
  amount_cents int not null check (amount_cents >= 0),
  gst_cents int not null default 0,
  -- False once the invoice is voided, so the session can be billed again.
  active boolean not null default true
);
create index if not exists billing_invoice_lines_invoice on public.billing_invoice_lines (invoice_id);
-- A session is never on two live invoices.
create unique index if not exists billing_invoice_lines_session_once
  on public.billing_invoice_lines (session_id) where active and session_id is not null;

-- ---------------------------------------------------------------------------
-- Payments, as reported by Stripe.
-- ---------------------------------------------------------------------------
create table if not exists public.billing_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoices (id) on delete restrict,
  provider text not null default 'stripe' check (provider in ('stripe', 'manual')),
  provider_ref text not null,
  method public.billing_method not null,
  amount_cents int not null check (amount_cents >= 0),
  status public.billing_payment_status not null,
  failure_message text check (char_length(failure_message) <= 500),
  xero_payment_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_ref)
);
create index if not exists billing_payments_invoice on public.billing_payments (invoice_id, status);

-- ---------------------------------------------------------------------------
-- Credits: one running balance per family. Positive rows add credit,
-- negative rows use it. Credits, not refunds (unless the law requires one).
-- ---------------------------------------------------------------------------
create table if not exists public.billing_credits (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families (id) on delete set null,
  kind public.billing_credit_kind not null,
  amount_cents int not null,
  session_id uuid references public.sessions (id) on delete set null,
  invoice_id uuid references public.billing_invoices (id) on delete set null,
  note text check (char_length(note) <= 500),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists billing_credits_family on public.billing_credits (family_id);
-- A session earns at most one cancellation credit.
create unique index if not exists billing_credits_session_once
  on public.billing_credits (session_id) where session_id is not null and kind in ('cancellation', 'missed_in_pause', 'tutor_day_off');

-- ---------------------------------------------------------------------------
-- Pauses: overrides, history and the messages tutors get.
-- ---------------------------------------------------------------------------

-- Lifting a pause without payment. Needs a reason and a date: the new due
-- date, or the next payment date of an agreed payment plan. If that date
-- passes unpaid, the pause comes back on its own.
create table if not exists public.billing_pause_overrides (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  reason text not null check (char_length(trim(reason)) between 5 and 500),
  until_on date not null,
  payment_plan text check (char_length(payment_plan) <= 1000),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists billing_pause_overrides_family on public.billing_pause_overrides (family_id);

create table if not exists public.billing_pause_events (
  id bigint generated always as identity primary key,
  family_id uuid references public.families (id) on delete set null,
  kind text not null check (kind in ('paused', 'resumed')),
  reason text not null,
  at timestamptz not null default now()
);

-- What tutors are told: that a student's sessions are on hold or back on.
-- No money details. The app sends these and stamps sent_at.
create table if not exists public.billing_tutor_notices (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  student_id uuid references public.students (id) on delete cascade,
  kind text not null check (kind in ('on_hold', 'back_on')),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index if not exists billing_tutor_notices_unsent on public.billing_tutor_notices (sent_at) where sent_at is null;

-- ---------------------------------------------------------------------------
-- Server-only tables: messages from Stripe and Xero already handled (so a
-- repeat is ignored), and the Xero connection (tokens encrypted by the app).
-- ---------------------------------------------------------------------------
create table if not exists public.billing_webhook_events (
  provider text not null check (provider in ('stripe', 'xero')),
  event_id text not null,
  event_type text,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);

create table if not exists public.billing_xero_connection (
  id boolean primary key default true check (id),
  tenant_id text not null,
  tenant_name text,
  tokens_encrypted text not null,
  expires_at timestamptz not null,
  connected_by uuid references public.accounts (id) on delete set null,
  connected_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row level security and grants
-- ---------------------------------------------------------------------------
alter table public.billing_settings enable row level security;
alter table public.billing_price_items enable row level security;
alter table public.billing_school_periods enable row level security;
alter table public.billing_accounts enable row level security;
alter table public.billing_family_rates enable row level security;
alter table public.billing_invoices enable row level security;
alter table public.billing_invoice_lines enable row level security;
alter table public.billing_payments enable row level security;
alter table public.billing_credits enable row level security;
alter table public.billing_pause_overrides enable row level security;
alter table public.billing_pause_events enable row level security;
alter table public.billing_tutor_notices enable row level security;
alter table public.billing_webhook_events enable row level security;
alter table public.billing_xero_connection enable row level security;

revoke all on public.billing_settings, public.billing_price_items, public.billing_school_periods,
  public.billing_accounts, public.billing_family_rates, public.billing_invoices,
  public.billing_invoice_lines, public.billing_payments, public.billing_credits,
  public.billing_pause_overrides, public.billing_pause_events, public.billing_tutor_notices,
  public.billing_webhook_events, public.billing_xero_connection
  from anon;
-- Server-only tables: nobody signed in reaches them at all.
revoke all on public.billing_webhook_events, public.billing_xero_connection from authenticated;
revoke all on sequence public.billing_invoice_number_seq from anon, authenticated;

-- Is the signed-in person a parent (or 16+ student) in this family?
create or replace function private.in_family(p_family uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.students s
    where s.family_id = p_family
      and (private.is_parent_of(s.id) or private.is_student_self(s.id))
  )
$$;

-- Someone who pays for this family: a parent of a child in it, an adult
-- (18+) learner in it, or the named bill payer. Students under 18 see only
-- "on hold", never invoices.
create or replace function private.is_family_payer(p_family uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
    exists (
      select 1 from public.students s
      join public.parent_student_links l on l.student_id = s.id
      where s.family_id = p_family and l.parent_id = auth.uid()
    )
    or exists (
      select 1 from public.students s
      where s.family_id = p_family and s.account_id = auth.uid()
        and s.date_of_birth <= (current_date - interval '18 years')::date
    )
    or exists (
      select 1 from public.billing_accounts b
      where b.family_id = p_family and b.bill_payer_id = auth.uid()
    )
  )
$$;

-- Can this person override a pause, under the current setting?
create or replace function private.can_override_pause()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select case (select override_by from public.billing_settings)
    when 'admin' then private.is_admin()
    else private.is_owner()
  end
$$;

-- Settings: admins read, the owner changes.
drop policy if exists "admins read billing settings" on public.billing_settings;
create policy "admins read billing settings" on public.billing_settings
  for select to authenticated using (private.is_admin());
drop policy if exists "owner changes billing settings" on public.billing_settings;
create policy "owner changes billing settings" on public.billing_settings
  for update to authenticated using (private.is_owner()) with check (private.is_owner());
revoke insert, delete on public.billing_settings from authenticated;

-- Prices: anyone signed in sees active prices; admins see and manage all.
drop policy if exists "see prices" on public.billing_price_items;
create policy "see prices" on public.billing_price_items
  for select to authenticated using (active or private.is_admin());
drop policy if exists "admins manage prices" on public.billing_price_items;
create policy "admins manage prices" on public.billing_price_items
  for all to authenticated using (private.is_admin()) with check (private.is_admin());
revoke delete on public.billing_price_items from authenticated;  -- turn off instead

-- School terms: anyone signed in reads; admins manage.
drop policy if exists "read school periods" on public.billing_school_periods;
create policy "read school periods" on public.billing_school_periods
  for select to authenticated using (true);
drop policy if exists "admins manage school periods" on public.billing_school_periods;
create policy "admins manage school periods" on public.billing_school_periods
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- Billing accounts: parents see their own family's; admins see all and set
-- the plan, bill payer and Xero contact. Payment details and the pause are
-- written only by the server.
drop policy if exists "see own billing account" on public.billing_accounts;
create policy "see own billing account" on public.billing_accounts
  for select to authenticated using (private.is_admin() or private.is_family_payer(family_id));
drop policy if exists "admins create billing accounts" on public.billing_accounts;
create policy "admins create billing accounts" on public.billing_accounts
  for insert to authenticated with check (private.is_admin());
drop policy if exists "admins change billing accounts" on public.billing_accounts;
create policy "admins change billing accounts" on public.billing_accounts
  for update to authenticated using (private.is_admin()) with check (private.is_admin());
revoke select, insert, update, delete on public.billing_accounts from authenticated;
grant select (family_id, bill_payer_id, plan, method, payment_ready, xero_contact_id,
  terms_version, terms_accepted_at, paused, paused_since, created_at, updated_at)
  on public.billing_accounts to authenticated;
grant insert (family_id, bill_payer_id, plan) on public.billing_accounts to authenticated;
grant update (bill_payer_id, plan, xero_contact_id) on public.billing_accounts to authenticated;

-- Kept rates: admins only.
drop policy if exists "admins manage family rates" on public.billing_family_rates;
create policy "admins manage family rates" on public.billing_family_rates
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

-- Invoices: a parent sees their family's once sent; admins see all. Made
-- and changed only through the functions below or by the server.
drop policy if exists "see own invoices" on public.billing_invoices;
create policy "see own invoices" on public.billing_invoices
  for select to authenticated using (
    private.is_admin()
    or (status in ('open', 'paid', 'void') and family_id is not null and private.is_family_payer(family_id))
  );
revoke insert, update, delete on public.billing_invoices from authenticated;

drop policy if exists "see own invoice lines" on public.billing_invoice_lines;
create policy "see own invoice lines" on public.billing_invoice_lines
  for select to authenticated using (
    exists (select 1 from public.billing_invoices i where i.id = invoice_id)
  );
revoke insert, update, delete on public.billing_invoice_lines from authenticated;

drop policy if exists "see own payments" on public.billing_payments;
create policy "see own payments" on public.billing_payments
  for select to authenticated using (
    exists (select 1 from public.billing_invoices i where i.id = invoice_id)
  );
revoke insert, update, delete on public.billing_payments from authenticated;

drop policy if exists "see own credits" on public.billing_credits;
create policy "see own credits" on public.billing_credits
  for select to authenticated using (
    private.is_admin() or (family_id is not null and private.is_family_payer(family_id))
  );
revoke insert, update, delete on public.billing_credits from authenticated;

drop policy if exists "admins see overrides" on public.billing_pause_overrides;
create policy "admins see overrides" on public.billing_pause_overrides
  for select to authenticated using (private.is_admin());
revoke insert, update, delete on public.billing_pause_overrides from authenticated;

drop policy if exists "admins see pause history" on public.billing_pause_events;
create policy "admins see pause history" on public.billing_pause_events
  for select to authenticated using (private.is_admin());
revoke insert, update, delete on public.billing_pause_events from authenticated;

drop policy if exists "tutors see own notices" on public.billing_tutor_notices;
create policy "tutors see own notices" on public.billing_tutor_notices
  for select to authenticated using (
    private.is_admin() or (tutor_id = auth.uid() and private.has_aal2())
  );
revoke insert, update, delete on public.billing_tutor_notices from authenticated;

-- ---------------------------------------------------------------------------
-- Activity log and timestamps
-- ---------------------------------------------------------------------------
drop trigger if exists audit on public.billing_settings;
create trigger audit after update on public.billing_settings
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_price_items;
create trigger audit after insert or update or delete on public.billing_price_items
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_accounts;
create trigger audit after insert or update or delete on public.billing_accounts
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_family_rates;
create trigger audit after insert or update or delete on public.billing_family_rates
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_invoices;
create trigger audit after insert or update or delete on public.billing_invoices
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_payments;
create trigger audit after insert or update on public.billing_payments
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_credits;
create trigger audit after insert on public.billing_credits
  for each row execute function private.audit_change();
drop trigger if exists audit on public.billing_pause_overrides;
create trigger audit after insert or update on public.billing_pause_overrides
  for each row execute function private.audit_change();

drop trigger if exists touch on public.billing_settings;
create trigger touch before update on public.billing_settings
  for each row execute function private.touch_updated_at();
drop trigger if exists touch on public.billing_price_items;
create trigger touch before update on public.billing_price_items
  for each row execute function private.touch_updated_at();
drop trigger if exists touch on public.billing_accounts;
create trigger touch before update on public.billing_accounts
  for each row execute function private.touch_updated_at();
drop trigger if exists touch on public.billing_invoices;
create trigger touch before update on public.billing_invoices
  for each row execute function private.touch_updated_at();
drop trigger if exists touch on public.billing_payments;
create trigger touch before update on public.billing_payments
  for each row execute function private.touch_updated_at();

create or replace function private.stamp_family_rate()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.set_by := auth.uid();
  new.set_at := now();
  return new;
end;
$$;
drop trigger if exists stamp on public.billing_family_rates;
create trigger stamp before insert or update on public.billing_family_rates
  for each row execute function private.stamp_family_rate();

-- ---------------------------------------------------------------------------
-- Money rules
-- ---------------------------------------------------------------------------

-- Minutes charged for a session: rounded up to the booking step, with the
-- minimum charge. A 45 minute session is charged as 1 hr.
create or replace function private.billing_minutes(p_minutes int)
returns int language sql stable
set search_path = ''
as $$
  select greatest(s.minimum_minutes, (ceil(p_minutes::numeric / s.step_minutes) * s.step_minutes)::int)
  from public.billing_settings s
$$;

-- The hourly rate a family pays for a session level: their kept rate if
-- they have one, otherwise the price list.
create or replace function private.billing_rate(p_family uuid, p_level text)
returns table (price_item_id uuid, hourly_cents int, gst_applies boolean)
language sql stable security definer
set search_path = ''
as $$
  select p.id, coalesce(r.amount_cents, p.amount_cents), p.gst_applies
  from public.billing_price_items p
  left join public.billing_family_rates r on r.price_item_id = p.id and r.family_id = p_family
  where p.session_level = p_level and p.active
  limit 1
$$;

-- Stripe's fee for a card or bank debit payment of this amount.
create or replace function private.billing_fee_cents(p_amount int, p_method public.billing_method)
returns int language sql stable
set search_path = ''
as $$
  select case
    when p_amount <= 0 then 0
    when p_method = 'bank_debit' then
      least(s.debit_fee_cap_cents, round(p_amount * s.debit_fee_percent / 100 + s.debit_fee_fixed_cents)::int)
    else round(p_amount * s.card_fee_percent / 100 + s.card_fee_fixed_cents)::int
  end
  from public.billing_settings s
$$;

-- Bank-debit discount: the family's share of what CLG saves against a card.
create or replace function private.billing_debit_discount(p_amount int)
returns int language sql stable
set search_path = ''
as $$
  select greatest(0, round(
    (private.billing_fee_cents(p_amount, 'card') - private.billing_fee_cents(p_amount, 'bank_debit'))
    * s.debit_discount_share)::int)
  from public.billing_settings s
$$;

-- Share of a session's charge given back as credit when it is cancelled.
-- CLG or tutor cancellations are always a full credit. A no-show earns none.
create or replace function private.billing_cancel_credit_percent(
  p_starts_at timestamptz, p_cancelled_at timestamptz, p_cancelled_by_role text, p_status text
)
returns int language sql stable
set search_path = ''
as $$
  select case
    when p_status = 'no_show' then 0
    when p_cancelled_by_role in ('tutor', 'admin') then 100
    when p_cancelled_at is null then 0
    when p_starts_at - p_cancelled_at > make_interval(hours => s.full_credit_hours) then 100
    when p_starts_at - p_cancelled_at >= make_interval(hours => s.half_credit_hours) then 50
    else 0
  end
  from public.billing_settings s
$$;

-- Send, due and charge dates for an invoice whose first session is on
-- p_first. Weekly and monthly: due 4 days before, sent 1 week before that.
-- Per term and upfront: due 1 week before, sent 2 weeks before that. A bank
-- debit is taken early enough to clear: the due date or 4 business days
-- before the first session, whichever is earlier.
create or replace function private.billing_dates(
  p_plan public.billing_plan, p_method public.billing_method, p_first date,
  out send_on date, out due_on date, out charge_on date
)
language plpgsql stable
set search_path = ''
as $$
declare
  s public.billing_settings;
begin
  select * into s from public.billing_settings;
  if p_plan in ('weekly', 'monthly') then
    due_on := p_first - s.short_plan_due_days;
    send_on := due_on - s.short_plan_send_days;
  else
    due_on := p_first - s.long_plan_due_days;
    send_on := due_on - s.long_plan_send_days;
  end if;
  charge_on := due_on;
  if p_method = 'bank_debit' then
    charge_on := least(due_on, private.business_days_before(p_first, s.debit_clear_business_days));
  end if;
end;
$$;

-- The billing period (start and end) that a day falls in, for a plan.
create or replace function private.billing_period_for(
  p_family uuid, p_plan public.billing_plan, p_day date,
  out period_start date, out period_end date
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_state public.au_state;
begin
  if p_plan = 'weekly' then
    period_start := p_day - (extract(isodow from p_day)::int - 1);
    period_end := period_start + 6;
  elsif p_plan = 'monthly' then
    period_start := date_trunc('month', p_day)::date;
    period_end := (date_trunc('month', p_day) + interval '1 month - 1 day')::date;
  elsif p_plan = 'term' then
    select st.state into v_state from public.students st where st.family_id = p_family limit 1;
    select sp.starts_on, sp.ends_on into period_start, period_end
    from public.billing_school_periods sp
    where sp.state = coalesce(v_state, 'SA') and p_day between sp.starts_on and sp.ends_on
    order by sp.starts_on limit 1;
  end if;
  -- 'upfront' periods are chosen by an admin, so there is no automatic one.
end;
$$;

-- ---------------------------------------------------------------------------
-- Building invoices
-- ---------------------------------------------------------------------------

-- Builds one invoice for a family's sessions between two dates (Adelaide
-- days), one line per session, using credit first. Sessions already on a
-- live invoice are skipped. Returns the new invoice, or nothing if there
-- was nothing to bill. Admins or the server only.
create or replace function public.billing_build_invoice(p_family uuid, p_from date, p_to date)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_account public.billing_accounts;
  v_family_name text;
  v_invoice uuid;
  v_first date;
  v_dates record;
  v_subtotal int;
  v_gst int;
  v_credit int;
  v_discount int;
  v_balance int;
  v_show_tutor boolean;
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can build invoices' using errcode = '42501';
  end if;
  if p_to < p_from then
    raise exception 'The end date is before the start date' using errcode = '22023';
  end if;

  select * into v_account from public.billing_accounts where family_id = p_family;
  if not found then
    raise exception 'This family has no billing account yet' using errcode = '22023';
  end if;
  select name into v_family_name from public.families where id = p_family;
  select show_tutor_on_invoice into v_show_tutor from public.billing_settings;

  -- Sessions to bill: booked or delivered, in the dates, not on a live
  -- invoice already. A session already cancelled before billing is left off.
  create temporary table if not exists pg_temp.billing_new_lines (
    session_id uuid, student_id uuid, price_item_id uuid, line_date date, description text,
    minutes int, billed_minutes int, hourly_cents int, amount_cents int, gst_cents int
  ) on commit drop;
  delete from pg_temp.billing_new_lines;

  insert into pg_temp.billing_new_lines
  select
    se.id,
    se.student_id,
    r.price_item_id,
    (se.starts_at at time zone 'Australia/Adelaide')::date,
    left(
      to_char(se.starts_at at time zone 'Australia/Adelaide', 'Dy FMDD Mon YYYY, FMHH12:MIam')
      || ' to ' || to_char(se.ends_at at time zone 'Australia/Adelaide', 'FMHH12:MIam')
      || ', ' || split_part(trim(st.full_name), ' ', 1)
      || ', ' || se.subject
      || case when v_show_tutor then coalesce(', with ' || split_part(trim(ta.full_name), ' ', 1), '') else '' end,
      300),
    m.minutes,
    bm.billed,
    r.hourly_cents,
    round(r.hourly_cents * bm.billed / 60.0)::int,
    case when r.gst_applies then round(round(r.hourly_cents * bm.billed / 60.0) / 11.0)::int else 0 end
  from public.sessions se
  join public.students st on st.id = se.student_id
  left join public.accounts ta on ta.id = se.tutor_id
  cross join lateral (select greatest(1, round(extract(epoch from se.ends_at - se.starts_at) / 60))::int as minutes) m
  cross join lateral (select private.billing_minutes(m.minutes) as billed) bm
  cross join lateral private.billing_rate(p_family, se.level_kind::text) r
  where coalesce(se.family_id, st.family_id) = p_family
    and se.status::text in ('scheduled', 'completed', 'no_show')
    and (se.starts_at at time zone 'Australia/Adelaide')::date between p_from and p_to
    and not exists (
      select 1 from public.billing_invoice_lines l
      where l.session_id = se.id and l.active
    );

  if not exists (select 1 from pg_temp.billing_new_lines) then
    return null;
  end if;

  select min(line_date), sum(amount_cents), sum(gst_cents)
    into v_first, v_subtotal, v_gst
  from pg_temp.billing_new_lines;
  select * into v_dates from private.billing_dates(v_account.plan, v_account.method, v_first);
  -- Built late (for example a new family starting this week): it goes out
  -- today and is due today, never in the past.
  v_dates.send_on := greatest(v_dates.send_on, private.billing_today());
  v_dates.due_on := greatest(v_dates.due_on, private.billing_today());
  v_dates.charge_on := greatest(v_dates.charge_on, private.billing_today());

  -- Credit first, then the bank-debit discount on what's left.
  select coalesce(sum(amount_cents), 0) into v_balance
  from public.billing_credits where family_id = p_family;
  v_credit := least(greatest(v_balance, 0), v_subtotal);
  v_discount := case when v_account.method = 'bank_debit'
    then private.billing_debit_discount(v_subtotal - v_credit) else 0 end;

  insert into public.billing_invoices (
    family_id, family_name, plan, method, period_start, period_end, first_session_on,
    send_on, due_on, charge_on, subtotal_cents, gst_cents, discount_cents,
    credit_applied_cents, total_cents, created_by
  ) values (
    p_family, coalesce(v_family_name, 'Family'), v_account.plan, v_account.method, p_from, p_to, v_first,
    v_dates.send_on, v_dates.due_on, v_dates.charge_on, v_subtotal, v_gst, v_discount,
    v_credit, v_subtotal - v_credit - v_discount, auth.uid()
  )
  returning id into v_invoice;

  insert into public.billing_invoice_lines (
    invoice_id, session_id, student_id, price_item_id, line_date, description,
    minutes, billed_minutes, hourly_cents, amount_cents, gst_cents
  )
  select v_invoice, session_id, student_id, price_item_id, line_date, description,
         minutes, billed_minutes, hourly_cents, amount_cents, gst_cents
  from pg_temp.billing_new_lines
  order by line_date, description;

  if v_credit > 0 then
    insert into public.billing_credits (family_id, kind, amount_cents, invoice_id, note, created_by)
    values (p_family, 'applied', -v_credit, v_invoice, 'Used on this invoice', auth.uid());
  end if;

  delete from pg_temp.billing_new_lines;
  return v_invoice;
end;
$$;

-- Builds every invoice that is due to go out by a day: for each family,
-- the coming periods of their plan whose send date has arrived. Run daily
-- by the server; admins can run it from the billing page.
create or replace function public.billing_build_due_invoices(p_today date default null)
returns int language plpgsql security definer
set search_path = ''
as $$
declare
  v_today date := coalesce(p_today, private.billing_today());
  a record;
  v_day date;
  v_period record;
  v_dates record;
  v_first date;
  v_made int := 0;
  v_id uuid;
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can build invoices' using errcode = '42501';
  end if;

  for a in select * from public.billing_accounts where plan <> 'upfront' loop
    -- Look at periods starting up to about 10 weeks ahead (covers a term
    -- invoice sent 3 weeks before the term).
    v_day := v_today;
    while v_day <= v_today + 70 loop
      select * into v_period from private.billing_period_for(a.family_id, a.plan, v_day);
      if v_period.period_start is null then
        v_day := v_day + 1;
        continue;
      end if;

      -- First unbilled session in this period decides the send date.
      select min((se.starts_at at time zone 'Australia/Adelaide')::date) into v_first
      from public.sessions se
      join public.students st on st.id = se.student_id
      where coalesce(se.family_id, st.family_id) = a.family_id
        and se.status::text in ('scheduled', 'completed')
        and (se.starts_at at time zone 'Australia/Adelaide')::date
            between greatest(v_period.period_start, v_today) and v_period.period_end
        and not exists (select 1 from public.billing_invoice_lines l where l.session_id = se.id and l.active);

      if v_first is not null then
        select * into v_dates from private.billing_dates(a.plan, a.method, v_first);
        if v_dates.send_on <= v_today then
          v_id := public.billing_build_invoice(a.family_id, greatest(v_period.period_start, v_today), v_period.period_end);
          if v_id is not null then
            v_made := v_made + 1;
          end if;
        end if;
      end if;
      v_day := v_period.period_end + 1;
    end loop;
  end loop;
  return v_made;
end;
$$;

-- Without Xero connected (or for a quick fix), an admin approves an invoice
-- in the app and it goes to the family.
create or replace function public.billing_approve_invoice(p_invoice uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can approve invoices' using errcode = '42501';
  end if;
  update public.billing_invoices
  set status = case when total_cents = 0 then 'paid' else 'open' end::public.billing_invoice_status,
      approved_at = now(), approved_by = auth.uid()
  where id = p_invoice and status in ('draft', 'awaiting_approval');
  if not found then
    raise exception 'Only a draft or waiting invoice can be approved' using errcode = '22023';
  end if;
end;
$$;

-- Cancels an invoice. Its sessions can be billed again and any credit it
-- used goes back to the family.
create or replace function public.billing_void_invoice(p_invoice uuid, p_reason text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v public.billing_invoices;
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can cancel invoices' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Please give a reason for cancelling the invoice' using errcode = '22023';
  end if;
  select * into v from public.billing_invoices where id = p_invoice for update;
  if not found or v.status in ('paid', 'void') then
    raise exception 'Only an unpaid invoice can be cancelled' using errcode = '22023';
  end if;
  if exists (select 1 from public.billing_payments where invoice_id = p_invoice and status in ('processing', 'succeeded')) then
    raise exception 'This invoice has a payment on it, so it can''t be cancelled' using errcode = '22023';
  end if;

  update public.billing_invoices
  set status = 'void', voided_at = now(), void_reason = left(trim(p_reason), 500)
  where id = p_invoice;
  update public.billing_invoice_lines set active = false where invoice_id = p_invoice;
  if v.credit_applied_cents > 0 then
    insert into public.billing_credits (family_id, kind, amount_cents, invoice_id, note, created_by)
    values (v.family_id, 'returned', v.credit_applied_cents, p_invoice, 'Invoice cancelled', auth.uid());
  end if;
  if v.family_id is not null then
    perform private.billing_refresh_pause(v.family_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Credits
-- ---------------------------------------------------------------------------

create or replace function public.billing_credit_balance(p_family uuid)
returns int language sql stable security definer
set search_path = ''
as $$
  select case when private.is_backend() or private.is_admin() or private.is_family_payer(p_family)
    then coalesce((select sum(amount_cents) from public.billing_credits where family_id = p_family), 0)::int
  end
$$;

-- Gives credit for billed sessions that were later cancelled, by the
-- notice rule. Run daily by the server; safe to run again. Returns how
-- many sessions were credited.
create or replace function public.billing_credit_cancellations()
returns int language plpgsql security definer
set search_path = ''
as $$
declare
  n int;
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  insert into public.billing_credits (family_id, kind, amount_cents, session_id, invoice_id, note)
  select i.family_id,
         'cancellation',
         round(l.amount_cents * private.billing_cancel_credit_percent(se.starts_at, se.cancelled_at, se.cancelled_by_role::text, se.status::text) / 100.0)::int,
         se.id,
         i.id,
         left(private.billing_cancel_credit_percent(se.starts_at, se.cancelled_at, se.cancelled_by_role::text, se.status::text)::text
              || '% credit: ' || l.description, 500)
  from public.billing_invoice_lines l
  join public.billing_invoices i on i.id = l.invoice_id
  join public.sessions se on se.id = l.session_id
  where l.active
    and i.status in ('open', 'paid')
    and se.status::text in ('cancelled', 'no_show')
    and not exists (
      select 1 from public.billing_credits c
      where c.session_id = se.id and c.kind in ('cancellation', 'missed_in_pause', 'tutor_day_off')
    )
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- An admin adds goodwill credit, with a note.
create or replace function public.billing_add_credit(p_family uuid, p_amount_cents int, p_note text)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v uuid;
begin
  if not private.is_admin() then
    raise exception 'Only admins can add credit' using errcode = '42501';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 or p_amount_cents > 500000 then
    raise exception 'Credit must be between $0.01 and $5,000' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_note, ''))) < 5 then
    raise exception 'Please say why the credit is given' using errcode = '22023';
  end if;
  insert into public.billing_credits (family_id, kind, amount_cents, note, created_by)
  values (p_family, 'goodwill', p_amount_cents, left(trim(p_note), 500), auth.uid())
  returning id into v;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pauses
-- ---------------------------------------------------------------------------

-- Is this family's support on hold? Scheduling calls this before booking
-- or making sessions.
create or replace function private.billing_family_paused(p_family uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select coalesce((select paused from public.billing_accounts where family_id = p_family), false)
$$;

-- Should this family be paused today? Yes when an invoice sent to them is
-- unpaid and either past its due date or its payment failed, and no
-- override is in force. A bank debit still processing is not overdue.
create or replace function private.billing_should_pause(p_family uuid, p_today date)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.billing_invoices i
      where i.family_id = p_family
        and i.status = 'open'
        and not exists (
          select 1 from public.billing_payments p
          where p.invoice_id = i.id and p.status in ('processing', 'succeeded')
        )
        and (
          i.due_on < p_today
          or exists (select 1 from public.billing_payments p where p.invoice_id = i.id and p.status = 'failed')
        )
    )
    and not exists (
      select 1 from public.billing_pause_overrides o
      where o.family_id = p_family and o.ended_at is null and o.until_on >= p_today
    )
$$;

-- Brings a family's pause up to date, records the change and queues the
-- message for their tutors. Returns the family's paused state.
create or replace function private.billing_refresh_pause(p_family uuid, p_today date default null)
returns boolean language plpgsql security definer
set search_path = ''
as $$
declare
  v_today date := coalesce(p_today, private.billing_today());
  v_was boolean;
  v_now boolean;
begin
  select paused into v_was from public.billing_accounts where family_id = p_family for update;
  if not found then
    return false;
  end if;
  v_now := private.billing_should_pause(p_family, v_today);
  if v_now = v_was then
    return v_now;
  end if;

  update public.billing_accounts
  set paused = v_now, paused_since = case when v_now then now() end
  where family_id = p_family;

  insert into public.billing_pause_events (family_id, kind, reason)
  values (p_family, case when v_now then 'paused' else 'resumed' end,
          case when v_now then 'Invoice unpaid' else 'Paid or override' end);

  -- Tell each current tutor of the family's students. No money details.
  insert into public.billing_tutor_notices (tutor_id, student_id, kind)
  select distinct a.tutor_id, a.student_id, case when v_now then 'on_hold' else 'back_on' end
  from public.tutor_assignments a
  join public.students s on s.id = a.student_id
  where s.family_id = p_family
    and private.assignment_is_current(a.starts_on, a.ends_on);

  perform private.log_event(case when v_now then 'billing_paused' else 'billing_resumed' end,
                            'billing_accounts', p_family::text, '{}'::jsonb);
  return v_now;
end;
$$;

-- Brings every family's pause up to date. Run daily by the server (and
-- after each payment message).
create or replace function public.billing_refresh_all_pauses(p_today date default null)
returns int language plpgsql security definer
set search_path = ''
as $$
declare
  a record;
  n int := 0;
  v_was boolean;
begin
  if not (private.is_backend() or private.is_admin()) then
    raise exception 'Only admins can do this' using errcode = '42501';
  end if;
  for a in select family_id, paused from public.billing_accounts loop
    v_was := a.paused;
    if private.billing_refresh_pause(a.family_id, p_today) is distinct from v_was then
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

-- Lifts a pause without payment until a date: the new due date, or the
-- next payment of an agreed plan. Owner only (or admins, if the setting
-- allows). Missing that date brings the pause back.
create or replace function public.billing_override_pause(
  p_family uuid, p_reason text, p_until date, p_payment_plan text default null
)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v uuid;
begin
  if not private.can_override_pause() then
    raise exception 'Only the owner can lift a pause without payment' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Please give a reason' using errcode = '22023';
  end if;
  if p_until is null or p_until < private.billing_today() or p_until > private.billing_today() + 90 then
    raise exception 'Choose a new due date or next plan payment date within 90 days' using errcode = '22023';
  end if;
  if not exists (select 1 from public.billing_accounts where family_id = p_family) then
    raise exception 'This family has no billing account' using errcode = '22023';
  end if;

  update public.billing_pause_overrides set ended_at = now()
  where family_id = p_family and ended_at is null;
  insert into public.billing_pause_overrides (family_id, reason, until_on, payment_plan, created_by)
  values (p_family, left(trim(p_reason), 500), p_until, nullif(left(trim(p_payment_plan), 1000), ''), auth.uid())
  returning id into v;
  perform private.billing_refresh_pause(p_family);
  return v;
end;
$$;

-- Is the signed-in student's or parent's support on hold? For the "please
-- check with your parent" notice. Shows no money details.
create or replace function public.my_support_on_hold()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.billing_accounts b
    where b.paused and private.in_family(b.family_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- Family actions
-- ---------------------------------------------------------------------------

-- A parent accepts the family terms. Recorded with the version and time.
create or replace function public.billing_accept_terms(p_family uuid, p_version text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_family_payer(p_family) then
    raise exception 'Only a parent or adult learner in this family can accept the terms' using errcode = '42501';
  end if;
  if nullif(trim(p_version), '') is null then
    raise exception 'Missing terms version' using errcode = '22023';
  end if;
  insert into public.billing_accounts (family_id, bill_payer_id)
  values (p_family, auth.uid())
  on conflict (family_id) do nothing;
  update public.billing_accounts
  set terms_version = left(trim(p_version), 40), terms_accepted_at = now(), terms_accepted_by = auth.uid(),
      bill_payer_id = coalesce(bill_payer_id, auth.uid())
  where family_id = p_family;
end;
$$;

-- ---------------------------------------------------------------------------
-- Server-only: results from Stripe
-- ---------------------------------------------------------------------------

-- Saves the reference to a family's card or bank debit after they set it
-- up on Stripe's page.
create or replace function public.billing_save_payment_method(
  p_family uuid, p_customer text, p_payment_method text, p_method public.billing_method, p_mandate text default null
)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_backend() then
    raise exception 'Only the server can do this' using errcode = '42501';
  end if;
  if p_method = 'none' then
    raise exception 'Missing payment method type' using errcode = '22023';
  end if;
  update public.billing_accounts
  set stripe_customer_id = p_customer,
      stripe_payment_method_id = p_payment_method,
      stripe_mandate_id = p_mandate,
      method = case when plan = 'weekly' and p_method = 'bank_debit' then method else p_method end
  where family_id = p_family;
end;
$$;

-- Records a payment result from Stripe (or a manual payment by the server)
-- and updates the invoice and the family's pause. Safe to repeat: the same
-- Stripe payment updates the same row.
create or replace function public.billing_record_payment(
  p_invoice uuid, p_provider text, p_ref text, p_method public.billing_method,
  p_amount_cents int, p_status public.billing_payment_status, p_message text default null
)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_family uuid;
  v_total int;
  v_paid int;
begin
  if not private.is_backend() then
    raise exception 'Only the server can record payments' using errcode = '42501';
  end if;
  select family_id, total_cents into v_family, v_total
  from public.billing_invoices where id = p_invoice for update;
  if not found then
    raise exception 'Unknown invoice' using errcode = '22023';
  end if;

  insert into public.billing_payments (invoice_id, provider, provider_ref, method, amount_cents, status, failure_message)
  values (p_invoice, p_provider, p_ref, p_method, p_amount_cents, p_status, left(p_message, 500))
  on conflict (provider, provider_ref) do update
    set status = excluded.status,
        amount_cents = excluded.amount_cents,
        failure_message = excluded.failure_message
    -- A late "processing" message never undoes a final result.
    where public.billing_payments.status = 'processing';

  select coalesce(sum(amount_cents), 0) into v_paid
  from public.billing_payments where invoice_id = p_invoice and status = 'succeeded';
  if v_paid >= v_total then
    update public.billing_invoices set status = 'paid'
    where id = p_invoice and status in ('open', 'awaiting_approval', 'draft');
  end if;

  if v_family is not null then
    perform private.billing_refresh_pause(v_family);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Who may run what
-- ---------------------------------------------------------------------------
revoke execute on function private.billing_family_paused(uuid) from public;
grant execute on function private.billing_family_paused(uuid) to authenticated, service_role;
revoke execute on function private.billing_refresh_pause(uuid, date) from public;

revoke all on function public.billing_build_invoice(uuid, date, date) from public, anon;
revoke all on function public.billing_build_due_invoices(date) from public, anon;
revoke all on function public.billing_approve_invoice(uuid) from public, anon;
revoke all on function public.billing_void_invoice(uuid, text) from public, anon;
revoke all on function public.billing_credit_balance(uuid) from public, anon;
revoke all on function public.billing_credit_cancellations() from public, anon;
revoke all on function public.billing_add_credit(uuid, int, text) from public, anon;
revoke all on function public.billing_refresh_all_pauses(date) from public, anon;
revoke all on function public.billing_override_pause(uuid, text, date, text) from public, anon;
revoke all on function public.my_support_on_hold() from public, anon;
revoke all on function public.billing_accept_terms(uuid, text) from public, anon;
revoke all on function public.billing_save_payment_method(uuid, text, text, public.billing_method, text) from public, anon, authenticated;
revoke all on function public.billing_record_payment(uuid, text, text, public.billing_method, int, public.billing_payment_status, text) from public, anon, authenticated;

grant execute on function public.billing_build_invoice(uuid, date, date) to authenticated, service_role;
grant execute on function public.billing_build_due_invoices(date) to authenticated, service_role;
grant execute on function public.billing_approve_invoice(uuid) to authenticated, service_role;
grant execute on function public.billing_void_invoice(uuid, text) to authenticated, service_role;
grant execute on function public.billing_credit_balance(uuid) to authenticated, service_role;
grant execute on function public.billing_credit_cancellations() to authenticated, service_role;
grant execute on function public.billing_add_credit(uuid, int, text) to authenticated;
grant execute on function public.billing_refresh_all_pauses(date) to authenticated, service_role;
grant execute on function public.billing_override_pause(uuid, text, date, text) to authenticated;
grant execute on function public.my_support_on_hold() to authenticated;
grant execute on function public.billing_accept_terms(uuid, text) to authenticated;
grant execute on function public.billing_save_payment_method(uuid, text, text, public.billing_method, text) to service_role;
grant execute on function public.billing_record_payment(uuid, text, text, public.billing_method, int, public.billing_payment_status, text) to service_role;
