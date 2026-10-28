-- Billing part 3 (module: billing): credits as Xero credit notes.
--
-- Each credit a family is given (a cancellation, a tutor's day off,
-- goodwill) becomes a credit note in Xero. When an invoice uses credit,
-- the app applies ("allocates") those credit notes to the invoice in Xero,
-- so the accountant sees the whole trail. Credit put back when an invoice
-- is cancelled is not a new credit note: in Xero the credit returns when
-- the allocation is removed.
--
-- Only the server writes these columns. Safe to run more than once.

alter table public.billing_credits add column if not exists xero_credit_note_id text;
alter table public.billing_invoices add column if not exists xero_credit_allocated_at timestamptz;
