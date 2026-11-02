-- Billing part 7 (module: billing): sessions already paid for go ahead.
--
-- Carla (2026-11-02): when part of an invoice has been paid (for example
-- one parent has paid their share), the family is paused only from the
-- first session that hasn't been paid for. Sessions the payment covers go
-- ahead. With nothing paid, the whole family goes on hold as before
-- (unless an override is in force).
--
-- How "paid for" is worked out: the payments made or on their way, plus
-- any credit and discount on the invoice, are counted against the sessions
-- in date order. The first session they don't fully cover is where the
-- pause starts.
--
-- Safe to run more than once. Run after 20261028230400_billing_split_payments.sql.

-- The day of the first session on an invoice that payments don't cover,
-- or null when the whole invoice is covered.
create or replace function private.billing_first_unpaid_day(p_invoice uuid)
returns date language sql stable security definer
set search_path = ''
as $$
  with covered as (
    select i.credit_applied_cents + i.discount_cents + coalesce((
             select sum(p.amount_cents) from public.billing_payments p
             where p.invoice_id = i.id and p.status in ('processing', 'succeeded')
           ), 0) as cents
    from public.billing_invoices i where i.id = p_invoice
  ),
  running as (
    select l.line_date,
           sum(l.amount_cents) over (order by l.line_date, l.id) as upto
    from public.billing_invoice_lines l
    where l.invoice_id = p_invoice and l.active
  )
  select min(r.line_date) from running r, covered c where r.upto > c.cents
$$;
revoke execute on function private.billing_first_unpaid_day(uuid) from public;

-- A family is paused when a sent invoice isn't fully paid (or on its way)
-- and either its due date has passed or a payer's payment failed and that
-- payer hasn't paid since, and no override is in force. If part of the
-- invoice has been paid, the pause waits until the first session that
-- isn't paid for.
create or replace function private.billing_should_pause(p_family uuid, p_today date)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
      select 1
      from public.billing_invoices i
      cross join lateral (
        select coalesce(sum(p.amount_cents), 0) as paid
        from public.billing_payments p
        where p.invoice_id = i.id and p.status in ('processing', 'succeeded')
      ) pay
      where i.family_id = p_family
        and i.status = 'open'
        and pay.paid < i.total_cents
        and (
          i.due_on < p_today
          or exists (
            select 1 from public.billing_payments f
            where f.invoice_id = i.id and f.status = 'failed'
              and not exists (
                select 1 from public.billing_payments g
                where g.invoice_id = i.id and g.status in ('processing', 'succeeded')
                  and g.payer_id is not distinct from f.payer_id
              )
          )
        )
        and (
          pay.paid = 0
          or coalesce(private.billing_first_unpaid_day(i.id), p_today) <= p_today
        )
    )
    and not exists (
      select 1 from public.billing_pause_overrides o
      where o.family_id = p_family and o.ended_at is null and o.until_on >= p_today
    )
$$;
