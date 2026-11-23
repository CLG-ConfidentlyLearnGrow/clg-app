-- Summary: checks the Student Success Program (Carla, 22 Nov 2026): a
-- family asks about it, only owner and Operations admins approve a place,
-- places are limited, approving makes the program invoices (a $500 deposit,
-- then the rest in full, monthly or weekly with plan fees), the deposit
-- secures the place, the program switches on only once everything is paid,
-- unpaid program invoices never put sessions on hold, the hourly job sends
-- the 48 hour deposit reminder, the 24 hour payment reminder and the missed
-- payment warnings, and forfeits places (unless a payment agreement is
-- running), and places can be declined, withdrawn, released or ended.
-- Program students get a study plan, included term reviews and first place
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
update public.billing_price_items set amount_cents = 1000, active = true where code = 'plan_fee_monthly'; -- the monthly plan fee is $10 (in case another test changed it)
update public.billing_price_items set amount_cents = 500, active = true where code = 'plan_fee_weekly'; -- the weekly plan fee is $5
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
select tests.eq((select count(*) from public.ssp_invoices), 0::bigint, 'the family cannot read the program invoice list directly'); -- admins only
select tests.fails($$insert into public.ssp_enrolments (student_id) select id from public.students limit 1$$, 'nobody writes the program list directly'); -- refused
select tests.fails_with(format($$select public.ssp_approve(%L, 200000, 'monthly', %L)$$, :'cara', :'today'::date + 100), 'Only CLG', 'a parent cannot approve a place'); -- refused
select tests.eq((select count(*) from public.ssp_places()), 0::bigint, 'a parent cannot see the place numbers'); -- nothing
select tests.fails($$select public.ssp_run_deadlines()$$, 'a parent cannot run the hourly job'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000002', 'aal2'); -- parent P2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.ssp_family_status(:'cara')), 0::bigint, 'another family sees nothing'); -- not visible
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- Places are limited, and approving makes the program invoices
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- the Operations admin
set role authenticated; -- as a signed-in person
select public.ssp_set_places(1, 7); -- one place, forfeit 7 days after a missed payment
select tests.eq((select waiting from public.ssp_places()), 1, 'the admin sees one request waiting'); -- waiting count
select tests.fails_with(format($$select public.ssp_approve(%L, 200000, 'monthly', %L, 500)$$, :'cara', :'today'::date + 100), 'between 1 and 200', 'an odd number of sessions is refused'); -- refused
select tests.fails_with(format($$select public.ssp_approve(%L, 200000, 'yearly', %L)$$, :'cara', :'today'::date + 100), 'choose a payment plan', 'an unknown plan is refused'); -- refused
select tests.fails_with(format($$select public.ssp_approve(%L, 40000, 'full', %L)$$, :'cara', :'today'::date + 100), 'at least the deposit', 'a total below the deposit is refused'); -- refused
select tests.fails_with(format($$select public.ssp_approve(%L, 200000, 'monthly', %L)$$, :'cara', :'today'::date + 10), 'too soon', 'a finish date under a month away is refused for a monthly plan'); -- refused
select tests.fails_with(format($$select public.ssp_approve(%L, 200000, 'full', %L)$$, :'cara', :'today'::date - 1), 'today or later', 'a finish date in the past is refused'); -- refused
-- $2,000 total, monthly, finishing 3 months and 2 days from now: the $500 deposit, then 3 monthly payments of $500 plus the $10 fee.
select public.ssp_approve(:'cara', 200000, 'monthly', ((:'today'::date + interval '3 months')::date + 2), 30, :'today'::date + 200, 'Spoke to mum') as summary \gset
select tests.eq((strpos(:'summary', '3 monthly payments of about $500.00 plus a $10.00 plan fee each') > 0 and strpos(:'summary', 'Total $2,030.00') > 0)::int::bigint, 1::bigint, 'the admin gets a plain summary of the payments'); -- the summary
select tests.eq((((select status from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'approved')::int::bigint, 1::bigint, 'the place is approved and held'); -- held
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'cara' and deposit_deadline between now() + interval '71 hours' and now() + interval '73 hours'), 1::bigint, 'the deposit is due within 72 hours'); -- the deadline
select tests.eq((((select format('%s/%s/%s', used, places_left, waiting) from public.ssp_places())) is not distinct from '1/0/0')::int::bigint, 1::bigint, 'one place used, none left, none waiting'); -- the numbers
select tests.fails_with(format($$select public.ssp_approve(%L, 50000, 'full', %L)$$, :'other', :'today'::date), 'All 1 places', 'no place is given when all are taken'); -- full
select tests.fails_with(format($$select public.ssp_approve(%L, 50000, 'full', %L)$$, :'cara', :'today'::date), 'already has a place', 'a place cannot be approved twice'); -- twice
reset role; -- back to the database itself
select deposit_invoice_id as inv from public.ssp_enrolments where student_id = :'cara' \gset
select tests.eq((((select format('%s/%s/%s/%s/%s', kind, status, total_cents, gst_cents, charge_on - :'today'::date) from public.billing_invoices where id = :'inv')) is not distinct from 'deposit/open/50000/0/0')::int::bigint, 1::bigint, 'a $500 GST-free deposit invoice is ready to pay and charged today'); -- the deposit
select tests.eq((select count(*) from public.ssp_invoices where invoice_id = :'inv' and student_id = :'cara' and payment_no = 1), 1::bigint, 'the deposit is payment 1'); -- listed
select tests.eq((select count(*) from public.billing_invoice_lines where invoice_id = :'inv' and student_id = :'cara' and description like 'Student Success Program for Cara: deposit (payment 1 of 4)%'), 1::bigint, 'the deposit line says it is payment 1 of 4'); -- the line
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'cara' and i.kind = 'program' and i.status = 'open' and i.total_cents = 51000), 3::bigint, 'three monthly payments of $510 (with the plan fee)'); -- the instalments
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoice_lines l on l.invoice_id = si.invoice_id join public.billing_price_items p on p.id = l.price_item_id where si.student_id = :'cara' and p.code = 'plan_fee_monthly' and l.amount_cents = 1000), 3::bigint, 'each monthly payment has a $10 plan fee line'); -- the fees
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'cara' and si.payment_no = 4 and i.due_on = (:'today'::date + interval '3 months')::date), 1::bigint, 'the last payment is due 3 months from today'); -- the last date
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'ssp_update' and account_id = '00000000-0000-0000-0000-000000000001' and body like '%or the place will be forfeited%'), 1::bigint, 'the family is told a place is offered and the deposit deadline'); -- the notice
select tests.eq((not private.ssp_member(:'cara'))::int::bigint, 1::bigint, 'Cara is not in the program until everything is paid'); -- not yet

