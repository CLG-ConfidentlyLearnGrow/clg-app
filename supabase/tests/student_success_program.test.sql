-- Summary: checks the Student Success Program (Carla, 22 Nov 2026): a
-- family asks about it, only owner and Operations admins approve a place,
-- places are limited, approving makes a $500 deposit invoice, the student
-- is in the program only once the deposit is paid, an unpaid deposit never
-- puts sessions on hold, places can be declined, withdrawn or released, and
-- program students get a study plan, included term reviews and first place
-- in Matching. Reuses the shared people: owner ...a0, Operations ...b0,
-- tutor T1 ...11 (teaches Cara One), parent P1 ...01 (Cara's parent),
-- parent P2 ...02 (another family). Everything is rolled back at the end.

begin; -- starts a transaction, so nothing here is kept
-- Runs the change again (checks it can run twice, and puts back the term review
-- change that an earlier test removed by re-running the paid term reviews file).
\ir ../migrations/20261124710900_student_success_program.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
select id as other, family_id as other_fam from public.students where family_id is not null and family_id <> :'fam' order by created_at limit 1 \gset
select (now() at time zone 'Australia/Adelaide')::date as today \gset
delete from public.ssp_enrolments; -- starts with an empty program list (rolled back at the end)
insert into public.billing_accounts (family_id, bill_payer_id, plan) values (:'fam', '00000000-0000-0000-0000-000000000001', 'weekly') on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id; -- Cara's family has billing set up, with P1 paying
update public.billing_accounts set paused = false where family_id = :'fam'; -- not on hold
delete from public.billing_accounts where family_id = :'other_fam'; -- the other family has not set up billing yet (rolled back at the end)
select private.billing_should_pause(:'fam', :'today'::date + 30) as pause_before, private.billing_has_invoice(:'fam') as has_before \gset

-- ---------------------------------------------------------------------------
-- The family asks
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- tutor T1
set role authenticated; -- as a signed-in person
select tests.fails_with(format($$select public.ssp_request(%L)$$, :'cara'), 'parent or guardian', 'a tutor cannot ask for a student'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000002', 'aal2'); -- parent P2 (another family)
set role authenticated; -- as a signed-in person
select tests.fails_with(format($$select public.ssp_request(%L)$$, :'cara'), 'parent or guardian', 'another family cannot ask for Cara'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- parent P1
set role authenticated; -- as a signed-in person
select public.ssp_request(:'cara', 'Cara would like help all year'); -- P1 ticks the box
select tests.eq((((select status from public.ssp_family_status(:'cara'))) is not distinct from 'requested')::int::bigint, 1::bigint, 'the family sees the request is waiting'); -- waiting
select tests.eq((select can_ask::int::bigint from public.ssp_family_status(:'cara')), 1::bigint, 'the parent can ask and cancel'); -- allowed
select tests.eq((select count(*) from public.ssp_enrolments), 0::bigint, 'the family cannot read the program list directly'); -- only through the status function
select tests.fails($$insert into public.ssp_enrolments (student_id) select id from public.students limit 1$$, 'nobody writes the program list directly'); -- refused
select tests.fails_with(format($$select public.ssp_approve(%L)$$, :'cara'), 'Only CLG', 'a parent cannot approve a place'); -- refused
select tests.eq((select count(*) from public.ssp_places()), 0::bigint, 'a parent cannot see the place numbers'); -- nothing
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000002', 'aal2'); -- parent P2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.ssp_family_status(:'cara')), 0::bigint, 'another family sees nothing'); -- not visible
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- Places are limited, and approving sends the deposit invoice
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- the Operations admin
set role authenticated; -- as a signed-in person
select public.ssp_set_places(1, 7); -- one place, seven days to pay
select tests.eq((select waiting from public.ssp_places()), 1, 'the admin sees one request waiting'); -- waiting count
select tests.fails_with(format($$select public.ssp_approve(%L, 500)$$, :'cara'), 'between 1 and 200', 'an odd number of sessions is refused'); -- refused
select public.ssp_approve(:'cara', 30, :'today'::date + 200, 'Spoke to mum') as inv \gset
select tests.eq((((select status from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'approved')::int::bigint, 1::bigint, 'the place is approved and held'); -- held
select tests.eq((((select format('%s/%s/%s', used, places_left, waiting) from public.ssp_places())) is not distinct from '1/0/0')::int::bigint, 1::bigint, 'one place used, none left, none waiting'); -- the numbers
select tests.fails_with(format($$select public.ssp_approve(%L)$$, :'other'), 'All 1 places', 'no place is given when all are taken'); -- full
select tests.fails_with(format($$select public.ssp_approve(%L)$$, :'cara'), 'already has a place', 'a place cannot be approved twice'); -- twice
reset role; -- back to the database itself
select tests.eq((((select format('%s/%s/%s/%s/%s', kind, status, total_cents, gst_cents, due_on - :'today'::date) from public.billing_invoices where id = :'inv')) is not distinct from 'deposit/open/50000/0/7')::int::bigint, 1::bigint, 'a $500 GST-free deposit invoice is ready to pay, due in 7 days'); -- the invoice
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and student_id = :'cara' and description like 'Student Success Program deposit for Cara%'), 1::bigint, 'the invoice has one line for Cara''s deposit'); -- the line
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'ssp_update' and account_id = '00000000-0000-0000-0000-000000000001' and body like '%$500.00 deposit%'), 1::bigint, 'the family is told a place is offered and the deposit amount'); -- the notice
select tests.eq((not private.ssp_member(:'cara'))::int::bigint, 1::bigint, 'Cara is not in the program until the deposit is paid'); -- not yet

-- An unpaid deposit never puts sessions on hold, and does not count as a session invoice.
update public.billing_invoices set due_on = :'today'::date - 5 where id = :'inv'; -- pretends the deposit is overdue (rolled back at the end)
select tests.eq((private.billing_should_pause(:'fam', :'today'::date + 30) = :'pause_before'::boolean)::int::bigint, 1::bigint, 'an overdue deposit does not pause the family'); -- no hold
select tests.eq((private.billing_has_invoice(:'fam') = :'has_before'::boolean)::int::bigint, 1::bigint, 'a deposit invoice does not lock the payment plan'); -- plan unaffected

-- The family sees it; only the payer sees the due date.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- parent P1 (the payer)
set role authenticated; -- as a signed-in person
select tests.eq((((select format('%s/%s', status, is_payer) from public.ssp_family_status(:'cara'))) is not distinct from 'approved/t')::int::bigint, 1::bigint, 'the payer sees the place is waiting for the deposit'); -- waiting for payment
select tests.fails_with(format($$select public.ssp_cancel_request(%L)$$, :'cara'), 'contact CLG', 'the family cannot cancel once a place is offered'); -- refused
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- The deposit is paid: Cara is in the program
-- ---------------------------------------------------------------------------
select tests.claims(null); -- acts as the server (as Stripe's message does)
select public.billing_record_payer_payment(:'inv', null, 'stripe', 'pi_ssp_test', 'card', 50000, 'succeeded'); -- the deposit is paid
select tests.eq((((select format('%s/%s', status, (deposit_paid_on = :'today'::date)::int) from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'enrolled/1')::int::bigint, 1::bigint, 'paying the deposit puts Cara in the program'); -- in
select tests.eq(private.ssp_member(:'cara')::int::bigint, 1::bigint, 'Cara counts as a program student'); -- in
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and ends_on is null and note = 'Student Success Program'), 1::bigint, 'the study plan add-on is given'); -- study plans
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'ssp_update' and title like '%is in the Student Success Program'), 1::bigint, 'the family is told the deposit was received'); -- the notice

