-- Summary: staff read and tick each linked policy again whenever it gets a
-- new version (Carla, 22 Nov 2026: a separate "read and understood" tick per
-- policy document linked to a contract, repeated for each new version; she
-- answered "Yes" to everyone ticking it again, even with contracts already
-- signed).
--
-- What changes (module: employment_contracts, which owns these tables):
--   * Each document staff acknowledge (Child Safe Policy, Code of Conduct,
--     the Fair Work statements) now has a version number, starting at 1,
--     and a short note of what changed.
--   * When the owner saves a document as a new version, its number goes up.
--     Every staff member whose contract includes it (signed or complete)
--     sees it again on My contract, with a number on the menu, and ticks it
--     again with their typed name. Each tick is kept, so the record shows
--     every version they read and when.
--   * Admins see who still has a new version to read.
--   * A contract's status (complete) does not change: the new tick is extra.
--
-- Safe to run more than once. Run after 20261121200200_contract_documents_in_app.sql.

-- ---------------------------------------------------------------------------
-- 1. Version numbers on documents and acknowledgements
-- ---------------------------------------------------------------------------
alter table public.employment_contract_documents add column if not exists version integer not null default 1 check (version >= 1); -- the document's version (1 to start)
alter table public.employment_contract_documents add column if not exists version_note text check (char_length(version_note) <= 500); -- what changed in the latest version (optional)
alter table public.employment_contract_documents add column if not exists version_at timestamptz; -- when the latest version was saved
alter table public.employment_contract_acknowledgements add column if not exists statement_version integer not null default 1 check (statement_version >= 1); -- which version they acknowledged (earlier ticks were version 1)
do $$ -- a one-off block
begin -- start
  if exists ( -- the key is still one tick per document per contract:
    select 1 from pg_constraint c -- (looks at the table's rules)
    where c.conrelid = 'public.employment_contract_acknowledgements'::regclass and c.contype = 'p' -- its primary key
      and pg_get_constraintdef(c.oid) not like '%statement_version%' -- without the version
  ) then -- yes:
    alter table public.employment_contract_acknowledgements drop constraint employment_contract_acknowledgements_pkey; -- removes it
    alter table public.employment_contract_acknowledgements add primary key (contract_id, statement, statement_version); -- one tick per document, per version, per contract
  end if; -- end of the check
end; -- finish
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- 2. Saving a document's wording, optionally as a new version (owner only)
-- ---------------------------------------------------------------------------
drop function if exists public.employment_contract_document_save_text(text, text, boolean); -- replaced by the version below (with two more inputs)
create or replace function public.employment_contract_document_save_text( -- saves a document's wording:
  p_key text, -- which document
  p_body text, -- its wording
  p_approved boolean, -- whether it is final
  p_new_version boolean default false, -- whether staff must read and tick it again
  p_version_note text default null -- what changed (shown to staff)
)
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change these documents.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  if coalesce(p_new_version, false) and not coalesce(p_approved, false) then -- a new version that is not final
    raise exception 'A new version must be approved (final) before staff are asked to read it again.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  update public.employment_contract_documents set -- saves:
    body = coalesce(p_body, ''), -- the wording (the table's check refuses anything too long),
    approved_at = case when coalesce(p_approved, false) then coalesce(approved_at, now()) else null end, -- approved now (or still), or back to draft,
    approved_by = case when coalesce(p_approved, false) then coalesce(approved_by, auth.uid()) else null end, -- who approved it,
    version = version + case when coalesce(p_new_version, false) then 1 else 0 end, -- the next version number, if asked
    version_note = case when coalesce(p_new_version, false) then nullif(left(btrim(coalesce(p_version_note, '')), 500), '') else version_note end, -- what changed, if a new version
    version_at = case when coalesce(p_new_version, false) then now() else version_at end, -- when, if a new version
    updated_at = now(), -- when it was changed,
    updated_by = auth.uid() -- and who changed it
  where key = p_key; -- this document
  if not found then raise exception 'That document could not be found.' using errcode = 'P0002'; end if; -- not there
end; -- end of the code
$$; -- end of employment_contract_document_save_text
revoke all on function public.employment_contract_document_save_text(text, text, boolean, boolean, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_document_save_text(text, text, boolean, boolean, text) to authenticated; -- signed-in people may try (the owner check decides)

-- A new version of a document kept outside the app (such as a Fair Work statement) (owner only).
create or replace function public.employment_contract_document_new_version(p_key text, p_version_note text default null) -- the document and what changed
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change these documents.' using errcode = '42501'; -- plain message
  end if; -- end of the check
  update public.employment_contract_documents set -- saves:
    version = version + 1, -- the next version number,
    version_note = nullif(left(btrim(coalesce(p_version_note, '')), 500), ''), -- what changed,
    version_at = now(), updated_at = now(), updated_by = auth.uid() -- when, and who
  where key = p_key; -- this document
  if not found then raise exception 'That document could not be found.' using errcode = 'P0002'; end if; -- not there
end; -- end of the code
$$; -- end of employment_contract_document_new_version
revoke all on function public.employment_contract_document_new_version(text, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_document_new_version(text, text) to authenticated; -- signed-in people may try (the owner check decides)

-- ---------------------------------------------------------------------------
-- 3. Acknowledging: the current version, also after the contract is complete
-- ---------------------------------------------------------------------------
create or replace function public.employment_contract_acknowledge(p_id uuid, p_statement text, p_typed_name text) -- takes the contract, the statement and the typed name
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_c public.employment_contracts; -- the contract
begin -- start
  select * into v_c from public.employment_contracts where id = p_id and account_id = auth.uid() for update; -- reads their own contract, holding it
  if not found then raise exception 'That contract could not be found.' using errcode = 'P0002'; end if; -- not theirs, or not there
  if v_c.status not in ('signed', 'complete') then -- not signed yet, or withdrawn
    raise exception 'Please sign the contract first.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then -- not signed in with two-step login
    raise exception 'Please sign in with two-step login first.' using errcode = '42501'; -- says what to do
  end if; -- end of the check
  if not (p_statement = any (v_c.statements)) then -- this contract does not need that document
    raise exception 'That document is not part of this contract.' using errcode = '22023'; -- plain message
  end if; -- end of the check
  if not private.contract_same_name(p_typed_name, (select full_name from public.accounts where id = auth.uid())) then -- the typed name does not match their name
    raise exception 'Please type your full name exactly as it shows on the page.' using errcode = '22023'; -- asks for it
  end if; -- end of the check
  if not exists (select 1 from public.employment_contract_documents d where d.key = p_statement) then -- the document has gone from the list
    raise exception 'That document could not be found. Please ask CLG.' using errcode = 'P0002'; -- plain message
  end if; -- end of the check
  insert into public.employment_contract_acknowledgements (contract_id, statement, statement_version, statement_title, statement_url, typed_name) -- records the acknowledgement
  select p_id, d.key, d.version, d.title, d.url, btrim(p_typed_name) from public.employment_contract_documents d where d.key = p_statement -- the document, its version, name and link now, and the typed name
  on conflict (contract_id, statement, statement_version) do nothing; -- already acknowledged this version: keeps the first record
  if v_c.status = 'signed' and (select count(distinct a.statement) from public.employment_contract_acknowledgements a where a.contract_id = p_id) >= cardinality(v_c.statements) then -- every document is now acknowledged
    update public.employment_contracts set status = 'complete', completed_at = now() where id = p_id; -- the contract is complete
  end if; -- end of the check
end; -- end of the code
$$; -- end of employment_contract_acknowledge
revoke all on function public.employment_contract_acknowledge(uuid, text, text) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_acknowledge(uuid, text, text) to authenticated; -- signed-in people may try (the checks decide)

-- ---------------------------------------------------------------------------
-- 4. Which new versions are still to be read
-- ---------------------------------------------------------------------------
-- Every contract and document where the staff member acknowledged an older
-- version than the current one. Only contracts that are signed or complete
-- count (a contract still to sign asks for the current version anyway).
create or replace view private.policy_rereads as -- the list
  select c.id as contract_id, c.account_id, c.staff_name, d.key as statement, d.title, d.version, d.version_note, d.version_at, -- the contract, person and document,
         max(a.statement_version) as read_version -- and the newest version they ticked
  from public.employment_contracts c -- from the contracts
  join public.employment_contract_documents d on d.key = any (c.statements) -- each document the contract needs
  join public.employment_contract_acknowledgements a on a.contract_id = c.id and a.statement = d.key -- that they have ticked before
  where c.status in ('signed', 'complete') -- signed contracts only
  group by c.id, c.account_id, c.staff_name, d.key, d.title, d.version, d.version_note, d.version_at -- one row per contract and document
  having max(a.statement_version) < d.version; -- where a newer version is waiting
revoke all on private.policy_rereads from public; -- inside use only

-- How many new versions the signed-in staff member has to read (for the menu number).
create or replace function public.my_policy_rereads_count() -- no inputs
returns integer -- the number
language sql stable security definer -- reads the list for them
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
  select count(*)::integer from private.policy_rereads r where r.account_id = auth.uid(); -- their own only
$$; -- end of the function
revoke all on function public.my_policy_rereads_count() from public, anon; -- not for signed-out visitors
grant execute on function public.my_policy_rereads_count() to authenticated; -- signed-in people (they only see their own)

-- Who still has a new version to read (owner and Operations admins).
create or replace function public.policy_rereads_outstanding() -- no inputs
returns table (contract_id uuid, staff_name text, title text, version integer, version_at timestamptz) -- one row per person and document
language plpgsql stable security definer -- reads the list for them; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_admin() then -- only the owner and Operations admins
    raise exception 'Only CLG admins can see this list' using errcode = '42501'; -- plain message for anyone else
  end if; -- end of the check
  return query select r.contract_id, r.staff_name, r.title, r.version, r.version_at -- hands back each one
    from private.policy_rereads r order by r.version_at nulls first, r.staff_name; -- oldest first
end; -- end of the code
$$; -- end of the function
revoke all on function public.policy_rereads_outstanding() from public, anon; -- not for signed-out visitors
grant execute on function public.policy_rereads_outstanding() to authenticated; -- signed-in people (the check is inside)
