-- Summary: three changes to normal billing (Carla, 22 Nov 2026):
--   1. Payment plan fees. Each monthly invoice gets a $10 "Monthly payment
--      plan fee" line and each weekly invoice a $5 "Weekly payment plan fee"
--      line. Per term and all upfront invoices have no fee. Both amounts are
--      price items the owner can change on Admin > Billing > Prices. The fee
--      is the same whether the family pays by card or bank debit, so it is a
--      plan fee and not a card surcharge. Fees only go on invoices whose first
--      session is on or after the "Plan fees start from" setting (30 Nov 2026
--      to begin with), so families have agreed to the terms that mention it.
--   2. Changing a family's hourly rate. The owner or a Finance admin can set
--      or remove a family's hourly rate at any time, choosing the first
--      session date it applies to. Unpaid invoices with sessions from that
--      date are re-priced straight away. If such an invoice was already sent,
--      it is marked as amended, the people who pay are told the new total,
--      and the daily billing run updates it in Xero and emails the amended
--      invoice from Xero. Paid invoices are never changed: a lower rate gives
--      the family credit for the difference, and a higher rate only applies
--      to invoices that are not paid yet. A higher rate cannot start before
--      today, because sessions already given were agreed at the old rate.
--   3. A reminder 24 hours before every payment. The daily billing run
--      reminds each person who pays the day before their saved card or bank
--      account is charged, or the day before an invoice they pay themselves
--      is due. The reminder is an app notice (which also sends a pop-up
--      notification) and an email. A saved card or bank account is only
--      charged once its reminder is at least 20 hours old, so nobody is
--      charged without a day's warning.
--
-- Module: billing. It reads sessions and writes app notices only through
-- the shared private.add_notice function, as other billing files do.
-- Safe to run more than once. Run after every earlier billing file,
-- including 20261124710900_student_success_program.sql.

-- ---------------------------------------------------------------------------
-- 1. New settings and invoice columns
-- ---------------------------------------------------------------------------
-- The first session date that plan fees apply to (invoices starting earlier have no fee).
alter table public.billing_settings -- the billing settings row
  add column if not exists plan_fees_from date not null default '2026-11-30'; -- 30 Nov 2026, when trial families start
-- When an invoice was last re-priced after a rate change, and what its total was before.
alter table public.billing_invoices -- the invoices table
  add column if not exists amended_at timestamptz, -- when it was last re-priced (blank if never)
  add column if not exists amended_from_cents int, -- its total before that change, in cents
  add column if not exists xero_amended_at timestamptz; -- when Xero was last updated to match (blank if not yet)
-- A quick list of amended invoices that Xero still needs to hear about.
create index if not exists billing_invoices_amended_waiting -- the index
  on public.billing_invoices (amended_at) -- by when they were amended
  where amended_at is not null and xero_invoice_id is not null; -- only amended invoices that are in Xero

-- ---------------------------------------------------------------------------
-- 2. The two plan fees, as prices the owner can change
-- ---------------------------------------------------------------------------
insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, active, description) values -- adds two prices:
  ('plan_fee_monthly', 'Monthly payment plan fee', 'once', 1000, false, true, -- $10 on each monthly invoice,
   'Added once to each monthly invoice (Carla, 22 Nov 2026). The same whether the family pays by card or bank debit.'), -- with a plain description
  ('plan_fee_weekly', 'Weekly payment plan fee', 'once', 500, false, true, -- $5 on each weekly invoice,
   'Added once to each weekly invoice (Carla, 22 Nov 2026). The same whatever the family pays with.') -- with a plain description
on conflict (code) do nothing; -- leaves them alone if they are already there (so a price the owner changed is kept)

-- The plan fee price item for a plan, if one is in use (none for per term or all upfront).
create or replace function private.billing_plan_fee_item(p_plan public.billing_plan) -- takes the plan
returns public.billing_price_items -- gives back the fee's price item (blank if none)
language sql stable security definer -- reads the price list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select p.* from public.billing_price_items p -- the price item
  where p.code = case p_plan when 'monthly' then 'plan_fee_monthly' when 'weekly' then 'plan_fee_weekly' end -- for this plan's fee
    and p.active and p.amount_cents > 0 -- only if it is in use and more than $0
$$; -- end of the function
revoke all on function private.billing_plan_fee_item(public.billing_plan) from public; -- for the database's own use only

-- The plan fee for a plan, in cents (0 when there is none). Other billing
-- parts, such as Student Success Program instalments, can reuse it.
create or replace function private.billing_plan_fee_cents(p_plan public.billing_plan) -- takes the plan
returns integer -- gives back the fee in cents
language sql stable security definer -- reads the price list for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select coalesce((private.billing_plan_fee_item(p_plan)).amount_cents, 0) -- the fee's amount, or 0 if there is none
$$; -- end of the function
revoke all on function private.billing_plan_fee_cents(public.billing_plan) from public; -- for the database's own use only

