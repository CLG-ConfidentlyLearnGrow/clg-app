-- Summary: proper first and last names for everyone, so staff show as real
-- names (like "Amy Swann") instead of the start of their email address
-- (like "amy.swann2000") (Carla, 15 Nov 2026).
--
-- What this adds:
--   1. Two new boxes on each account: first name and last name.
--   2. A rule that builds the full name (shown everywhere in the app) from
--      those two boxes whenever both are filled in, so every page that shows
--      a name picks up the real name with no other change.
--   3. set_my_name(): anyone signed in can set or change their own name.
--   4. set_staff_name(): the owner and operations admins can set or change
--      a tutor's or admin's name (for example, to fix a spelling).
--   5. People can no longer change their own first or last name directly in
--      the table: changes go through the two functions above, which tidy
--      the name, check it, and note who changed it in the activity log.
--
-- Staff who joined before this have no first or last name yet. The app asks
-- them for it the next time they open their dashboard.
--
-- Safe to run more than once. Run after 20261117200100_feedback.sql.
-- See docs/features/staff-names.md.

-- ---------------------------------------------------------------------------
-- 1. First and last name boxes
-- ---------------------------------------------------------------------------

-- Adds the first name box (empty until the person fills it in).
alter table public.accounts add column if not exists first_name text;
-- Adds the last name box (empty until the person fills it in).
alter table public.accounts add column if not exists last_name text;

-- Removes the first name length rule if an earlier run added it (so it can be added fresh below).
alter table public.accounts drop constraint if exists accounts_first_name_length;
-- A first name, when given, is 1 to 100 letters long once spaces at each end are trimmed.
alter table public.accounts add constraint accounts_first_name_length
  check (first_name is null or char_length(btrim(first_name)) between 1 and 100); -- (the rule itself)
-- Removes the last name length rule if an earlier run added it.
alter table public.accounts drop constraint if exists accounts_last_name_length;
-- A last name, when given, is 1 to 100 letters long once spaces at each end are trimmed.
alter table public.accounts add constraint accounts_last_name_length
  check (last_name is null or char_length(btrim(last_name)) between 1 and 100); -- (the rule itself)

-- ---------------------------------------------------------------------------
-- 2. The full name follows the first and last name
-- ---------------------------------------------------------------------------

