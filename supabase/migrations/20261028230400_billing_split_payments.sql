-- Billing part 5 (module: billing): splitting a family's invoices between
-- payers, for example two parents who each pay half.
--
-- How it works:
--   * The family's bill payer stays the main payer. An admin can add other
--     payers (a parent of a child in the family, or an adult learner in it)
--     with a whole-number share, for example 50%. The main payer pays what
--     is left.
--   * Each invoice is still one invoice (one set of lines, one Xero invoice
--     to the main payer). When it is made, each payer's share of the total
--     is worked out and kept with it, so later changes to the split only
--     affect new invoices.
--   * Each payer saves their own card or bank debit and is charged only
--     their share. Each payer sees only their own share and payments, never
--     the other payer's payment details (separated parents).
--   * The invoice is paid when the shares add up to the total. CLG's rule
--     stays: an overdue invoice puts the whole family on hold, even if one
--     payer has paid their share.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Extra payers
-- ---------------------------------------------------------------------------
create table if not exists public.billing_payers (
  family_id uuid not null references public.families (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  share_percent int not null check (share_percent between 1 and 99),
  method public.billing_method not null default 'none',
  -- Stripe references only. Not card or bank numbers.
  stripe_customer_id text,
  stripe_payment_method_id text,
  stripe_mandate_id text,
  payment_ready boolean generated always as (method <> 'none' and stripe_payment_method_id is not null) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (family_id, account_id)
);

-- Each invoice's split, kept when the invoice is made. No rows means the
-- main payer pays it all (every invoice made before splits existed).
create table if not exists public.billing_invoice_shares (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoices (id) on delete cascade,
  payer_id uuid references public.accounts (id) on delete set null,
  share_percent int not null check (share_percent between 1 and 100),
  amount_cents int not null check (amount_cents >= 0)
);
create unique index if not exists billing_invoice_shares_once
  on public.billing_invoice_shares (invoice_id, coalesce(payer_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Who made each payment, so each payer's share can be tracked.
alter table public.billing_payments add column if not exists payer_id uuid references public.accounts (id) on delete set null;

alter table public.billing_payers enable row level security;
alter table public.billing_invoice_shares enable row level security;
revoke all on public.billing_payers, public.billing_invoice_shares from anon;

drop trigger if exists audit on public.billing_payers;
create trigger audit after insert or update or delete on public.billing_payers
  for each row execute function private.audit_change();
drop trigger if exists touch on public.billing_payers;
create trigger touch before update on public.billing_payers
  for each row execute function private.touch_updated_at();

-- Is this account someone who may pay for this family: a parent of a child
-- in it, or an adult (18+) learner in it?
create or replace function private.can_pay_for_family(p_family uuid, p_account uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.students s
      join public.parent_student_links l on l.student_id = s.id
      where s.family_id = p_family and l.parent_id = p_account
    )
    or exists (
      select 1 from public.students s
      where s.family_id = p_family and s.account_id = p_account
        and s.date_of_birth <= (current_date - interval '18 years')::date
    )
$$;
revoke execute on function private.can_pay_for_family(uuid, uuid) from public;

-- Extra payers: admins see and manage; a payer sees their own row and the
-- family's main payer sees the split (shares only, never the other
-- payer's Stripe references).
drop policy if exists "see payers" on public.billing_payers;
create policy "see payers" on public.billing_payers
  for select to authenticated using (
    private.is_admin()
    or account_id = auth.uid()
    or exists (select 1 from public.billing_accounts b where b.family_id = billing_payers.family_id and b.bill_payer_id = auth.uid())
  );
revoke select, insert, update, delete on public.billing_payers from authenticated;
grant select (family_id, account_id, share_percent, method, payment_ready, created_at, updated_at)
  on public.billing_payers to authenticated;

-- Shares: admins see all; a payer sees their own share.
drop policy if exists "see own share" on public.billing_invoice_shares;
create policy "see own share" on public.billing_invoice_shares
  for select to authenticated using (private.is_admin() or payer_id = auth.uid());
revoke insert, update, delete on public.billing_invoice_shares from authenticated;

-- Payments: a payer sees their own payments (and older ones made before
-- splits); admins see all.
drop policy if exists "see own payments" on public.billing_payments;
create policy "see own payments" on public.billing_payments
  for select to authenticated using (
    private.is_admin()
    or (
      exists (select 1 from public.billing_invoices i where i.id = invoice_id)
      and (payer_id is null or payer_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- Admin: set or remove a split
-- ---------------------------------------------------------------------------
create or replace function public.billing_set_split(p_family uuid, p_payer uuid, p_share int)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_main uuid;
  v_plan public.billing_plan;
  v_others int;
begin
  if not private.is_admin() then
    raise exception 'Only admins can split payments' using errcode = '42501';
  end if;
  select bill_payer_id, plan into v_main, v_plan from public.billing_accounts where family_id = p_family;
  if v_main is null then
    raise exception 'Choose the family''s bill payer first' using errcode = '22023';
  end if;
  if p_payer = v_main then
    raise exception 'This person is already the main bill payer' using errcode = '22023';
  end if;
  if not private.can_pay_for_family(p_family, p_payer) then
    raise exception 'Only a parent or adult learner in this family can share the payments' using errcode = '22023';
  end if;
  if p_share is null or p_share < 1 or p_share > 99 then
    raise exception 'The share must be between 1%% and 99%%' using errcode = '22023';
  end if;
  select coalesce(sum(share_percent), 0) into v_others
  from public.billing_payers where family_id = p_family and account_id <> p_payer;
  if v_others + p_share > 99 then
    raise exception 'The shares add up to more than 99%%, so the main payer would pay nothing' using errcode = '22023';
  end if;

  insert into public.billing_payers (family_id, account_id, share_percent)
  values (p_family, p_payer, p_share)
  on conflict (family_id, account_id) do update set share_percent = excluded.share_percent;
end;
$$;

create or replace function public.billing_remove_split(p_family uuid, p_payer uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can change split payments' using errcode = '42501';
  end if;
  delete from public.billing_payers where family_id = p_family and account_id = p_payer;
end;
$$;

-- ---------------------------------------------------------------------------
-- Keeping each invoice's split
-- ---------------------------------------------------------------------------

-- Before an invoice is saved: if any payer uses bank debit, the charge date
-- allows for it to clear in time.
create or replace function private.billing_split_charge_date()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_dates record;
begin
  if new.family_id is not null and exists (
    select 1 from public.billing_payers p
    where p.family_id = new.family_id and p.method = 'bank_debit'
  ) then
    select * into v_dates from private.billing_dates(new.plan, 'bank_debit', new.first_session_on);
    new.charge_on := greatest(least(new.charge_on, v_dates.charge_on), private.billing_today());
  end if;
  return new;
end;
$$;
drop trigger if exists split_charge_date on public.billing_invoices;
create trigger split_charge_date before insert on public.billing_invoices
  for each row execute function private.billing_split_charge_date();

-- After an invoice is saved: each payer's share of the total. The main
-- payer gets what's left, so the shares always add up exactly.
create or replace function private.billing_split_invoice()
returns trigger language plpgsql security definer
set search_path = ''
as $$
declare
  v_main uuid;
  v_others int;
  v_assigned int;
begin
  if new.family_id is null or not exists (select 1 from public.billing_payers where family_id = new.family_id) then
    return new;
  end if;
  select bill_payer_id into v_main from public.billing_accounts where family_id = new.family_id;

  insert into public.billing_invoice_shares (invoice_id, payer_id, share_percent, amount_cents)
  select new.id, p.account_id, p.share_percent, floor(new.total_cents * p.share_percent / 100.0)::int
  from public.billing_payers p
  where p.family_id = new.family_id
  on conflict do nothing;

  select coalesce(sum(share_percent), 0), coalesce(sum(amount_cents), 0) into v_others, v_assigned
  from public.billing_invoice_shares where invoice_id = new.id;
  insert into public.billing_invoice_shares (invoice_id, payer_id, share_percent, amount_cents)
  values (new.id, v_main, 100 - v_others, new.total_cents - v_assigned)
  on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists split_invoice on public.billing_invoices;
create trigger split_invoice after insert on public.billing_invoices
  for each row execute function private.billing_split_invoice();

-- Each payer's share of an invoice and what they've paid or have on its
-- way. Admins and the server see every payer; a parent sees only their own
-- share. An invoice with no split shows the whole amount for the main
-- payer, which any payer in the family may pay (as before).
create or replace function public.billing_invoice_payers(p_invoice uuid)
returns table (payer_id uuid, share_percent int, amount_cents int, paid_cents int, pending_cents int)
language sql stable security definer
set search_path = ''
as $$
  with inv as (
    select i.id, i.family_id, i.total_cents, b.bill_payer_id
    from public.billing_invoices i
    left join public.billing_accounts b on b.family_id = i.family_id
    where i.id = p_invoice
  ),
  shares as (
    select s.payer_id, s.share_percent, s.amount_cents
    from public.billing_invoice_shares s where s.invoice_id = p_invoice
    union all
    select inv.bill_payer_id, 100, inv.total_cents
    from inv
    where not exists (select 1 from public.billing_invoice_shares s where s.invoice_id = p_invoice)
  ),
  split as (
    select exists (select 1 from public.billing_invoice_shares s where s.invoice_id = p_invoice) as yes
  )
  select sh.payer_id, sh.share_percent, sh.amount_cents,
    coalesce((
      select sum(p.amount_cents) from public.billing_payments p
      where p.invoice_id = p_invoice and p.status = 'succeeded'
        and (not split.yes or p.payer_id is not distinct from sh.payer_id)
    ), 0)::int,
    coalesce((
      select sum(p.amount_cents) from public.billing_payments p
      where p.invoice_id = p_invoice and p.status = 'processing'
        and (not split.yes or p.payer_id is not distinct from sh.payer_id)
    ), 0)::int
  from shares sh, inv, split
  where private.is_backend()
     or private.is_admin()
     or (split.yes and sh.payer_id = auth.uid())
     or (not split.yes and inv.family_id is not null and private.is_family_payer(inv.family_id))
$$;

-- ---------------------------------------------------------------------------
-- Server-only: results from Stripe for a payer
-- ---------------------------------------------------------------------------

-- Saves an extra payer's card or bank debit reference.
create or replace function public.billing_save_payer_method(
  p_family uuid, p_payer uuid, p_customer text, p_payment_method text,
  p_method public.billing_method, p_mandate text default null
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
  update public.billing_payers p
  set stripe_customer_id = p_customer,
      stripe_payment_method_id = p_payment_method,
      stripe_mandate_id = p_mandate,
      -- Weekly plans pay by card only.
      method = case
        when p_method = 'bank_debit' and (select plan from public.billing_accounts b where b.family_id = p.family_id) = 'weekly'
          then p.method
        else p_method end
  where p.family_id = p_family and p.account_id = p_payer;
end;
$$;

-- Records a payment result for a payer (null for the main payer on an
-- invoice without a split). Same rules as billing_record_payment.
create or replace function public.billing_record_payer_payment(
  p_invoice uuid, p_payer uuid, p_provider text, p_ref text, p_method public.billing_method,
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

  insert into public.billing_payments (invoice_id, payer_id, provider, provider_ref, method, amount_cents, status, failure_message)
  values (p_invoice, p_payer, p_provider, p_ref, p_method, p_amount_cents, p_status, left(p_message, 500))
  on conflict (provider, provider_ref) do update
    set status = excluded.status,
        amount_cents = excluded.amount_cents,
        failure_message = excluded.failure_message,
        payer_id = coalesce(public.billing_payments.payer_id, excluded.payer_id)
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
-- Pauses with split payments
-- ---------------------------------------------------------------------------

-- A family is paused when a sent invoice isn't fully paid (or on its way)
-- and either its due date has passed or a payer's payment failed and that
-- payer hasn't paid since. No override in force. Without a split this is
-- the same rule as before.
create or replace function private.billing_should_pause(p_family uuid, p_today date)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.billing_invoices i
      where i.family_id = p_family
        and i.status = 'open'
        and coalesce((
          select sum(p.amount_cents) from public.billing_payments p
          where p.invoice_id = i.id and p.status in ('processing', 'succeeded')
        ), 0) < i.total_cents
        and (
          i.due_on < p_today
          or exists (
            select 1 from public.billing_payments f
            where f.invoice_id = i.id and f.status = 'failed'
              and not exists (
                select 1 from public.billing_payments g
                where g.invoice_id = i.id and g.status in ('processing', 'succeeded')
                  and g.payer_id is not distinct from f.payer_id
              )
          )
        )
    )
    and not exists (
      select 1 from public.billing_pause_overrides o
      where o.family_id = p_family and o.ended_at is null and o.until_on >= p_today
    )
$$;

-- ---------------------------------------------------------------------------
-- Who may run what
-- ---------------------------------------------------------------------------
revoke execute on function private.billing_split_charge_date() from public;
revoke execute on function private.billing_split_invoice() from public;
revoke all on function public.billing_set_split(uuid, uuid, int) from public, anon;
revoke all on function public.billing_remove_split(uuid, uuid) from public, anon;
revoke all on function public.billing_invoice_payers(uuid) from public, anon;
revoke all on function public.billing_save_payer_method(uuid, uuid, text, text, public.billing_method, text) from public, anon, authenticated;
revoke all on function public.billing_record_payer_payment(uuid, uuid, text, text, public.billing_method, int, public.billing_payment_status, text) from public, anon, authenticated;
grant execute on function public.billing_set_split(uuid, uuid, int) to authenticated;
grant execute on function public.billing_remove_split(uuid, uuid) to authenticated;
grant execute on function public.billing_invoice_payers(uuid) to authenticated, service_role;
grant execute on function public.billing_save_payer_method(uuid, uuid, text, text, public.billing_method, text) to service_role;
grant execute on function public.billing_record_payer_payment(uuid, uuid, text, text, public.billing_method, int, public.billing_payment_status, text) to service_role;
