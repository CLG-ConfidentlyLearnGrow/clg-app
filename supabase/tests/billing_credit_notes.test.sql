-- Xero credit note references are written only by the server.

-- Keeps psql quiet so only problems are printed.
\set QUIET on
-- Runs the database change 20261028230200_billing_credit_notes.sql first, as this test needs it.
\ir ../migrations/20261028230200_billing_credit_notes.sql
-- Re-running an older billing file resets its rules, so apply admin levels again.
-- Runs the database change 20261029900200_admin_levels.sql first, as this test needs it.
\ir ../migrations/20261029900200_admin_levels.sql

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2'); -- Signs in as test account ...a0 with two-step sign-in.
set role authenticated; -- Acts as a signed-in user, so the access rules apply.
select tests.fails($$update public.billing_credits set xero_credit_note_id = 'cn_x'$$, 'owner sets a credit note reference by hand'); -- Checks this is refused: owner sets a credit note reference by hand.
select tests.fails($$update public.billing_invoices set xero_credit_allocated_at = now()$$, 'owner marks credit applied by hand'); -- Checks this is refused: owner marks credit applied by hand.
reset role; -- Goes back to the all-powerful test user (access rules off).
select tests.claims(null); -- Signs out, so no one is signed in.

set role service_role; -- Acts as the server's own key (the only one allowed to write these).
select tests.eq((select count(*) from public.billing_credits where xero_credit_note_id is not null), 0, 'server can read the reference'); -- Checks: server can read the reference.
reset role; -- Goes back to the all-powerful test user (access rules off).

-- Prints that every check in this file passed.
\echo '  billing credit notes: all checks passed'