-- Unpaid program invoices never put sessions on hold, and do not count as session invoices.
update public.billing_invoices set due_on = :'today'::date - 5 where id in (select invoice_id from public.ssp_invoices where student_id = :'cara'); -- pretends every payment is overdue (put back below)
select tests.eq((private.billing_should_pause(:'fam', :'today'::date + 30) = :'pause_before'::boolean)::int::bigint, 1::bigint, 'overdue program payments do not pause the family'); -- no hold
select tests.eq((private.billing_has_invoice(:'fam') = :'has_before'::boolean)::int::bigint, 1::bigint, 'program invoices do not lock the payment plan'); -- plan unaffected
update public.billing_invoices i set due_on = l.line_date from public.billing_invoice_lines l where l.invoice_id = i.id and i.id in (select invoice_id from public.ssp_invoices where student_id = :'cara'); -- puts the due dates back (each line carries its due day)

-- The family sees it; only the payer sees the money.
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- parent P1 (the payer)
set role authenticated; -- as a signed-in person
select tests.eq((((select format('%s/%s/%s/%s/%s', status, is_payer, plan, total_cents, paid_cents) from public.ssp_family_status(:'cara'))) is not distinct from 'approved/t/monthly/203000/0')::int::bigint, 1::bigint, 'the payer sees the plan, total and nothing paid yet'); -- waiting for payment
select tests.fails_with(format($$select public.ssp_cancel_request(%L)$$, :'cara'), 'contact CLG', 'the family cannot cancel once a place is offered'); -- refused
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- The hourly job: the 48 hour deposit reminder
-- ---------------------------------------------------------------------------
select tests.claims(null); -- acts as the server (as the scheduled job does)
select public.ssp_run_deadlines() as ran \gset
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and title like 'Reminder: Student Success Program deposit%'), 0::bigint, 'no reminder before 48 hours'); -- too early
update public.ssp_enrolments set decided_at = now() - interval '49 hours' where student_id = :'cara'; -- pretends the place was offered 49 hours ago
select public.ssp_run_deadlines() as ran \gset
select public.ssp_run_deadlines() as ran \gset
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and title like 'Reminder: Student Success Program deposit%' and account_id = '00000000-0000-0000-0000-000000000001'), 1::bigint, 'the payer is reminded once at 48 hours'); -- reminded once

