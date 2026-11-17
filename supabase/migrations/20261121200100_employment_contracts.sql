-- Employment contracts (module: employment_contracts). Carla, 17 Nov 2026.
--
-- "Please ensure things like [Tutor name] can be auto filled, and what can't
-- be auto filled can be filled in by writing in the needed information from
-- an admin standpoint within the app then sent to them."
--
-- What this file adds:
--   1. Contract templates, one set per contract type (tutor casual, tutor
--      part-time or full-time, and later admin staff). Each template has
--      versions: the owner writes a draft, then publishes it. Only one
--      version of each type is in use at a time. Gaps in the wording are
--      written in square brackets, as in the contract documents, for
--      example [Tutor name], or in double curly brackets, {{Tutor name}}.
--      Gaps such as [Tutor name] fill in by themselves; any other gap
--      becomes a box the admin types into when sending. A gap ending in
--      ", or Not applicable" (or any ", or ..." words) may be left empty,
--      and then shows those words; a gap ending in "?" shows "Not
--      applicable". The same gap words always get the same value, so gaps
--      that need different values need different words (for example
--      [School rate] and [Tertiary rate]). The owner can paste a contract
--      straight from its Claude Doc (Export > Markdown).
--   2. Sent contracts. The owner or an Operations admin picks a staff
--      member and a template, types in the gaps, and sends it. The finished
--      wording is saved exactly as sent, with a fingerprint (SHA-256), so
--      what the staff member signs can never change afterwards.
--   3. Signing. The staff member reads the contract in the app, types their
--      full name, ticks that they agree to sign electronically, and presses
--      "Sign and accept". This needs two-step login, so the signature can
--      only come from them (Electronic Transactions Act 1999 (Cth) s 10 and
--      Electronic Communications Act 2000 (SA) s 9: a method that identifies
--      the person and shows they intend to sign, reliable for the purpose,
--      with their consent to sign electronically).
--   4. Acknowledgements. After signing, they open and acknowledge each
--      linked document, with their typed name and the date: the Fair Work
--      Information Statement (everyone), the Casual Employment Information
--      Statement (casual staff), the Child Safe Policy and the Staff Code of
--      Conduct (everyone). Fair Work accepts giving its statements as a link
--      to its website. The owner can change a document's link (for example
--      when the policies move into the app).
--   5. Pay as further acceptance. The record keeps that this notice was
--      shown, and a function lets admins see the first pay sent to Xero
--      after the contract was sent (backup evidence of acceptance).
--   6. A Xero step. Xero's employee self-setup invite can only be sent from
--      inside Xero, so once everything is signed the contract shows a to-do
--      for an admin to send it, which they tick off here.
--
-- Who can do what:
--   Owner: everything, including writing and publishing templates.
--   Operations: send and withdraw contracts, see all contracts.
--   Finance: see contracts and tick off the Xero step (read only otherwise).
--   Staff member: sees and signs only their own contracts.
-- Two-step login is needed for every admin action (the admin checks below
-- include it) and for signing.
--
-- This module writes only its own tables. It reads accounts, account_private,
-- account_roles and billing_pay_lines (reading only).
-- See docs/features/employment-contracts.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Contract templates.
-- ---------------------------------------------------------------------------
create table if not exists public.employment_contract_templates ( -- one row per version of a contract template
  id uuid primary key default gen_random_uuid(), -- its id
  contract_type text not null check (contract_type in ('tutor_casual', 'tutor_permanent', 'admin_casual', 'admin_permanent')), -- which kind of contract it is
  version integer not null check (version >= 1), -- its version number within that kind (1, 2, 3 and so on)
  title text not null check (char_length(btrim(title)) between 3 and 200), -- its title, shown at the top of the contract
  body text not null check (char_length(body) between 1 and 100000), -- the wording, with [gaps] to fill in
  status text not null default 'draft' check (status in ('draft', 'published', 'retired')), -- draft (being written), published (in use) or retired (replaced)
  created_at timestamptz not null default now(), -- when this version was started
  updated_at timestamptz not null default now(), -- when it was last changed
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed it
  published_at timestamptz, -- when it was published (empty for drafts)
  published_by uuid references public.accounts (id) on delete set null, -- who published it
  unique (contract_type, version) -- each version number is used once per kind
); -- end of employment_contract_templates
create unique index if not exists employment_contract_templates_one_live on public.employment_contract_templates (contract_type) where status = 'published'; -- only one version of each kind is in use at a time
create unique index if not exists employment_contract_templates_one_draft on public.employment_contract_templates (contract_type) where status = 'draft'; -- only one draft of each kind at a time, so nobody edits two copies
alter table public.employment_contract_templates enable row level security; -- turns on access rules
revoke all on public.employment_contract_templates from anon; -- people who are not signed in get nothing
revoke insert, update, delete, truncate on public.employment_contract_templates from authenticated; -- changes only go through the functions below
drop trigger if exists audit on public.employment_contract_templates; -- removes the old change log trigger (so this file can run twice)
create trigger audit after insert or update or delete on public.employment_contract_templates -- logs each change to a template
  for each row execute function private.audit_change(); -- using the shared change log

-- Owner and Operations admins can read templates (to send them); Finance
-- admins can too, so they can see what staff were offered.
drop policy if exists "admins read contract templates" on public.employment_contract_templates; -- removes the old rule (so this file can run twice)
create policy "admins read contract templates" on public.employment_contract_templates -- reading templates
  for select to authenticated using (private.is_admin() or private.is_pay_admin()); -- owner, Operations or Finance (both checks include two-step login)