-- ---------------------------------------------------------------------------
-- 3. Building an invoice now adds the plan fee line
-- ---------------------------------------------------------------------------
-- Same as before, with one new step: a monthly or weekly invoice whose
-- first session is on or after the "Plan fees start from" date gets one
-- plan fee line, dated the first session's day (so payments cover it first).
create or replace function public.billing_build_invoice(p_family uuid, p_from date, p_to date) -- takes the family and the session dates
returns uuid -- gives back the new invoice's id (blank if there was nothing to bill)
language plpgsql security definer -- reads sessions and writes invoices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_account public.billing_accounts; -- the family's billing account
  v_family_name text; -- the family's name, copied onto the invoice
  v_invoice uuid; -- the new invoice's id
  v_first date; -- the first session's day
  v_dates record; -- the send, due and charge dates
  v_subtotal int; -- the total before credit and discount, in cents
  v_gst int; -- the GST in the total, in cents
  v_credit int; -- the credit used, in cents
  v_discount int; -- the bank debit discount, in cents
  v_balance int; -- the family's credit balance, in cents
  v_show_tutor boolean; -- whether the tutor's first name goes on each line
  v_fee public.billing_price_items; -- the plan fee's price item (if any)
  v_fees_from date; -- the first session date plan fees apply to
begin -- start
  if not (private.is_backend() or private.is_pay_admin()) then -- only the server, the owner or a Finance admin:
    raise exception 'Only the owner or a Finance admin can build invoices' using errcode = '42501'; -- anyone else is refused
  end if; -- end of the check
  if p_to < p_from then -- dates the wrong way round:
    raise exception 'The end date is before the start date' using errcode = '22023'; -- plain message
  end if; -- end of the check

  select * into v_account from public.billing_accounts where family_id = p_family; -- reads the family's billing account
  if not found then -- none yet:
    raise exception 'This family has no billing account yet' using errcode = '22023'; -- plain message
  end if; -- end of the check
  select name into v_family_name from public.families where id = p_family; -- reads the family's name
  select show_tutor_on_invoice, plan_fees_from into v_show_tutor, v_fees_from from public.billing_settings; -- reads the two settings used below

  -- Sessions to bill: booked or delivered, in the dates, not on a live
  -- invoice already. A session already cancelled before billing is left off.
  create temporary table if not exists pg_temp.billing_new_lines ( -- a scratch table for the new lines:
    session_id uuid, student_id uuid, price_item_id uuid, line_date date, description text, -- what each line is for,
    minutes int, billed_minutes int, hourly_cents int, amount_cents int, gst_cents int -- and its time and money
  ) on commit drop; -- (thrown away at the end)
  delete from pg_temp.billing_new_lines; -- empties it, in case it was used earlier in this transaction

  insert into pg_temp.billing_new_lines -- fills it with one line per session:
  select -- each line's values:
    se.id, -- the session,
    se.student_id, -- the student,
    r.price_item_id, -- the price used,
    (se.starts_at at time zone 'Australia/Adelaide')::date, -- the session's day in Adelaide,
    left( -- the words (at most 300 letters):
      to_char(se.starts_at at time zone 'Australia/Adelaide', 'Dy FMDD Mon YYYY, FMHH12:MIam') -- the day, date and start time,
      || ' to ' || to_char(se.ends_at at time zone 'Australia/Adelaide', 'FMHH12:MIam') -- the end time,
      || ', ' || split_part(trim(st.full_name), ' ', 1) -- the student's first name,
      || ', ' || se.subject -- the subject,
      || case when v_show_tutor then coalesce(', with ' || split_part(trim(ta.full_name), ' ', 1), '') else '' end, -- and the tutor's first name, if that setting is on
      300), -- (end of the words)
    m.minutes, -- the booked minutes,
    bm.billed, -- the minutes charged (half-hour steps, 1 hr minimum),
    r.hourly_cents, -- the hourly price,
    round(r.hourly_cents * bm.billed / 60.0)::int, -- the line's amount,
    case when r.gst_applies then round(round(r.hourly_cents * bm.billed / 60.0) / 11.0)::int else 0 end -- and the GST in it, if GST applies
  from public.sessions se -- from the sessions
  join public.students st on st.id = se.student_id -- with their student
  left join public.accounts ta on ta.id = se.tutor_id -- and tutor (if any)
  cross join lateral (select greatest(1, round(extract(epoch from se.ends_at - se.starts_at) / 60))::int as minutes) m -- works out the booked minutes
  cross join lateral (select private.billing_minutes(m.minutes) as billed) bm -- and the minutes charged
  cross join lateral private.billing_rate(p_family, se.level_kind::text) r -- and the family's hourly rate for the session's level
  where coalesce(se.family_id, st.family_id) = p_family -- sessions for this family
    and se.status::text in ('scheduled', 'completed', 'no_show') -- that are booked, done or missed
    and (se.starts_at at time zone 'Australia/Adelaide')::date between p_from and p_to -- in the dates asked for
    and not exists ( -- and not already
      select 1 from public.billing_invoice_lines l -- on an invoice line
      where l.session_id = se.id and l.active -- that is still in use
    ); -- end of the sessions

  if not exists (select 1 from pg_temp.billing_new_lines) then -- nothing to bill:
    return null; -- gives back nothing
  end if; -- end of the check

  select min(line_date) into v_first from pg_temp.billing_new_lines; -- the first session's day

  -- The plan fee (Carla, 22 Nov 2026): one line on each monthly or weekly
  -- invoice, the same however the family pays.
  v_fee := private.billing_plan_fee_item(v_account.plan); -- the fee for the family's plan (blank for per term or all upfront)
  if v_fee.id is not null and v_first >= v_fees_from then -- there is a fee, and this invoice starts on or after the start date:
    insert into pg_temp.billing_new_lines -- adds a fee line:
    values (null, null, v_fee.id, v_first, left(v_fee.name, 300), -- not for a session, dated the first session's day, named after the fee,
            60, 60, v_fee.amount_cents, v_fee.amount_cents, -- one unit at the fee's amount,
            case when v_fee.gst_applies then round(v_fee.amount_cents / 11.0)::int else 0 end); -- with GST only if the fee's GST setting is on
  end if; -- end of the fee

  select sum(amount_cents), sum(gst_cents) into v_subtotal, v_gst from pg_temp.billing_new_lines; -- the totals, fee included
  select * into v_dates from private.billing_dates(v_account.plan, v_account.method, v_first); -- the send, due and charge dates
  -- Built late (for example a new family starting this week): it goes out
  -- today and is due today, never in the past.
  v_dates.send_on := greatest(v_dates.send_on, private.billing_today()); -- sends no earlier than today
  v_dates.due_on := greatest(v_dates.due_on, private.billing_today()); -- due no earlier than today
  v_dates.charge_on := greatest(v_dates.charge_on, private.billing_today()); -- charged no earlier than today

  -- Credit first, then the bank-debit discount on what is left.
  select coalesce(sum(amount_cents), 0) into v_balance -- the family's credit balance
  from public.billing_credits where family_id = p_family; -- (all their credit rows added up)
  v_credit := least(greatest(v_balance, 0), v_subtotal); -- uses as much credit as the invoice needs
  v_discount := case when v_account.method = 'bank_debit' -- bank debit families
    then private.billing_debit_discount(v_subtotal - v_credit) else 0 end; -- get their discount on what is left

  insert into public.billing_invoices ( -- saves the invoice:
    family_id, family_name, plan, method, period_start, period_end, first_session_on, -- who and when,
    send_on, due_on, charge_on, subtotal_cents, gst_cents, discount_cents, -- its dates and money,
    credit_applied_cents, total_cents, created_by -- credit used, total and who built it
  ) values ( -- with:
    p_family, coalesce(v_family_name, 'Family'), v_account.plan, v_account.method, p_from, p_to, v_first, -- the family, plan, method and dates,
    v_dates.send_on, v_dates.due_on, v_dates.charge_on, v_subtotal, v_gst, v_discount, -- the dates and amounts,
    v_credit, v_subtotal - v_credit - v_discount, auth.uid() -- the credit, the total to pay, and who built it
  ) -- end of the values
  returning id into v_invoice; -- keeps the new invoice's id

  insert into public.billing_invoice_lines ( -- saves the lines:
    invoice_id, session_id, student_id, price_item_id, line_date, description, -- what each is for,
    minutes, billed_minutes, hourly_cents, amount_cents, gst_cents -- and its time and money
  ) -- end of the columns
  select v_invoice, session_id, student_id, price_item_id, line_date, description, -- from the scratch table,
         minutes, billed_minutes, hourly_cents, amount_cents, gst_cents -- every value
  from pg_temp.billing_new_lines -- (each new line)
  order by line_date, description; -- in date order

  if v_credit > 0 then -- if credit was used:
    insert into public.billing_credits (family_id, kind, amount_cents, invoice_id, note, created_by) -- records it as used:
    values (p_family, 'applied', -v_credit, v_invoice, 'Used on this invoice', auth.uid()); -- (a negative row on the family's balance)
  end if; -- end of the credit

  delete from pg_temp.billing_new_lines; -- empties the scratch table
  return v_invoice; -- gives back the new invoice's id
end; -- finish
$$; -- end of the function
revoke all on function public.billing_build_invoice(uuid, date, date) from public, anon; -- nobody by default
grant execute on function public.billing_build_invoice(uuid, date, date) to authenticated, service_role; -- signed-in people (checked inside) and the server

-- ---------------------------------------------------------------------------
-- 4. Re-pricing one invoice's totals after its lines change
-- ---------------------------------------------------------------------------
-- Works out the totals again from the lines: credit used stays the same
-- unless the invoice is now smaller than it (the rest goes back to the
-- family's credit), the bank debit discount is worked out again, and each
-- payer's share of a split invoice follows the new total.
create or replace function private.billing_retotal_invoice(p_invoice uuid) -- takes the invoice
returns void -- gives back nothing
language plpgsql security definer -- writes invoices for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v public.billing_invoices; -- the invoice as it was
  v_subtotal int; -- the new total before credit and discount
  v_gst int; -- the new GST
  v_credit int; -- the credit used now
  v_discount int; -- the new bank debit discount
  v_total int; -- the new total to pay
  v_others int; -- the total of the other payers' shares
begin -- start
  select * into v from public.billing_invoices where id = p_invoice for update; -- reads the invoice, and holds it while it changes
  select coalesce(sum(amount_cents), 0), coalesce(sum(gst_cents), 0) into v_subtotal, v_gst -- adds up
  from public.billing_invoice_lines where invoice_id = p_invoice and active; -- its lines still in use
  v_credit := least(v.credit_applied_cents, v_subtotal); -- the credit it can still use
  if v_credit < v.credit_applied_cents then -- some credit is no longer needed:
    insert into public.billing_credits (family_id, kind, amount_cents, invoice_id, note) -- gives it back to the family:
    values (v.family_id, 'returned', v.credit_applied_cents - v_credit, p_invoice, 'Invoice re-priced'); -- (a positive row on their balance)
  end if; -- end of the credit
  v_discount := case when v.method = 'bank_debit' -- bank debit invoices
    then private.billing_debit_discount(v_subtotal - v_credit) else 0 end; -- get the discount worked out again
  v_total := greatest(v_subtotal - v_credit - v_discount, 0); -- the new total (never below $0)
  update public.billing_invoices -- saves the new totals:
  set subtotal_cents = v_subtotal, gst_cents = v_gst, credit_applied_cents = v_credit, -- the total, GST and credit,
      discount_cents = v_discount, total_cents = v_total -- the discount and the total to pay
  where id = p_invoice; -- on this invoice
  -- A split invoice: each other payer's share follows their percentage, and the bill payer pays the rest.
  update public.billing_invoice_shares s -- the shares
  set amount_cents = floor(v_total * s.share_percent / 100.0)::int -- each the payer's percentage of the new total
  from public.billing_accounts b -- (with the family's bill payer)
  where s.invoice_id = p_invoice and b.family_id = v.family_id -- on this invoice
    and s.payer_id is distinct from b.bill_payer_id; -- for payers other than the bill payer
  select coalesce(sum(s.amount_cents), 0) into v_others -- adds up the other payers' shares
  from public.billing_invoice_shares s join public.billing_accounts b on b.family_id = v.family_id -- (with the bill payer)
  where s.invoice_id = p_invoice and s.payer_id is distinct from b.bill_payer_id; -- on this invoice
  update public.billing_invoice_shares s -- the bill payer's share
  set amount_cents = v_total - v_others -- is what is left
  from public.billing_accounts b -- (with the family's bill payer)
  where s.invoice_id = p_invoice and b.family_id = v.family_id and s.payer_id = b.bill_payer_id; -- on this invoice
end; -- finish
$$; -- end of the function
revoke all on function private.billing_retotal_invoice(uuid) from public; -- for the database's own use only

-- ---------------------------------------------------------------------------
-- 5. Setting a family's hourly rate (owner or Finance admin)
-- ---------------------------------------------------------------------------
-- Sets (or, with no amount, removes) a family's own hourly rate for one
-- session price, and re-prices invoices from the chosen session date.
-- Gives back how many invoices were re-priced, how many of those the
-- family had already been sent, and any credit given for paid invoices.
create or replace function public.billing_set_family_rate( -- the function
  p_family uuid, -- the family
  p_price_item uuid, -- the session price (school or tertiary tutoring)
  p_amount_cents integer, -- their hourly rate in cents (blank to go back to the price list)
  p_note text default null, -- an optional note for admins
  p_from date default null -- the first session date it applies to (today if blank)
) -- end of the inputs
returns jsonb -- gives back what changed
language plpgsql security definer -- writes billing tables for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_item public.billing_price_items; -- the session price
  v_old int; -- the family's hourly rate before the change
  v_new int; -- the family's hourly rate after the change
  v_from date := coalesce(p_from, private.billing_today()); -- the first session date it applies to
  r record; -- one invoice
  v_old_total int; -- an invoice's total before re-pricing
  v_new_total int; -- an invoice's total after re-pricing
  v_credit int; -- credit for a paid invoice
  v_repriced int := 0; -- how many invoices were re-priced
  v_amended int := 0; -- how many of those had been sent to the family
  v_credit_total int := 0; -- the credit given for paid invoices
  v_payer uuid; -- one person who pays
begin -- start
  if not (private.is_backend() or (select private.is_pay_admin())) then -- only the server, the owner or a Finance admin:
    raise exception 'Only the owner or a Finance admin can change a family''s hourly rate' using errcode = '42501'; -- anyone else is refused
  end if; -- end of the check
  select * into v_item from public.billing_price_items where id = p_price_item; -- reads the price
  if not found or v_item.session_level is null then -- not a session price:
    raise exception 'Choose the school or tertiary tutoring price' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if p_amount_cents is not null and (p_amount_cents < 0 or p_amount_cents > 100000) then -- a strange amount:
    raise exception 'Enter an hourly rate between $0 and $1000' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not exists (select 1 from public.families where id = p_family) then -- no such family:
    raise exception 'That family could not be found' using errcode = '22023'; -- plain message
  end if; -- end of the check

  v_old := coalesce((select amount_cents from public.billing_family_rates where family_id = p_family and price_item_id = p_price_item), v_item.amount_cents); -- the rate they pay now
  v_new := coalesce(p_amount_cents, v_item.amount_cents); -- the rate they will pay
  if v_new > v_old and v_from < private.billing_today() then -- a higher rate starting in the past:
    raise exception 'A higher rate can only start from today or later, because sessions already given were agreed at the old rate' using errcode = '22023'; -- plain message
  end if; -- end of the check

  if p_amount_cents is null then -- going back to the price list:
    delete from public.billing_family_rates where family_id = p_family and price_item_id = p_price_item; -- removes their own rate
  else -- a rate of their own:
    insert into public.billing_family_rates (family_id, price_item_id, amount_cents, note) -- saves it:
    values (p_family, p_price_item, p_amount_cents, nullif(left(trim(coalesce(p_note, '')), 500), '')) -- with the note (if any)
    on conflict (family_id, price_item_id) do update -- or, if they had one already,
      set amount_cents = excluded.amount_cents, note = coalesce(excluded.note, public.billing_family_rates.note); -- replaces the amount (keeping the old note if none is given)
  end if; -- end of the save

  -- Each of the family's invoices with lines at this price from the chosen date, at a different hourly amount.
  for r in -- goes through:
    select i.id, i.number, i.status, i.total_cents, -- each invoice's id, number, stage and total,
           exists (select 1 from public.billing_payments p where p.invoice_id = i.id and p.status in ('processing', 'succeeded')) as has_payment -- and whether any payment is on it
    from public.billing_invoices i -- from the invoices
    where i.family_id = p_family and i.kind = 'sessions' -- this family's session invoices
      and i.status in ('draft', 'awaiting_approval', 'open', 'paid') -- that are not cancelled
      and exists ( -- and that have
        select 1 from public.billing_invoice_lines l -- a line
        where l.invoice_id = i.id and l.active and l.price_item_id = p_price_item -- at this price, still in use,
          and l.session_id is not null and l.line_date >= v_from and l.hourly_cents <> v_new -- for a session from the date, at another amount
      ) -- end of the check
    order by i.first_session_on -- oldest first
  loop -- for each one:
    if r.status = 'paid' or r.has_payment then -- already paid, or partly paid: the invoice is a record and stays as it is
      select coalesce(sum(l.amount_cents - round(v_new * l.billed_minutes / 60.0)::int), 0) into v_credit -- the difference the new rate makes
      from public.billing_invoice_lines l -- (on its lines)
      where l.invoice_id = r.id and l.active and l.price_item_id = p_price_item -- at this price
        and l.session_id is not null and l.line_date >= v_from and l.hourly_cents > v_new; -- for sessions from the date, where the new rate is lower
      if v_credit > 0 then -- the rate went down:
        insert into public.billing_credits (family_id, kind, amount_cents, invoice_id, note, created_by) -- gives credit for the difference:
        values (p_family, 'goodwill', v_credit, r.id, left('Hourly rate lowered: difference for sessions on invoice ' || r.number, 500), auth.uid()); -- (a goodwill credit, which also goes to Xero as a credit note)
        v_credit_total := v_credit_total + v_credit; -- adds it to the total given
        for v_payer in select private.billing_family_payer_ids(p_family) loop -- tells each person who pays:
          perform private.add_notice(v_payer, null, null, 'request_update', 'Credit for a lower hourly rate', -- a notice:
            'Your hourly rate has been lowered. Invoice ' || r.number || ' was already paid, so you have been given ' -- what happened,
              || to_char(v_credit / 100.0, 'FM$999990.00') || ' credit, which comes off your next invoice.', now()); -- and the credit given
        end loop; -- end of the payers
      end if; -- end of the credit (a higher rate never changes an invoice already paid)
      continue; -- moves on to the next invoice
    end if; -- end of the paid case

    v_old_total := r.total_cents; -- keeps the old total
    update public.billing_invoice_lines l -- re-prices its lines:
    set hourly_cents = v_new, -- the new hourly rate,
        amount_cents = round(v_new * l.billed_minutes / 60.0)::int, -- the new amount,
        gst_cents = case when v_item.gst_applies then round(round(v_new * l.billed_minutes / 60.0) / 11.0)::int else 0 end -- and the GST in it, if any
    where l.invoice_id = r.id and l.active and l.price_item_id = p_price_item -- on this invoice, at this price,
      and l.session_id is not null and l.line_date >= v_from; -- for sessions from the date
    perform private.billing_retotal_invoice(r.id); -- works out the invoice's totals again
    select total_cents into v_new_total from public.billing_invoices where id = r.id; -- reads the new total
    v_repriced := v_repriced + 1; -- counts it
    delete from public.billing_payment_reminders where invoice_id = r.id; -- any payment reminder had the old amount, so a new one is sent (and any charge waits for it)

    if r.status in ('awaiting_approval', 'open') then -- already in Xero:
      update public.billing_invoices -- marks it amended,
      set amended_at = now(), amended_from_cents = coalesce(amended_from_cents, v_old_total) -- keeping the total the family was first sent
      where id = r.id; -- so the billing run updates Xero to match
    end if; -- end of the Xero case
    if r.status = 'open' then -- the family already has it:
      v_amended := v_amended + 1; -- counts it as amended
      for v_payer in select private.billing_family_payer_ids(p_family) loop -- tells each person who pays:
        perform private.add_notice(v_payer, null, null, 'request_update', 'Invoice ' || r.number || ' has been updated', -- a notice:
          'Your hourly rate has changed, so invoice ' || r.number || ' has been updated. The new total is ' -- what happened,
            || to_char(v_new_total / 100.0, 'FM$999990.00') || ' (it was ' || to_char(v_old_total / 100.0, 'FM$999990.00') -- the new and old totals,
            || '). You can see it under Billing, and the amended invoice will also be emailed to you.', now()); -- and where to see it
      end loop; -- end of the payers
    end if; -- end of the sent case
  end loop; -- end of the invoices

  perform private.billing_refresh_pause(p_family); -- a new total can start or end a hold, so checks it
  return jsonb_build_object('repriced', v_repriced, 'amended', v_amended, 'credit_cents', v_credit_total); -- gives back what changed
end; -- finish
$$; -- end of the function
revoke all on function public.billing_set_family_rate(uuid, uuid, integer, text, date) from public, anon; -- nobody by default
grant execute on function public.billing_set_family_rate(uuid, uuid, integer, text, date) to authenticated, service_role; -- signed-in people (checked inside) and the server

-- ---------------------------------------------------------------------------
-- 6. Payment reminders, 24 hours before each payment
-- ---------------------------------------------------------------------------
-- One row for each person reminded about each invoice. Written only by the
-- server. Admins can read them; families see the reminder as a notice.
create table if not exists public.billing_payment_reminders ( -- the table
  id uuid primary key default gen_random_uuid(), -- the reminder's id
  invoice_id uuid not null references public.billing_invoices (id) on delete cascade, -- the invoice it is about
  payer_id uuid not null references public.accounts (id) on delete cascade, -- the person reminded
  amount_cents int not null check (amount_cents >= 0), -- the amount they were told about, in cents
  pay_on date not null, -- the day the payment is taken or due
  automatic boolean not null, -- true if their saved card or bank account will be charged
  created_at timestamptz not null default now(), -- when the reminder was made (a charge waits until this is 20 hours old)
  email_id uuid, -- the email's id once it is sent
  emailed_at timestamptz, -- when the email was sent
  unique (invoice_id, payer_id) -- one reminder per person per invoice
); -- end of the table
-- A quick list of reminder emails waiting to go.
create index if not exists billing_payment_reminders_email_waiting on public.billing_payment_reminders (created_at) where emailed_at is null; -- the index
alter table public.billing_payment_reminders enable row level security; -- access rules on
drop policy if exists "finance reads payment reminders" on public.billing_payment_reminders; -- removes the old rule (safe to run again)
create policy "finance reads payment reminders" on public.billing_payment_reminders -- the rule:
  for select to authenticated using ((select private.is_finance_admin())); -- billing admins can read them (nobody can write them)
grant select on public.billing_payment_reminders to authenticated; -- reading is allowed, within the rule above
grant all on public.billing_payment_reminders to service_role; -- the server can do everything

-- Makes tomorrow's reminders. For each sent, unpaid session invoice: each person
-- who pays is reminded once, the day before their saved method is charged,
-- or the day before the invoice is due if they pay it themselves. An
-- automatic charge whose day has already come is reminded now and taken
-- on the next run. Gives back how many reminders were made.
create or replace function public.billing_queue_payment_reminders(p_today date default null) -- takes the day (today if blank)
returns integer -- how many reminders were made
language plpgsql security definer -- reads and writes billing tables for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_today date := coalesce(p_today, private.billing_today()); -- the day
  r record; -- one reminder to make
  v_count integer := 0; -- how many were made
  v_id uuid; -- the new reminder's id
begin -- start
  if not private.is_backend() then -- only the server's daily run:
    raise exception 'Only the billing run can send payment reminders' using errcode = '42501'; -- anyone else is refused
  end if; -- end of the check
  for r in -- goes through each person to remind:
    with payers as ( -- who pays each sent, unpaid invoice, and how much:
      select i.id as invoice_id, i.number, i.kind, i.charge_on, i.due_on, -- the invoice,
             coalesce(s.payer_id, b.bill_payer_id) as payer_id, -- the person (a split payer, or the bill payer),
             coalesce(s.amount_cents, i.total_cents) as amount_cents, -- their amount (their share, or the whole invoice),
             i.auto_charge_attempted_at -- and whether an automatic charge was already tried
      from public.billing_invoices i -- from the invoices
      join public.billing_accounts b on b.family_id = i.family_id -- with the family's billing account
      left join public.billing_invoice_shares s on s.invoice_id = i.id and s.amount_cents > 0 -- and any split shares
      where i.status = 'open' and i.total_cents > 0 -- sent and for more than $0
        and i.kind = 'sessions' -- session invoices only (Student Success Program invoices send their own reminders, with program wording)
    ), methods as ( -- each payer's saved method:
      select p.*, -- the payer's details,
             coalesce(bp.payment_ready, ba.payment_ready, false) as ready, -- whether they have a saved card or bank account,
             coalesce(bp.method, ba.method) as method -- and which
      from payers p -- for each payer
      join public.billing_invoices i on i.id = p.invoice_id -- (with the invoice)
      left join public.billing_payers bp on bp.family_id = i.family_id and bp.account_id = p.payer_id -- their own method if they are a split payer
      left join public.billing_accounts ba on ba.family_id = i.family_id and ba.bill_payer_id = p.payer_id -- or the family's method if they are the bill payer
    ) -- end of the steps
    select m.*, -- each payer's details,
           (m.ready and m.method <> 'none' and m.auto_charge_attempted_at is null) as automatic -- and whether they will be charged automatically
    from methods m -- from the list
    where m.payer_id is not null and m.amount_cents > 0 -- a real person with something to pay
      and not exists ( -- not already
        select 1 from public.billing_payment_reminders x -- reminded
        where x.invoice_id = m.invoice_id and x.payer_id = m.payer_id -- about this invoice
      ) -- end of the check
      and not exists ( -- and not already paying
        select 1 from public.billing_payments p -- a payment
        where p.invoice_id = m.invoice_id and p.status in ('processing', 'succeeded') -- on this invoice, on its way or done,
          and (p.payer_id is null or p.payer_id = m.payer_id) -- by them (or for the whole invoice)
      ) -- end of the check
  loop -- for each one:
    if r.automatic then -- charged automatically:
      if r.charge_on > v_today + 1 then continue; end if; -- not yet: waits until the day before the charge
    else -- paid by the family themselves:
      if r.due_on <> v_today + 1 then continue; end if; -- only the day before it is due (never once it is overdue)
    end if; -- end of the timing
    insert into public.billing_payment_reminders (invoice_id, payer_id, amount_cents, pay_on, automatic) -- saves the reminder:
    values (r.invoice_id, r.payer_id, r.amount_cents, greatest(case when r.automatic then r.charge_on else r.due_on end, v_today + 1), r.automatic) -- the amount, the day (never sooner than tomorrow), and how it is paid
    on conflict do nothing -- (unless another run just made it)
    returning id into v_id; -- keeps its id
    if v_id is null then continue; end if; -- already made: moves on
    perform private.add_notice(r.payer_id, null, null, 'request_update', -- the app notice (with its pop-up notification):
      case when r.automatic then 'Payment tomorrow for invoice ' || r.number else 'Invoice ' || r.number || ' is due tomorrow' end, -- its title,
      case when r.automatic -- its words:
        then 'CLG will take ' || to_char(r.amount_cents / 100.0, 'FM$999990.00') || ' for invoice ' || r.number -- the amount and invoice,
          || ' from your saved ' || case when r.method = 'bank_debit' then 'bank account' else 'card' end -- from which saved method,
          || ' tomorrow, about 24 hours from now. If you need to change your card or bank account, go to Billing before then.' -- when, and how to change it
        else to_char(r.amount_cents / 100.0, 'FM$999990.00') || ' for invoice ' || r.number -- the amount and invoice,
          || ' is due tomorrow. You can pay it under Billing.' -- when, and how to pay
      end, now()); -- now (the notice waits if it is quiet hours)
    v_count := v_count + 1; -- counts it
    v_id := null; -- clears the id for the next one
  end loop; -- end of the people
  return v_count; -- gives back how many were made
end; -- finish
$$; -- end of the function
revoke all on function public.billing_queue_payment_reminders(date) from public, anon, authenticated; -- nobody but the server
grant execute on function public.billing_queue_payment_reminders(date) to service_role; -- the server's daily run

-- Hands the server the reminder emails waiting to go, marking them sent.
create or replace function public.billing_payment_reminder_emails_claim(p_limit integer default 50) -- takes how many at most
returns table (id uuid, email text, first_name text, subject text, body text, link text, button text, footer text) -- each email's parts
language plpgsql security definer -- reads and writes billing tables for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  update public.billing_payment_reminders r set emailed_at = now() -- first, old ones no longer worth sending
  where r.emailed_at is null and r.created_at <= now() - interval '12 hours'; -- (waiting more than 12 hours) are marked as dealt with
  return query -- then hands back:
  with due as ( -- the emails to send:
    select r.id from public.billing_payment_reminders r -- each reminder
    where r.emailed_at is null -- not yet emailed
    order by r.created_at -- oldest first
    limit least(greatest(p_limit, 1), 100) -- at most the number asked for (1 to 100)
    for update skip locked -- so two senders never take the same one
  ), marked as ( -- marks them sent:
    update public.billing_payment_reminders r -- each reminder taken
    set email_id = gen_random_uuid(), emailed_at = now() -- gets a new email id and the time
    from due where r.id = due.id -- (only the ones taken)
    returning r.email_id, r.payer_id, r.invoice_id, r.amount_cents, r.pay_on, r.automatic -- what the email needs
  ) -- end of the steps
  select m.email_id, -- the email's id
    ap.email, -- who it goes to
    private.first_name(a.full_name), -- their first name
    case when m.automatic then 'Payment tomorrow for CLG invoice ' || i.number else 'CLG invoice ' || i.number || ' is due tomorrow' end, -- the subject
    case when m.automatic -- the message:
      then 'CLG will take ' || to_char(m.amount_cents / 100.0, 'FM$999990.00') || ' for invoice ' || i.number -- the amount and invoice,
        || ' from your saved card or bank account on ' || to_char(m.pay_on, 'FMDay FMDD FMMonth YYYY') || '.' -- when,
        || E'\n\nIf you need to change your card or bank account, open Billing in the CLG app before then.' -- and how to change it
      else to_char(m.amount_cents / 100.0, 'FM$999990.00') || ' for invoice ' || i.number -- the amount and invoice,
        || ' is due on ' || to_char(m.pay_on, 'FMDay FMDD FMMonth YYYY') || '.' -- when,
        || E'\n\nYou can pay it under Billing in the CLG app. If a payment is overdue, sessions go on hold until it is paid.' -- how to pay, and what happens if not
    end, -- end of the message
    '/billing'::text, -- the page the button opens
    'Open Billing'::text, -- the button's words
    'You get this email because you pay for CLG sessions. CLG reminds you 24 hours before every payment.'::text -- the small print
  from marked m -- from the reminders taken
  join public.billing_invoices i on i.id = m.invoice_id -- with the invoice
  join public.accounts a on a.id = m.payer_id -- and the person's name
  join public.account_private ap on ap.account_id = m.payer_id; -- and email
end; -- finish
$$; -- end of the function
revoke all on function public.billing_payment_reminder_emails_claim(integer) from public, anon, authenticated; -- nobody but the server
grant execute on function public.billing_payment_reminder_emails_claim(integer) to service_role; -- the server's daily run

-- Puts reminder emails back to try again (when the email service refused them).
create or replace function public.billing_payment_reminder_emails_release(p_ids uuid[]) -- takes the email ids
returns void -- gives back nothing
language sql security definer -- writes billing tables for the database
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the change
  update public.billing_payment_reminders set email_id = null, emailed_at = null -- clears the email marks
  where email_id = any (p_ids) and emailed_at > now() - interval '1 hour' -- for those emails, taken in the last hour
$$; -- end of the function
revoke all on function public.billing_payment_reminder_emails_release(uuid[]) from public, anon, authenticated; -- nobody but the server
grant execute on function public.billing_payment_reminder_emails_release(uuid[]) to service_role; -- the server's daily run

-- Check after running (should say true):
-- select exists (select 1 from public.billing_price_items where code = 'plan_fee_monthly')
--    and to_regclass('public.billing_payment_reminders') is not null
--    and to_regprocedure('public.billing_set_family_rate(uuid,uuid,integer,text,date)') is not null;