-- ---------------------------------------------------------------------------
-- The deposit is paid: the place is secured, but the program is not on yet
-- ---------------------------------------------------------------------------
select public.billing_record_payer_payment(:'inv', null, 'stripe', 'pi_ssp_test', 'card', 50000, 'succeeded'); -- the deposit is paid
select tests.eq((((select format('%s/%s', status, (deposit_paid_on = :'today'::date)::int) from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'secured/1')::int::bigint, 1::bigint, 'paying the deposit secures the place'); -- secured
select tests.eq((not private.ssp_member(:'cara'))::int::bigint, 1::bigint, 'Cara is still not in the program (more to pay)'); -- not yet
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and note = 'Student Success Program' and ends_on is null), 0::bigint, 'the study plan is not given yet'); -- not yet
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'ssp_update' and title like 'Student Success Program place secured%'), 1::bigint, 'the family is told the place is secured'); -- the notice
update public.ssp_enrolments set deposit_deadline = now() - interval '1 minute' where student_id = :'cara'; -- the deposit deadline passes
select public.ssp_run_deadlines() as ran \gset
select tests.eq((((select status from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'secured')::int::bigint, 1::bigint, 'a paid deposit is never forfeited at the deadline'); -- still secured

-- ---------------------------------------------------------------------------
-- The 24 hour reminder, a missed payment, and a payment agreement
-- ---------------------------------------------------------------------------
select invoice_id as p2 from public.ssp_invoices where student_id = :'cara' and payment_no = 2 \gset
update public.billing_invoices set charge_on = :'today'::date + 1, due_on = :'today'::date + 1 where id = :'p2'; -- payment 2 is taken tomorrow
select public.ssp_run_deadlines() as ran \gset
select public.ssp_run_deadlines() as ran \gset
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and title like 'Student Success Program payment tomorrow%' and body like '%$510.00%'), 1::bigint, 'the payer is reminded once, 24 hours before a payment'); -- reminded once
update public.billing_invoices set charge_on = :'today'::date - 1, due_on = :'today'::date - 1 where id = :'p2'; -- payment 2 was missed yesterday
select public.ssp_run_deadlines() as ran \gset
select public.ssp_run_deadlines() as ran \gset
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and title like 'Student Success Program payment missed%' and body like '%payment plan%'), 1::bigint, 'the payer is warned once about the missed payment'); -- warned once
update public.billing_invoices set due_on = :'today'::date - 5 where id = :'p2'; -- now 5 days late (2 days before forfeiting)
select public.ssp_run_deadlines() as ran \gset
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and title like 'Final reminder: Student Success Program payment%'), 1::bigint, 'a final warning is sent 2 days before the place is forfeited'); -- final warning
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_set_agreement(:'cara', :'today'::date + 3, 'Paying on Friday'); -- records a payment agreement
reset role; -- back to the database itself
select tests.claims(null); -- as the server
update public.billing_invoices set due_on = :'today'::date - 8 where id = :'p2'; -- now 8 days late
select public.ssp_run_deadlines() as ran \gset
select tests.eq((((select status from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'secured')::int::bigint, 1::bigint, 'a payment agreement stops the place being forfeited'); -- kept

-- ---------------------------------------------------------------------------
-- Everything is paid: Cara is in the program
-- ---------------------------------------------------------------------------
do $$ -- pays the rest of Cara's program invoices (as Stripe's messages do)
declare r record; -- each invoice
begin -- start
  for r in select i.id, i.total_cents, si.payment_no from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id join public.students s on s.id = si.student_id where s.full_name = 'Cara One' and i.status = 'open' order by si.payment_no loop -- each unpaid one
    perform public.billing_record_payer_payment(r.id, null, 'stripe', 'pi_ssp_test_' || r.payment_no, 'card', r.total_cents, 'succeeded'); -- pays it
  end loop; -- end of the list
end; -- finish
$$;
select tests.eq((((select status from public.ssp_enrolments where student_id = :'cara')) is not distinct from 'enrolled')::int::bigint, 1::bigint, 'paying everything puts Cara in the program'); -- in
select tests.eq(private.ssp_member(:'cara')::int::bigint, 1::bigint, 'Cara counts as a program student'); -- in
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and ends_on is null and note = 'Student Success Program'), 1::bigint, 'the study plan add-on is given'); -- study plans
select tests.eq((select count(*) from public.progress_notices where student_id = :'cara' and kind = 'ssp_update' and title like '%is in the Student Success Program'), 1::bigint, 'the family is told everything is paid'); -- the notice

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
select tests.fails_with(format($$select public.ssp_approve(%L, 50000, 'full', %L)$$, :'other', :'today'::date), 'not set up billing', 'no program invoice is made for a family without billing set up'); -- refused, nothing changed
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
-- A $500 total paid in full: only the deposit.
select public.ssp_approve(:'other', 50000, 'full', :'today'::date + 30) as summary \gset
select tests.eq((strpos(:'summary', 'nothing more to pay') > 0)::int::bigint, 1::bigint, 'a total equal to the deposit makes only the deposit invoice'); -- the summary
select tests.fails_with(format($$select public.ssp_withdraw(%L, 'no')$$, :'other'), 'give a reason', 'withdrawing needs a reason'); -- reason
select public.ssp_withdraw(:'other', 'The family changed their mind.'); -- the place is withdrawn
select tests.eq((((select status from public.ssp_enrolments where student_id = :'other')) is not distinct from 'withdrawn')::int::bigint, 1::bigint, 'the place is withdrawn'); -- withdrawn
reset role; -- back to the database itself
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'other' and i.status <> 'void'), 0::bigint, 'its invoices are cancelled'); -- cancelled
-- Weekly, finishing 3 weeks away: a cancelled deposit releases the place and cancels the rest.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_approve(:'other', 65000, 'weekly', :'today'::date + 21) as summary \gset
select tests.eq((strpos(:'summary', '3 weekly payments of about $50.00 plus a $5.00 plan fee each') > 0)::int::bigint, 1::bigint, 'a weekly plan makes one payment per week with the $5 fee'); -- the summary
select deposit_invoice_id as inv3 from public.ssp_enrolments where student_id = :'other' \gset
select public.billing_void_invoice(:'inv3', 'Cancelled in Xero'); -- the deposit invoice is cancelled in billing (as when cancelled in Xero)
select tests.eq((((select format('%s/%s', status, (deposit_invoice_id is null)::int) from public.ssp_enrolments where student_id = :'other')) is not distinct from 'requested/1')::int::bigint, 1::bigint, 'a cancelled deposit invoice releases the place back to a request'); -- released
reset role; -- back to the database itself
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'other' and i.status <> 'void'), 0::bigint, 'the rest of the program invoices are cancelled too'); -- cancelled

