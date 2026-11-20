-- Summary: Operations admins see billing but do not change money matters
-- (Carla, 20 Nov 2026). Runs after staff_levels.test.sql, which adds (then
-- removes) the Finance admin Bo Books (...7c2); this file gives Bo the Finance
-- level again inside its own transaction. Reuses the owner (...a0) and the
-- Operations admin (...b0). Checks, in the database itself:
--   * Operations cannot add credit, build, approve or cancel invoices,
--     change split payments, or waive a late cancellation;
--   * Operations can still read prices, invoices and credit;
--   * Finance and the owner can still add credit.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the change again (and twice), to check it is safe to run more than once.
\ir ../migrations/20261123400300_operations_billing_view_only.sql
\ir ../migrations/20261123400300_operations_billing_view_only.sql

-- Keeps any family, and any invoice and session, to try things on.
select id as fam from public.families order by created_at limit 1 \gset
-- Any invoice id (or a made-up one: the refusal comes before the invoice is looked up).
select coalesce((select id from public.billing_invoices limit 1), gen_random_uuid()) as inv \gset
-- Any session id (or a made-up one: the refusal comes first).
select coalesce((select id from public.sessions limit 1), gen_random_uuid()) as ses \gset

-- As the Operations admin, with two-step sign-in.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- signs in as the Operations admin
set local role authenticated; -- acts as a signed-in user, so the access rules apply
select tests.fails_with(format($$select public.billing_add_credit(%L, 500, 'test')$$, :'fam'), 'owner or a Finance admin', 'operations cannot add credit'); -- adding credit is refused
select tests.fails_with(format($$select public.billing_build_invoice(%L, current_date, current_date + 7)$$, :'fam'), 'owner or a Finance admin', 'operations cannot build an invoice'); -- building an invoice is refused
select tests.fails_with(format($$select public.billing_approve_invoice(%L)$$, :'inv'), 'owner or a Finance admin', 'operations cannot approve an invoice'); -- approving is refused
select tests.fails_with(format($$select public.billing_void_invoice(%L, 'test')$$, :'inv'), 'owner or a Finance admin', 'operations cannot cancel an invoice'); -- cancelling is refused
select tests.fails_with(format($$select public.billing_set_split(%L, '00000000-0000-0000-0000-000000000001', 50)$$, :'fam'), 'owner or a Finance admin', 'operations cannot split payments'); -- splitting is refused
select tests.fails_with(format($$select public.billing_remove_split(%L, '00000000-0000-0000-0000-000000000001')$$, :'fam'), 'owner or a Finance admin', 'operations cannot remove a split'); -- removing a split is refused
select tests.fails_with(format($$select public.billing_waive_late_cancel(%L, 'test', false)$$, :'ses'), 'Only the owner can waive', 'operations cannot waive a late cancellation'); -- waiving is refused
select tests.fails($$select public.billing_build_due_invoices(current_date)$$, 'operations cannot run billing by hand'); -- running billing by hand is refused
-- Operations can still read prices and invoices (the same rows the owner sees).
select (select count(*) from public.billing_price_items) as ops_prices, (select count(*) from public.billing_invoices) as ops_invoices \gset
reset role; -- back to the test user (access rules off)
select tests.eq(:ops_prices, (select count(*) from public.billing_price_items), 'operations still sees every price'); -- checks prices are visible
select tests.eq(:ops_invoices, (select count(*) from public.billing_invoices), 'operations still sees every invoice'); -- checks invoices are visible

-- As the Finance admin: adding credit still works.
-- staff_levels.test.sql removes Bo's admin role at its end, so gives it back here (undone at the end).
insert into public.account_roles (account_id, role) values ('00000000-0000-0000-0000-0000000007c2', 'admin') on conflict do nothing; -- Bo is an admin again,
insert into public.admin_profiles (account_id, level) values ('00000000-0000-0000-0000-0000000007c2', 'finance') on conflict (account_id) do update set level = 'finance'; -- at Finance level.
select tests.claims('00000000-0000-0000-0000-0000000007c2', 'aal2'); -- signs in as the Finance admin
set local role authenticated; -- acts as a signed-in user
select public.billing_add_credit(:'fam', 500, 'test credit from Finance'); -- adds credit (fails the test if refused)
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_credits where family_id = :'fam' and note = 'test credit from Finance'), 1::bigint, 'finance can still add credit'); -- checks it was saved

-- As the owner: adding credit still works.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- signs in as the owner
set local role authenticated; -- acts as a signed-in user
select public.billing_add_credit(:'fam', 500, 'test credit from the owner'); -- adds credit (fails the test if refused)
reset role; -- back to the test user
select tests.eq((select count(*) from public.billing_credits where family_id = :'fam' and note = 'test credit from the owner'), 1::bigint, 'owner can still add credit'); -- checks it was saved

-- Undoes everything above.
rollback;
-- Says the test passed.
\echo '  operations billing view only: all checks passed'
