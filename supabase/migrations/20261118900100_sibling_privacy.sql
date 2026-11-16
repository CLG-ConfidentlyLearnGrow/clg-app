-- Brothers and sisters keep their profiles private from each other
-- (Carla, 16 Nov 2026).
--
-- Carla's rule: when a parent has several children, each child's own
-- profile is private. A child with their own login must not see anything on
-- a sibling's profile, even though they share the parent and the family.
-- The parent still sees all their own children.
--
-- A check of every access rule found one gap. An adult learner (18 or over)
-- with their own login was treated as paying for their whole family. So an
-- adult sibling could see the family's invoices, which list every child's
-- sessions by name, the family's credits, and could accept the family terms
-- or choose the family's payment plan.
--
-- The fix: an adult learner pays for (and sees the billing of) their family
-- only when they are the only learner in it. In a family with brothers or
-- sisters, billing stays with the parents, or with whoever CLG names as the
-- bill payer on Admin > Billing (for example an older sibling who pays for
-- everyone, which is a deliberate choice by CLG). Every other access rule
-- already works per student, and the new test (sibling_privacy.test.sql)
-- checks every table and view to keep it that way.
--
-- Safe to run more than once.

-- Who may see and manage a family's billing as the signed-in person: a
-- parent of a child in the family, an adult learner who is the family's
-- only learner, or the person CLG named as the family's bill payer.
create or replace function private.is_family_payer(p_family uuid) -- takes the family
returns boolean language sql stable security definer -- yes or no; reads past the access rules to check
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select auth.uid() is not null and ( -- someone is signed in, and they are:
    exists ( -- a parent of a child in the family,
      select 1 from public.students s -- (a student
      join public.parent_student_links l on l.student_id = s.id -- linked to a parent
      where s.family_id = p_family and l.parent_id = auth.uid() -- in this family, where the parent is them)
    )
    or exists ( -- or an adult learner who is the family's only learner,
      select 1 from public.students s -- (their own student profile
      where s.family_id = p_family and s.account_id = auth.uid() -- in this family,
        and s.date_of_birth <= (current_date - interval '18 years')::date -- aged 18 or over,
        and not exists (select 1 from public.students o where o.family_id = p_family and o.id <> s.id) -- with no brothers or sisters in the family)
    )
    or exists ( -- or the person CLG named as the family's bill payer.
      select 1 from public.billing_accounts b -- (the family's billing account
      where b.family_id = p_family and b.bill_payer_id = auth.uid() -- names them)
    )
  ) -- (end of the choices)
$$; -- end of the function

-- Who CLG may add as a person sharing a family's payments (used when an
-- admin splits payments): a parent of a child in the family, or an adult
-- learner who is the family's only learner. In a family with brothers or
-- sisters, an adult sibling can still be named the main bill payer instead.
create or replace function private.can_pay_for_family(p_family uuid, p_account uuid) -- takes the family and the person
returns boolean language sql stable security definer -- yes or no; reads past the access rules to check
set search_path = '' -- only fully named tables, for safety
as $$ -- the check
  select exists ( -- a parent of a child in the family,
      select 1 from public.students s -- (a student
      join public.parent_student_links l on l.student_id = s.id -- linked to a parent
      where s.family_id = p_family and l.parent_id = p_account -- in this family, where the parent is this person)
    )
    or exists ( -- or an adult learner who is the family's only learner.
      select 1 from public.students s -- (their own student profile
      where s.family_id = p_family and s.account_id = p_account -- in this family,
        and s.date_of_birth <= (current_date - interval '18 years')::date -- aged 18 or over,
        and not exists (select 1 from public.students o where o.family_id = p_family and o.id <> s.id) -- with no brothers or sisters in the family)
    )
$$; -- end of the function
revoke execute on function private.can_pay_for_family(uuid, uuid) from public; -- only used by the billing functions
