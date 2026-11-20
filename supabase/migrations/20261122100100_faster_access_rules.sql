-- Summary: makes the database's access rules (row level security) much
-- faster, without changing who can see or change anything (Carla asked how
-- to keep the app fast, 18 Nov 2026).
--
-- Why it was slow: every access rule asks questions such as "is this person
-- an admin?" (private.is_admin()) or "who is signed in?" (auth.uid()). The
-- database asked those questions again for EVERY row it looked at. A parent
-- opening a page that lists sessions made the database ask "is this person
-- an admin?" once per session in the whole table, and each of those answers
-- itself needs several look-ups. As the number of sessions, notes and
-- invoices grows each week, pages got slower and slower.
--
-- The fix: wrap each of those questions in "(select ...)". This tells the
-- database to ask the question ONCE per page request and reuse the answer
-- for every row. The answer cannot change partway through one request, so
-- the rules mean exactly the same thing. This is Supabase's own advice:
-- https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select
--
-- Only questions with no row details in them are wrapped: auth.uid(),
-- auth.jwt(), every private function that takes nothing (is_admin,
-- has_aal2, is_front_desk and so on), and private.has_role('tutor') style
-- checks that name a fixed role. Questions about a particular row, such as
-- private.can_view_student(student_id), are left as they are, because their
-- answer is different for each row.
--
-- Safe to run more than once: rules already wrapped are skipped. Run it
-- again after any older update file is re-run, because re-running an older
-- file puts that file's rules back in the slow form.
--
-- Measured on a test copy with 20,000 sessions: a parent counting their
-- sessions went from about 10 seconds to well under one second. See
-- docs/features/app-speed.md.

-- ===========================================================================
-- Step 1: a helper that rewrites one access rule's wording into the fast form.
-- ===========================================================================
create or replace function private.fast_rule_text(p_rule text) -- Takes the wording of one access rule and gives back the fast wording.
returns text -- Hands back text (the rewritten rule).
language plpgsql -- Written in PL/pgSQL, so it can loop.
stable -- Only reads the database (the list of functions), never changes it.
set search_path to '' -- Uses full names only, so nobody can swap in a look-alike function.
as $$ -- Start of the helper's code.
declare -- Working values:
  v_out text := p_rule; -- the rule wording being rewritten (starts as the original),
  v_fn record; -- one function name at a time, from the list below.
begin -- Start of the steps.
  if v_out is null then -- Some rules have no "using" or no "with check" part:
    return null; -- nothing to rewrite.
  end if; -- End of the empty check.
  -- "Who is signed in" and "their sign-in details": wrap each one that is
  -- not already wrapped. "(?<!select )" means "not already straight after
  -- the word select", so a wrapped one is never wrapped twice.
  v_out := regexp_replace(v_out, '(?<!select )\mauth\.uid\(\)', '(select auth.uid())', 'gi'); -- auth.uid() becomes (select auth.uid()).
  v_out := regexp_replace(v_out, '(?<!select )\mauth\.jwt\(\)', '(select auth.jwt())', 'gi'); -- auth.jwt() becomes (select auth.jwt()).
  -- Every private function that takes nothing and only reads (never one
  -- that changes data, so nothing is skipped by asking once).
  for v_fn in -- Goes through each such function:
    select p.proname -- its name,
    from pg_catalog.pg_proc p -- from the database's list of functions,
    where p.pronamespace = 'private'::regnamespace -- in the private area,
      and p.pronargs = 0 -- taking nothing,
      and p.provolatile in ('s', 'i') -- that only read (stable) or never change (immutable),
      and p.prorettype = 'boolean'::regtype -- and that answer yes or no (the kind used in rules).
  loop -- For each one:
    v_out := regexp_replace( -- rewrite the wording:
      v_out, -- in the rule so far,
      '(?<!select )\mprivate\.' || v_fn.proname || '\(\)', -- find this function called with nothing (not already wrapped),
      '(select private.' || v_fn.proname || '())', -- and wrap it in (select ...),
      'gi'); -- everywhere it appears (in any mix of capitals, as the database writes "SELECT" in capitals).
  end loop; -- End of the function list.
  -- "Does this person hold the tutor role?" style checks that name a fixed
  -- role (the answer is the same for every row).
  v_out := regexp_replace( -- Rewrites the wording:
    v_out, -- in the rule so far,
    '(?<!select )\mprivate\.has_role\((''[a-z]+''(?:::app_role)?)\)', -- find has_role with a fixed role name, with or without its type label (not already wrapped),
    '(select private.has_role(\1))', -- and wrap it, keeping the role name,
    'gi'); -- everywhere it appears (in any mix of capitals).
  return v_out; -- Hands back the fast wording.
