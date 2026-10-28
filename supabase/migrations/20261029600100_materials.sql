-- Materials library: CLG's own worksheets, lesson plans, activities and
-- tests, kept in the app. See docs/features/materials.md.
--
-- * Admins upload and tag each material with a subject, the year levels it
--   suits, and the curriculum skills it works on (from the shared skill
--   library). Tags are what will later let the app suggest materials from a
--   student's goals and roadmap.
-- * Tutors see only published materials for a subject they teach, at year
--   levels they teach it for, and only with two-step login.
-- * Tutors never get the original file. They open a copy stamped with their
--   name, email and the date on every page (made by the app's server), one
--   material at a time, up to 30 different materials a day. Every open is
--   logged and admins can see who opened what.
--
-- Safe to run twice: each step skips or replaces what is already there.

-- Files. One private store for everything; only admins can touch it
-- directly. "view/" holds the file tutors see (PDF or picture), "source/"
-- holds an optional editable original (for example the Word file), which
-- tutors never see. The app's server reads view files with its own key after
-- public.open_material says yes, so a tutor can't skip the stamp by asking
-- the file store directly.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'materials', 'materials', false, 52428800,
  array[
    'application/pdf', 'image/jpeg', 'image/png',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword', 'application/vnd.ms-powerpoint', 'application/vnd.ms-excel'
  ]
)
on conflict (id) do nothing;

drop policy if exists "materials: admins manage files" on storage.objects;
create policy "materials: admins manage files" on storage.objects
  for all to authenticated
  using (bucket_id = 'materials' and private.is_admin())
  with check (bucket_id = 'materials' and private.is_admin());

-- Where a curriculum level sits as year-level numbers, so a skill for
-- "Year 7", "Year 11 (Stage 1)", "Years 3 and 4" or "Foundation" can be
-- matched to a material's year range. Returns {from, to} as ranks in
-- private.year_level_rank's list, or null when it can't tell.
create or replace function private.level_band_ranks(p_band text)
returns int[] language plpgsql immutable
set search_path = ''
as $$
declare
  v text := lower(trim(coalesce(p_band, '')));
  v_nums int[];
begin
  if v like 'foundation%' or v like 'reception%' or v like 'prep%' then
    v_nums := array[0];
  end if;
  select coalesce(v_nums, '{}') || coalesce(array_agg(m[1]::int), '{}')
    into v_nums
    from regexp_matches(regexp_replace(v, '\(.*\)', '', 'g'), '(\d+)', 'g') as m;
  v_nums := array(select n from unnest(v_nums) n where n between 0 and 12);
  if cardinality(v_nums) = 0 then return null; end if;
  -- Foundation is rank 1, Year 1 is rank 2, ... Year 12 is rank 13.
  return array[(select min(n) from unnest(v_nums) n) + 1, (select max(n) from unnest(v_nums) n) + 1];
end;
$$;

create table if not exists public.materials (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 200),
  -- A line for tutors: what it is and how to use it.
  description text check (char_length(description) <= 1000),
  kind text not null default 'worksheet' check (kind in (
    'worksheet', 'lesson_plan', 'activity', 'assessment', 'answers', 'slides', 'reference', 'game'
  )),
  subject text not null check (char_length(subject) between 1 and 100),
  from_level text not null check (private.year_level_rank(from_level) is not null),
  to_level text not null check (private.year_level_rank(to_level) is not null),
  -- The file tutors open (a PDF or picture in the "materials" store).
  file_path text not null check (file_path ~ '^view/[0-9a-f-]{36}\.(pdf|jpg|png)$'),
  file_type text not null check (file_type in ('application/pdf', 'image/jpeg', 'image/png')),
  file_bytes integer not null check (file_bytes between 1 and 4194304),
  page_count integer check (page_count between 1 and 500),
  -- Optional editable original, admins only.
  source_path text check (source_path is null or source_path ~ '^source/[0-9a-f-]{36}\.[a-z]{3,4}$'),
  source_name text check (char_length(source_name) <= 200),
  status text not null default 'draft' check (status in ('draft', 'published', 'retired')),
  -- Publishing needs curriculum skills. If no curriculum fits (for example
  -- study skills or a university unit), say why instead.
  no_skills_reason text check (char_length(no_skills_reason) <= 300),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  check (private.year_level_rank(from_level) <= private.year_level_rank(to_level))
);
create index if not exists materials_browse on public.materials (status, lower(subject));

-- The curriculum skills each material works on.
create table if not exists public.material_skills (
  material_id uuid not null references public.materials (id) on delete cascade,
  skill_id uuid not null references public.curriculum_skills (id) on delete restrict,
  primary key (material_id, skill_id)
);
create index if not exists material_skills_skill on public.material_skills (skill_id);