-- ---------------------------------------------------------------------------
-- Matching puts program students first
-- ---------------------------------------------------------------------------
select tests.eq((strpos(pg_get_functiondef('public.matching_queue(text, text, text, text, integer, integer)'::regprocedure), 'order by private.ssp_member(r.student_id) desc') > 0)::int::bigint, 1::bigint, 'the Matching queue lists program students first'); -- the order
select tests.eq((strpos(pg_get_functiondef('public.matching_tutor_fill(uuid)'::regprocedure), 'order by private.ssp_member(m.student_id) desc') > 0)::int::bigint, 1::bigint, '"Fill a tutor''s times" lists program students first'); -- the order

-- ---------------------------------------------------------------------------
-- Term reviews are included (accepted at no charge)
-- ---------------------------------------------------------------------------
delete from public.availability_checks where term_id in (select id from public.school_terms where state = 'SA'); -- clears checks that point at SA terms (rolled back at the end)
delete from public.school_terms where state = 'SA'; -- clears the SA terms, so the test controls them
update public.sessions set status = 'cancelled', cancelled_at = now() where student_id = :'cara' and status = 'scheduled' and starts_at > now(); -- sets Cara's future sessions aside
insert into public.school_terms (state, year, term, starts_on, ends_on) values ('SA', extract(year from :'today'::date - 40)::int, 4, :'today'::date - 40, :'today'::date + 20); -- a term ending in 20 days
insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status) values -- a booked session reaching the end of term:
  ('00000000-0000-0000-0000-0000000f0101', :'cara', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() + interval '25 days', now() + interval '25 days 1 hour', 'scheduled');
