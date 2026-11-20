-- Billing: Operations admins see money matters but do not change them
-- (Carla, 20 Nov 2026, for Emma's admin role).
--
-- Before: Operations admins (Lauren, and Emma from 2027) could build,
-- approve and cancel invoices, add credit, split payments between payers
-- and waive late cancellations.
-- Now: Operations admins still SEE prices, kept family rates, invoices,
-- credits, splits, waivers and staff pay, so they can talk with families
-- and tutors. Only the owner and Finance admins build, approve or cancel
-- invoices, add credit, change split payments, credit cancellations by
-- hand, or give a term review at no charge. Waiving a late cancellation is
-- the owner's alone (Finance does not see student sessions).
--
-- Unchanged for Operations: choosing a family's plan and bill payer
-- (helping families set up), school terms and holidays, and the automatic
-- daily billing run (the server still does it). Lifting a pause without
-- payment stays as the billing setting says (owner only unless Carla
-- switches it to admins).
--
-- Each function is edited in place (only who may use it), so anything else
-- changed in it later is kept. Safe to run more than once. If an older
-- billing file is ever run again, run this file again afterwards, because
-- older files put back their old rules.

-- Money changes: owner or Finance only (private.is_pay_admin means owner or finance).
select private.retarget_function('public.billing_add_credit', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- adding credit
select private.retarget_function('public.billing_approve_invoice', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- approving an invoice
select private.retarget_function('public.billing_void_invoice', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- cancelling an invoice
select private.retarget_function('public.billing_build_invoice', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- building an invoice by hand
select private.retarget_function('public.billing_build_due_invoices', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- running billing now by hand (the server's run is not affected)
select private.retarget_function('public.billing_credit_cancellations', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- crediting cancellations by hand (the server's run is not affected)
select private.retarget_function('public.billing_set_split', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- adding or changing a split payer
select private.retarget_function('public.billing_remove_split', 'private.is_finance_admin()', 'private.is_pay_admin()'); -- removing a split payer

-- Plainer refusals that say who can do it.
select private.retarget_function('public.billing_add_credit', '''Only admins can add credit''', '''Only the owner or a Finance admin can add credit'''); -- credit
select private.retarget_function('public.billing_approve_invoice', '''Only admins can approve invoices''', '''Only the owner or a Finance admin can approve invoices'''); -- approving
select private.retarget_function('public.billing_void_invoice', '''Only admins can cancel invoices''', '''Only the owner or a Finance admin can cancel invoices'''); -- cancelling
select private.retarget_function('public.billing_build_invoice', '''Only admins can build invoices''', '''Only the owner or a Finance admin can build invoices'''); -- building
select private.retarget_function('public.billing_set_split', '''Only admins can split payments''', '''Only the owner or a Finance admin can split payments'''); -- splitting
select private.retarget_function('public.billing_remove_split', '''Only admins can change split payments''', '''Only the owner or a Finance admin can change split payments'''); -- removing a split

-- A term review at no charge is a money decision: owner or Finance only.
-- (Operations admins can still record a family's yes or no.)
select private.retarget_function('public.answer_term_review_offer', -- the "no charge" check only:
  'if v_free and not private.is_finance_admin() then', -- old rule,
  'if v_free and not private.is_pay_admin() then'); -- new rule
select private.retarget_function('public.answer_term_review_offer', -- and its message:
  'Only CLG''''s owner, operations or finance admins can give a review at no charge', -- old words,
  'Only CLG''''s owner or a Finance admin can give a review at no charge'); -- new words

-- Waiving a late cancellation: the owner only.
select private.retarget_function('public.billing_waive_late_cancel', -- the check:
  'if not (private.is_admin() and private.has_aal2()) then', -- old rule (owner or Operations),
  'if not (private.is_owner() and private.has_aal2()) then'); -- new rule (owner)
select private.retarget_function('public.billing_waive_late_cancel', -- and its message:
  'Only Owner and Operations admins can waive a late cancellation', -- old words,
  'Only the owner can waive a late cancellation'); -- new words
