-- Contract documents inside the app (module: employment_contracts). Carla, 18 Nov 2026.
--
-- "Can these links instead be buttons which take them to the documents
-- which are within the app rather than to claude?"
--
-- The Child Safe Policy and Staff Code of Conduct now live in the app, at
-- /policies/child_safe_policy and /policies/code_of_conduct, instead of
-- linking out to Claude. The owner pastes each document's wording on the
-- Contract templates page (Export > Markdown from its Claude Doc) and ticks
-- "Approved" once it is final; until then the page shows a draft label.
-- Links in contracts that still point at the old Claude addresses open the
-- app page instead (the old addresses are kept in also_known_as), so
-- contracts already written or sent do not need changing.
--
-- Each document can also hold one link per country (Carla, 18 Nov 2026:
-- "This will eventually need to include the links for each country CLG is
-- active in"). The main link is Australia's; other countries are kept in
-- country_urls, ready for when CLG works outside Australia.
--
-- This module writes only its own tables. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- New columns: the wording, approval, and old addresses.
-- ---------------------------------------------------------------------------
alter table public.employment_contract_documents add column if not exists body text not null default '' check (char_length(body) <= 100000); -- the document's wording, for documents kept in the app (empty for outside links)
alter table public.employment_contract_documents add column if not exists approved_at timestamptz; -- when the owner marked the wording as final (empty while it is a draft)
alter table public.employment_contract_documents add column if not exists approved_by uuid references public.accounts (id) on delete set null; -- who marked it as final
alter table public.employment_contract_documents add column if not exists also_known_as text[] not null default '{}'; -- older addresses of the same document, which now open its app page
alter table public.employment_contract_documents add column if not exists country_urls jsonb not null default '{}'::jsonb check (jsonb_typeof(country_urls) = 'object'); -- links for countries other than Australia, by two-letter country code (for example {"NZ": "https://..."})

-- ---------------------------------------------------------------------------
-- Point the two CLG policies at their app pages.
-- ---------------------------------------------------------------------------
update public.employment_contract_documents -- the Child Safe Policy:
set url = '/policies/child_safe_policy', -- now opens its page in the app,
    also_known_as = array['https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC'] -- and its old Claude address opens that page too
where key = 'child_safe_policy' and url = 'https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC'; -- only if it still has the old link (keeps any change the owner made)
update public.employment_contract_documents -- the Staff Code of Conduct:
set url = '/policies/code_of_conduct', -- now opens its page in the app,
    also_known_as = array['https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz'] -- and its old Claude address opens that page too
where key = 'code_of_conduct' and url = 'https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz'; -- only if it still has the old link (keeps any change the owner made)

-- ---------------------------------------------------------------------------
-- Saving a document's wording (owner only).
-- ---------------------------------------------------------------------------
-- Saves the wording of a document kept in the app, and whether it is
-- approved (final). Changing the wording of an approved document keeps it
-- approved only if the owner ticks "Approved" again.
create or replace function public.employment_contract_document_save_text(p_key text, p_body text, p_approved boolean) -- takes the document, its wording, and whether it is final
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change these documents.' using errcode = '42501'; -- plain message
  end if;
  update public.employment_contract_documents set -- saves:
    body = coalesce(p_body, ''), -- the wording (the table's check refuses anything too long),
    approved_at = case when coalesce(p_approved, false) then coalesce(approved_at, now()) else null end, -- approved now (or still), or back to draft,
    approved_by = case when coalesce(p_approved, false) then coalesce(approved_by, auth.uid()) else null end, -- who approved it,
    updated_at = now(), -- when,
    updated_by = auth.uid() -- and who changed it
  where key = p_key; -- this document
  if not found then raise exception 'That document could not be found.' using errcode = 'P0002'; end if; -- not there
end;
$$; -- end of employment_contract_document_save_text
revoke all on function public.employment_contract_document_save_text(text, text, boolean) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_document_save_text(text, text, boolean) to authenticated; -- signed-in people may try (the owner check decides)

-- ---------------------------------------------------------------------------
-- Saving a document's links for other countries (owner only).
-- ---------------------------------------------------------------------------
-- Replaces a document's other-country links with the list given. Each
-- country is a two-letter code (such as NZ or GB) and each link must start
-- with https:// or be a page in this app (starting with /).
create or replace function public.employment_contract_document_save_country_urls(p_key text, p_urls jsonb) -- takes the document and its other-country links
returns void language plpgsql security definer -- gives back nothing; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_urls jsonb := coalesce(p_urls, '{}'::jsonb); -- the links (none if nothing was given)
begin
  if not private.is_owner() then -- only the owner
    raise exception 'Only the owner can change these documents.' using errcode = '42501'; -- plain message
  end if;
  if jsonb_typeof(v_urls) <> 'object' then -- not a list of country and link
    raise exception 'The country links could not be read. Please put one country per line.' using errcode = '22023'; -- plain message
  end if;
  if exists (select 1 from jsonb_each(v_urls) e where e.key !~ '^[A-Z]{2}$') then -- a country that is not two capital letters
    raise exception 'Each country must be a two-letter code, such as NZ or GB.' using errcode = '22023'; -- plain message
  end if;
  if exists (select 1 from jsonb_each(v_urls) e where jsonb_typeof(e.value) <> 'string' or char_length(e.value #>> '{}') > 500 or (e.value #>> '{}') !~ '^(https://|/[^/])') then -- a link that is not a web address or app page
    raise exception 'Each country link must start with https:// or be a page in this app (starting with /).' using errcode = '22023'; -- plain message
  end if;
  update public.employment_contract_documents set country_urls = v_urls, updated_at = now(), updated_by = auth.uid() where key = p_key; -- saves them
  if not found then raise exception 'That document could not be found.' using errcode = 'P0002'; end if; -- not there
end;
$$; -- end of employment_contract_document_save_country_urls
revoke all on function public.employment_contract_document_save_country_urls(text, jsonb) from public, anon; -- not for people who are not signed in
grant execute on function public.employment_contract_document_save_country_urls(text, jsonb) to authenticated; -- signed-in people may try (the owner check decides)