delete from public.term_review_offers where student_id = :'cara'; -- no earlier offers
update public.billing_price_items set amount_cents = 4000, active = true where code = 'term_review'; -- the review price is in use
select tests.eq(private.queue_term_reviews()::bigint, 1::bigint, 'one review made for the program student'); -- one offer
select tests.eq((select count(*) from public.term_review_offers where student_id = :'cara' and answer = 'yes' and no_charge and invoice_id is null), 1::bigint, 'accepted at no charge, with no invoice'); -- included
select tests.eq((select count(*) from public.term_reviews r join public.term_review_offers o on o.id = r.offer_id where o.student_id = :'cara'), 1::bigint, 'the tutor''s draft is made'); -- the draft
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'review_booked' and account_id = '00000000-0000-0000-0000-000000000001'
  and body like '%included in the Student Success Program%'), 1::bigint, 'the family is told it is included'); -- the notice
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'review_offer'), 0::bigint, 'no price offer is sent'); -- no offer with a price

-- ---------------------------------------------------------------------------
-- Declining, withdrawing and releasing places (the other student)
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_set_places(5, 7); -- more places
select tests.fails_with(format($$select public.ssp_approve(%L)$$, :'other'), 'not set up billing', 'no deposit invoice is made for a family without billing set up'); -- refused, nothing changed
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'other'), 0::bigint, 'the refused approval leaves nothing behind'); -- rolled back
reset role; -- back to the database itself
select tests.claims(null); -- as the database itself
insert into public.billing_accounts (family_id, bill_payer_id, plan) values (:'other_fam', '00000000-0000-0000-0000-000000000002', 'weekly') on conflict (family_id) do update set bill_payer_id = excluded.bill_payer_id; -- the other family sets up billing
insert into public.ssp_enrolments (student_id, status, requested_at) values (:'other', 'requested', now()); -- the other family asks (written directly to keep the test short)
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_decline(:'other', 'All places for this term are planned.'); -- declined
select tests.eq((((select status from public.ssp_enrolments where student_id = :'other')) is not distinct from 'declined')::int::bigint, 1::bigint, 'the owner declines a request'); -- declined
select tests.fails_with(format($$select public.ssp_decline(%L)$$, :'other'), 'no request waiting', 'cannot decline twice'); -- twice
select public.ssp_approve(:'other') as inv2 \gset
select tests.fails_with(format($$select public.ssp_withdraw(%L, 'no')$$, :'other'), 'give a reason', 'withdrawing needs a reason'); -- reason
select public.ssp_withdraw(:'other', 'The family changed their mind.'); -- the place is withdrawn
select tests.eq((((select status from public.ssp_enrolments where student_id = :'other')) is not distinct from 'withdrawn')::int::bigint, 1::bigint, 'the place is withdrawn'); -- withdrawn
reset role; -- back to the database itself
select tests.eq((((select status::text from public.billing_invoices where id = :'inv2')) is not distinct from 'void')::int::bigint, 1::bigint, 'its deposit invoice is cancelled'); -- cancelled
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_approve(:'other') as inv3 \gset
select public.billing_void_invoice(:'inv3', 'Cancelled in Xero'); -- the deposit invoice is cancelled in billing (as when cancelled in Xero)
select tests.eq((((select format('%s/%s', status, (deposit_invoice_id is null)::int) from public.ssp_enrolments where student_id = :'other')) is not distinct from 'requested/1')::int::bigint, 1::bigint, 'a cancelled deposit invoice releases the place back to a request'); -- released

-- ---------------------------------------------------------------------------
-- Leaving the program
-- ---------------------------------------------------------------------------
select public.ssp_save_details(:'cara', 40, null, 'Extended'); -- the owner changes Cara's details
select tests.eq((select sessions_planned from public.ssp_enrolments where student_id = :'cara'), 40, 'the details of a place can be changed'); -- saved
select public.ssp_leave(:'cara'); -- Cara leaves the program
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'cara' and status = 'left' and ended_at is not null), 1::bigint, 'the owner takes Cara out of the program'); -- left
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and ends_on is not null), 1::bigint, 'the program''s study plan add-on ends'); -- ended
select tests.fails_with(format($$select public.ssp_leave(%L)$$, :'cara'), 'not in the Student Success Program', 'cannot take a student out twice'); -- refused
reset role; -- back to the database itself

\echo '  student success program: all checks passed'
rollback; -- throws away everything this test did
