-- Summary: students who don't pay for their own lessons get no billing
-- (Carla, 16 Nov 2026). Before this, any student aged 18 or over with their
-- own login counted as a payer for their family, even when a parent pays,
-- so they could see the family's plan and invoices and got a Billing tab.
-- Now a student with their own login only counts as a payer when:
--   * they are the family's chosen bill payer, or
--   * they are an adult learner in a family with no parent or guardian
--     linked (they signed up for themselves, so they pay for themselves).
-- Parents and the chosen bill payer are unchanged.
-- Also adds public.billing_i_pay(), which the menu uses to decide whether
-- to show the Billing tab on a student's dashboard.
-- Safe to run more than once. Run after 20261117230100_billing_xero_staff.sql.

-- ---------------------------------------------------------------------------
-- Who pays for a family
-- ---------------------------------------------------------------------------

-- True when the signed-in person pays for this family: a linked parent or
-- guardian of one of its students, the chosen bill payer, or an adult
-- learner (18+) in a family with no parent linked. (Split share payers are
-- handled by their own rules, as before.)
create or replace function private.is_family_payer(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select auth.uid() is not null and ( -- someone is signed in, and they are:
    exists ( -- a parent or guardian of one of the family's students (unchanged),
      select 1 from public.students s -- a student
      join public.parent_student_links l on l.student_id = s.id -- with a parent link
      where s.family_id = p_family and l.parent_id = auth.uid() -- in this family, to this person
    ) -- end of the parent case
    or exists ( -- or an adult learner paying for themselves (narrowed):
      select 1 from public.students s -- a student
      where s.family_id = p_family and s.account_id = auth.uid() -- in this family, with this person's own login
        and s.date_of_birth <= (current_date - interval '18 years')::date -- aged 18 or over
        and not exists ( -- and nobody is a parent or guardian in this family:
          select 1 from public.students other -- any student
          join public.parent_student_links l on l.student_id = other.id -- with a parent link
          where other.family_id = p_family -- in this family
        ) -- end of the no-parent check
    ) -- end of the adult learner case
    or exists ( -- or the chosen bill payer (unchanged),
      select 1 from public.billing_accounts b -- the family's billing account
      where b.family_id = p_family and b.bill_payer_id = auth.uid() -- naming this person as bill payer
    ) -- end of the bill payer case
  ) -- end of the list
$$; -- end of the function

-- ---------------------------------------------------------------------------
-- Does the signed-in person pay for any family?
-- ---------------------------------------------------------------------------

-- Used by the dashboard menu: a student only gets a Billing tab when this
-- says yes: they pay for a family, or pay a split share of its invoices.
-- Gives back no for anyone not signed in.
create or replace function public.billing_i_pay() -- no inputs: it's about the signed-in person
returns boolean language sql stable security definer -- gives back yes or no; reads tables people can't read directly
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- any family
    select 1 from public.families f -- of all families
    where private.is_family_payer(f.id) -- that this person pays for
  ) -- end of the first case
  or exists ( -- or a split share
    select 1 from public.billing_payers p -- of a family's invoices
    where p.account_id = auth.uid() -- paid by this person
  ) -- end of the second case
$$; -- end of the function
revoke all on function public.billing_i_pay() from public, anon; -- not for everyone, and never for people who aren't signed in
grant execute on function public.billing_i_pay() to authenticated; -- signed-in people can ask about themselves
