-- Summary: term reviews become something a family chooses and pays for,
-- one review at a time, and there are no monthly summaries. Carla, 12 Nov
-- 2026. See docs/features/term-reviews.md.
--
-- How it works now:
--   1. Billing (module: billing) gets a "Term review" price item. The owner
--      sets its price and turns it on under Admin > Billing > Prices. Until
--      then no offers go out.
--   2. Four weeks before the end of each term (each semester or study
--      period for tertiary students), the family is offered a review, with
--      the price. If the student's booked sessions stop at a date that
--      doesn't line up with a term's end, the offer comes four weeks
--      before their last booked session instead.
--   3. The adult who manages the student (or a student who manages their
--      own account) says yes or no on the progress page. CLG front desk or
--      finance admins can answer for them, and finance admins can give a
--      review at no charge (for example on hardship).
--   4. On "yes", billing makes an invoice with one line for the review, at
--      the price the family was shown, and the student's tutor gets a
--      draft review to write. On "no", nothing happens.
--   5. Monthly summaries stay switched off (since 2 Nov 2026), and the old
--      "Term reviews" add-on is removed, because the price item replaces it.
--
-- Modules: progress owns the offers and reviews; billing owns prices and
-- invoices. Progress asks billing to charge through one billing function
-- and never writes billing's tables; billing never writes progress tables.
--
-- Needs 20261103000800_progress_term_review_add_on.sql and
-- 20261113200100_quiet_hours.sql. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Billing: the "Term review" price item
-- ---------------------------------------------------------------------------

-- Adds the price item, off and at $0 until the owner sets a price.
insert into public.billing_price_items (code, name, unit, amount_cents, gst_applies, active, description) -- the price list
values ('term_review', 'Term review', 'once', 0, false, false, -- code, name, charged once per review, $0, no GST, not in use yet
  'A written review from the student''s tutor near the end of a term, semester or booking. Charged once for each review a family says yes to. Set the price (including GST if it applies) and tick "in use" to start offering it.') -- what it is, for admins
on conflict (code) do nothing; -- leaves it alone if it is already there (so a price already set stays)

-- ---------------------------------------------------------------------------
-- 2. Billing: charging for one thing (not a session)
-- ---------------------------------------------------------------------------

-- Makes an invoice with a single line for something charged once, such as
-- a term review. Uses the family's credit first and the bank-debit
-- discount, the same way session invoices do. Gives back the new invoice,
-- or nothing when the family has no billing account yet (CLG then bills it
-- by hand). Only other database functions call this.
create or replace function private.billing_charge_once( -- the function's name
  p_family uuid, -- the family to bill
  p_student uuid, -- the student it is for
  p_price_code text, -- which price item it is (for example 'term_review')
  p_description text, -- the words on the invoice line
  p_line_date date, -- the date on the line (when it is delivered)
  p_amount_cents int, -- the amount the family agreed to, including any GST
  p_gst boolean -- whether GST is included in that amount
)
returns uuid -- the new invoice's id (or nothing)
language plpgsql security definer -- runs with the database's own rights, as billing tables are locked down
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_account public.billing_accounts; -- the family's billing set-up
  v_price_id uuid; -- the price item's id
  v_family_name text; -- the family's name (copied onto the invoice)
  v_dates record; -- when the invoice is sent, due and charged
  v_gst int; -- the GST part of the amount
  v_balance int; -- the family's credit
  v_credit int; -- the credit used on this invoice
  v_discount int; -- the bank-debit discount
  v_invoice uuid; -- the new invoice
