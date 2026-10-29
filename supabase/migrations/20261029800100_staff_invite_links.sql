-- Staff invite links: CLG's own link for each tutor or admin invitation.
--
-- Before this, staff invitations used Supabase's invite email, whose link
-- only works for about an hour and can be used up by email virus scanners
-- that open links. Now each invitation gets its own CLG link:
--   * tied to one email and one role (tutor or admin),
--   * works for 7 days, once,
--   * opening it only shows a form; nothing happens until the person
--     chooses their name and password and presses the button,
--   * sending a new link cancels the old one.
-- Whoever joins through the link gets the role straight away (no approval
-- step), because only the invited inbox received it. Tutors still can't be
-- matched with students until CLG confirms their checks.
--
-- Only a scrambled copy (hash) of the link is stored, so even someone who
-- could read this table couldn't rebuild a working link.
--
-- Safe to run more than once.

alter table public.invitations add column if not exists link_hash text;
create unique index if not exists invitations_link_hash
  on public.invitations (link_hash) where link_hash is not null;

create or replace function private.invite_link_hash(p_token text)
returns text language sql immutable
set search_path = ''
as $$ select encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') $$;
revoke execute on function private.invite_link_hash(text) from public;

-- An admin makes a new invite link. Any admin may invite tutors; only the
-- owner may invite admins (same rule as before). Replaces any earlier
-- invitation for the same email that hasn't been used, so only the newest
-- link works. Returns the secret part of the link, once.
create or replace function public.create_staff_invite_link(p_email text, p_role public.app_role)
returns text language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_open public.invitations;
  v_token text;
begin
  if not private.is_admin() then
    raise exception 'Only admins can invite staff' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('tutor', 'admin') then
    raise exception 'Choose tutor or admin' using errcode = '22023';
  end if;
  if p_role = 'admin' and not private.is_owner() then
    raise exception 'Only the owner can invite admins' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if exists (
    select 1 from auth.users
    where lower(email) = v_email and email_confirmed_at is not null
  ) then
    raise exception 'That email already has a CLG account. Add the role to it instead' using errcode = '23505';
  end if;

  -- An earlier invitation not yet used (still open, or expired) is replaced.
  -- A staff admin can't replace an owner's admin invitation.
  select * into v_open from public.invitations
  where email = v_email and accepted_at is null;
  if v_open.id is not null then
    if (v_open.role = 'admin' or v_open.admin_level <> 'staff') and not private.is_owner() then
      raise exception 'That email has an admin invitation waiting. Only the owner can change it' using errcode = '42501';
    end if;
    delete from public.invitations where id = v_open.id;
  end if;

  -- 64 random hex characters from Postgres's secure random source.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (email, role, invited_by, link_hash, expires_at)
  values (v_email, p_role, auth.uid(), private.invite_link_hash(v_token), now() + interval '7 days');
  return v_token;
end;
$$;
revoke execute on function public.create_staff_invite_link(text, public.app_role) from public, anon;
grant execute on function public.create_staff_invite_link(text, public.app_role) to authenticated;

-- What the join page shows for a link: the invited email and role, and
-- whether the link can still be used ('open', 'used' or 'expired').
-- Returns nothing for a link that doesn't exist or was replaced. Anyone may
-- ask, because only the person holding the link knows its secret part.
create or replace function public.staff_invite_link_details(p_token text)
returns table (email text, role public.app_role, expires_at timestamptz, status text)
language sql stable security definer
set search_path = ''
as $$
  select i.email, i.role, i.expires_at,
         case
           when i.accepted_at is not null then 'used'
           when i.expires_at <= now() then 'expired'
           else 'open'
         end
  from public.invitations i
  where p_token is not null
    and length(p_token) between 32 and 128
    and i.link_hash = private.invite_link_hash(p_token)
$$;
revoke execute on function public.staff_invite_link_details(text) from public;
grant execute on function public.staff_invite_link_details(text) to anon, authenticated;
