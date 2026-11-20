-- Billing: a family can book a change of payment plan at any time, and the
-- change starts from their next invoice (Carla, 20 Nov 2026).
--
-- Before: once a family had an invoice, changing the plan switched it
-- straight away, so an invoice on the new plan could be built the same day
-- (for example the rest of a term, all at once).
-- Now:
--   * Before the family's first invoice, choosing a plan still saves it
--     straight away (nothing has been billed yet).
--   * After that, the person who pays books the change. Their current plan
--     stays in place until its next invoice is due to be built. On that day
--     the daily billing run switches to the new plan, and that invoice and
--     every later one follow the new plan. Invoices already built stay as
--     they are.
--   * The booked change shows on the Billing page with the expected start
--     date, and the person who pays (or an admin) can cancel it.
--   * The person who pays and the owner and Operations admins are told when
--     a change is booked, cancelled and made.
--   * Weekly still needs a card. If the family moves to bank debit before a
--     booked weekly change starts, the change is not made and they are told.
--
-- Safe to run more than once. Run after 20261123400500_payment_plan_required.sql.

-- ---------------------------------------------------------------------------
-- 1. Where a booked change is kept: three new columns on the billing account.
-- ---------------------------------------------------------------------------
alter table public.billing_accounts add column if not exists pending_plan public.billing_plan; -- the plan the family has asked to change to (empty when none is booked)
alter table public.billing_accounts add column if not exists pending_plan_at timestamptz; -- when the change was booked
alter table public.billing_accounts add column if not exists pending_plan_by uuid references public.accounts (id) on delete set null; -- who booked it (kept empty if that login is removed)

