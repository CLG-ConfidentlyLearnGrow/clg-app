-- Billing part 8 (module: billing): families choose how often they pay.
--
-- Carla (2026-11-02, testing): nothing ever asked a family how often they
-- want to pay. Until now only an admin could set the plan, and new families
-- quietly got "weekly".
--
--   * The family's Billing page asks "How often would you like to pay?"
--     (weekly, monthly, per term, or all upfront) before the payment terms.
--   * A parent (or adult learner) can choose or change it until CLG sends
--     the family's first invoice. After that, they ask CLG to change it.
--   * Admins can still set it on Admin > Billing, and see which families
--     haven't chosen yet.
--
-- Safe to run more than once.

alter table public.billing_accounts add column if not exists plan_chosen_at timestamptz;
alter table public.billing_accounts add column if not exists plan_chosen_by uuid references public.accounts (id) on delete set null;

-- Families already invoiced keep the plan they have (it counts as chosen).
-- Families never invoiced yet are asked.
update public.billing_accounts b set plan_chosen_at = b.updated_at
where b.plan_chosen_at is null
  and exists (select 1 from public.billing_invoices i where i.family_id = b.family_id and i.status <> 'void');

-- Admins record that they set the plan (the admin page saves this).
grant insert (plan_chosen_at, plan_chosen_by) on public.billing_accounts to authenticated;
grant update (plan_chosen_at, plan_chosen_by) on public.billing_accounts to authenticated;

-- True once CLG has sent the family an invoice (so the plan is locked for them).
create or replace function private.billing_family_invoiced(p_family uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.billing_invoices i
    where i.family_id = p_family and i.status in ('open', 'paid')
  )
$$;

-- The families this person pays for, with their plan and whether they can
-- still change it. Drives the "How often would you like to pay?" card.
create or replace function public.billing_my_plan_choices()
returns table (family_id uuid, family_name text, plan public.billing_plan, chosen boolean, can_change boolean)
language sql stable security definer
set search_path = ''
as $$
  select f.id, f.name, coalesce(b.plan, 'weekly'::public.billing_plan),
         b.plan_chosen_at is not null,
         not private.billing_family_invoiced(f.id)
  from public.families f
  left join public.billing_accounts b on b.family_id = f.id
  where private.is_family_payer(f.id)
  order by f.name
$$;

-- A parent or adult learner chooses how often the family pays.
create or replace function public.billing_choose_plan(p_family uuid, p_plan public.billing_plan)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_family_payer(p_family) then
    raise exception 'Only a parent or adult learner in this family can choose how often to pay' using errcode = '42501';
  end if;
  if p_plan is null then
    raise exception 'Please choose how often you''d like to pay' using errcode = '22023';
  end if;
  if private.billing_family_invoiced(p_family)
     and p_plan is distinct from (select plan from public.billing_accounts where family_id = p_family) then
    raise exception 'Your first invoice has already been sent. Please contact CLG to change how often you pay' using errcode = '22023';
  end if;
  if p_plan = 'weekly' and (
       exists (select 1 from public.billing_accounts where family_id = p_family and method = 'bank_debit')
       or exists (select 1 from public.billing_payers where family_id = p_family and method = 'bank_debit')
     ) then
    raise exception 'Weekly plans pay by card. Choose monthly or per term to keep paying by bank debit' using errcode = '22023';
  end if;
  insert into public.billing_accounts (family_id, bill_payer_id, plan, plan_chosen_at, plan_chosen_by)
  values (p_family, auth.uid(), p_plan, now(), auth.uid())
  on conflict (family_id) do update
    set plan = excluded.plan, plan_chosen_at = now(), plan_chosen_by = auth.uid(),
        bill_payer_id = coalesce(public.billing_accounts.bill_payer_id, auth.uid());
end;
$$;

revoke all on function private.billing_family_invoiced(uuid) from public, anon, authenticated;
revoke all on function public.billing_my_plan_choices() from public, anon;
revoke all on function public.billing_choose_plan(uuid, public.billing_plan) from public, anon;
grant execute on function public.billing_my_plan_choices() to authenticated;
grant execute on function public.billing_choose_plan(uuid, public.billing_plan) to authenticated;