-- ---------------------------------------------------------------------------
-- Forfeiting: the deposit not paid in time, and a missed payment
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_approve(:'other', 100000, 'full', :'today'::date + 30) as summary \gset
reset role; -- back to the database itself
select tests.claims(null); -- as the server
update public.ssp_enrolments set deposit_deadline = now() - interval '1 minute' where student_id = :'other'; -- the 72 hours have passed
select public.ssp_run_deadlines() as ran \gset
select tests.eq((((select format('%s/%s', status, decline_reason like 'Place forfeited because the deposit%') from public.ssp_enrolments where student_id = :'other')) is not distinct from 'requested/t')::int::bigint, 1::bigint, 'an unpaid deposit forfeits the place at the deadline, and the family is back on the waiting list'); -- forfeited, waiting again
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'other' and i.status <> 'void'), 0::bigint, 'the forfeited place''s invoices are cancelled'); -- cancelled
select tests.eq((select count(*) from public.progress_notices where student_id = :'other' and title like 'Student Success Program place forfeited%' and body like '%back on the waiting list%' and account_id = '00000000-0000-0000-0000-000000000002'), 1::bigint, 'the family is told the place was forfeited and they are back on the waiting list'); -- the family
select tests.eq((select count(*) from public.session_notices where account_id = '00000000-0000-0000-0000-0000000000a0' and title = 'Student Success Program place open' and body like '%forfeited because the deposit%'), 1::bigint, 'the owner is told a place is open, for whom and why'); -- the admins
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_approve(:'other', 65000, 'weekly', :'today'::date + 21) as summary \gset
reset role; -- back to the database itself
select tests.claims(null); -- as the server
select deposit_invoice_id as inv4 from public.ssp_enrolments where student_id = :'other' \gset
select public.billing_record_payer_payment(:'inv4', null, 'stripe', 'pi_ssp_test_other', 'card', 50000, 'succeeded'); -- the deposit is paid
select si.invoice_id as p2b from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'other' and i.kind = 'program' and i.status = 'open' order by i.due_on limit 1 \gset
update public.billing_invoices set due_on = :'today'::date - 7, charge_on = :'today'::date - 7 where id = :'p2b'; -- the first weekly payment is 7 days late
select public.ssp_run_deadlines() as ran \gset
select tests.eq((((select status from public.ssp_enrolments where student_id = :'other')) is not distinct from 'requested')::int::bigint, 1::bigint, 'a payment 7 days late forfeits the place (back on the waiting list)'); -- forfeited
select tests.eq((((select status::text from public.billing_invoices where id = :'inv4')) is not distinct from 'paid')::int::bigint, 1::bigint, 'the paid deposit stays paid (any refund follows CLG''s terms)'); -- kept
select tests.eq((select count(*) from public.ssp_invoices si join public.billing_invoices i on i.id = si.invoice_id where si.student_id = :'other' and i.status = 'open'), 0::bigint, 'the unpaid weekly payments are cancelled'); -- cancelled