-- ---------------------------------------------------------------------------
-- 2. Sent contracts.
-- ---------------------------------------------------------------------------
create table if not exists public.employment_contracts ( -- one row per contract sent to a staff member
  id uuid primary key default gen_random_uuid(), -- its id
  account_id uuid references public.accounts (id) on delete set null, -- the staff member (kept empty if their account is ever deleted)
  staff_name text not null check (char_length(staff_name) between 1 and 200), -- their full name when it was sent (kept even if the account goes)
  staff_email text not null check (char_length(staff_email) between 3 and 254), -- their app email when it was sent
  template_id uuid references public.employment_contract_templates (id) on delete set null, -- the template version it came from
  contract_type text not null check (contract_type in ('tutor_casual', 'tutor_permanent', 'admin_casual', 'admin_permanent')), -- which kind of contract
  template_version integer not null, -- the template's version number, kept for the record
  employment text not null check (employment in ('casual', 'part_time', 'full_time')), -- casual, part-time or full-time
  title text not null, -- the contract's title as sent
  filled_values jsonb not null default '{}' check (jsonb_typeof(filled_values) = 'object'), -- every gap and what it was filled with
  body text not null, -- the finished wording exactly as sent (never changes)
  body_sha256 text not null check (body_sha256 ~ '^[0-9a-f]{64}$'), -- the fingerprint of that wording, to prove it has not changed
  statements text[] not null, -- the documents they must acknowledge after signing (keys from employment_contract_documents)
  status text not null default 'sent' check (status in ('sent', 'signed', 'complete', 'withdrawn')), -- sent, signed (documents still to acknowledge), complete, or withdrawn
  sent_at timestamptz not null default now(), -- when it was sent
  sent_by uuid references public.accounts (id) on delete set null, -- the admin who sent it
  sent_by_name text not null, -- that admin's name, kept for the record
  signed_at timestamptz, -- when they signed it
  signed_name text check (char_length(signed_name) <= 200), -- the full name they typed as their signature
  signed_consent_electronic boolean, -- they agreed to sign electronically
  signed_aal text check (signed_aal in ('aal2')), -- how they were signed in when signing (always two-step login)
  pay_notice_shown boolean not null default false, -- the "receiving pay is further acceptance" notice was shown to them when signing
  completed_at timestamptz, -- when the last document was acknowledged
  withdrawn_at timestamptz, -- when an admin withdrew it (or it was replaced by a newer one)
  withdrawn_by uuid references public.accounts (id) on delete set null, -- who withdrew it
  withdrawn_reason text check (char_length(withdrawn_reason) <= 500), -- why it was withdrawn
  xero_invite_at timestamptz, -- when an admin recorded sending the Xero self-setup invite
  xero_invite_by uuid references public.accounts (id) on delete set null -- who recorded it
); -- end of employment_contracts
create index if not exists employment_contracts_person on public.employment_contracts (account_id, sent_at desc); -- quick "this person's contracts, newest first"
create index if not exists employment_contracts_status on public.employment_contracts (status, sent_at desc); -- quick admin list by status
alter table public.employment_contracts enable row level security; -- turns on access rules
revoke all on public.employment_contracts from anon; -- people who are not signed in get nothing
revoke insert, update, delete, truncate on public.employment_contracts from authenticated; -- changes only go through the functions below
drop trigger if exists audit on public.employment_contracts; -- removes the old change log trigger (so this file can run twice)
create trigger audit after insert or update or delete on public.employment_contracts -- logs each change to a contract
  for each row execute function private.audit_change(); -- using the shared change log

-- The owner, Operations and Finance admins see every contract; each staff
-- member sees only their own.
drop policy if exists "admins and the staff member read contracts" on public.employment_contracts; -- removes the old rule (so this file can run twice)
create policy "admins and the staff member read contracts" on public.employment_contracts -- reading contracts
  for select to authenticated -- for signed-in people
  using (private.is_admin() or private.is_pay_admin() or account_id = auth.uid()); -- admins (with two-step login), or the staff member it was sent to

-- ---------------------------------------------------------------------------
-- 3. Acknowledgements of the linked documents.
-- ---------------------------------------------------------------------------
create table if not exists public.employment_contract_acknowledgements ( -- one row per document acknowledged
  contract_id uuid not null references public.employment_contracts (id) on delete cascade, -- the contract it belongs to
  statement text not null check (char_length(statement) between 1 and 40), -- which document (a key from employment_contract_documents)
  statement_title text not null, -- the document's name at the time
  statement_url text not null, -- the link they were given
  typed_name text not null check (char_length(typed_name) <= 200), -- the full name they typed
  acknowledged_at timestamptz not null default now(), -- when they acknowledged it
  primary key (contract_id, statement) -- each document once per contract
); -- end of employment_contract_acknowledgements
alter table public.employment_contract_acknowledgements enable row level security; -- turns on access rules
revoke all on public.employment_contract_acknowledgements from anon; -- people who are not signed in get nothing
revoke insert, update, delete, truncate on public.employment_contract_acknowledgements from authenticated; -- changes only go through the functions below
drop trigger if exists audit on public.employment_contract_acknowledgements; -- removes the old change log trigger (so this file can run twice)
create trigger audit after insert or update or delete on public.employment_contract_acknowledgements -- logs each acknowledgement
  for each row execute function private.audit_change(); -- using the shared change log
