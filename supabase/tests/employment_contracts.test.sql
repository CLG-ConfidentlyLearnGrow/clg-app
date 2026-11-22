-- Employment contracts: only the owner writes and publishes templates; only
-- the owner and Operations admins send or withdraw contracts; gaps fill in
-- automatically or must be typed in; each staff member sees only their own
-- contracts; signing needs two-step login, their typed full name, consent
-- and the exact wording; casual staff acknowledge both information
-- statements before the contract is complete; the Xero step is recorded
-- once. Reuses access_rules.test.sql people: owner (...a0), operations admin
-- (...b0), tutor T1 Tess Tutor (...11), tutor T2 (...12), parent (...01).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs the contracts database change again (checks it can run twice).
\ir ../migrations/20261121200100_employment_contracts.sql
-- Runs the 22 Nov 2026 policy versions change again too: it replaces the acknowledge function
-- the line above re-creates, and checks it can also run twice.
\ir ../migrations/20261124710800_policy_versions_read_again.sql

-- Makes sure T1's app name is known exactly, for the signature checks.
update public.accounts set full_name = 'Tess Tutor' where id = '00000000-0000-0000-0000-000000000011'; -- sets T1's full name
-- The starter drafts were added once, even though the file ran twice.
select tests.eq((select count(*) from public.employment_contract_templates where status = 'draft'), 2, 'two starter drafts, added once'); -- checks the starter drafts

-- ---------------------------------------------------------------------------
-- Templates: who can read and change them.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.employment_contract_templates), 0, 'tutor cannot read templates'); -- checks tutors see no templates
select tests.eq((select count(*) from public.employment_contract_documents), 4, 'tutor reads the document list'); -- checks staff can see the document names and links
select tests.fails($$select public.employment_contract_template_save(null, 'tutor_casual', 'Mine', 'x')$$, 'tutor writes a template'); -- checks tutors cannot write templates
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.employment_contract_templates), 2, 'operations admin reads templates'); -- checks Operations admins can read them
select tests.fails($$select public.employment_contract_template_save(null, 'tutor_casual', 'Mine', 'x')$$, 'operations admin writes a template'); -- checks only the owner writes them
select tests.fails($$select public.employment_contract_template_publish((select id from public.employment_contract_templates where contract_type = 'tutor_casual'))$$, 'operations admin publishes'); -- checks only the owner publishes
select tests.fails($$select public.employment_contract_document_save('fwis', 'Fair Work', 'https://example.com')$$, 'operations admin changes a document link'); -- checks only the owner changes document links
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal1'); -- the owner without two-step login
set role authenticated; -- as a signed-in person
select tests.fails($$select public.employment_contract_template_save(null, 'tutor_casual', 'Mine', 'x')$$, 'owner without two-step login writes a template'); -- checks two-step login is needed
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner with two-step login
set role authenticated; -- as a signed-in person
-- Saves the casual draft with test wording (saving with no id lands in the existing draft), keeping its id.
select public.employment_contract_template_save(null, 'tutor_casual', 'Casual contract for [Tutor name]', 'Between {{clg name}} and **\[Tutor name\]** ([Tutor email]). Type: [Full-time or Part-time]. Start: [Start date]. Tertiary: [Post-Secondary Award level, or Not applicable]. See [the policy](https://x.example). Weeks: {{weeks?}}.') as tpl \gset
select tests.eq((select count(*) from public.employment_contract_templates where contract_type = 'tutor_casual'), 1, 'saving with no id reuses the draft'); -- checks there is still one casual template
select public.employment_contract_template_publish(:'tpl'); -- publishes it
select tests.eq((select count(*) from public.employment_contract_templates where id = :'tpl' and status = 'published' and version = 1), 1, 'owner publishes the draft'); -- checks it is in use
-- Editing the published version starts version 2 as a draft, leaving version 1 in use.
select public.employment_contract_template_save(:'tpl', 'tutor_casual', 'Casual v2', 'New words for {{tutor name}}') as tpl2 \gset
select tests.eq((select version from public.employment_contract_templates where id = :'tpl2' and status = 'draft'), 2, 'editing a published version starts a new draft'); -- checks the new draft
select tests.eq((select count(*) from public.employment_contract_templates where id = :'tpl' and status = 'published'), 1, 'version 1 stays in use'); -- checks version 1 is unchanged
select public.employment_contract_template_discard(:'tpl2'); -- deletes the version 2 draft
select public.employment_contract_document_save('child_safe_policy', 'CLG Child Safe Policy', '/handbook'); -- moves the policy link to an app page
select tests.fails($$select public.employment_contract_document_save('code_of_conduct', 'Code', 'javascript:alert(1)')$$, 'document link that is not a web address'); -- checks only safe links are kept
select tests.fails(format($$select public.employment_contract_template_discard(%L)$$, :'tpl'), 'deleting a published version'); -- checks published versions are kept
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- Sending.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- acting as a parent
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.employment_contract_send(%L, '00000000-0000-0000-0000-000000000011', 'casual', '{"start date":"1 December 2026"}')$$, :'tpl'), 'parent sends a contract'); -- checks parents cannot send
reset role; -- back to the test user

