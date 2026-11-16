-- Summary: only the people paying see billing (Carla, 16 Nov 2026: "the
-- person/s paying are the only ones to see billing information").
-- Replaces the earlier rules in 20261118900100_sibling_privacy.sql and
-- 20261118900200_billing_students_who_pay.sql, where being a parent, or an
-- adult learner who is the family's only learner, was enough to see the
-- family's plan, invoices and credit.
-- Now a person sees and manages a family's billing only when they are:
--   * the family's bill payer (named by CLG on Admin > Billing, or the
--     person who set up the family's payments), or
--   * an extra payer sharing the family's invoices (named by CLG).
-- A parent, student or adult learner who isn't paying sees no plan, no
-- invoices, no credit and no Billing tab. They still see "Sessions on hold"
-- on their dashboard if an invoice is overdue.
-- Getting started: until a family has a bill payer, a parent of a child in
-- the family (or an adult learner who signed up alone) can choose the plan
-- or accept the payment terms, and doing so makes them the bill payer.
-- CLG can change the bill payer at any time.
-- Safe to run more than once. Run AFTER 20261118900200_billing_students_who_pay.sql.

-- ---------------------------------------------------------------------------
-- Who pays for a family
-- ---------------------------------------------------------------------------

-- True when the signed-in person is the family's bill payer or an extra
-- payer. Every billing access rule (plan, invoices, invoice lines,
-- payments, credit, terms) uses this check, so it decides who sees billing.
create or replace function private.is_family_payer(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select auth.uid() is not null and ( -- someone is signed in, and they are:
    exists ( -- the family's bill payer,
      select 1 from public.billing_accounts b -- the family's billing account
      where b.family_id = p_family and b.bill_payer_id = auth.uid() -- naming this person as bill payer
    ) -- end of the bill payer case
    or exists ( -- or an extra payer sharing the invoices
      select 1 from public.billing_payers p -- a split share
      where p.family_id = p_family and p.account_id = auth.uid() -- for this family, paid by this person
    ) -- end of the extra payer case
  ) -- end of the list
$$; -- end of the function

-- ---------------------------------------------------------------------------
-- Who may set up a family's payments when nobody pays yet
-- ---------------------------------------------------------------------------

-- True when the family has no bill payer yet and the signed-in person is a
-- parent of a child in it, or an adult learner (18+) who is its only
-- learner with no parent linked. Lets them choose the plan or accept the
-- terms, which makes them the bill payer. It never shows invoices.
create or replace function private.billing_can_start(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select auth.uid() is not null -- someone is signed in,
    and not exists ( -- the family has no bill payer yet,
      select 1 from public.billing_accounts b -- its billing account
      where b.family_id = p_family and b.bill_payer_id is not null -- naming someone
    ) -- end of the no-payer check
    and ( -- and they are:
      exists ( -- a parent of a child in the family,
        select 1 from public.students s -- a student
        join public.parent_student_links l on l.student_id = s.id -- with a parent link
        where s.family_id = p_family and l.parent_id = auth.uid() -- in this family, to this person
      ) -- end of the parent case
      or exists ( -- or an adult learner who signed up alone:
        select 1 from public.students s -- their own student record
        where s.family_id = p_family and s.account_id = auth.uid() -- in this family
          and s.date_of_birth <= (current_date - interval '18 years')::date -- aged 18 or over,
          and not exists (select 1 from public.students o where o.family_id = p_family and o.id <> s.id) -- the only learner,
          and not exists (select 1 from public.parent_student_links l where l.student_id = s.id) -- with no parent linked
      ) -- end of the adult learner case
    ) -- end of the list
$$; -- end of the function
revoke all on function private.billing_can_start(uuid) from public; -- for the database's own use only

-- ---------------------------------------------------------------------------
-- The plan choice, the terms and the Billing tab
-- ---------------------------------------------------------------------------

-- The families whose plan this person chooses: ones they pay for, or ones
-- with no bill payer yet that they may start.
create or replace function public.billing_my_plan_choices() -- no inputs: it's about the signed-in person
returns table (family_id uuid, family_name text, plan public.billing_plan, chosen boolean, can_change boolean) -- one row per family
language sql stable security definer -- reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  select f.id, f.name, coalesce(b.plan, 'weekly'::public.billing_plan), -- the family, its name and plan (weekly until chosen),
         b.plan_chosen_at is not null, -- whether a plan was chosen,
         not private.billing_family_invoiced(f.id) -- and whether it can still change (not after the first invoice)
  from public.families f -- of all families
  left join public.billing_accounts b on b.family_id = f.id -- with their billing account, if any
  where private.is_family_payer(f.id) or private.billing_can_start(f.id) -- that they pay for, or may start
  order by f.name -- in name order
$$; -- end of the function
revoke all on function public.billing_my_plan_choices() from public, anon; -- not for everyone
grant execute on function public.billing_my_plan_choices() to authenticated; -- signed-in people ask about themselves

-- The payer (or the person starting the family's payments) chooses how
-- often the family pays. Unchanged apart from who may do it.
create or replace function public.billing_choose_plan(p_family uuid, p_plan public.billing_plan) -- takes the family and plan
returns void language plpgsql security definer -- changes the billing account for them
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not (private.is_family_payer(p_family) or private.billing_can_start(p_family)) then -- not paying, and can't start it
    raise exception 'Only the person who pays for this family can choose how often to pay' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of the who check
  if p_plan is null then -- no plan chosen
    raise exception 'Please choose how often you''d like to pay' using errcode = '22023'; -- asks for one
  end if; -- end of the plan check
  if private.billing_family_invoiced(p_family) -- after the first invoice
     and p_plan is distinct from (select plan from public.billing_accounts where family_id = p_family) then -- a different plan
    raise exception 'Your first invoice has already been sent. Please contact CLG to change how often you pay' using errcode = '22023'; -- refuses
  end if; -- end of the invoice check
  if p_plan = 'weekly' and ( -- weekly, while
       exists (select 1 from public.billing_accounts where family_id = p_family and method = 'bank_debit') -- the family pays by bank debit
       or exists (select 1 from public.billing_payers where family_id = p_family and method = 'bank_debit') -- or an extra payer does
     ) then -- (weekly needs a card)
    raise exception 'Weekly plans pay by card. Choose monthly or per term to keep paying by bank debit' using errcode = '22023'; -- refuses
  end if; -- end of the method check
  insert into public.billing_accounts (family_id, bill_payer_id, plan, plan_chosen_at, plan_chosen_by) -- saves the plan:
  values (p_family, auth.uid(), p_plan, now(), auth.uid()) -- a new account with this person as bill payer,
  on conflict (family_id) do update -- or the existing account,
    set plan = excluded.plan, plan_chosen_at = now(), plan_chosen_by = auth.uid(), -- with the new plan,
        bill_payer_id = coalesce(public.billing_accounts.bill_payer_id, auth.uid()); -- and this person as bill payer if there wasn't one
end; -- end of the code
$$; -- end of the function
revoke all on function public.billing_choose_plan(uuid, public.billing_plan) from public, anon; -- not for everyone
grant execute on function public.billing_choose_plan(uuid, public.billing_plan) to authenticated; -- signed-in people

-- The payer (or the person starting the family's payments) accepts the
-- payment terms. Unchanged apart from who may do it.
create or replace function public.billing_accept_terms(p_family uuid, p_version text) -- takes the family and terms version
returns void language plpgsql security definer -- changes the billing account for them
set search_path = '' -- only fully named tables, for safety
as $$ -- the code
begin -- starts the code
  if not (private.is_family_payer(p_family) or private.billing_can_start(p_family)) then -- not paying, and can't start it
    raise exception 'Only the person who pays for this family can accept the payment terms' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of the who check
  if nullif(trim(p_version), '') is null then -- no version given
    raise exception 'Missing terms version' using errcode = '22023'; -- refuses
  end if; -- end of the version check
  insert into public.billing_accounts (family_id, bill_payer_id) -- makes the account if there isn't one,
  values (p_family, auth.uid()) -- with this person as bill payer
  on conflict (family_id) do nothing; -- (or keeps the existing one)
  update public.billing_accounts -- then records the terms:
  set terms_version = left(trim(p_version), 40), terms_accepted_at = now(), terms_accepted_by = auth.uid(), -- the version, when and who,
      bill_payer_id = coalesce(bill_payer_id, auth.uid()) -- and this person as bill payer if there wasn't one
  where family_id = p_family; -- for this family
end; -- end of the code
$$; -- end of the function
revoke all on function public.billing_accept_terms(uuid, text) from public, anon; -- not for everyone
grant execute on function public.billing_accept_terms(uuid, text) to authenticated; -- signed-in people

-- Used by the dashboard menus: a Billing tab only for someone who pays for
-- a family, or may start a family's payments. Gives back no for anyone
-- not signed in.
create or replace function public.billing_i_pay() -- no inputs: it's about the signed-in person
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- any family
    select 1 from public.families f -- of all families
    where private.is_family_payer(f.id) or private.billing_can_start(f.id) -- that they pay for (bill payer or extra payer), or may start
  ) -- end of the check
$$; -- end of the function
revoke all on function public.billing_i_pay() from public, anon; -- not for everyone, and never for people who aren't signed in
grant execute on function public.billing_i_pay() to authenticated; -- signed-in people can ask about themselves
