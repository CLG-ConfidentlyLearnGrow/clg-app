-- Tutors add their own child safety checks (number, date done, expiry).
-- A tutor's entry waits for an admin to confirm it against the official
-- record before it counts. Unconfirmed entries never make a tutor eligible
-- for a student, because eligibility only uses confirmed checks.
-- No copies of certificates are stored: CLG sights them and records the
-- details (APP 3: collect only what is needed).

alter table public.tutor_checks
  add column submitted_by uuid references public.accounts (id) on delete set null,
  add column submitted_at timestamptz,
  add column declined_at timestamptz,
  add column declined_reason text
    check (declined_reason is null or char_length(declined_reason) between 3 and 300);

-- Existing rows were entered by admins.
update public.tutor_checks set submitted_by = verified_by, submitted_at = created_at
where submitted_at is null;

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

  -- A tutor's own entry: logged, and waits for an admin.
  if tg_op <> 'INSERT' then
    raise exception 'Only an admin can change a recorded check' using errcode = '42501';
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

-- Tutors (with two-step login) add checks for themselves only.
create policy "tutors add own checks" on public.tutor_checks
  for insert to authenticated
  with check (tutor_id = auth.uid() and private.has_role('tutor') and private.has_aal2());

-- An admin confirms a tutor's entry after checking the official record.
create function public.confirm_tutor_check(p_check uuid)
returns boolean language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can confirm checks' using errcode = '42501';
  end if;
  update public.tutor_checks
  set verified_by = auth.uid(), verified_at = now()
  where id = p_check and verified_at is null and declined_at is null;
  return found;
end;
$$;

-- Or sends it back with a reason the tutor can see.
create function public.decline_tutor_check(p_check uuid, p_reason text)
returns boolean language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can decline checks' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Give the tutor a short reason' using errcode = '22023';
  end if;
  update public.tutor_checks
  set declined_at = now(), declined_reason = left(trim(p_reason), 300)
  where id = p_check and verified_at is null and declined_at is null;
  return found;
end;
$$;

revoke execute on function public.confirm_tutor_check(uuid) from public, anon;
revoke execute on function public.decline_tutor_check(uuid, text) from public, anon;
grant execute on function public.confirm_tutor_check(uuid) to authenticated;
grant execute on function public.decline_tutor_check(uuid, text) to authenticated;