drop policy if exists "admins and the staff member read acknowledgements" on public.employment_contract_acknowledgements; -- removes the old rule (so this file can run twice)
create policy "admins and the staff member read acknowledgements" on public.employment_contract_acknowledgements -- reading acknowledgements
  for select to authenticated -- for signed-in people
  using (exists (select 1 from public.employment_contracts c where c.id = contract_id)); -- whoever can see the contract (the rule above decides)

-- ---------------------------------------------------------------------------
-- Helpers.
-- ---------------------------------------------------------------------------

-- The documents staff acknowledge after signing, with their links. The
-- owner can change a link or name here; each acknowledgement keeps the name
-- and link it was given at the time.
create table if not exists public.employment_contract_documents ( -- one row per document
  key text primary key check (key ~ '^[a-z_]{2,40}$'), -- its short key, for example fwis
  title text not null check (char_length(btrim(title)) between 3 and 200), -- its name
  url text not null check (url ~ '^(https://|/)' and char_length(url) <= 500), -- its link (a web address, or a page in this app)
  casual_only boolean not null default false, -- only casual staff acknowledge it
  sort integer not null default 0, -- its place in the list
  updated_at timestamptz not null default now(), -- when it was last changed
  updated_by uuid references public.accounts (id) on delete set null -- who last changed it
); -- end of employment_contract_documents
alter table public.employment_contract_documents enable row level security; -- turns on access rules
revoke all on public.employment_contract_documents from anon; -- people who are not signed in get nothing
revoke insert, update, delete, truncate on public.employment_contract_documents from authenticated; -- changes only go through the function below
drop policy if exists "signed-in people read contract documents" on public.employment_contract_documents; -- removes the old rule (so this file can run twice)
create policy "signed-in people read contract documents" on public.employment_contract_documents -- reading the list
  for select to authenticated using (true); -- anyone signed in (it holds only public names and links)
drop trigger if exists audit on public.employment_contract_documents; -- removes the old change log trigger (so this file can run twice)
create trigger audit after insert or update or delete on public.employment_contract_documents -- logs each change
  for each row execute function private.audit_change(); -- using the shared change log
insert into public.employment_contract_documents (key, title, url, casual_only, sort) values -- the starting documents:
  ('fwis', 'Fair Work Information Statement', 'https://www.fairwork.gov.au/employment-conditions/information-statements/fair-work-information-statement', false, 1), -- for everyone (Fair Work Act s 125)
  ('ceis', 'Casual Employment Information Statement', 'https://www.fairwork.gov.au/employment-conditions/information-statements/casual-employment-information-statement', true, 2), -- for casual staff (Fair Work Act s 125B)
  ('child_safe_policy', 'CLG Child Safe Policy', 'https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC', false, 3), -- CLG's Child Safe Policy (link moves to an app page later)
  ('code_of_conduct', 'CLG Staff Code of Conduct', 'https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz', false, 4) -- CLG's Staff Code of Conduct (link moves to an app page later)
on conflict (key) do nothing; -- leaves any the owner has changed alone (so this file can run twice)