end; -- End of the steps.
$$; -- End of the helper's code.

revoke all on function private.fast_rule_text(text) from public, anon, authenticated; -- Only the database owner may use the helper (it is for updates, not for the app).

-- ===========================================================================
-- Step 2: rewrite every access rule in the app's own areas.
-- ===========================================================================
do $$ -- Runs the steps below once.
declare -- Working values:
  v_rule record; -- one access rule at a time,
  v_using text; -- its fast "who can see or change rows" wording,
  v_check text; -- its fast "what new rows may hold" wording,
  v_count integer := 0; -- how many rules were made faster.
begin -- Start of the steps.
  for v_rule in -- Goes through each access rule:
    select schemaname, tablename, policyname, qual, with_check -- its area, table, name and both wordings,
    from pg_catalog.pg_policies -- from the database's list of access rules,
    where schemaname in ('public', 'private', 'storage') -- in the app's areas and the file store,
    order by schemaname, tablename, policyname -- in a fixed order (so the run is the same every time).
  loop -- For each rule:
    v_using := private.fast_rule_text(v_rule.qual); -- works out its fast "using" wording,
    v_check := private.fast_rule_text(v_rule.with_check); -- and its fast "with check" wording.
    if v_using is distinct from v_rule.qual or v_check is distinct from v_rule.with_check then -- If either part changed:
      begin -- Starts a small block, so one rule that cannot be changed does not stop the rest:
        if v_using is distinct from v_rule.qual then -- If the "using" part changed:
          execute format('alter policy %I on %I.%I using (%s)', -- updates it in place (same name, same table),
            v_rule.policyname, v_rule.schemaname, v_rule.tablename, v_using); -- filling in the rule's name, area, table and new wording.
        end if; -- End of the "using" update.
        if v_check is distinct from v_rule.with_check then -- If the "with check" part changed:
          execute format('alter policy %I on %I.%I with check (%s)', -- updates it in place,
            v_rule.policyname, v_rule.schemaname, v_rule.tablename, v_check); -- filling in the rule's name, area, table and new wording.
        end if; -- End of the "with check" update.
        v_count := v_count + 1; -- Counts it as made faster.
      exception when insufficient_privilege then -- If the database does not let this login change that rule (for example a file store rule owned by Supabase):
        raise notice 'Left as it was (no permission): % on %.%', v_rule.policyname, v_rule.schemaname, v_rule.tablename; -- says which one, and carries on (the rule still works, just more slowly).
      end; -- End of the small block.
    end if; -- End of the change.
  end loop; -- End of the rules.
  raise notice 'Access rules made faster: %', v_count; -- Shows how many rules were updated (0 on a second run).
end; -- End of the steps.
$$; -- End of the run.

-- ===========================================================================
-- Step 3: indexes (look-up lists) for the columns the access rules and the
-- busiest pages search by, where none existed. Without them the database
-- reads a whole table to find a few rows.
-- ===========================================================================
-- Each index is only made when its table and column are there, so this
-- file still runs if an earlier update file has not been run yet (it says
-- which ones it skipped). Run this file again after running that update.
do $$ -- Runs the steps below once.
declare -- Working values:
  v_ix record; -- one index at a time, from the list below.