begin -- start of the steps
  if coalesce(p_amount_cents, 0) <= 0 then -- nothing to charge:
    return null; -- makes no invoice
  end if; -- end of that check
  select * into v_account from public.billing_accounts where family_id = p_family; -- reads the family's billing set-up
  if not found then -- no billing account yet:
    return null; -- makes no invoice (CLG bills it by hand)
  end if; -- end of that check
  select id into v_price_id from public.billing_price_items where code = p_price_code; -- finds the price item, for the line
  select name into v_family_name from public.families where id = p_family; -- reads the family's name

  select * into v_dates from private.billing_dates(v_account.plan, v_account.method, p_line_date); -- works out send, due and charge dates from the line date, as for sessions
  v_dates.send_on := greatest(v_dates.send_on, private.billing_today()); -- never sent in the past
  v_dates.due_on := greatest(v_dates.due_on, private.billing_today()); -- never due in the past
  v_dates.charge_on := greatest(v_dates.charge_on, private.billing_today()); -- never charged in the past

  v_gst := case when p_gst then round(p_amount_cents / 11.0)::int else 0 end; -- GST is one eleventh of a GST-inclusive price
  select coalesce(sum(amount_cents), 0) into v_balance from public.billing_credits where family_id = p_family; -- adds up the family's credit
  v_credit := least(greatest(v_balance, 0), p_amount_cents); -- uses credit first, up to the amount
  v_discount := case when v_account.method = 'bank_debit' -- families paying by bank debit
    then private.billing_debit_discount(p_amount_cents - v_credit) else 0 end; -- get the usual discount on what's left

  insert into public.billing_invoices ( -- makes the invoice:
    family_id, family_name, plan, method, period_start, period_end, first_session_on, -- who, their plan and method, and its dates
    send_on, due_on, charge_on, subtotal_cents, gst_cents, discount_cents, -- when it goes out, and the money
    credit_applied_cents, total_cents, created_by -- credit, total, and who made it
  ) values ( -- with these values:
    p_family, coalesce(v_family_name, 'Family'), v_account.plan, v_account.method, p_line_date, p_line_date, p_line_date, -- the family, their plan and method, and the line date as its dates
    v_dates.send_on, v_dates.due_on, v_dates.charge_on, p_amount_cents, v_gst, v_discount, -- the dates and amounts
    v_credit, p_amount_cents - v_credit - v_discount, auth.uid() -- credit used, what's left to pay, and who said yes
  ) -- end of the values
  returning id into v_invoice; -- keeps the new invoice's id

  -- The line counts as 60 minutes at the item's price, so Xero shows it as
  -- quantity 1 at that price (Xero's quantity is minutes divided by 60).
  insert into public.billing_invoice_lines ( -- adds the one line:
    invoice_id, student_id, price_item_id, line_date, description, -- which invoice, student, price, date and words
    minutes, billed_minutes, hourly_cents, amount_cents, gst_cents -- quantity and money
  ) values ( -- with these values:
    v_invoice, p_student, v_price_id, p_line_date, left(p_description, 300), -- the invoice, student, price item, date and words (300 characters at most)
    60, 60, p_amount_cents, p_amount_cents, v_gst -- one unit at the agreed amount
  ); -- end of the line

  if v_credit > 0 then -- if credit was used:
    insert into public.billing_credits (family_id, kind, amount_cents, invoice_id, note, created_by) -- records it coming off
    values (p_family, 'applied', -v_credit, v_invoice, 'Used on this invoice', auth.uid()); -- the family's credit balance
  end if; -- end of the credit step
  return v_invoice; -- gives back the new invoice
end; -- end of the steps
$$; -- end of the function
revoke all on function private.billing_charge_once(uuid, uuid, text, text, date, int, boolean) from public; -- no one calls it directly; only database functions do

-- ---------------------------------------------------------------------------
-- 3. Progress: who is offered a review, and when
-- ---------------------------------------------------------------------------

-- Each offer of a paid term review to a family, and their answer.
create table if not exists public.term_review_offers ( -- the table, made only if it isn't there yet
  id uuid primary key default gen_random_uuid(), -- the offer's id
  student_id uuid not null references public.students (id) on delete cascade, -- the student (offers go when the student's records go)
  -- What the review is the end of: a school term, a tertiary study period,
  -- or the student's last booked session.
  period_kind text not null check (period_kind in ('term', 'study_period', 'booking_end')), -- one of those three
  period_label text not null check (char_length(period_label) <= 80), -- its name, for example "Term 4 2026"
  period_starts_on date not null, -- the first day the review covers
  period_ends_on date not null, -- the last day (the end of term, or the last booked session)
  -- The price shown in the offer, kept so the family pays what they saw.
  price_cents int not null check (price_cents >= 0), -- in cents, including GST if it applies
  gst_applies boolean not null default false, -- whether that price includes GST
  answer text not null default 'waiting' check (answer in ('waiting', 'yes', 'no')), -- the family's answer
  no_charge boolean not null default false, -- true when CLG gave it at no charge
  answered_by uuid references public.accounts (id) on delete set null, -- who answered
  answered_at timestamptz, -- when they answered
  -- The invoice billing made for it (blank for no charge, or no billing account).
  invoice_id uuid references public.billing_invoices (id) on delete set null, -- the invoice, if there is one
  created_at timestamptz not null default now(), -- when it was offered
  constraint term_review_offers_dates check (period_ends_on >= period_starts_on), -- the end can't be before the start
  constraint term_review_offers_free_only_yes check (not no_charge or answer = 'yes') -- only a "yes" can be at no charge
); -- end of the table
create unique index if not exists term_review_offers_once on public.term_review_offers (student_id, period_ends_on); -- one offer per student for each end date
create index if not exists term_review_offers_open on public.term_review_offers (answer, period_ends_on); -- quick lookup of offers still waiting

alter table public.term_review_offers enable row level security; -- access rules apply to this table
revoke all on public.term_review_offers from anon; -- signed-out visitors can't see it
revoke insert, update, delete, truncate on public.term_review_offers from authenticated; -- every change goes through the functions below
drop trigger if exists audit on public.term_review_offers; -- replaces the audit trigger if this is run again
create trigger audit after insert or update or delete on public.term_review_offers -- records every change
  for each row execute function private.audit_change(); -- in the audit log

-- Reviews remember which offer they came from, and their own due date.
alter table public.term_reviews add column if not exists offer_id uuid references public.term_review_offers (id) on delete set null; -- the offer (blank for older reviews)
alter table public.term_reviews add column if not exists due_on date; -- the date the tutor should send it by (blank for older reviews)
create unique index if not exists term_reviews_offer_once on public.term_reviews (offer_id) where offer_id is not null; -- one review per paid offer

-- True when the signed-in person answers for this student's family: a
-- parent who manages the student, or a student who manages their own
-- account (no managing parent). Tutors never see offers or prices.
create or replace function private.can_answer_term_review(p_student uuid) -- takes the student
returns boolean -- yes or no
language sql stable security definer -- reads the family links whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the value
  select private.can_manage_student(p_student) -- a managing parent
    or (private.is_student_self(p_student) and not private.has_managing_parent(p_student)) -- or an adult student who manages themselves
$$; -- end of the function
revoke all on function private.can_answer_term_review(uuid) from public; -- only used inside rules and functions
grant execute on function private.can_answer_term_review(uuid) to authenticated; -- the access rule below needs it for signed-in people

-- Who sees offers: CLG front desk and finance admins, and the family member
-- who answers. Not tutors, and not parents who only view.
drop policy if exists "see term review offers" on public.term_review_offers; -- replaces the rule if this is run again
create policy "see term review offers" on public.term_review_offers -- the rule
  for select to authenticated using ( -- for reading, by signed-in people who are:
    private.is_front_desk() or private.is_finance_admin() -- CLG admins who handle families or money
    or private.can_answer_term_review(student_id) -- or the family member who answers
  ); -- end of the rule

-- The people an offer goes to: the student's managing parents, or the
-- student themselves when they manage their own account.
create or replace function private.term_review_family(p_student uuid) -- takes the student
returns table (account_id uuid) -- one row per person
language sql stable security definer -- reads the family links whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the rows
  select l.parent_id from public.parent_student_links l -- parents
  where l.student_id = p_student and l.can_manage -- who manage this student
  union -- plus
  select s.account_id from public.students s -- the student's own login
  where s.id = p_student and s.account_id is not null -- if they have one
    and not private.has_managing_parent(p_student) -- and no parent manages them
$$; -- end of the function
revoke all on function private.term_review_family(uuid) from public; -- only used inside other functions

-- The end a review would be for, if it is within the next 4 weeks:
--   * the end of a term or study period that the student's bookings reach
--     (they have sessions booked up to at least 2 weeks before it ends), or
--   * otherwise the student's last booked session, when that isn't within
--     2 weeks of any term's end (the booking doesn't line up with terms).
-- Gives back nothing when there is no end coming up.
create or replace function private.term_review_next_end(p_student uuid, p_today date) -- takes the student and today's date
returns table (period_kind text, period_label text, period_starts_on date, period_ends_on date) -- what the review covers
language plpgsql stable security definer -- reads terms and sessions whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_last date; -- the student's last booked session
  v_first date; -- their first session in the 16 weeks before it
  v_term record; -- a term ending soon
begin -- start of the steps
  select max((se.starts_at at time zone 'Australia/Adelaide')::date) into v_last -- the last booked session's date
  from public.sessions se -- from the sessions
  where se.student_id = p_student and se.status = 'scheduled' and se.starts_at > now(); -- this student's sessions still to come
  if v_last is null then -- nothing booked from now on:
    return; -- no review to offer
  end if; -- end of that check

  select t.label, t.starts_on, t.ends_on, t.own_term_id is not null as own into v_term -- a term or study period
  from private.student_terms(p_student) t -- from the student's own term dates (school, private school or tertiary)
  where t.ends_on between p_today and p_today + 28 -- ending in the next 4 weeks
    and v_last >= t.ends_on - 14 -- that their bookings reach
  order by t.ends_on -- the soonest
  limit 1; -- just one
  if v_term.ends_on is not null then -- found one:
    period_kind := case when v_term.own then 'study_period' else 'term' end; -- a tertiary study period, or a school term
    period_label := left(v_term.label, 80); -- its name
    period_starts_on := v_term.starts_on; -- its first day
    period_ends_on := v_term.ends_on; -- its last day
    return next; -- gives back that row
    return; -- and stops
  end if; -- end of the term case

  if v_last <= p_today + 28 -- the last booked session is in the next 4 weeks
     and not exists ( -- and isn't near the end of any term:
       select 1 from private.student_terms(p_student) t -- the student's terms
       where v_last between t.ends_on - 14 and t.ends_on + 14) then -- within 2 weeks either side of one ending
    select min((se.starts_at at time zone 'Australia/Adelaide')::date) into v_first -- the first session
    from public.sessions se -- from the sessions
    where se.student_id = p_student and se.status in ('scheduled', 'completed') -- this student's held or booked sessions
      and se.starts_at at time zone 'Australia/Adelaide' >= (v_last - 112)::timestamp; -- in the 16 weeks before the last one
    period_kind := 'booking_end'; -- the end of their booked sessions
    period_label := 'Sessions to ' || to_char(v_last, 'FMDD Mon YYYY'); -- named by the last date, for example "Sessions to 12 Dec 2026"
    period_starts_on := coalesce(v_first, v_last); -- covers from the first of those sessions
    period_ends_on := v_last; -- to the last booked session
    return next; -- gives back that row
  end if; -- end of the booking case
end; -- end of the steps
$$; -- end of the function
revoke all on function private.term_review_next_end(uuid, date) from public; -- only used inside other functions

-- The date a tutor should send a review by: 2 weeks before the end, but
-- always at least 5 days from today (for late answers).
create or replace function private.term_review_due_on(p_ends_on date) -- takes the end date
returns date -- the due date
language sql stable -- same answer all day
set search_path = '' -- only fully named things, for safety
as $$ -- the value
  select greatest((now() at time zone 'Australia/Adelaide')::date + 5, p_ends_on - 14) -- the later of those two dates
$$; -- end of the function
revoke all on function private.term_review_due_on(date) from public; -- only used inside other functions

-- The notices learn two new kinds: an offer to the family, and "a review
-- was booked" for CLG's admins. Notices can point at an offer.
alter table public.progress_notices add column if not exists offer_id uuid references public.term_review_offers (id) on delete cascade; -- the offer a notice is about (if any)
alter table public.progress_notices drop constraint if exists progress_notices_kind_check; -- replaces the list of kinds
alter table public.progress_notices add constraint progress_notices_kind_check -- the new list:
  check (kind in ('session_update', 'note_reminder', 'note_overdue', 'step_due', -- session notes and roadmap steps,
                  'review_due', 'review_to_check', 'review_returned', 'review_ready', 'review_reply', -- term reviews,
                  'monthly_summary', 'evidence_added', -- old monthly summaries (kept readable) and uploads,
                  'review_offer', 'review_booked')); -- and the two new kinds
create unique index if not exists progress_notices_offer_once -- each person hears about each offer once
  on public.progress_notices (account_id, offer_id, kind) where offer_id is not null; -- for each kind of notice

-- ---------------------------------------------------------------------------
-- 4. Progress: making the draft for the tutor
-- ---------------------------------------------------------------------------

-- After a "yes": a draft review for the student's current tutor (the one
-- with the most session notes in the period, if there are several), and a
-- notice asking them to write it. Gives back the review, or nothing if
-- there's no current tutor yet (the daily job tries again).
create or replace function private.make_term_review_draft(p_offer uuid) -- takes the offer
returns uuid -- the new review's id (or nothing)
language plpgsql security definer -- writes reviews and notices, which are locked down
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_o public.term_review_offers; -- the offer
  v_tutor uuid; -- the tutor who writes it
  v_due date; -- when it's due
  v_id uuid; -- the new review
