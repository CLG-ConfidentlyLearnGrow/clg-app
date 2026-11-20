-- Billing: choosing a payment plan is compulsory, and families can change
-- their plan later (Carla, 20 Nov 2026).
--
-- Before: a family could book and approve sessions without choosing how
-- often they pay (weekly was assumed), and once the first invoice was sent
-- only CLG could change the plan.
-- Now:
--   * A family must choose a plan (weekly, monthly, per term or all
--     upfront) before they ask for a booking or approve a time CLG offers.
--     CLG admins can still make offers, and can set the plan for a family.
--   * The person who pays can change the plan at any time. The new plan
--     carries on from the next session that is not already on an invoice:
--     sessions already invoiced stay on those invoices (paid or not), and
--     the next invoice is built on the new plan. Admins are told.
--   * Weekly still needs a card, as before.
--
-- Safe to run more than once. Each existing function is edited in place,
-- so anything else changed in it later is kept.

-- Whether a family has chosen how often they pay (read by scheduling).
create or replace function private.billing_plan_chosen(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- reads billing for the scheduling checks
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- true when
    select 1 from public.billing_accounts b -- the family's billing account
    where b.family_id = p_family and b.plan_chosen_at is not null -- has a chosen plan
  ) -- (end of the check)
$$; -- end of the function
revoke all on function private.billing_plan_chosen(uuid) from public; -- not for everyone
grant execute on function private.billing_plan_chosen(uuid) to authenticated, service_role; -- used inside the booking functions

-- The plan choice: the person who pays can now change it after the first
-- invoice. The change applies from the next session not already invoiced.
create or replace function public.billing_choose_plan(p_family uuid, p_plan public.billing_plan) -- takes the family and plan
returns void language plpgsql security definer -- changes the billing account for them
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
declare -- working values
  v_old public.billing_plan; -- the plan before the change (if any)
  v_invoiced boolean; -- whether the family has been invoiced
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
  select plan into v_old from public.billing_accounts where family_id = p_family and plan_chosen_at is not null; -- the plan they had chosen (if any)
  v_invoiced := private.billing_family_invoiced(p_family); -- whether invoices have been sent
  insert into public.billing_accounts (family_id, bill_payer_id, plan, plan_chosen_at, plan_chosen_by) -- saves the plan:
  values (p_family, auth.uid(), p_plan, now(), auth.uid()) -- a new account with this person as bill payer,
  on conflict (family_id) do update -- or the existing account,
    set plan = excluded.plan, plan_chosen_at = now(), plan_chosen_by = auth.uid(), -- with the new plan,
        bill_payer_id = coalesce(public.billing_accounts.bill_payer_id, auth.uid()); -- and this person as bill payer if there was not one
  if v_invoiced and v_old is distinct from p_plan then -- a change after invoices were sent:
    perform private.notify_admins( -- tells the owner and Operations admins:
      'Payment plan changed', -- the title,
      coalesce((select name from public.families where id = p_family), 'A family') -- the family,
        || ' changed how often they pay from ' || coalesce(v_old::text, 'not chosen') || ' to ' || p_plan::text -- the old and new plan,
        || '. It applies from the next session not already on an invoice. Sessions already invoiced stay on those invoices.'); -- and what it means
  end if; -- end of the notice
end; -- end of the code
$$; -- end of the function
revoke all on function public.billing_choose_plan(uuid, public.billing_plan) from public, anon; -- not for everyone
grant execute on function public.billing_choose_plan(uuid, public.billing_plan) to authenticated; -- signed-in people

-- The plan list: a plan can always be changed now.
create or replace function public.billing_my_plan_choices() -- no inputs: it is about the signed-in person
returns table (family_id uuid, family_name text, plan public.billing_plan, chosen boolean, can_change boolean) -- one row per family
language sql stable security definer -- reads tables people cannot read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select f.id, f.name, coalesce(b.plan, 'weekly'::public.billing_plan), -- the family, its name and plan (weekly until chosen),
         b.plan_chosen_at is not null, -- whether a plan was chosen,
         true -- and that it can be changed (from the next session not already invoiced)
  from public.families f -- of all families
  left join public.billing_accounts b on b.family_id = f.id -- with their billing account, if any
  where private.is_family_payer(f.id) or private.billing_can_start(f.id) -- that they pay for, or may start
  order by f.name -- in name order
$$; -- end of the function
revoke all on function public.billing_my_plan_choices() from public, anon; -- not for everyone
grant execute on function public.billing_my_plan_choices() to authenticated; -- signed-in people ask about themselves

-- A family asking for a weekly booking must have chosen a plan first.
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.request_booking(uuid, text, uuid, smallint, time, integer, public.session_delivery, uuid, date, date, text)'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'billing_plan_chosen') = 0 then -- not changed yet:
    if strpos(v_def, 'if private.family_paused(v_student.family_id) then') = 0 then -- the expected code is not there:
      raise exception 'request_booking has changed since this was written; please ask for help'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, -- before the paused check, adds the plan check:
      'if private.family_paused(v_student.family_id) then', -- the paused check,
      'if not private.is_front_desk() and not private.billing_plan_chosen(v_student.family_id) then
    raise exception ''Please choose how often you would like to pay (on the Billing page) before booking. If someone else pays, please ask them to choose.'' using errcode = ''23514'';
  end if;
  if private.family_paused(v_student.family_id) then'); -- with the plan check before it
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block

-- A family approving a time CLG offered must have chosen a plan first.
do $$ -- a one-off block
declare -- working values
  v_sig regprocedure; -- the function's full name
  v_def text; -- the function's current code
begin -- start
  v_sig := to_regprocedure('public.approve_booking(uuid, boolean, text)'); -- finds it
  if v_sig is null then return; end if; -- not there: nothing to do
  v_def := pg_catalog.pg_get_functiondef(v_sig); -- reads its current code
  if strpos(v_def, 'billing_plan_chosen') = 0 then -- not changed yet:
    if strpos(v_def, 'if private.family_paused(v_b.family_id) then') = 0 then -- the expected code is not there:
      raise exception 'approve_booking has changed since this was written; please ask for help'; -- stops
    end if; -- end of the check
    v_def := replace(v_def, -- before the paused check, adds the plan check:
      'if private.family_paused(v_b.family_id) then', -- the paused check,
      'if not private.is_front_desk() and not private.billing_plan_chosen(v_b.family_id) then
    raise exception ''Please choose how often you would like to pay (on the Billing page) before approving. If someone else pays, please ask them to choose.'' using errcode = ''23514'';
  end if;
  if private.family_paused(v_b.family_id) then'); -- with the plan check before it
    execute v_def; -- saves the changed function
  end if; -- done
end; -- finish
$$; -- end of the block