begin -- Start of the steps.
  for v_ix in -- Goes through each index to make:
    select * from (values -- the list (index name, table, column):
      ('bookings_family_id_idx', 'bookings', 'family_id'), -- Bookings by family (family pages, billing).
      ('consent_records_student_id_idx', 'consent_records', 'student_id'), -- Consent records by student (privacy pages).
      ('session_notices_session_id_idx', 'session_notices', 'session_id'), -- Session notices by session (Sessions page).
      ('session_notices_booking_id_idx', 'session_notices', 'booking_id'), -- Session notices by booking (Sessions page).
      ('billing_invoice_lines_student_id_idx', 'billing_invoice_lines', 'student_id'), -- Invoice lines by student (billing pages).
      ('billing_credits_invoice_id_idx', 'billing_credits', 'invoice_id'), -- Credits by invoice (billing pages).
      ('billing_pause_events_family_id_idx', 'billing_pause_events', 'family_id'), -- Pause history by family (billing pages).
      ('progress_notices_student_id_idx', 'progress_notices', 'student_id'), -- Progress notices by student (dashboards).
      ('student_reflections_student_id_idx', 'student_reflections', 'student_id'), -- Student reflections by student (progress pages).
      ('student_login_offers_student_id_idx', 'student_login_offers', 'student_id'), -- Own-login offers by student (parent dashboard).
      ('safety_concerns_student_id_idx', 'safety_concerns', 'student_id'), -- Child safety concerns by student (safety pages).
      ('safety_word_flags_student_id_idx', 'safety_word_flags', 'student_id'), -- Flagged words by student (safety pages).
      ('safety_holds_student_id_idx', 'safety_holds', 'student_id'), -- Safety holds by student (matching checks).
      ('match_blocks_student_id_idx', 'match_blocks', 'student_id'), -- Match blocks by student (matching checks).
      ('match_check_ins_student_id_idx', 'match_check_ins', 'student_id'), -- Match check-ins by student (check-in pages).
      ('help_messages_student_id_idx', 'help_messages', 'student_id'), -- Help chat messages by student (help chats).
      ('billing_payers_account_id_idx', 'billing_payers', 'account_id'), -- Extra bill payers by person (who sees billing).
      ('billing_accounts_bill_payer_id_idx', 'billing_accounts', 'bill_payer_id'), -- Billing accounts by bill payer (who sees billing).
      ('billing_invoice_shares_payer_id_idx', 'billing_invoice_shares', 'payer_id'), -- Invoice shares by payer (who sees billing).
      ('help_chats_started_by_idx', 'help_chats', 'started_by'), -- Help chats by the person who started them (their Help page).
      ('help_chat_reads_account_id_idx', 'help_chat_reads', 'account_id'), -- Read markers by person (the unread help number on every page).
      ('session_makeup_offers_makeup_session_id_idx', 'session_makeup_offers', 'makeup_session_id'), -- Make-up offers by make-up session (Sessions page).
      ('sessions_makeup_for_idx', 'sessions', 'makeup_for'), -- Make-up sessions by the session they replace (Sessions page).
      ('term_renewals_next_booking_id_idx', 'term_renewals', 'next_booking_id'), -- Renewals by the next booking (renewals page).
      ('employment_contracts_template_id_idx', 'employment_contracts', 'template_id'), -- Contracts by template (Contracts page).
      ('training_completions_module_id_idx', 'training_completions', 'module_id'), -- Training completions by module (training pages).
      ('training_attempts_module_id_idx', 'training_attempts', 'module_id'), -- Training attempts by module (training pages).
      ('training_progress_module_id_idx', 'training_progress', 'module_id'), -- Saved training progress by module (training pages).
      ('sessions_ends_at_idx', 'sessions', 'ends_at') -- Sessions by finishing time (the "summaries still to write" list looks at the last 30 days).
    ) as t(index_name, table_name, column_name) -- (names for the three parts)
  loop -- For each one:
    if exists ( -- if the table has that column:
      select 1 from pg_catalog.pg_attribute a -- looks in the database's list of columns
      where a.attrelid = to_regclass('public.' || quote_ident(v_ix.table_name)) -- for this table (nothing if the table is missing),
        and a.attname = v_ix.column_name -- for this column,
        and not a.attisdropped -- that has not been removed.
    ) then -- Found:
      execute format('create index if not exists %I on public.%I (%I)', -- makes the index (skipped if it is already there),
        v_ix.index_name, v_ix.table_name, v_ix.column_name); -- filling in its name, table and column.
    else -- Not found (an earlier update file has not been run yet):
      raise notice 'Skipped index % (table %, column % not there yet)', v_ix.index_name, v_ix.table_name, v_ix.column_name; -- says which one, and carries on.
    end if; -- End of the check.
  end loop; -- End of the list.
end; -- End of the steps.
$$; -- End of the run.

-- ===========================================================================
-- Step 4: the "summaries still to write" list (public.list_notes_due) is
-- worked out on EVERY page, for the to-do numbers in the menus. It had the
-- same slow pattern inside it ("is this person an admin?" asked once per
-- session), so a page took over a second on the test copy. The same
-- rewrite is applied to its code in place, so any earlier changes to it are
-- kept. Safe to run more than once.
-- ===========================================================================
do $$ -- Runs the steps below once.
declare -- Working values:
  v_def text; -- the function's current code,
  v_new text; -- its fast version.
begin -- Start of the steps.
  if to_regprocedure('public.list_notes_due()') is null then -- If the function is not there (should not happen):
    return; -- nothing to do.
  end if; -- End of the check.
  v_def := pg_catalog.pg_get_functiondef('public.list_notes_due()'::regprocedure); -- Reads its current code.
  v_new := private.fast_rule_text(v_def); -- Wraps each "same for every row" question in (select ...).
  if v_new is distinct from v_def then -- If anything changed:
    execute v_new; -- saves the fast version (the code is a full "create or replace function" statement).
    raise notice 'Summaries still to write list made faster.'; -- Says it was done.
  end if; -- End of the change.
end; -- End of the steps.
$$; -- End of the run.