begin -- start of the steps
  select * into v_o from public.term_review_offers where id = p_offer; -- reads the offer
  if v_o.id is null or v_o.answer <> 'yes' then -- no such offer, or not a "yes":
    return null; -- makes nothing
  end if; -- end of that check
  select ta.tutor_id into v_tutor -- picks the tutor
  from public.tutor_assignments ta -- from who teaches whom
  where ta.student_id = v_o.student_id -- for this student
    and private.assignment_is_current(ta.starts_on, ta.ends_on) -- who teaches them now
  order by (select count(*) from public.session_notes n -- most session notes
            where n.student_id = v_o.student_id and n.tutor_id = ta.tutor_id -- for this student by that tutor
              and n.session_date >= v_o.period_starts_on) desc, -- in the period first
           ta.starts_on desc -- then the most recent tutor
  limit 1; -- just one
  if v_tutor is null then -- no current tutor:
    return null; -- makes nothing for now
  end if; -- end of that check
  v_due := private.term_review_due_on(v_o.period_ends_on); -- works out the due date

  insert into public.term_reviews (student_id, tutor_id, term_label, term_starts_on, term_ends_on, offer_id, due_on) -- makes the draft
  values (v_o.student_id, v_tutor, left(v_o.period_label, 50), v_o.period_starts_on, v_o.period_ends_on, v_o.id, v_due) -- for this student, tutor, period and offer
  on conflict do nothing -- unless there's already one
  returning id into v_id; -- keeps the new review's id
  if v_id is null then -- one was already there:
    return null; -- nothing more to do
  end if; -- end of that check

  insert into public.progress_notices (account_id, student_id, review_id, kind, title, body, deliver_at) -- tells the tutor
  select v_tutor, st.id, v_id, 'review_due', -- a "review to write" notice for this review
         left('Term review to write: ' || st.full_name, 200), -- titled with the student's name
         left(format('%s''s family asked for a review (%s). Please write it by %s, so CLG can check it before it goes to the family. ' -- what to do and by when
                     || 'Write it yourself and don''t put any student details into AI tools.', -- and the reminder about AI tools
                     st.full_name, v_o.period_label, to_char(v_due, 'FMDD Mon')), 1000), -- (the name, period and date)
         now() -- sent now (the quiet hours rule holds it overnight)
  from public.students st where st.id = v_o.student_id -- the student's details
  on conflict do nothing; -- never twice
  return v_id; -- gives back the new review