select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.employment_contract_send(%L, '00000000-0000-0000-0000-000000000011', 'casual', '{}')$$, :'tpl'), 'sending with the start date empty'); -- checks required gaps must be filled
select tests.fails(format($$select public.employment_contract_send(%L, '00000000-0000-0000-0000-000000000011', 'part_time', '{"start date":"1 December 2026"}')$$, :'tpl'), 'casual contract as part-time'); -- checks the employment type must match
select tests.fails(format($$select public.employment_contract_send(%L, '00000000-0000-0000-0000-000000000001', 'casual', '{"start date":"1 December 2026"}')$$, :'tpl'), 'tutor contract to a parent'); -- checks the person must hold the role
select tests.fails($$select public.employment_contract_send((select id from public.employment_contract_templates where contract_type = 'tutor_permanent'), '00000000-0000-0000-0000-000000000011', 'part_time', '{"start date":"1 December 2026","guaranteed hours":"10"}')$$, 'sending a draft template'); -- checks only published templates can be sent
-- Sends the first contract to T1, keeping its id as c1.
select public.employment_contract_send(:'tpl', '00000000-0000-0000-0000-000000000011', 'casual', '{"Start Date":"1 December 2026","tutor name":"Someone Else"}') as c1 \gset
reset role; -- back to the test user
select tests.eq((select count(*) from public.employment_contracts where id = :'c1' and body = 'Between CLG Tutoring and **Tess Tutor** (t1@clg.example). Type: Casual. Start: 1 December 2026. Tertiary: Not applicable. See [the policy](https://x.example). Weeks: Not applicable.'), 1, 'gaps filled automatically and from typed values'); -- checks every gap filled (square and curly brackets, escaped brackets, optional gaps), links left alone, and the automatic name won over the typed one
select tests.eq((select count(*) from public.employment_contracts where id = :'c1' and title = 'Casual contract for Tess Tutor' and statements = array['fwis', 'ceis', 'child_safe_policy', 'code_of_conduct'] and body_sha256 = encode(sha256(convert_to(body, 'UTF8')), 'hex')), 1, 'title filled, casual statements, fingerprint saved'); -- checks the title, statements and fingerprint

-- Sending again replaces the one still waiting.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select public.employment_contract_send(:'tpl', '00000000-0000-0000-0000-000000000011', 'casual', '{"start date":"2 December 2026"}') as c2 \gset
reset role; -- back to the test user
select tests.eq((select count(*) from public.employment_contracts where id = :'c1' and status = 'withdrawn'), 1, 'older waiting contract withdrawn when replaced'); -- checks the first one was withdrawn

