-- Xero credit note references are written only by the server.

\set QUIET on
\ir ../migrations/20261028230200_billing_credit_notes.sql
-- Re-running an older billing file resets its rules, so apply admin levels again.
\ir ../migrations/20261029900200_admin_levels.sql

select tests.claims('00000000-0000-0000-0000-0000000000a0', 'aal2');
set role authenticated;
select tests.fails($$update public.billing_credits set xero_credit_note_id = 'cn_x'$$, 'owner sets a credit note reference by hand');
select tests.fails($$update public.billing_invoices set xero_credit_allocated_at = now()$$, 'owner marks credit applied by hand');
reset role;
select tests.claims(null);

set role service_role;
select tests.eq((select count(*) from public.billing_credits where xero_credit_note_id is not null), 0, 'server can read the reference');
reset role;

\echo '  billing credit notes: all checks passed'