-- Every time someone opens a material. Kept 2 years, then deleted; deleted
-- straight away with the account.
create table if not exists public.material_opens (
  id bigint generated always as identity primary key,
  material_id uuid not null references public.materials (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  opened_at timestamptz not null default now()
);
create index if not exists material_opens_who on public.material_opens (account_id, opened_at desc);
create index if not exists material_opens_when on public.material_opens (opened_at desc);

alter table public.materials enable row level security;
alter table public.material_skills enable row level security;
alter table public.material_opens enable row level security;
revoke all on public.materials, public.material_skills, public.material_opens from anon;

drop trigger if exists audit on public.materials;
create trigger audit after insert or update or delete on public.materials
  for each row execute function private.audit_change();
drop trigger if exists audit on public.material_skills;
create trigger audit after insert or update or delete on public.material_skills
  for each row execute function private.audit_change();

-- Can the signed-in person open this material? Admins: any. Tutors (with
-- two-step login): published ones in a subject they teach, where the
-- material's year range overlaps the range they teach it for.
create or replace function private.can_open_material(p_material uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select private.is_admin() or (
    private.has_role('tutor') and private.has_aal2() and exists (
      select 1
      from public.materials m
      join public.tutor_teaching t on t.tutor_id = auth.uid()
        and private.norm_subject(t.subject) = private.norm_subject(m.subject)
      where m.id = p_material
        and m.status = 'published'
        and private.year_level_rank(m.from_level) <= private.year_level_rank(t.to_level)
        and private.year_level_rank(m.to_level) >= private.year_level_rank(t.from_level)
    )
  )
$$;

drop policy if exists "see materials you can open" on public.materials;
create policy "see materials you can open" on public.materials
  for select to authenticated using (private.can_open_material(id));
drop policy if exists "admins add materials" on public.materials;
create policy "admins add materials" on public.materials
  for insert to authenticated with check (private.is_admin());
drop policy if exists "admins change materials" on public.materials;
create policy "admins change materials" on public.materials
  for update to authenticated using (private.is_admin()) with check (private.is_admin());
-- Only drafts can be deleted. A published material is retired instead, so
-- the record of who opened it stays.
drop policy if exists "admins delete drafts" on public.materials;
create policy "admins delete drafts" on public.materials
  for delete to authenticated using (private.is_admin() and status = 'draft');
revoke truncate on public.materials from authenticated;

drop policy if exists "see tags of materials you can open" on public.material_skills;
create policy "see tags of materials you can open" on public.material_skills
  for select to authenticated using (private.can_open_material(material_id));
drop policy if exists "admins tag materials" on public.material_skills;
-- Only skills from a confirmed curriculum can be used as tags.
create policy "admins tag materials" on public.material_skills
  for all to authenticated
  using (private.is_admin())
  with check (private.is_admin() and private.skill_confirmed(skill_id));

-- Opens are written only by public.open_material. Admins read them.
drop policy if exists "admins see opens" on public.material_opens;
create policy "admins see opens" on public.material_opens
  for select to authenticated using (private.is_admin());
revoke insert, update, delete, truncate on public.material_opens from authenticated;

-- Stamps who made and changed a material, and checks the rules for
-- publishing.
create or replace function private.stamp_material()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  new.no_skills_reason := nullif(trim(new.no_skills_reason), '');

  if new.status = 'published' then
    if not exists (select 1 from public.material_skills where material_id = new.id)
       and new.no_skills_reason is null then
      raise exception 'Tag at least one curriculum skill before publishing, or say why no curriculum fits'
        using errcode = '23514';
    end if;
    if tg_op = 'INSERT' or old.status <> 'published' then
      new.published_at := now();
    end if;
  end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' and new.status = 'draft' then
    raise exception 'A published material can''t go back to a draft. Retire it instead'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists stamp on public.materials;
create trigger stamp before insert or update on public.materials
  for each row execute function private.stamp_material();

-- A published material can't lose its last skill unless it says why no
-- curriculum fits.
create or replace function private.keep_material_tagged()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  -- Skip when the whole material is being removed (the tags go with it).
  if pg_trigger_depth() > 1 then return null; end if;
  if exists (
    select 1 from public.materials m
    where m.id = old.material_id and m.status = 'published' and m.no_skills_reason is null
      and not exists (select 1 from public.material_skills s where s.material_id = m.id)
  ) then
    raise exception 'A published material needs at least one curriculum skill' using errcode = '23514';
  end if;
  return null;
end;
$$;
drop trigger if exists keep_tagged on public.material_skills;
create trigger keep_tagged after delete on public.material_skills
  for each row execute function private.keep_material_tagged();

-- Skills an admin can tag a material with: skills in the live curricula
-- for the material's subject whose level falls inside its year range
-- (skills whose level can't be read are listed too). Optional search words.
create or replace function public.skills_for_material(
  p_subject text, p_from text, p_to text, p_search text default null
)
returns table (
  id uuid, framework text, subject text, level_band text, code text,
  description text, plain_description text
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select s.id, f.code || ' v' || f.version, s.subject, s.level_band, s.code,
           s.description, s.plain_description
    from public.curriculum_skills s
    join public.curriculum_frameworks f on f.id = s.framework_id
    cross join lateral (select private.level_band_ranks(s.level_band) as r) b
    where f.active and f.confirmed_at is not null
      and s.retired_at is null
      and (private.subject_fits(p_subject, s.subject)
           or private.norm_subject(p_subject) = private.norm_subject(s.subject))
      and (b.r is null or (
            b.r[1] <= private.year_level_rank(p_to)
        and b.r[2] >= private.year_level_rank(p_from)))
      and (coalesce(trim(p_search), '') = '' or (
            coalesce(s.code, '') || ' ' || s.description || ' ' || coalesce(s.plain_description, '')
          ) ilike '%' || trim(p_search) || '%')
    order by f.code, s.sort_order, s.code
    limit 300;
end;
$$;
revoke all on function public.skills_for_material(text, text, text, text) from public, anon;
grant execute on function public.skills_for_material(text, text, text, text) to authenticated;

-- Opening a material. Checks the person may open it, holds tutors to 30
-- different materials in 24 hours (to stop bulk copying; the same material
-- again doesn't count), logs the open, and returns what the app's server
-- needs to make the stamped copy.
create or replace function public.open_material(p_material uuid)
returns table (file_path text, file_type text, title text, viewer_name text, viewer_email text)
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_recent int;
begin
  if auth.uid() is null or not private.can_open_material(p_material) then
    raise exception 'This material isn''t available to you' using errcode = '42501';
  end if;

  if not private.is_admin() then
    select count(distinct o.material_id) into v_recent
    from public.material_opens o
    where o.account_id = auth.uid()
      and o.opened_at > now() - interval '24 hours'
      and o.material_id <> p_material;
    if v_recent >= 30 then
      raise exception 'You''ve opened 30 different materials today, which is the daily limit. Please contact CLG if you need more'
        using errcode = '54000';
    end if;
  end if;

  insert into public.material_opens (material_id, account_id) values (p_material, auth.uid());

  return query
    select m.file_path, m.file_type, m.title, a.full_name, p.email
    from public.materials m
    join public.accounts a on a.id = auth.uid()
    left join public.account_private p on p.account_id = auth.uid()
    where m.id = p_material;
end;
$$;
revoke all on function public.open_material(uuid) from public, anon;
grant execute on function public.open_material(uuid) to authenticated;

-- Admin view of use: per person over the last p_days days, how many opens
-- and how many different materials, busiest first.
create or replace function public.material_open_summary(p_days int default 7)
returns table (account_id uuid, full_name text, opens bigint, different_materials bigint, last_opened timestamptz)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    select o.account_id, a.full_name, count(*), count(distinct o.material_id), max(o.opened_at)
    from public.material_opens o
    join public.accounts a on a.id = o.account_id
    where o.opened_at > now() - make_interval(days => greatest(1, least(p_days, 365)))
    group by o.account_id, a.full_name
    order by count(distinct o.material_id) desc, max(o.opened_at) desc;
end;
$$;
revoke all on function public.material_open_summary(int) from public, anon;
grant execute on function public.material_open_summary(int) to authenticated;

-- Suggestions for a tutor: published materials they can open that are
-- tagged with skills in their current students' active goals. Reads the
-- progress module's goals; never changes them.
create or replace function public.materials_for_my_students()
returns table (
  student_id uuid, student_name text, goal_title text,
  material_id uuid, material_title text, matching_skills bigint
)
language sql stable security definer
set search_path = ''
as $$
  select st.id, st.full_name, g.title, m.id, m.title, count(distinct ms.skill_id)
  from public.tutor_assignments ta
  join public.students st on st.id = ta.student_id
  join public.learning_goals g on g.student_id = st.id and g.status = 'active'
  join public.goal_skills gs on gs.goal_id = g.id
  join public.material_skills ms on ms.skill_id = gs.skill_id
  join public.materials m on m.id = ms.material_id
  where ta.tutor_id = auth.uid()
    and private.assignment_is_current(ta.starts_on, ta.ends_on)
    and private.is_tutor_of(st.id)
    and private.can_open_material(m.id)
  group by st.id, st.full_name, g.title, m.id, m.title
  order by st.full_name, g.title, count(distinct ms.skill_id) desc, m.title
$$;
revoke all on function public.materials_for_my_students() from public, anon;
grant execute on function public.materials_for_my_students() to authenticated;

-- Remove open records older than 2 years. Runs nightly.
create or replace function private.clear_old_material_opens()
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_rows int;
begin
  delete from public.material_opens where opened_at < now() - interval '2 years';
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;
revoke all on function private.clear_old_material_opens() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    execute $job$
      select cron.schedule('clg-material-opens-cleanup', '40 3 * * *', 'select private.clear_old_material_opens()')
    $job$;
  end if;
end;
$$;