-- ---------------------------------------------------------------------------
-- Who sees contracts.
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.employment_contracts), 2, 'tutor sees their own contracts'); -- checks T1 sees both of theirs
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-000000000012', 'aal2'); -- acting as tutor T2
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.employment_contracts), 0, 'another tutor sees none'); -- checks T2 sees none of T1's
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess Tutor', (select body_sha256 from public.employment_contracts where id = %L), true, true)$$, :'c2', :'c2'), 'another tutor signs it'); -- checks T2 cannot sign T1's contract
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-000000000001', 'aal2'); -- acting as a parent
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.employment_contracts), 0, 'parent sees none'); -- checks parents see none
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- Signing and acknowledging.
-- ---------------------------------------------------------------------------
select body_sha256 as hash from public.employment_contracts where id = :'c2' \gset
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal1'); -- T1 without two-step login
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess Tutor', %L, true, true)$$, :'c2', :'hash'), 'signing without two-step login'); -- checks two-step login is needed
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- T1 with two-step login
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess T', %L, true, true)$$, :'c2', :'hash'), 'signing with the wrong name'); -- checks the typed name must match
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess Tutor', %L, true, true)$$, :'c2', repeat('0', 64)), 'signing different wording'); -- checks the wording fingerprint must match
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess Tutor', %L, false, true)$$, :'c2', :'hash'), 'signing without consent'); -- checks consent to sign electronically is needed
select tests.fails(format($$select public.employment_contract_acknowledge(%L, 'fwis', 'Tess Tutor')$$, :'c2'), 'acknowledging before signing'); -- checks the contract is signed first
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess Tutor', (select body_sha256 from public.employment_contracts where id = %L), true, true)$$, :'c1', :'c1'), 'signing a withdrawn contract'); -- checks withdrawn contracts cannot be signed
select public.employment_contract_sign(:'c2', '  tess   TUTOR ', :'hash', true, true); -- signs (case and spaces do not matter)
select tests.eq((select count(*) from public.employment_contracts where id = :'c2' and status = 'signed' and signed_name = 'tess   TUTOR' and pay_notice_shown and signed_aal = 'aal2'), 1, 'tutor signs their contract'); -- checks the signature was recorded
select tests.fails(format($$select public.employment_contract_sign(%L, 'Tess Tutor', %L, true, true)$$, :'c2', :'hash'), 'signing twice'); -- checks it cannot be signed twice
select tests.fails(format($$select public.employment_contract_acknowledge(%L, 'fwis', 'Someone')$$, :'c2'), 'acknowledging with the wrong name'); -- checks the typed name must match
select public.employment_contract_acknowledge(:'c2', 'fwis', 'Tess Tutor'); -- acknowledges the Fair Work Information Statement
select tests.eq((select count(*) from public.employment_contracts where id = :'c2' and status = 'signed'), 1, 'still waiting for the casual statement'); -- checks one statement is not enough for casual staff
select public.employment_contract_acknowledge(:'c2', 'ceis', 'Tess Tutor'); -- acknowledges the Casual Employment Information Statement
select public.employment_contract_acknowledge(:'c2', 'child_safe_policy', 'Tess Tutor'); -- acknowledges the Child Safe Policy
select tests.eq((select count(*) from public.employment_contracts where id = :'c2' and status = 'signed'), 1, 'still waiting for the Code of Conduct'); -- checks every document is needed
select public.employment_contract_acknowledge(:'c2', 'code_of_conduct', 'Tess Tutor'); -- acknowledges the Staff Code of Conduct
select tests.eq((select count(*) from public.employment_contracts where id = :'c2' and status = 'complete' and completed_at is not null), 1, 'contract complete after every document'); -- checks it is complete
select tests.eq((select count(*) from public.employment_contract_acknowledgements where contract_id = :'c2' and statement_url like 'https://www.fairwork.gov.au/%'), 2, 'tutor sees both Fair Work acknowledgements with their links'); -- checks the records and links
select tests.fails(format($$select public.employment_contract_xero_done(%L)$$, :'c2'), 'tutor records the Xero step'); -- checks only admins record the Xero step
select tests.eq((select coalesce(sum(paid_lines), 0) from public.employment_contract_pay_evidence(:'c2'))::bigint, 0, 'tutor gets no pay evidence'); -- checks the pay evidence is for admins only
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- After signing (admins).
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails(format($$select public.employment_contract_withdraw(%L, 'Oops')$$, :'c2'), 'withdrawing a signed contract'); -- checks a signed contract stays as the record
select public.employment_contract_xero_done(:'c2'); -- records the Xero invite
select tests.eq((select count(*) from public.employment_contracts where id = :'c2' and xero_invite_at is not null), 1, 'Xero step recorded'); -- checks it was recorded
select tests.fails(format($$select public.employment_contract_xero_done(%L)$$, :'c2'), 'Xero step recorded twice'); -- checks it is recorded once
select tests.eq((select count(*) from public.employment_contract_acknowledgements where contract_id = :'c2'), 4, 'admin sees acknowledgements'); -- checks admins see the acknowledgements
select tests.eq((select count(*) from public.employment_contract_pay_evidence(:'c2')), 1, 'admin gets the pay evidence row'); -- checks admins can ask for pay evidence
reset role; -- back to the test user

