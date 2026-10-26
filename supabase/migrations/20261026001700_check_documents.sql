-- Tutors attach a copy of the certificate or card with each check they add
-- (Carla, 26 Oct 2026). This replaces the earlier "no copies stored" rule.
--
-- Copies are kept in a private file store ("check-documents"). Each tutor's
-- files sit in a folder named with their account id. Only that tutor and
-- CLG admins can open them; nobody else, and never without signing in with
-- two-step login. A police check copy holds sensitive information (criminal
-- record) under the Privacy Act, so access is kept this tight.
--
-- Copies are kept as long as the check record itself (screening records:
-- 7 years after the tutor leaves CLG).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'check-documents', 'check-documents', false, 4194304,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Safe to run twice: each step skips or replaces what is already there.
alter table public.tutor_checks
  add column if not exists document_path text
    check (document_path is null or document_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$');

-- Is this file in the tutor's own folder and actually uploaded?
create or replace function private.check_document_ok(p_tutor uuid, p_path text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select p_path is not null
    and split_part(p_path, '/', 1) = p_tutor::text
    and exists (
      select 1 from storage.objects
      where bucket_id = 'check-documents' and name = p_path
    )
$$;

-- Is this file already attached to a check? (Then it can't be deleted.)
create or replace function private.check_document_in_use(p_path text)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.tutor_checks where document_path = p_path)
$$;

create or replace function private.stamp_tutor_check()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  -- A police check counts for 5 years from the date it was issued.
  if new.kind = 'police_check' then
    if new.completed_on is null or new.completed_on > current_date then
      raise exception 'Enter the date the police check was issued' using errcode = '23514';
    end if;
    new.expires_on := new.completed_on + interval '5 years';
  end if;

  if private.is_admin() or private.is_backend() then
    -- An admin may attach a copy too; it must be in that tutor's folder.
    if new.document_path is not null
       and (tg_op = 'INSERT' or new.document_path is distinct from old.document_path)
       and not private.check_document_ok(new.tutor_id, new.document_path) then
      raise exception 'That file isn''t in this tutor''s folder' using errcode = '23514';
    end if;
    -- Admin entry counts as verification against the official record.
    if tg_op = 'INSERT' then
      new.submitted_by := auth.uid();
      new.submitted_at := now();
    end if;
    if tg_op = 'INSERT'
       or new.reference is distinct from old.reference
       or new.expires_on is distinct from old.expires_on
       or new.completed_on is distinct from old.completed_on
       or new.kind is distinct from old.kind then
      new.verified_by := auth.uid();
      new.verified_at := now();
      new.declined_at := null;
      new.declined_reason := null;
    end if;
    return new;
  end if;

  -- A tutor's own entry: needs a copy of the certificate, is logged, and
  -- waits for an admin.
  if tg_op <> 'INSERT' then
    raise exception 'Only an admin can change a recorded check' using errcode = '42501';
  end if;
  if not private.check_document_ok(new.tutor_id, new.document_path) then
    raise exception 'Attach a copy of the certificate or card' using errcode = '23514';
  end if;
  if new.completed_on is not null and new.completed_on > current_date then
    raise exception 'The date done can''t be in the future' using errcode = '23514';
  end if;
  if new.expires_on < current_date then
    raise exception 'That check has already expired. Please renew it first' using errcode = '23514';
  end if;
  new.submitted_by := auth.uid();
  new.submitted_at := now();
  new.verified_by := null;
  new.verified_at := null;
  new.declined_at := null;
  new.declined_reason := null;
  return new;
end;
$$;

-- File access. Tutors (with two-step login) upload into their own folder
-- and open their own files. Admins open and manage all of them.
drop policy if exists "check documents: tutors upload own" on storage.objects;
create policy "check documents: tutors upload own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'check-documents'
    and (
      ((storage.foldername(name))[1] = auth.uid()::text and private.has_role('tutor') and private.has_aal2())
      or private.is_admin()
    )
  );

drop policy if exists "check documents: tutor or admin opens" on storage.objects;
create policy "check documents: tutor or admin opens" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'check-documents'
    and (
      ((storage.foldername(name))[1] = auth.uid()::text and private.has_aal2())
      or private.is_admin()
    )
  );

-- A tutor can remove a file only before it is attached to a check (for
-- example, an upload that failed half way). Attached copies stay.
drop policy if exists "check documents: remove unattached" on storage.objects;
create policy "check documents: remove unattached" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'check-documents'
    and (
      ((storage.foldername(name))[1] = auth.uid()::text and private.has_aal2()
        and not private.check_document_in_use(name))
      or private.is_admin()
    )
  );