end; -- end of the steps
$$; -- end of the function
revoke all on function private.make_term_review_draft(uuid) from public; -- only used inside other functions

-- ---------------------------------------------------------------------------
-- 5. Progress: the daily job (same name, so the existing schedule runs it)
-- ---------------------------------------------------------------------------

-- Runs every morning. Makes offers for students whose term, study period
-- or booking ends in the next 4 weeks, and drafts for any "yes" still
-- waiting for a tutor. Gives back how many offers it made.
create or replace function private.queue_term_reviews() -- the function's name (the daily schedule calls it)
returns integer -- how many offers it made
language plpgsql security definer -- reads and writes locked-down tables
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_today date := (now() at time zone 'Australia/Adelaide')::date; -- today in Adelaide
  v_price int; -- the price in cents
  v_gst boolean; -- whether it includes GST
  v_count integer := 0; -- offers made
  r record; -- each student due an offer
  v_offer uuid; -- the new offer
begin -- start of the steps
  select amount_cents, gst_applies into v_price, v_gst -- reads the price
  from public.billing_price_items -- from billing's price list (read only)
  where code = 'term_review' and active and amount_cents > 0; -- only once it's in use with a price

  if v_price is not null then -- with a price set:
    for r in -- for each student
      select st.id as student_id, st.full_name, e.period_kind, e.period_label, e.period_starts_on, e.period_ends_on -- with what the review would cover
      from public.students st -- from all students
      cross join lateral private.term_review_next_end(st.id, v_today) e -- whose term or booking ends in the next 4 weeks
      where exists (select 1 from public.tutor_assignments ta -- who have a tutor now
                    where ta.student_id = st.id and private.assignment_is_current(ta.starts_on, ta.ends_on) -- (current)
                      and exists (select 1 from public.session_notes n -- who has written a session note
                                  where n.student_id = st.id and n.tutor_id = ta.tutor_id -- for this student
                                    and n.session_date >= e.period_starts_on)) -- in the period
        and not coalesce((select b.paused from public.billing_accounts b where b.family_id = st.family_id), false) -- whose family isn't on hold for an unpaid invoice
        and not exists (select 1 from public.term_review_offers o -- and who hasn't had an offer
                        where o.student_id = st.id -- for this student
                          and o.period_ends_on between e.period_ends_on - 21 and e.period_ends_on + 21) -- for about the same end (within 3 weeks)
    loop -- (start of the loop)
      v_offer := null; -- clears the last offer's id
      insert into public.term_review_offers (student_id, period_kind, period_label, period_starts_on, period_ends_on, price_cents, gst_applies) -- makes the offer
      values (r.student_id, r.period_kind, r.period_label, r.period_starts_on, r.period_ends_on, v_price, v_gst) -- with the period and today's price
      on conflict do nothing -- unless one is already there
      returning id into v_offer; -- keeps the new offer's id
      if v_offer is not null then -- a new offer:
        v_count := v_count + 1; -- counts it
        insert into public.progress_notices (account_id, student_id, offer_id, kind, title, body, deliver_at) -- tells the family
        select f.account_id, r.student_id, v_offer, 'review_offer', -- an offer notice to each person who answers
               left('Term review for ' || private.first_name(r.full_name) || '?', 200), -- titled "Term review for Cara?"
               left(format('Would you like a written review from %s''s tutor for %s? It covers how it went, skills at the start and now, ' -- what's on offer
                           || 'and what to focus on next, and CLG checks it before you see it. The price is $%s%s. ' -- the price
                           || 'Choose yes or no on %s''s progress page by %s. If you don''t answer, no review is written and nothing is charged.', -- how to answer, and that silence costs nothing
                           private.first_name(r.full_name), -- (the student's first name)
                           case when r.period_kind = 'booking_end' then 'the sessions to ' || to_char(r.period_ends_on, 'FMDD Mon') else r.period_label end, -- (the period in words)
                           to_char(v_price / 100.0, 'FM999990.00'), -- (the price in dollars)
                           case when v_gst then ' including GST' else '' end, -- (and whether GST is included)
                           private.first_name(r.full_name), -- (the first name again)
                           to_char(r.period_ends_on, 'FMDD Mon')), 1000), -- (and the last day to answer)
               now() -- sent now (the quiet hours rule holds it overnight)
        from private.term_review_family(r.student_id) f -- for each person who answers for this student
        on conflict do nothing; -- never twice
      end if; -- end of the new-offer step
    end loop; -- end of the loop
  end if; -- end of the price check

  perform private.make_term_review_draft(o.id) -- makes a draft for
  from public.term_review_offers o -- each offer
  where o.answer = 'yes' and o.period_ends_on >= v_today - 14 -- with a recent "yes"
    and not exists (select 1 from public.term_reviews tr where tr.offer_id = o.id); -- that has no review yet (no tutor when they said yes)
  return v_count; -- gives back how many offers were made
end; -- end of the steps
$$; -- end of the function
revoke all on function private.queue_term_reviews() from public; -- only the daily schedule runs it

-- ---------------------------------------------------------------------------
-- 6. Progress: the family's answer
-- ---------------------------------------------------------------------------

-- The family says yes or no. CLG front desk and finance admins can answer
-- for them, and finance admins can give it at no charge. A "yes" asks
-- billing for an invoice (at the offered price) and makes the tutor's
-- draft. Gives back the invoice number, if one was made.
create or replace function public.answer_term_review_offer(p_offer uuid, p_yes boolean, p_no_charge boolean default false) -- takes the offer, yes or no, and "no charge"
returns text -- the invoice number (or nothing)
language plpgsql security definer -- writes locked-down tables after its own checks
set search_path = '' -- only fully named tables, for safety
as $$ -- the function's body
declare -- values used along the way:
  v_o public.term_review_offers; -- the offer
  v_today date := (now() at time zone 'Australia/Adelaide')::date; -- today in Adelaide
  v_free boolean := coalesce(p_no_charge, false); -- whether it's at no charge
  v_student public.students; -- the student
  v_invoice uuid; -- the invoice billing made
  v_number text; -- its number
begin -- start of the steps
  select * into v_o from public.term_review_offers where id = p_offer for update; -- reads the offer, holding it while it changes
  if v_o.id is null or not (private.is_front_desk() or private.is_finance_admin() -- no such offer, or the person isn't a CLG admin
                            or private.can_answer_term_review(v_o.student_id)) then -- or the family member who answers:
    raise exception 'Offer not found' using errcode = 'P0002'; -- says it wasn't found (without saying whether it exists)
  end if; -- end of that check
  if p_yes is null then -- no answer given:
    raise exception 'Please choose yes or no' using errcode = '22023'; -- asks for one
  end if; -- end of that check
  if v_free and not private.is_finance_admin() then -- "no charge" from someone who isn't a finance admin:
    raise exception 'Only CLG''s owner, operations or finance admins can give a review at no charge' using errcode = '42501'; -- refuses
  end if; -- end of that check
  if v_free and not p_yes then -- "no charge" with a "no":
    raise exception 'No charge only goes with a yes' using errcode = '22023'; -- refuses
  end if; -- end of that check
  if v_o.answer = 'yes' then -- already a "yes":
    raise exception 'This review is already booked. To change it, please contact CLG.' using errcode = '22023'; -- refuses (it may already be invoiced)
  end if; -- end of that check
  if v_today > v_o.period_ends_on then -- after the end date:
    raise exception 'This offer has closed' using errcode = '22023'; -- refuses
  end if; -- end of that check

  if not p_yes then -- a "no":
    update public.term_review_offers -- records it
    set answer = 'no', answered_by = auth.uid(), answered_at = now() -- with who and when
    where id = p_offer; -- for this offer
    return null; -- nothing is charged
  end if; -- end of the "no" case

  select * into v_student from public.students where id = v_o.student_id; -- reads the student
  if not v_free then -- unless CLG gave it free:
    v_invoice := private.billing_charge_once( -- asks billing to charge:
      v_student.family_id, v_student.id, 'term_review', -- the student's family, for this student, as a term review
      'Term review, ' || v_o.period_label || ', ' || private.first_name(v_student.full_name), -- with these words on the invoice
      private.term_review_due_on(v_o.period_ends_on), v_o.price_cents, v_o.gst_applies); -- dated when it's due, at the offered price
  end if; -- end of the charge step
  update public.term_review_offers -- records the "yes"
  set answer = 'yes', no_charge = v_free, answered_by = auth.uid(), answered_at = now(), invoice_id = v_invoice -- with who, when and the invoice
  where id = p_offer; -- for this offer
  perform private.make_term_review_draft(p_offer); -- makes the tutor's draft
  select number into v_number from public.billing_invoices where id = v_invoice; -- reads the invoice number (read only)

  insert into public.progress_notices (account_id, student_id, offer_id, kind, title, body, deliver_at) -- tells CLG's admins
  select a.account_id, v_student.id, p_offer, 'review_booked', -- a "review booked" notice
         left('Term review booked: ' || v_student.full_name, 200), -- titled with the student's name
         left(v_o.period_label || '. ' || case -- with the period and how it's paid:
           when v_free then 'Given at no charge.' -- free,
           when v_number is not null then 'On invoice ' || v_number || '.' -- on an invoice,
           else 'This family has no billing account yet, so please bill it by hand.' end, 1000), -- or to bill by hand
         now() -- sent now (the quiet hours rule holds it overnight)
  from (select distinct account_id from public.account_roles where role = 'admin') a -- to each admin
  where a.account_id is distinct from auth.uid() -- other than the admin who answered
  on conflict do nothing; -- never twice
  return v_number; -- gives back the invoice number
end; -- end of the steps
$$; -- end of the function
revoke all on function public.answer_term_review_offer(uuid, boolean, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.answer_term_review_offer(uuid, boolean, boolean) to authenticated; -- signed-in people (it checks who they are)

-- ---------------------------------------------------------------------------
-- 7. The old add-on and monthly summaries
-- ---------------------------------------------------------------------------

-- The "Term reviews" add-on is replaced by the price item. It is removed
-- only if no student was given it, so nothing an admin set up is lost.
delete from public.add_ons a -- removes the add-on
where a.code = 'term_reviews' -- for term reviews
  and not exists (select 1 from public.add_on_members m where m.add_on = a.code); -- if no student has it

-- Monthly summaries stay off: the function makes none, and no schedule runs it.
create or replace function private.queue_monthly_summaries(p_month date default null) -- the old function's name
returns integer -- how many it made
language sql -- a one-line function
set search_path = '' -- only fully named things, for safety
as $$ select 0 $$; -- always none
revoke all on function private.queue_monthly_summaries(date) from public; -- no one calls it directly
do $$ -- a one-off block:
begin -- start
  if to_regclass('cron.job') is not null then -- if the scheduler is installed:
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'clg-monthly-summaries'$q$; -- removes the monthly summary schedule, if it's still there
  end if; -- end of that check
end; -- end
$$; -- end of the block