-- Before any account is saved: if both first and last name are filled in,
-- the full name becomes "First Last". Everything in the app reads the full
-- name, so this is what makes real names show everywhere.
create or replace function private.full_name_from_parts()
returns trigger language plpgsql -- (a rule that runs on each saved row, written in SQL's programming language)
set search_path = '' -- (looks nothing up by short name, for safety)
as $$
begin
  if new.first_name is not null and new.last_name is not null then -- Both names are filled in:
    new.full_name := left(btrim(new.first_name) || ' ' || btrim(new.last_name), 200); -- the full name is "First Last" (cut to 200 letters, the full name's limit).
  end if; -- Otherwise the full name is left as it is.
  return new; -- Saves the row with that full name.
end;
$$;

-- Removes the rule from the table if an earlier run added it (so it's added once below).
drop trigger if exists full_name_from_parts on public.accounts;
-- Runs the rule above every time an account is added or changed.
create trigger full_name_from_parts before insert or update on public.accounts
  for each row execute function private.full_name_from_parts(); -- (once for each row)

-- ---------------------------------------------------------------------------
-- 3. Tidying and checking a name (shared by both functions below)
-- ---------------------------------------------------------------------------

-- Tidies one name part: trims spaces at each end and turns runs of spaces
-- into one space. Gives back nothing for a blank box.
create or replace function private.tidy_name_part(p_text text)
returns text language sql immutable -- (always gives the same answer for the same text)
set search_path = '' -- (looks nothing up by short name, for safety)
as $$
  select nullif(btrim(regexp_replace(coalesce(p_text, ''), '\s+', ' ', 'g')), ''); -- Squashes spaces, trims the ends, and treats blank as nothing.
$$;

-- Checks a tidied first and last name, with a plain message if one is wrong.
create or replace function private.check_name_parts(p_first text, p_last text)
returns void language plpgsql immutable -- (only checks; changes nothing)
set search_path = '' -- (looks nothing up by short name, for safety)
as $$
begin
  if p_first is null then -- No first name:
    raise exception 'Please enter a first name' using errcode = '22023'; -- asks for one.
  end if; -- (end of that check)
  if p_last is null then -- No last name:
    raise exception 'Please enter a last name' using errcode = '22023'; -- asks for one.
  end if; -- (end of that check)
  if char_length(p_first) > 100 or char_length(p_last) > 100 then -- Either name is too long:
    raise exception 'Please keep each name to 100 characters or fewer' using errcode = '22023'; -- asks for a shorter one.
  end if; -- (end of that check)
  if p_first ~ '[@<>]' or p_last ~ '[@<>]' then -- An email address or web code was typed instead of a name:
    raise exception 'Please enter your name, not an email address' using errcode = '22023'; -- asks for a name.
  end if; -- (end of that check)
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Changing your own name
-- ---------------------------------------------------------------------------

-- Anyone signed in sets or changes their own first and last name. The change
-- is noted in the activity log (old and new name), so a strange change can
-- be spotted later.
create or replace function public.set_my_name(p_first text, p_last text)
returns void language plpgsql security definer -- (runs with the table owner's rights, so it can save what people can't save directly)
set search_path = '' -- (looks nothing up by short name, for safety)
as $$
declare
  v_first text := private.tidy_name_part(p_first); -- The tidied first name.
  v_last text := private.tidy_name_part(p_last); -- The tidied last name.
  v_old text; -- The name before the change (for the log).
begin
  if auth.uid() is null then -- Nobody is signed in:
    raise exception 'Please sign in first' using errcode = '42501'; -- refuses.
  end if; -- (end of that check)
  perform private.check_name_parts(v_first, v_last); -- Checks the name (stops with a plain message if it's wrong).
  select full_name into v_old from public.accounts where id = auth.uid(); -- Notes their name before the change.
  update public.accounts set first_name = v_first, last_name = v_last where id = auth.uid(); -- Saves the new name (the rule above updates the full name).
  perform private.log_event('name_change', 'accounts', auth.uid()::text, -- Notes the change in the activity log:
                            jsonb_build_object('from', v_old, 'to', v_first || ' ' || v_last, 'by', 'self')); -- the old name, the new name, and that they changed it themselves.
end;
$$;
-- Nobody can use it until allowed below.
revoke execute on function public.set_my_name(text, text) from public, anon;
-- Anyone signed in may use it (it only ever changes their own name).
grant execute on function public.set_my_name(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Admins changing a staff member's name
-- ---------------------------------------------------------------------------

-- The owner or an operations admin sets or changes a tutor's or admin's
-- first and last name (for example, someone who joined before names were
-- asked for, or a spelling fix). Noted in the activity log.
create or replace function public.set_staff_name(p_account uuid, p_first text, p_last text)
returns void language plpgsql security definer -- (runs with the table owner's rights)
set search_path = '' -- (looks nothing up by short name, for safety)
as $$
declare
  v_first text := private.tidy_name_part(p_first); -- The tidied first name.
  v_last text := private.tidy_name_part(p_last); -- The tidied last name.
  v_old text; -- The name before the change (for the log).
begin
  if not private.is_admin() then -- Not the owner or an operations admin (with two-step sign-in):
    raise exception 'Only the owner or an operations admin can change staff names' using errcode = '42501'; -- refuses.
  end if; -- (end of that check)
  if not exists ( -- The person isn't a tutor or admin:
    select 1 from public.account_roles r -- (looks through roles)
    where r.account_id = p_account and r.role in ('admin', 'tutor') -- (for a tutor or admin role on this account)
  ) then -- (end of the question)
    raise exception 'That person isn''t a staff member' using errcode = '22023'; -- refuses.
  end if; -- (end of that check)
  perform private.check_name_parts(v_first, v_last); -- Checks the name (stops with a plain message if it's wrong).
  select full_name into v_old from public.accounts where id = p_account; -- Notes their name before the change.
  update public.accounts set first_name = v_first, last_name = v_last where id = p_account; -- Saves the new name (the rule above updates the full name).
  perform private.log_event('name_change', 'accounts', p_account::text, -- Notes the change in the activity log:
                            jsonb_build_object('from', v_old, 'to', v_first || ' ' || v_last, 'by', 'admin')); -- the old name, the new name, and that an admin changed it.
end;
$$;
-- Nobody can use it until allowed below.
revoke execute on function public.set_staff_name(uuid, text, text) from public, anon;
-- Signed-in people may call it; the check inside lets only the owner and operations admins through.
grant execute on function public.set_staff_name(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. No direct changes to first and last names
-- ---------------------------------------------------------------------------

-- Takes away the right to change any part of an account row directly.
revoke update on public.accounts from anon, authenticated;
-- Gives back only the full name (the support desk and families could already
-- correct this; it is overwritten by first and last name once those are set).
grant update (full_name) on public.accounts to authenticated;