-- The person who pays and admins may read the booked change (the existing
-- row rule already limits rows to the family's payers and admins).
grant select (pending_plan, pending_plan_at, pending_plan_by) on public.billing_accounts to authenticated; -- lets them read the three new columns
-- Admins may clear a booked change when they set the plan themselves (the
-- existing row rule only lets admins update billing accounts).
grant update (pending_plan, pending_plan_at, pending_plan_by) on public.billing_accounts to authenticated; -- lets admins write the three new columns

-- The daily run only looks at accounts with a booked change, so a small
-- index on just those rows keeps it fast as CLG grows.
create index if not exists billing_accounts_pending_plan_idx -- names the index
  on public.billing_accounts (family_id) -- by family
  where pending_plan is not null; -- only rows with a booked change

-- ---------------------------------------------------------------------------
-- 2. Whether a family has any invoice that is not cancelled (draft, waiting
--    for approval, sent or paid). Once one exists, a plan change is booked
--    for the next invoice instead of made straight away.
-- ---------------------------------------------------------------------------
create or replace function private.billing_has_invoice(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- reads invoices for the plan functions
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- true when
    select 1 from public.billing_invoices i -- an invoice
    where i.family_id = p_family and i.status <> 'void' -- for this family is not cancelled
  ) -- (end of the check)
$$; -- end of the function
revoke all on function private.billing_has_invoice(uuid) from public; -- not for everyone
grant execute on function private.billing_has_invoice(uuid) to authenticated, service_role; -- used inside the plan functions

-- ---------------------------------------------------------------------------
-- 3. The day a plan's next invoice is due to be built. It looks at the same
--    periods the daily run looks at (about 10 weeks ahead) and returns the
--    send day of the first period with a session not already on an invoice.
--    A send day in the past comes back as today. Empty when nothing is
--    booked to bill, or for "all upfront" (CLG builds those by hand).
-- ---------------------------------------------------------------------------
create or replace function private.billing_next_send_on( -- the function
  p_family uuid, -- the family
  p_plan public.billing_plan, -- the plan to work it out for
  p_method public.billing_method, -- how they pay (bank debit can change the dates)
  p_today date -- the day to count from
) -- (end of the inputs)
returns date language plpgsql stable security definer -- reads sessions and invoices
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- working values
  v_day date := p_today; -- the day being looked at
  v_period record; -- the billing period that day falls in
  v_first date; -- the first session in that period not already on an invoice
  v_dates record; -- the send, due and charge days for that period
begin -- starts the code
  if p_plan = 'upfront' then -- "all upfront" has no automatic invoices:
    return null; -- so there is no day to give
  end if; -- end of that check
  while v_day <= p_today + 70 loop -- looks up to 10 weeks ahead (as the daily run does):
    select * into v_period from private.billing_period_for(p_family, p_plan, v_day); -- the period this day falls in
    if v_period.period_start is null then -- no period (for example no school term entered for that day):
      v_day := v_day + 1; -- tries the next day
      continue; -- and goes round again
    end if; -- end of that check
    select min((se.starts_at at time zone 'Australia/Adelaide')::date) into v_first -- the first session day
    from public.sessions se -- among sessions
    join public.students st on st.id = se.student_id -- with their student
    where coalesce(se.family_id, st.family_id) = p_family -- for this family
      and se.status::text in ('scheduled', 'completed') -- that are booked or done
      and (se.starts_at at time zone 'Australia/Adelaide')::date -- whose day is
          between greatest(v_period.period_start, p_today) and v_period.period_end -- in this period, from today on
      and not exists (select 1 from public.billing_invoice_lines l where l.session_id = se.id and l.active); -- and not already on an invoice
    if v_first is not null then -- there is something to bill in this period:
      select * into v_dates from private.billing_dates(p_plan, p_method, v_first); -- works out its send day
      return greatest(v_dates.send_on, p_today); -- and gives it back (today if it has already passed)
    end if; -- end of that check
    v_day := v_period.period_end + 1; -- moves on to the next period
  end loop; -- end of the look ahead
  return null; -- nothing to bill in the next 10 weeks
end; -- end of the code
$$; -- end of the function
revoke all on function private.billing_next_send_on(uuid, public.billing_plan, public.billing_method, date) from public; -- not for everyone
grant execute on function private.billing_next_send_on(uuid, public.billing_plan, public.billing_method, date) to authenticated, service_role; -- used inside the plan functions

-- ---------------------------------------------------------------------------
-- 4. Choosing a plan. Before the first invoice it is saved straight away.
--    After that it is booked for the next invoice. Choosing the plan the
--    family is already on cancels a booked change.
-- ---------------------------------------------------------------------------
create or replace function public.billing_choose_plan(p_family uuid, p_plan public.billing_plan) -- takes the family and plan
returns void language plpgsql security definer -- changes the billing account for them
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- working values
  v_acc public.billing_accounts; -- the family's billing account (if any)
  v_family text; -- the family's name, for the notices
begin -- starts the code
  if not (private.is_family_payer(p_family) or private.billing_can_start(p_family)) then -- not paying, and cannot start it
    raise exception 'Only the person who pays for this family can choose how often to pay' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of the who check
  if p_plan is null then -- no plan chosen
    raise exception 'Please choose how often you would like to pay' using errcode = '22023'; -- asks for one
  end if; -- end of the plan check
  if p_plan = 'weekly' and ( -- weekly, while
       exists (select 1 from public.billing_accounts where family_id = p_family and method = 'bank_debit') -- the family pays by bank debit
       or exists (select 1 from public.billing_payers where family_id = p_family and method = 'bank_debit') -- or an extra payer does
     ) then -- (weekly needs a card)
    raise exception 'Weekly plans pay by card. Choose monthly or per term to keep paying by bank debit' using errcode = '22023'; -- refuses
  end if; -- end of the method check
  select * into v_acc from public.billing_accounts where family_id = p_family for update; -- the account, held so two changes cannot cross
  v_family := coalesce((select name from public.families where id = p_family), 'A family'); -- the family's name

  -- No plan chosen yet, no invoice yet, or "all upfront" (built by hand):
  -- the plan is saved straight away, as before.
  if v_acc.family_id is null or v_acc.plan_chosen_at is null or v_acc.plan = 'upfront' -- no account, no plan yet or upfront,
     or not private.billing_has_invoice(p_family) then -- or nothing billed yet:
    insert into public.billing_accounts (family_id, bill_payer_id, plan, plan_chosen_at, plan_chosen_by) -- saves the plan:
    values (p_family, auth.uid(), p_plan, now(), auth.uid()) -- a new account with this person as bill payer,
    on conflict (family_id) do update -- or the existing account,
      set plan = excluded.plan, plan_chosen_at = now(), plan_chosen_by = auth.uid(), -- with the new plan,
          pending_plan = null, pending_plan_at = null, pending_plan_by = null, -- no booked change,
          bill_payer_id = coalesce(public.billing_accounts.bill_payer_id, auth.uid()); -- and this person as bill payer if there was not one
    if v_acc.plan = 'upfront' and v_acc.plan_chosen_at is not null and p_plan <> 'upfront' then -- moving off upfront after it was chosen:
      perform private.notify_admins('Payment plan changed', -- tells the owner and Operations admins,
        v_family || ' changed how often they pay from all upfront to ' || p_plan::text || '. Their next invoice uses the new plan.'); -- in plain words
    end if; -- end of that notice
    return; -- done
  end if; -- end of the straight away case

  -- The plan they are already on: cancels any booked change.
  if v_acc.plan = p_plan then -- same as the current plan:
    if v_acc.pending_plan is not null then -- a change was booked:
      perform public.billing_cancel_plan_change(p_family); -- cancels it (and tells everyone)
    end if; -- end of that check
    return; -- nothing else to do
  end if; -- end of the same plan case

  -- Otherwise the change is booked for the next invoice.
  update public.billing_accounts -- saves the booked change:
  set pending_plan = p_plan, pending_plan_at = now(), pending_plan_by = auth.uid() -- the new plan, when and by whom
  where family_id = p_family; -- on this family's account
  perform private.notify_admins('Payment plan change booked', -- tells the owner and Operations admins:
    v_family || ' asked to change how often they pay from ' || v_acc.plan::text || ' to ' || p_plan::text -- the old and new plan,
      || '. It starts from their next invoice. Invoices already built stay as they are.'); -- and when it starts
end; -- end of the code
$$; -- end of the function
revoke all on function public.billing_choose_plan(uuid, public.billing_plan) from public, anon; -- not for everyone
grant execute on function public.billing_choose_plan(uuid, public.billing_plan) to authenticated; -- signed-in people (the code checks who)

-- ---------------------------------------------------------------------------
-- 5. Cancelling a booked change. The person who pays or an admin can do it.
-- ---------------------------------------------------------------------------
create or replace function public.billing_cancel_plan_change(p_family uuid) -- takes the family
returns void language plpgsql security definer -- changes the billing account for them
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- working values
  v_acc public.billing_accounts; -- the family's billing account
begin -- starts the code
  if not ((select private.is_family_payer(p_family)) or (select private.is_admin())) then -- not paying and not an admin:
    raise exception 'Only the person who pays for this family can cancel a plan change' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of the who check
  select * into v_acc from public.billing_accounts where family_id = p_family for update; -- the account, held while it changes
  if v_acc.pending_plan is null then -- nothing booked:
    return; -- nothing to cancel (pressing twice does no harm)
  end if; -- end of that check
  update public.billing_accounts -- clears the booked change:
  set pending_plan = null, pending_plan_at = null, pending_plan_by = null -- no plan, time or person
  where family_id = p_family; -- on this family's account
  perform private.notify_admins('Payment plan change cancelled', -- tells the owner and Operations admins:
    coalesce((select name from public.families where id = p_family), 'A family') -- the family,
      || ' will stay on ' || v_acc.plan::text || '. The change to ' || v_acc.pending_plan::text || ' was cancelled.'); -- and what was cancelled
end; -- end of the code
$$; -- end of the function
revoke all on function public.billing_cancel_plan_change(uuid) from public, anon; -- not for everyone
grant execute on function public.billing_cancel_plan_change(uuid) to authenticated; -- signed-in people (the code checks who)

-- ---------------------------------------------------------------------------
-- 6. The day a booked change is expected to start (the current plan's next
--    invoice day), for the Billing page. Empty when nothing is booked, or no
--    sessions are booked to bill yet.
-- ---------------------------------------------------------------------------
create or replace function public.billing_plan_change_starts(p_family uuid) -- takes the family
returns date language plpgsql stable security definer -- reads sessions and invoices people cannot read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- working values
  v_acc public.billing_accounts; -- the family's billing account
begin -- starts the code
  if not ((select private.is_family_payer(p_family)) or (select private.is_admin())) then -- not paying and not an admin:
    return null; -- gives nothing away
  end if; -- end of the who check
  select * into v_acc from public.billing_accounts where family_id = p_family; -- the account
  if v_acc.pending_plan is null then -- nothing booked:
    return null; -- no day to give
  end if; -- end of that check
  return private.billing_next_send_on(p_family, v_acc.plan, v_acc.method, private.billing_today()); -- the current plan's next invoice day
end; -- end of the code
$$; -- end of the function
revoke all on function public.billing_plan_change_starts(uuid) from public, anon; -- not for everyone
grant execute on function public.billing_plan_change_starts(uuid) to authenticated; -- signed-in people (the code checks who)

-- ---------------------------------------------------------------------------
-- 7. Making booked changes on the day. For each family with a booked change
--    whose current plan's next invoice is due to be built today, the plan
--    switches, so that invoice is built on the new plan. Called by the
--    invoice builder below, just before it builds invoices.
-- ---------------------------------------------------------------------------
create or replace function private.billing_apply_plan_changes(p_today date) -- takes the day
returns int language plpgsql security definer -- changes billing accounts for the daily run
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- working values
  a record; -- one account with a booked change
  v_send date; -- the current plan's next invoice day
  v_family text; -- the family's name, for the notices
  v_made int := 0; -- how many changes were made
begin -- starts the code
  for a in -- for each account
    select * from public.billing_accounts where pending_plan is not null -- with a booked change (uses the small index)
  loop -- goes through them:
    v_family := coalesce((select name from public.families where id = a.family_id), 'A family'); -- the family's name
    if a.pending_plan = 'weekly' and ( -- a weekly change while
         a.method = 'bank_debit' -- the family now pays by bank debit
         or exists (select 1 from public.billing_payers p where p.family_id = a.family_id and p.method = 'bank_debit') -- or an extra payer does
       ) then -- (weekly needs a card, so it cannot go ahead)
      update public.billing_accounts set pending_plan = null, pending_plan_at = null, pending_plan_by = null where family_id = a.family_id; -- clears the booked change
      if a.bill_payer_id is not null then -- someone pays:
        perform private.add_notice(a.bill_payer_id, null, null, 'request_update', 'Payment plan not changed', -- tells them,
          'Your change to a weekly plan was not made, because weekly plans pay by card and your family now pays by bank debit. You are staying on the ' || a.plan::text || ' plan. You can choose again on the Billing page.', now()); -- why, and what to do
      end if; -- end of that notice
      perform private.notify_admins('Payment plan change not made', -- tells the owner and Operations admins:
        v_family || ' asked to change to weekly, but now pays by bank debit, so they stay on ' || a.plan::text || '.'); -- what happened
      continue; -- on to the next account
    end if; -- end of the weekly check
    if a.plan <> 'upfront' then -- a plan with automatic invoices:
      v_send := private.billing_next_send_on(a.family_id, a.plan, a.method, p_today); -- its next invoice day
      if v_send is null or v_send > p_today then -- not due yet (or nothing to bill):
        continue; -- waits for another day
      end if; -- end of that check
    end if; -- (upfront has no automatic invoice, so the change is made straight away)
    update public.billing_accounts -- makes the change:
    set plan = a.pending_plan, plan_chosen_at = now(), plan_chosen_by = a.pending_plan_by, -- the new plan, now, by the person who booked it,
        pending_plan = null, pending_plan_at = null, pending_plan_by = null -- and clears the booked change
    where family_id = a.family_id; -- on this family's account
    v_made := v_made + 1; -- counts it
    if a.bill_payer_id is not null then -- someone pays:
      perform private.add_notice(a.bill_payer_id, null, null, 'request_update', 'Payment plan changed', -- tells them,
        'Your payment plan is now ' || a.pending_plan::text || '. Your next invoice uses the new plan. Invoices you already have stay as they are.', now()); -- in plain words
    end if; -- end of that notice
    perform private.notify_admins('Payment plan changed', -- tells the owner and Operations admins:
      v_family || ' now pays ' || a.pending_plan::text || ' (was ' || a.plan::text || '), starting with their next invoice.'); -- what changed
  end loop; -- end of the accounts
  return v_made; -- how many changes were made
end; -- end of the code
$$; -- end of the function
revoke all on function private.billing_apply_plan_changes(date) from public, anon, authenticated; -- only the invoice builder (below) calls it
grant execute on function private.billing_apply_plan_changes(date) to service_role; -- and the server

-- ---------------------------------------------------------------------------
-- 8. The invoice builder makes booked changes first, so the invoice built
--    that day is on the new plan. This edits the builder in place, so any
--    other change made to it later is kept.
-- ---------------------------------------------------------------------------
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.billing_build_due_invoices(date)'); -- finds the invoice builder
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'billing_apply_plan_changes') = 0 then -- not changed yet:
    if strpos(v_def, 'for a in select * from public.billing_accounts where plan <> ''upfront'' loop') = 0 then -- the expected code is not there:
      raise exception 'billing_build_due_invoices has changed since this was written; please ask for help'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, -- before the loop over families, adds the plan changes:
      'for a in select * from public.billing_accounts where plan <> ''upfront'' loop', -- the loop,
      'perform private.billing_apply_plan_changes(v_today);
  for a in select * from public.billing_accounts where plan <> ''upfront'' loop'); -- with the plan changes before it
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- Check (should return true): the new columns and functions are in place.
-- select to_regprocedure('public.billing_cancel_plan_change(uuid)') is not null
--    and strpos(pg_get_functiondef('public.billing_build_due_invoices(date)'::regprocedure), 'billing_apply_plan_changes') > 0;
-- ---------------------------------------------------------------------------
