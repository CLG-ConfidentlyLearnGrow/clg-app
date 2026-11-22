-- Summary: checks the Student Success Program tick box (Carla, 22 Nov
-- 2026): only owner and Operations admins tick or untick it, the family and
-- tutor can see it, it gives the study plan add-on, term review offers are
-- accepted at no charge with the tutor's draft made, and Matching puts
-- program students first. Reuses the shared people: owner ...a0, Operations
-- ...b0, tutor T1 ...11 (teaches Cara One), parent P1 ...01 (Cara's parent).
-- Everything is rolled back at the end.

begin; -- starts a transaction, so nothing here is kept
-- Runs the change again (checks it can run twice, and puts back the term review
-- change that an earlier test removed by re-running the paid term reviews file).
\ir ../migrations/20261124710900_student_success_program.sql

select tests.claims(null); -- acts as the database itself while setting up
select id as cara, family_id as fam from public.students where full_name = 'Cara One' \gset
select (now() at time zone 'Australia/Adelaide')::date as today \gset

-- ---------------------------------------------------------------------------
-- Who can tick the box
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- tutor T1
set role authenticated; -- as a signed-in person
select tests.fails_with(format($$select public.ssp_enrol(%L, 20)$$, :'cara'), 'Only CLG', 'a tutor cannot tick the box'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- parent P1
set role authenticated; -- as a signed-in person
select tests.fails_with(format($$select public.ssp_enrol(%L, 20)$$, :'cara'), 'Only CLG', 'a parent cannot tick the box'); -- refused
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- the Operations admin
set role authenticated; -- as a signed-in person
select tests.fails_with(format($$select public.ssp_enrol(%L, 500)$$, :'cara'), 'between 1 and 200', 'an odd number of sessions is refused'); -- refused
select public.ssp_enrol(:'cara', 30, :'today'::date + 200, :'today'::date - 3, 'Deposit paid by bank transfer'); -- Cara joins the program
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'cara' and sessions_planned = 30 and ended_at is null), 1::bigint, 'Operations ticks the box'); -- she is in it
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and ends_on is null), 1::bigint, 'the study plan add-on is given'); -- study plans
reset role; -- back to the database itself

-- ---------------------------------------------------------------------------
-- Who can see it
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- parent P1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'cara'), 1::bigint, 'the family sees their child is in the program'); -- visible
reset role; -- back to the database itself
select tests.claims('00000000-0000-0000-0000-000000000002', 'aal2'); -- parent P2 (another family)
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.ssp_enrolments), 0::bigint, 'another family sees nothing'); -- not visible
select tests.fails($$insert into public.ssp_enrolments (student_id) select id from public.students limit 1$$, 'nobody writes the table directly'); -- refused
reset role; -- back to the database itself

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
insert into public.billing_accounts (family_id, bill_payer_id, plan) values (:'fam', '00000000-0000-0000-0000-000000000001', 'weekly') on conflict (family_id) do nothing; -- billing for the family
update public.billing_accounts set paused = false where family_id = :'fam'; -- not on hold
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
-- Unticking the box
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- the owner
set role authenticated; -- as a signed-in person
select public.ssp_leave(:'cara'); -- Cara leaves the program
select tests.eq((select count(*) from public.ssp_enrolments where student_id = :'cara' and ended_at is not null), 1::bigint, 'the owner unticks the box'); -- left
select tests.eq((select count(*) from public.add_on_members where add_on = 'study_plans' and student_id = :'cara' and ends_on is not null), 1::bigint, 'the program''s study plan add-on ends'); -- ended
select tests.fails_with(format($$select public.ssp_leave(%L)$$, :'cara'), 'not in the Student Success Program', 'cannot untick twice'); -- refused
reset role; -- back to the database itself

\echo '  student success program: all checks passed'
rollback; -- throws away everything this test did