-- Nobody signed in can change the tables directly.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.fails(format($$update public.employment_contracts set body = 'changed' where id = %L$$, :'c2'), 'tutor edits the contract wording'); -- checks the wording cannot be changed
select tests.fails(format($$insert into public.employment_contract_acknowledgements (contract_id, statement, statement_title, statement_url, typed_name) values (%L, 'fwis', 'x', 'x', 'x')$$, :'c1'), 'tutor adds an acknowledgement directly'); -- checks acknowledgements only go through the function
reset role; -- back to the test user

-- ---------------------------------------------------------------------------
-- A new version of a policy: staff read and tick it again (Carla, 22 Nov 2026)
-- ---------------------------------------------------------------------------
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq(public.my_policy_rereads_count()::bigint, 0, 'nothing to read again yet'); -- no new versions
select tests.fails($$select public.employment_contract_document_new_version('child_safe_policy', 'x')$$, 'a tutor makes a new version'); -- only the owner can
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select tests.fails_with($$select public.employment_contract_document_save_text('child_safe_policy', '# Child Safe Policy v2', false, true, 'x')$$, 'must be approved', 'a new version must be approved first'); -- a draft cannot be a new version
select public.employment_contract_document_save_text('child_safe_policy', '# Child Safe Policy v2', true, true, 'Added the online safety section.'); -- saves version 2
select tests.eq((select version::bigint from public.employment_contract_documents where key = 'child_safe_policy'), 2, 'the policy is now version 2'); -- version 2
select tests.eq((select count(*) from public.policy_rereads_outstanding() where contract_id = :'c2' and title like '%Child Safe%' and version = 2), 1, 'the owner sees who still has to read it'); -- on the admin list
select public.employment_contract_document_save_text('child_safe_policy', '# Child Safe Policy v2 (typo fixed)', true); -- a small fix that is not a new version
select tests.eq((select version::bigint from public.employment_contract_documents where key = 'child_safe_policy'), 2, 'a save without a new version keeps the number'); -- still 2
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq(public.my_policy_rereads_count()::bigint, 1, 'the tutor has one policy to read again'); -- one to read
select public.employment_contract_acknowledge(:'c2', 'child_safe_policy', 'Tess Tutor'); -- ticks version 2
select tests.eq((select count(*) from public.employment_contract_acknowledgements where contract_id = :'c2' and statement = 'child_safe_policy'), 2, 'both ticks are kept (version 1 and 2)'); -- the record of both
select tests.eq(public.my_policy_rereads_count()::bigint, 0, 'nothing left to read again'); -- done
select tests.eq((select count(*) from public.employment_contracts where id = :'c2' and status = 'complete'), 1, 'the contract stays complete'); -- unchanged
reset role; -- back to the test user

\echo '  employment contracts: all checks passed'
-- Throws away everything this test did.
rollback;