-- A weekly-paying family: sessions credited two weeks in a row (missed while
-- on hold for not paying) forfeit the place.
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_approve(:'other', 50000, 'full', :'today'::date + 30) as summary \gset
reset role; -- back to the database itself
select tests.claims(null); -- as the server
select deposit_invoice_id as inv5 from public.ssp_enrolments where student_id = :'other' \gset
select public.billing_record_payer_payment(:'inv5', null, 'stripe', 'pi_ssp_test_other5', 'card', 50000, 'succeeded'); -- the deposit (the whole total) is paid
select tests.eq((((select status from public.ssp_enrolments where student_id = :'other')) is not distinct from 'enrolled')::int::bigint, 1::bigint, 'a total equal to the deposit is fully paid by the deposit'); -- in
insert into public.sessions (id, student_id, tutor_id, subject, level_kind, delivery, starts_at, ends_at, status, cancelled_at) values -- two sessions a week apart, missed while on hold:
  ('00000000-0000-0000-0000-0000000f0201', :'other', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '14 days', now() - interval '14 days' + interval '1 hour', 'cancelled', now()), -- two weeks ago
  ('00000000-0000-0000-0000-0000000f0202', :'other', '00000000-0000-0000-0000-000000000011', 'General Maths', 'school', 'online', now() - interval '7 days', now() - interval '7 days' + interval '1 hour', 'cancelled', now()); -- last week
insert into public.billing_credits (family_id, kind, amount_cents, session_id, note) values (:'other_fam', 'missed_in_pause', 9500, '00000000-0000-0000-0000-0000000f0201', 'test'); -- the first is credited
select public.ssp_run_deadlines() as ran \gset
select tests.eq((((select status from public.ssp_enrolments where student_id = :'other')) is not distinct from 'enrolled')::int::bigint, 1::bigint, 'one credited week does not forfeit the place'); -- kept
insert into public.billing_credits (family_id, kind, amount_cents, session_id, note) values (:'other_fam', 'missed_in_pause', 9500, '00000000-0000-0000-0000-0000000f0202', 'test'); -- the next week is credited too
select public.ssp_run_deadlines() as ran \gset
select tests.eq((((select format('%s/%s', status, decline_reason like '%two weeks in a row%') from public.ssp_enrolments where student_id = :'other')) is not distinct from 'requested/t')::int::bigint, 1::bigint, 'two weeks in a row of credited sessions forfeits a weekly payer''s place'); -- forfeited
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'other' and note = 'Student Success Program' and ends_on is null), 0::bigint, 'the program''s study plan ends when the place is forfeited'); -- switched off

-- ---------------------------------------------------------------------------
-- Leaving the program
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_save_details(:'cara', 40, null, 'Extended'); -- the owner changes Cara's details
select tests.eq((select sessions_planned from public.ssp_enrolments where student_id = :'cara'), 40, 'the details of a place can be changed'); -- saved
select public.ssp_leave(:'cara'); -- Cara leaves the program
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'cara' and status = 'left' and ended_at is not null), 1::bigint, 'the owner takes Cara out of the program'); -- left
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and ends_on is not null), 1::bigint, 'the program''s study plan add-on ends'); -- ended
select tests.fails_with(format($$select public.ssp_leave(%L)$$, :'cara'), 'not in the Student Success Program', 'cannot take a student out twice'); -- refused
reset role; -- back to the database itself

\echo '  student success program: all checks passed'
rollback; -- throws away everything this test did