-- Changes a document's name or link (owner only).
create or replace function public.employment_contract_document_save(p_key text, p_title text, p_url text) -- takes the document, its new name and link
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change these documents.' using errcode = '42501'; -- plain message
  end if;
  update public.employment_contract_documents set title = btrim(p_title), url = btrim(p_url), updated_at = now(), updated_by = auth.uid() where key = p_key; -- saves it (the table's checks refuse a bad link)
  if not found then raise exception 'That document could not be found.' using errcode = 'P0002'; end if; -- not there
end;
$$; -- end of employment_contract_document_save
revoke all on function public.employment_contract_document_save(text, text, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_document_save(text, text, text) to authenticated; -- signed-in people may try (the owner check decides)

-- Turns a gap's words into its key: lower case letters and numbers joined
-- by single underscores, so [Tutor name], {{tutor_name}} and [ Tutor  Name ]
-- are the same gap, and [$ rate] becomes "rate".
create or replace function private.contract_gap_key(p_words text) -- takes the words inside the brackets
returns text language sql immutable set search_path = '' -- gives back the key, always the same
as $$ select coalesce(nullif(btrim(regexp_replace(lower(coalesce(p_words, '')), '[^a-z0-9]+', '_', 'g'), '_'), ''), 'gap') $$; -- lower case; anything else becomes one underscore; underscores trimmed from the ends ("gap" if nothing is left)

-- Compares two names loosely (case and extra spaces do not matter), for
-- checking a typed signature matches the person's name.
create or replace function private.contract_same_name(p_a text, p_b text) -- takes two names
returns boolean language sql immutable set search_path = '' -- gives back yes or no
as $$ select lower(regexp_replace(btrim(coalesce(p_a, '')), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(coalesce(p_b, '')), '\s+', ' ', 'g')) and btrim(coalesce(p_a, '')) <> '' $$; -- same letters once spaces are tidied and case ignored, and not blank

-- The gaps that fill in by themselves for one staff member. Any of these
-- words can be used inside {{ }} in a template.
create or replace function private.contract_auto_values(p_account uuid, p_employment text) -- takes the staff member and their employment type
returns jsonb language sql stable security definer -- gives back a bundle of gap keys and values; reads names the caller may not see directly
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select jsonb_build_object( -- builds the bundle:
    'tutor_name', a.full_name, -- {{tutor name}}: their full name
    'staff_name', a.full_name, -- {{staff name}}: the same, for admin staff contracts
    'employee_name', a.full_name, -- {{employee name}}: the same again
    'full_name', a.full_name, -- {{full name}}: the same again
    'first_name', coalesce(nullif(btrim(a.first_name), ''), split_part(a.full_name, ' ', 1)), -- {{first name}}: their first name (or the first word of their full name)
    'last_name', coalesce(nullif(btrim(a.last_name), ''), nullif(regexp_replace(a.full_name, '^\S+\s*', ''), ''), ''), -- {{last name}}: their last name (or the rest of their full name)
    'email', p.email, -- {{email}}: their app email
    'tutor_email', p.email, -- [Tutor email]: the same
    'staff_email', p.email, -- [Staff email]: the same
    'app_email', p.email, -- [App email]: the same
    'phone', coalesce(p.phone, ''), -- {{phone}}: their phone (blank if none)
    'employment_type', case p_employment when 'casual' then 'Casual' when 'part_time' then 'Part-time' when 'full_time' then 'Full-time' end, -- {{employment type}}: in words
    'full_time_or_part_time', case p_employment when 'casual' then 'Casual' when 'part_time' then 'Part-time' when 'full_time' then 'Full-time' end, -- [Full-time or Part-time]: the same
    'part_time_or_full_time', case p_employment when 'casual' then 'Casual' when 'part_time' then 'Part-time' when 'full_time' then 'Full-time' end, -- [Part-time or Full-time]: the same
    'date_sent', to_char((now() at time zone 'Australia/Adelaide')::date, 'FMDD FMMonth YYYY'), -- {{date sent}}: today in Adelaide, for example 17 November 2026
    'clg_name', 'CLG Tutoring', -- CLG Tutoring: CLG's legal name for contracts
    'clg_abn', '61 247 841 912', -- 61 247 841 912: CLG's ABN
    'clg_signatory', 'Carla Gore, Director' -- {{clg signatory}}: who signs for CLG
  ) -- end of the bundle
  from public.accounts a -- from their account
  left join public.account_private p on p.account_id = a.id -- with their contact details
  where a.id = p_account -- just this person
$$; -- end of contract_auto_values
revoke all on function private.contract_auto_values(uuid, text) from public; -- only the database's own functions use it

-- Fills the gaps in a template's wording. Gives back the finished wording,
-- the values used, and the words of any required gaps left empty. A gap is
-- [words] (also written \[words\] when pasted from a Markdown export) or
-- {{words}}; square brackets straight before "(" are a link, not a gap.
create or replace function private.contract_fill(p_body text, p_values jsonb) -- takes the wording and every value (automatic and typed)
returns table (body text, used jsonb, missing text[]) -- gives back the finished wording, what was used, and what is missing
language plpgsql immutable -- same answer for the same inputs
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_body text := p_body; -- the wording being filled in
  v_used jsonb := '{}'; -- the gaps found and the value each got
  v_missing text[] := '{}'; -- required gaps with no value
  v_match text[]; -- one gap found: the whole gap, its words in curly brackets, or its words in square brackets
  v_words text; -- the gap's words
  v_fallback text; -- what an optional gap shows when left empty (none if required)
  v_key text; -- the gap's key
  v_value text; -- the value it gets
begin
  for v_match in select regexp_matches(p_body, '(\{\{\s*([^{}]+?)\s*\}\}|\\?\[([^][\\]+?)\\?\](?!\())', 'g') loop -- each gap in the wording
    v_words := btrim(coalesce(v_match[2], v_match[3])); -- its words, from whichever kind of brackets
    v_fallback := null; -- required unless shown otherwise
    if v_words ~ '\?$' then -- ends with "?":
      v_fallback := 'Not applicable'; -- optional, showing "Not applicable"
      v_words := btrim(regexp_replace(v_words, '\?$', '')); -- the words without the "?"
    elsif v_words ~* ',\s*or\s+\S' then -- ends with ", or ...":
      v_fallback := btrim(substring(v_words from '(?i),\s*or\s+(.+)$')); -- optional, showing the words after "or"
      v_words := btrim(regexp_replace(v_words, '(?i),\s*or\s+.+$', '')); -- the words before ", or"
    end if;
    v_key := private.contract_gap_key(v_words); -- works out its key
    v_value := nullif(btrim(coalesce(p_values ->> v_key, '')), ''); -- looks up its value (empty counts as none)
    v_value := coalesce(v_value, v_fallback); -- an empty optional gap shows its fallback words
    if v_value is null then -- no value for a required gap
      if not (v_words = any (v_missing)) then v_missing := v_missing || v_words; end if; -- notes it once, in the template's own words
      continue; -- leaves the gap as it is and moves on
    end if;
    v_body := replace(v_body, v_match[1], v_value); -- puts the value in place of the gap (every copy of it)
    v_used := v_used || jsonb_build_object(v_key, v_value); -- records what it got
  end loop; -- end of the gaps
  return query select v_body, v_used, v_missing; -- hands back the three results
end;
$$; -- end of contract_fill

-- The documents a contract needs acknowledged, in order: every document,
-- leaving out the casual-only ones for part-time and full-time staff.
create or replace function private.contract_statements_for(p_employment text) -- takes the employment type
returns text[] language sql stable security definer set search_path = '' -- gives back the list of keys
as $$ select coalesce(array_agg(d.key order by d.sort, d.key), '{}') from public.employment_contract_documents d where p_employment = 'casual' or not d.casual_only $$; -- every document, or only those not just for casual staff

-- ---------------------------------------------------------------------------
-- Templates: saving and publishing (owner only).
-- ---------------------------------------------------------------------------

-- Saves a template's wording. Editing a draft changes it; "editing" a
-- published or retired version starts a new draft from the words given (the
-- version in use stays as it is until the draft is published). With no id,
-- starts the first draft for that kind of contract. Gives back the draft's id.
create or replace function public.employment_contract_template_save(p_id uuid, p_contract_type text, p_title text, p_body text) -- takes the template (or none), its kind, title and wording
returns uuid language plpgsql security definer -- gives back the draft's id; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_t public.employment_contract_templates; -- the template being changed (if any)
  v_type text := p_contract_type; -- the kind of contract
  v_id uuid; -- the draft's id
begin
  if not private.is_owner() then -- only the owner writes contract wording
    raise exception 'Only the owner can change contract templates.' using errcode = '42501'; -- plain message
  end if;
  if char_length(btrim(coalesce(p_title, ''))) < 3 or char_length(btrim(coalesce(p_body, ''))) < 1 then -- no title or no wording
    raise exception 'Please give the template a title and its wording.' using errcode = '22023'; -- says what is needed
  end if;
  if p_id is not null then -- an existing template
    select * into v_t from public.employment_contract_templates where id = p_id for update; -- reads it, holding it while saving
    if not found then raise exception 'That template could not be found.' using errcode = 'P0002'; end if; -- not there
    v_type := v_t.contract_type; -- its kind stays the same
    if v_t.status = 'draft' then -- a draft: change it in place
      update public.employment_contract_templates set title = btrim(p_title), body = p_body, updated_at = now(), updated_by = auth.uid() where id = p_id; -- saves the new words
      return p_id; -- hands back its id
    end if;
  end if;
  select id into v_id from public.employment_contract_templates where contract_type = v_type and status = 'draft'; -- an existing draft of this kind?
  if v_id is not null then -- yes: save into it, so there is only ever one draft
    update public.employment_contract_templates set title = btrim(p_title), body = p_body, updated_at = now(), updated_by = auth.uid() where id = v_id; -- saves the words into that draft
    return v_id; -- hands back its id
  end if;
  insert into public.employment_contract_templates (contract_type, version, title, body, updated_by) -- starts a new draft
  values (v_type, coalesce((select max(version) from public.employment_contract_templates where contract_type = v_type), 0) + 1, btrim(p_title), p_body, auth.uid()) -- the next version number for this kind
  returning id into v_id; -- keeps its id (the table's checks refuse an unknown kind)
  return v_id; -- hands back its id
end;
$$; -- end of employment_contract_template_save
revoke all on function public.employment_contract_template_save(uuid, text, text, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_template_save(uuid, text, text, text) to authenticated; -- signed-in people may try (the owner check decides)

-- Publishes a draft: it becomes the version used for new contracts, and the
-- version it replaces is retired. Contracts already sent keep their own
-- wording.
create or replace function public.employment_contract_template_publish(p_id uuid) -- takes the draft
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_t public.employment_contract_templates; -- the draft
begin
  if not private.is_owner() then -- only the owner publishes contract wording
    raise exception 'Only the owner can publish contract templates.' using errcode = '42501'; -- plain message
  end if;
  select * into v_t from public.employment_contract_templates where id = p_id for update; -- reads the draft, holding it
  if not found or v_t.status <> 'draft' then -- missing, or not a draft
    raise exception 'Only a draft can be published.' using errcode = '22023'; -- plain message
  end if;
  update public.employment_contract_templates set status = 'retired', updated_at = now() where contract_type = v_t.contract_type and status = 'published'; -- retires the version in use
  update public.employment_contract_templates set status = 'published', published_at = now(), published_by = auth.uid(), updated_at = now() where id = p_id; -- puts this one in use
end;
$$; -- end of employment_contract_template_publish
revoke all on function public.employment_contract_template_publish(uuid) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_template_publish(uuid) to authenticated; -- signed-in people may try (the owner check decides)

-- Deletes a draft that is no longer wanted (published versions are kept).
create or replace function public.employment_contract_template_discard(p_id uuid) -- takes the draft
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change contract templates.' using errcode = '42501'; -- plain message
  end if;
  delete from public.employment_contract_templates where id = p_id and status = 'draft'; -- deletes it only if it is a draft
  if not found then raise exception 'Only a draft can be deleted.' using errcode = '22023'; end if; -- nothing deleted: says why
end;
$$; -- end of employment_contract_template_discard
revoke all on function public.employment_contract_template_discard(uuid) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_template_discard(uuid) to authenticated; -- signed-in people may try (the owner check decides)

-- ---------------------------------------------------------------------------
-- Sending and withdrawing (owner and Operations admins).
-- ---------------------------------------------------------------------------

-- Fills a published template for one staff member and sends it. p_values
-- holds what the admin typed into each gap. If they already have a contract
-- waiting to be signed, that one is withdrawn and replaced. Gives back the
-- new contract's id.
create or replace function public.employment_contract_send(p_template uuid, p_account uuid, p_employment text, p_values jsonb) -- takes the template, the staff member, the employment type and the typed values
returns uuid language plpgsql security definer -- gives back the new id; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_t public.employment_contract_templates; -- the template
  v_role text; -- the role this kind of contract is for (tutor or admin)
  v_auto jsonb; -- the gaps that fill in by themselves
  v_typed jsonb := '{}'; -- the typed values, with tidied keys
  v_kv record; -- one typed value, while tidying
  v_fill record; -- the filled-in wording, values used and gaps missing
  v_title record; -- the filled-in title
  v_id uuid; -- the new contract's id
begin
  if not private.is_admin() then -- only the owner and Operations admins send contracts
    raise exception 'Only the owner or an Operations admin can send contracts.' using errcode = '42501'; -- plain message
  end if;
  select * into v_t from public.employment_contract_templates where id = p_template; -- reads the template
  if not found or v_t.status <> 'published' then -- missing, or not the version in use
    raise exception 'Choose a published contract template.' using errcode = '22023'; -- plain message
  end if;
  if (v_t.contract_type like '%_casual' and p_employment <> 'casual') -- a casual contract must be for casual work
     or (v_t.contract_type like '%_permanent' and p_employment not in ('part_time', 'full_time')) then -- and a permanent one for part-time or full-time
    raise exception 'That employment type does not match this contract. Choose casual for a casual contract, or part-time or full-time for the other.' using errcode = '22023'; -- plain message
  end if;
  v_role := split_part(v_t.contract_type, '_', 1); -- "tutor" or "admin", from the kind of contract
  if not exists (select 1 from public.account_roles r where r.account_id = p_account and r.role::text = v_role) then -- the person does not hold that role
    raise exception 'This person is not a % in the app. Add the role first, or choose a different contract.', v_role using errcode = '22023'; -- says what to do
  end if;
  if jsonb_typeof(coalesce(p_values, '{}')) <> 'object' then -- the typed values are not a bundle
    raise exception 'The details did not come through. Please try again.' using errcode = '22023'; -- plain message
  end if;
  for v_kv in select key, value from jsonb_each_text(coalesce(p_values, '{}')) loop -- each typed value
    if char_length(coalesce(v_kv.value, '')) > 2000 then -- far too long for a gap
      raise exception 'Please keep each detail under 2,000 characters.' using errcode = '22023'; -- plain message
    end if;
    v_typed := v_typed || jsonb_build_object(private.contract_gap_key(v_kv.key), btrim(coalesce(v_kv.value, ''))); -- keeps it under its tidy key
  end loop; -- end of the typed values
  v_auto := private.contract_auto_values(p_account, p_employment); -- the gaps that fill in by themselves
  if v_auto is null then -- the person was not found
    raise exception 'That staff member could not be found.' using errcode = 'P0002'; -- plain message
  end if;
  select * into v_fill from private.contract_fill(v_t.body, v_typed || v_auto); -- fills the wording (automatic values win over typed ones)
  select * into v_title from private.contract_fill(v_t.title, v_typed || v_auto); -- fills any gaps in the title too
  if cardinality(v_fill.missing) > 0 or cardinality(v_title.missing) > 0 then -- some required gaps are empty
    raise exception 'Please fill in: %.', array_to_string(v_fill.missing || v_title.missing, ', ') using errcode = '22023'; -- names them
  end if;
  update public.employment_contracts set status = 'withdrawn', withdrawn_at = now(), withdrawn_by = auth.uid(), withdrawn_reason = 'Replaced by a newer contract.' -- withdraws any contract still waiting
  where account_id = p_account and status = 'sent'; -- for this person (a signed one stays as their record)
  insert into public.employment_contracts ( -- saves the contract
    account_id, staff_name, staff_email, template_id, contract_type, template_version, employment, title, -- who, which template, which type and title,
    filled_values, body, body_sha256, statements, sent_by, sent_by_name -- the values, the wording and its fingerprint, the statements, and who sent it
  ) values ( -- with:
    p_account, v_auto ->> 'full_name', v_auto ->> 'email', v_t.id, v_t.contract_type, v_t.version, p_employment, v_title.body, -- the person, the template and the filled title,
    v_fill.used || v_title.used, v_fill.body, encode(sha256(convert_to(v_fill.body, 'UTF8')), 'hex'), private.contract_statements_for(p_employment), -- the values used, the wording, its fingerprint, and the statements needed,
    auth.uid(), coalesce((select full_name from public.accounts where id = auth.uid()), 'CLG admin') -- who sent it, and their name
  ) returning id into v_id; -- keeps the new id
  return v_id; -- hands it back
end;
$$; -- end of employment_contract_send
revoke all on function public.employment_contract_send(uuid, uuid, text, jsonb) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_send(uuid, uuid, text, jsonb) to authenticated; -- signed-in people may try (the admin check decides)

-- Withdraws a contract that has not been signed yet (for example, it had a
-- mistake). The staff member no longer sees it as waiting.
create or replace function public.employment_contract_withdraw(p_id uuid, p_reason text) -- takes the contract and why
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only the owner or an Operations admin can withdraw contracts.' using errcode = '42501'; -- plain message
  end if;
  update public.employment_contracts set status = 'withdrawn', withdrawn_at = now(), withdrawn_by = auth.uid(), withdrawn_reason = nullif(left(btrim(coalesce(p_reason, '')), 500), '') -- withdraws it, with the reason
  where id = p_id and status = 'sent'; -- only if it is still waiting to be signed
  if not found then raise exception 'Only a contract that has not been signed can be withdrawn.' using errcode = '22023'; end if; -- nothing changed: says why
end;
$$; -- end of employment_contract_withdraw
revoke all on function public.employment_contract_withdraw(uuid, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_withdraw(uuid, text) to authenticated; -- signed-in people may try (the admin check decides)

-- ---------------------------------------------------------------------------
-- Signing and acknowledging (the staff member).
-- ---------------------------------------------------------------------------

-- Signs a contract. The staff member must be signed in with two-step login,
-- type their full name as it is in the app, agree to sign electronically,
-- and have been shown the exact wording (its fingerprint must match).
create or replace function public.employment_contract_sign(p_id uuid, p_typed_name text, p_body_sha256 text, p_consent_electronic boolean, p_pay_notice_shown boolean) -- takes the contract, typed name, fingerprint seen, consent, and whether the pay notice was shown
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_c public.employment_contracts; -- the contract
begin
  select * into v_c from public.employment_contracts where id = p_id and account_id = auth.uid() for update; -- reads their own contract, holding it
  if not found then raise exception 'That contract could not be found.' using errcode = 'P0002'; end if; -- not theirs, or not there
  if v_c.status <> 'sent' then -- already signed, or withdrawn
    raise exception 'This contract is not waiting to be signed.' using errcode = '22023'; -- plain message
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then -- not signed in with two-step login
    raise exception 'Please sign in with two-step login before signing your contract.' using errcode = '42501'; -- says what to do
  end if;
  if p_body_sha256 is distinct from v_c.body_sha256 then -- the wording they saw is not the wording saved
    raise exception 'The contract has changed since you opened it. Please reload the page and read it again.' using errcode = '22023'; -- says what to do
  end if;
  if coalesce(p_consent_electronic, false) is false then -- they did not agree to sign electronically
    raise exception 'Please tick that you agree to sign electronically.' using errcode = '22023'; -- asks for it
  end if;
  if not private.contract_same_name(p_typed_name, (select full_name from public.accounts where id = auth.uid())) then -- the typed name does not match their name
    raise exception 'Please type your full name exactly as it shows on the page.' using errcode = '22023'; -- asks for it
  end if;
  update public.employment_contracts set -- records the signature:
    status = 'signed', -- signed (documents still to acknowledge)
    signed_at = now(), -- when
    signed_name = btrim(p_typed_name), -- the name they typed
    signed_consent_electronic = true, -- they agreed to sign electronically
    signed_aal = 'aal2', -- they used two-step login
    pay_notice_shown = coalesce(p_pay_notice_shown, false) -- whether the pay notice was on screen
  where id = p_id; -- this contract
end;
$$; -- end of employment_contract_sign
revoke all on function public.employment_contract_sign(uuid, text, text, boolean, boolean) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_sign(uuid, text, text, boolean, boolean) to authenticated; -- signed-in people may try (the checks decide)

-- Acknowledges one linked document after signing. Once every document the
-- contract needs is acknowledged, the contract is complete.
create or replace function public.employment_contract_acknowledge(p_id uuid, p_statement text, p_typed_name text) -- takes the contract, the statement and the typed name
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_c public.employment_contracts; -- the contract
begin
  select * into v_c from public.employment_contracts where id = p_id and account_id = auth.uid() for update; -- reads their own contract, holding it
  if not found then raise exception 'That contract could not be found.' using errcode = 'P0002'; end if; -- not theirs, or not there
  if v_c.status <> 'signed' then -- not signed yet, already complete, or withdrawn
    raise exception 'Please sign the contract first.' using errcode = '22023'; -- plain message
  end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then -- not signed in with two-step login
    raise exception 'Please sign in with two-step login first.' using errcode = '42501'; -- says what to do
  end if;
  if not (p_statement = any (v_c.statements)) then -- this contract does not need that document
    raise exception 'That document is not part of this contract.' using errcode = '22023'; -- plain message
  end if;
  if not private.contract_same_name(p_typed_name, (select full_name from public.accounts where id = auth.uid())) then -- the typed name does not match their name
    raise exception 'Please type your full name exactly as it shows on the page.' using errcode = '22023'; -- asks for it
  end if;
  insert into public.employment_contract_acknowledgements (contract_id, statement, statement_title, statement_url, typed_name) -- records the acknowledgement
  select p_id, d.key, d.title, d.url, btrim(p_typed_name) from public.employment_contract_documents d where d.key = p_statement -- the document, its name and link now, and the typed name
  on conflict (contract_id, statement) do nothing; -- already acknowledged: keeps the first record
  if not found and not exists (select 1 from public.employment_contract_acknowledgements a where a.contract_id = p_id and a.statement = p_statement) then -- the document has gone from the list
    raise exception 'That document could not be found. Please ask CLG.' using errcode = 'P0002'; -- plain message
  end if;
  if (select count(*) from public.employment_contract_acknowledgements a where a.contract_id = p_id) >= cardinality(v_c.statements) then -- every document is now acknowledged
    update public.employment_contracts set status = 'complete', completed_at = now() where id = p_id; -- the contract is complete
  end if;
end;
$$; -- end of employment_contract_acknowledge
revoke all on function public.employment_contract_acknowledge(uuid, text, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_acknowledge(uuid, text, text) to authenticated; -- signed-in people may try (the checks decide)

-- ---------------------------------------------------------------------------
-- After signing: the Xero step and the pay evidence (admins).
-- ---------------------------------------------------------------------------

-- Records that an admin sent the Xero self-setup invite (from inside Xero).
create or replace function public.employment_contract_xero_done(p_id uuid) -- takes the contract
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not (private.is_admin() or private.is_pay_admin()) then -- owner, Operations or Finance only
    raise exception 'Only the owner, an Operations admin or a Finance admin can record this.' using errcode = '42501'; -- plain message
  end if;
  update public.employment_contracts set xero_invite_at = now(), xero_invite_by = auth.uid() -- records it
  where id = p_id and status in ('signed', 'complete') and xero_invite_at is null; -- only for a signed contract, once
  if not found then raise exception 'This can only be recorded once, after the contract is signed.' using errcode = '22023'; end if; -- nothing changed: says why
end;
$$; -- end of employment_contract_xero_done
revoke all on function public.employment_contract_xero_done(uuid) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_xero_done(uuid) to authenticated; -- signed-in people may try (the admin check decides)

-- Pay sent to Xero for this staff member since the contract was sent. The
-- contract says receiving pay is further acceptance of its terms, so this
-- is backup evidence. Reads the billing module's pay lines (reading only).
create or replace function public.employment_contract_pay_evidence(p_id uuid) -- takes the contract
returns table (first_paid_work_date date, paid_lines bigint) -- gives back the first paid work day and how many paid lines
language sql stable security definer -- reads pay lines the caller may not see directly
set search_path = '' -- no hidden schema lookups (safety)
as $$
  select min(l.work_date), count(l.id) -- the first work day paid, and the number of lines
  from public.employment_contracts c -- from the contract
  join public.billing_pay_lines l on l.account_id = c.account_id -- and the staff member's pay lines
  where c.id = p_id -- this contract
    and (private.is_admin() or private.is_pay_admin()) -- only for admins who can see contracts
    and l.status = 'sent' -- only pay already sent to Xero
    and l.created_at >= c.sent_at -- worked out after the contract was sent
$$; -- end of employment_contract_pay_evidence
revoke all on function public.employment_contract_pay_evidence(uuid) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_pay_evidence(uuid) to authenticated; -- signed-in people may ask (the admin check inside decides)

-- ---------------------------------------------------------------------------
-- Starter templates (drafts for the owner to finish and publish).
-- ---------------------------------------------------------------------------
-- The final wording comes from the contract review. Until then these
-- drafts show the layout and the gaps, and cannot be sent until published.
insert into public.employment_contract_templates (contract_type, version, title, body) -- adds a starter draft
select 'tutor_casual', 1, 'CLG Casual Tutor Employment Contract', $body$# Your employment

This contract is between CLG Tutoring, ABN 61 247 841 912 (**CLG**), and **[Tutor name]** (**you**).

- **Position:** Tutor
- **Employment type:** **[Employment type]**
- **Start date:** **[Start date]**
- **School tutoring classification (Miscellaneous Award 2020):** **[Miscellaneous Award level]**
- **Tertiary tutoring classification (Educational Services (Post-Secondary Education) Award 2020):** **[Post-Secondary Award level, or Not applicable]**

# Policies that form part of this contract

You must follow CLG's [Child Safe Policy](https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC) and [Staff Code of Conduct](https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz).

# The rest of the contract

The owner pastes the final wording here before publishing: open the contract's Claude Doc, choose Export, then Markdown, and paste the whole text in place of this starter.

# Accepting this contract

You accept this contract by signing it in the CLG app. Accepting pay from CLG under this contract is also acceptance of its terms.

Signed for CLG: [CLG signatory], [Date sent]$body$ -- the starter wording
where not exists (select 1 from public.employment_contract_templates where contract_type = 'tutor_casual'); -- only if there is no casual tutor template yet (so this file can run twice)
insert into public.employment_contract_templates (contract_type, version, title, body) -- adds a second starter draft
select 'tutor_permanent', 1, 'CLG Part-time and Full-time Tutor Employment Contract', $body$# Your employment

This contract is between CLG Tutoring, ABN 61 247 841 912 (**CLG**), and **[Tutor name]** (**you**).

- **Position:** Tutor
- **Employment type:** **[Employment type]**
- **Start date:** **[Start date]**
- **Agreed hours each week:** **[Hours]**
- **School tutoring classification (Miscellaneous Award 2020):** **[Miscellaneous Award level]**
- **Tertiary tutoring classification (Educational Services (Post-Secondary Education) Award 2020):** **[Post-Secondary Award level, or Not applicable]**

# Policies that form part of this contract

You must follow CLG's [Child Safe Policy](https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC) and [Staff Code of Conduct](https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz).

# The rest of the contract

The owner pastes the final wording here before publishing: open the contract's Claude Doc, choose Export, then Markdown, and paste the whole text in place of this starter.

# Accepting this contract

You accept this contract by signing it in the CLG app. Accepting pay from CLG under this contract is also acceptance of its terms.

Signed for CLG: [CLG signatory], [Date sent]$body$ -- the starter wording
where not exists (select 1 from public.employment_contract_templates where contract_type = 'tutor_permanent'); -- only if there is no part-time or full-time tutor template yet (so this file can run twice)
