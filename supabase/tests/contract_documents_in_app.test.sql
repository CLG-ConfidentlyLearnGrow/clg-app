-- Contract documents inside the app: the Child Safe Policy and Staff Code of
-- Conduct point at their app pages (with the old Claude addresses kept), the
-- owner saves their wording and approval, nobody else can, and every
-- signed-in staff member can read them. Reuses access_rules.test.sql people:
-- owner (...a0), operations admin (...b0), tutor T1 (...11).
-- Everything is rolled back.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Starts a transaction so nothing here is kept.
begin;
-- Runs this database change again (checks it can run twice).
\ir ../migrations/20261121200200_contract_documents_in_app.sql
-- Runs the 22 Nov 2026 policy versions change again too: it replaces the wording-save function
-- the line above re-creates, and checks it can also run twice.
\ir ../migrations/20261124710800_policy_versions_read_again.sql

-- The two policies now open their app pages, and remember their old addresses.
select tests.eq((select count(*) from public.employment_contract_documents where key = 'child_safe_policy' and url = '/policies/child_safe_policy' and 'https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC' = any (also_known_as)), 1, 'Child Safe Policy opens its app page'); -- checks the policy link
select tests.eq((select count(*) from public.employment_contract_documents where key = 'code_of_conduct' and url = '/policies/code_of_conduct' and 'https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz' = any (also_known_as)), 1, 'Code of Conduct opens its app page'); -- checks the code link

-- Only the owner saves the wording.
select tests.claims('00000000-0000-0000-0000-0000000000b0', 'aal2'); -- acting as the operations admin
set role authenticated; -- as a signed-in person
select tests.fails($$select public.employment_contract_document_save_text('code_of_conduct', 'x', true)$$, 'operations admin saves policy wording'); -- checks only the owner can
select tests.fails($$select public.employment_contract_document_save_country_urls('fwis', '{}')$$, 'operations admin saves country links'); -- checks only the owner can
reset role; -- back to the test user
select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- acting as the owner
set role authenticated; -- as a signed-in person
select public.employment_contract_document_save_text('code_of_conduct', '# Code of Conduct', false); -- saves a draft
select tests.eq((select count(*) from public.employment_contract_documents where key = 'code_of_conduct' and body = '# Code of Conduct' and approved_at is null), 1, 'owner saves draft wording'); -- checks the draft
select public.employment_contract_document_save_text('code_of_conduct', '# Code of Conduct', true); -- approves it
select tests.eq((select count(*) from public.employment_contract_documents where key = 'code_of_conduct' and approved_at is not null and approved_by is not null), 1, 'owner approves the wording'); -- checks the approval
select tests.fails($$select public.employment_contract_document_save_text('nothing_here', 'x', true)$$, 'saving an unknown document'); -- checks an unknown document is refused
select public.employment_contract_document_save_country_urls('fwis', '{"NZ": "https://www.employment.govt.nz/"}'); -- saves a link for New Zealand
select tests.eq((select count(*) from public.employment_contract_documents where key = 'fwis' and country_urls ->> 'NZ' = 'https://www.employment.govt.nz/'), 1, 'owner saves a link for another country'); -- checks it was kept
select tests.fails($$select public.employment_contract_document_save_country_urls('fwis', '{"New Zealand": "https://x.nz/"}')$$, 'a country that is not a two-letter code'); -- checks bad country codes are refused
select tests.fails($$select public.employment_contract_document_save_country_urls('fwis', '{"NZ": "javascript:alert(1)"}')$$, 'a country link that is not a web address'); -- checks unsafe links are refused
reset role; -- back to the test user

-- Staff can read the wording.
select tests.claims('00000000-0000-0000-0000-000000000011', 'aal2'); -- acting as tutor T1
set role authenticated; -- as a signed-in person
select tests.eq((select count(*) from public.employment_contract_documents where key = 'code_of_conduct' and body = '# Code of Conduct'), 1, 'tutor reads the policy wording'); -- checks staff can read it
select tests.fails($$update public.employment_contract_documents set body = 'changed' where key = 'code_of_conduct'$$, 'tutor changes the wording directly'); -- checks nobody changes it directly
reset role; -- back to the test user

\echo '  contract documents in the app: all checks passed'
-- Throws away everything this test did.
rollback;
