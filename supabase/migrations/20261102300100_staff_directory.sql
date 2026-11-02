-- Staff directory (module: staff directory).
--
-- Carla (2026-10-29): a list of every employee and their job role that
-- can be searched and filtered. See docs/features/staff-directory.md.
--
-- What this adds:
--   1. staff_job_titles: one job title per staff member (for example
--      "Director and Child Safety Officer", "Operations coordinator",
--      "Tutor"). Only this module writes it.
--   2. staff_directory(): every staff member (tutors and admins) with their
--      job title, app roles, admin level, work state, subjects and whether
--      they are current or finished. Any admin level can read it; tutors,
--      parents and students can't.
--   3. set_staff_job_title(): owner and operations admins set or clear a
--      job title. Each change is recorded in the activity log.
--
-- Safe to run more than once. Run after 20261029900200_admin_levels.sql.

-- ---------------------------------------------------------------------------
-- 1. Job titles
-- ---------------------------------------------------------------------------

create table if not exists public.staff_job_titles (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  job_title text not null check (char_length(btrim(job_title)) between 2 and 80),
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.staff_job_titles enable row level security;

-- Any admin can read job titles; each person can read their own.
-- Nobody writes the table directly: changes go through set_staff_job_title.
drop policy if exists "admins and the person read job titles" on public.staff_job_titles;
create policy "admins and the person read job titles" on public.staff_job_titles
  for select to authenticated
  using (private.is_any_admin() or account_id = auth.uid());
revoke insert, update, delete, truncate on public.staff_job_titles from anon, authenticated;
grant select on public.staff_job_titles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The directory
-- ---------------------------------------------------------------------------

-- Everyone with a tutor or admin role. Only what's needed to find a
-- colleague and know what they do: no phone numbers, addresses, dates of
-- birth, checks or pay.
create or replace function public.staff_directory()
returns table (
  account_id uuid,
  full_name text,
  email text,
  job_title text,
  is_tutor boolean,
  is_admin boolean,
  admin_level text,
  tutor_active boolean,
  work_state text,
  subjects text[]
)
language sql stable security definer
set search_path = ''
as $$
  select a.id,
         a.full_name,
         p.email,
         j.job_title,
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'tutor'),
         exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin'),
         (select ap.level::text from public.admin_profiles ap
          where ap.account_id = a.id
            and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role = 'admin')),
         t.active,
         w.work_state::text,
         coalesce((select array_agg(tt.subject order by tt.subject)
                   from public.tutor_teaching tt where tt.tutor_id = a.id), '{}')
  from public.accounts a
  left join public.account_private p on p.account_id = a.id
  left join public.staff_job_titles j on j.account_id = a.id
  left join public.tutor_profiles t on t.account_id = a.id
  left join public.tutor_work_settings w on w.tutor_id = a.id
  where private.is_any_admin()
    and exists (select 1 from public.account_roles r where r.account_id = a.id and r.role in ('admin', 'tutor'))
  order by a.full_name
$$;
revoke execute on function public.staff_directory() from public, anon;
grant execute on function public.staff_directory() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Setting a job title
-- ---------------------------------------------------------------------------

-- Owner or operations sets a staff member's job title. A blank title
-- removes it.
create or replace function public.set_staff_job_title(p_account uuid, p_title text)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_title text := nullif(btrim(regexp_replace(coalesce(p_title, ''), '\s+', ' ', 'g')), '');
begin
  if not private.is_admin() then
    raise exception 'Only the owner or an operations admin can change job titles' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.account_roles r
    where r.account_id = p_account and r.role in ('admin', 'tutor')
  ) then
    raise exception 'That person isn''t a staff member' using errcode = '22023';
  end if;
  if v_title is not null and char_length(v_title) not between 2 and 80 then
    raise exception 'A job title needs 2 to 80 characters' using errcode = '22023';
  end if;

  if v_title is null then
    delete from public.staff_job_titles where account_id = p_account;
  else
    insert into public.staff_job_titles (account_id, job_title, updated_by, updated_at)
    values (p_account, v_title, auth.uid(), now())
    on conflict (account_id) do update
      set job_title = excluded.job_title, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;

  perform private.log_event('job_title', 'staff_job_titles', p_account::text,
                            jsonb_build_object('job_title', v_title));
end;
$$;
revoke execute on function public.set_staff_job_title(uuid, text) from public, anon;
grant execute on function public.set_staff_job_title(uuid, text) to authenticated;
