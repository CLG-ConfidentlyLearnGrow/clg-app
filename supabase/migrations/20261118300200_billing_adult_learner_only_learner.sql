-- Summary: who sees and manages a family's billing (Carla, 16 Nov 2026).
--
-- Before: any adult (18+) learner in a family saw and managed the whole
-- family's billing: plan, invoices, credit and payment set-up, even when
-- brothers or sisters were in the same family.
--
-- Now: an adult learner sees and manages family billing only when they are
-- the family's only learner. In a family with more than one learner,
-- billing stays with the parents, or with whoever CLG names as bill payer
-- (or extra payer) on Admin > Billing. Naming an adult learner as bill payer
-- is a deliberate choice by CLG; it gives them the family's billing only,
-- never their siblings' profiles (those access rules are unchanged).
--
-- Every billing access rule, page and action already asks
-- private.is_family_payer, so changing that one check applies the rule
-- everywhere: billing accounts, invoices, invoice lines, payments, credits,
-- the credit balance, the plan choice, accepting the terms, invoice payer
-- shares and the Billing count on the menu.
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- How many learners are in a family
-- ---------------------------------------------------------------------------

-- Is this person an adult (18+) learner in this family who is also its only
-- learner? Used by the billing check below.
create or replace function private.is_only_adult_learner(p_family uuid, p_account uuid) -- Takes the family and the person to check.
returns boolean language sql stable security definer -- Gives back yes or no; reads only; runs with the database's own rights so it can count every learner in the family.
set search_path = '' -- Uses full table names only, so nothing can be swapped in.
as $$
  select p_account is not null -- Someone must be named,
    and exists ( -- and they must be:
      select 1 from public.students s -- a student record
      where s.family_id = p_family -- in this family,
        and s.account_id = p_account -- that belongs to this person's own login,
        and s.date_of_birth <= (current_date - interval '18 years')::date -- for someone aged 18 or over,
    ) -- (end of the adult learner check)
    and ( -- and the family must have
      select count(*) from public.students s -- learners
      where s.family_id = p_family -- in this family
    ) = 1 -- numbering exactly one (them).
$$; -- (end of the function)
revoke execute on function private.is_only_adult_learner(uuid, uuid) from public; -- Only other database rules may use it, never a signed-in person directly.

-- ---------------------------------------------------------------------------
-- Who pays for a family
-- ---------------------------------------------------------------------------

-- Someone who pays for this family, and so sees and manages its billing:
--   * a parent of a child in it;
--   * an adult (18+) learner in it, only when they are its only learner;
--   * the bill payer CLG named on Admin > Billing;
--   * an extra payer CLG added on Admin > Billing (split payments).
-- Students under 18 see only "on hold", never invoices.
create or replace function private.is_family_payer(p_family uuid) -- Takes the family to check.
returns boolean language sql stable security definer -- Gives back yes or no; reads only; runs with the database's own rights.
set search_path = '' -- Uses full table names only, so nothing can be swapped in.
as $$
  select auth.uid() is not null and ( -- Someone must be signed in, and be one of:
    exists ( -- a parent:
      select 1 from public.students s -- a student
      join public.parent_student_links l on l.student_id = s.id -- linked to a parent
      where s.family_id = p_family and l.parent_id = auth.uid() -- in this family, where the parent is the signed-in person;
    ) -- (end of the parent check)
    or private.is_only_adult_learner(p_family, auth.uid()) -- the family's only learner, aged 18 or over;
    or exists ( -- the named bill payer:
      select 1 from public.billing_accounts b -- the family's billing account
      where b.family_id = p_family and b.bill_payer_id = auth.uid() -- names the signed-in person as bill payer;
    ) -- (end of the bill payer check)
    or exists ( -- or an extra payer CLG added:
      select 1 from public.billing_payers p -- a split payment row
      where p.family_id = p_family and p.account_id = auth.uid() -- for this family and the signed-in person.
    ) -- (end of the extra payer check)
  ) -- (end of the list)
$$; -- (end of the function)

-- ---------------------------------------------------------------------------
-- Telling an adult learner who looks after billing
-- ---------------------------------------------------------------------------

-- Is the signed-in person an adult learner whose family billing is looked
-- after by someone else (because the family has more than one learner)?
-- The Billing page uses this to explain why they see no billing, instead of
-- "no billing yet". It says only yes or no: never who the other learners
-- are, nor who pays.
create or replace function public.billing_paid_by_others() -- Takes nothing: it is always about the signed-in person.
returns boolean language sql stable security definer -- Gives back yes or no; reads only; runs with the database's own rights.
set search_path = '' -- Uses full table names only, so nothing can be swapped in.
as $$
  select exists ( -- Yes if there is
    select 1 from public.students s -- a student record
    where s.account_id = auth.uid() -- that is the signed-in person's own,
      and s.date_of_birth <= (current_date - interval '18 years')::date -- aged 18 or over,
      and not private.is_family_payer(s.family_id) -- in a family whose billing they don't look after.
  ) -- (end of the check)
$$; -- (end of the function)
revoke all on function public.billing_paid_by_others() from public, anon; -- Not for anyone who isn't signed in.
grant execute on function public.billing_paid_by_others() to authenticated; -- Signed-in people may ask about themselves.
