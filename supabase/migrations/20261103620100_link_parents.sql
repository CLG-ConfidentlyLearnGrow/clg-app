-- More than one parent or guardian for a student (Carla, 3 Nov 2026).
--
-- - CLG links another parent or guardian to a student who is already in the
--   app, so the child has one record that every parent sees, instead of each
--   parent adding the child again.
-- - CLG can remove a link, but never the last adult on the account of a child
--   without their own login (someone must be able to manage the child).
-- - Possible duplicates: two student records with the same name and the
--   same date of birth (or one date missing) are listed for CLG to check.
--   Parents are never told about another family's child, for privacy.
--
-- Who can do this: owner, operations and support (the same people who set up
-- families), with two-step login, as for every admin action.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- Link another parent or guardian
-- ---------------------------------------------------------------------------
create or replace function public.admin_link_parent(
  p_parent uuid,
  p_student uuid,
  p_relationship text default 'parent',
  p_can_manage boolean default true
)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_relationship text := lower(coalesce(nullif(trim(p_relationship), ''), 'parent'));
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG staff can link a parent to a student' using errcode = '42501';
  end if;
  if not exists (select 1 from public.students where id = p_student) then
    raise exception 'That student could not be found' using errcode = '22023';
  end if;
  if not exists (select 1 from public.accounts where id = p_parent) then
    raise exception 'That account could not be found' using errcode = '22023';
  end if;
  if exists (select 1 from public.students where id = p_student and account_id = p_parent) then
    raise exception 'A student can''t be linked as their own parent' using errcode = '22023';
  end if;
  if v_relationship not in ('parent', 'guardian', 'carer', 'other') then
    raise exception 'Choose parent, guardian, carer or other' using errcode = '22023';
  end if;

  -- Someone who is only a tutor or admin so far gets the parent role too.
  insert into public.account_roles (account_id, role, granted_by)
  values (p_parent, 'parent', auth.uid())
  on conflict do nothing;
  insert into public.parent_profiles (account_id) values (p_parent)
  on conflict do nothing;

  -- A link made by CLG is already checked.
  insert into public.parent_student_links (parent_id, student_id, relationship, can_manage, verified_by, verified_at)
  values (p_parent, p_student, v_relationship, coalesce(p_can_manage, true), auth.uid(), now())
  on conflict (parent_id, student_id) do update
    set relationship = excluded.relationship,
        can_manage = excluded.can_manage,
        verified_by = coalesce(public.parent_student_links.verified_by, excluded.verified_by),
        verified_at = coalesce(public.parent_student_links.verified_at, excluded.verified_at);
end;
$$;
revoke all on function public.admin_link_parent(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.admin_link_parent(uuid, uuid, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Remove a link (for example a link made by mistake)
-- ---------------------------------------------------------------------------
create or replace function public.admin_unlink_parent(p_parent uuid, p_student uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG staff can remove a parent link' using errcode = '42501';
  end if;
  if not exists (select 1 from public.parent_student_links where parent_id = p_parent and student_id = p_student) then
    raise exception 'That parent isn''t linked to this student' using errcode = '22023';
  end if;
  -- A child on a parent's account must keep at least one adult who can manage them.
  if not exists (select 1 from public.students where id = p_student and account_id is not null)
     and not exists (
       select 1 from public.parent_student_links
       where student_id = p_student and parent_id <> p_parent and can_manage
     ) then
    raise exception 'This is the only parent who can manage this student. Link another parent first'
      using errcode = '22023';
  end if;
  delete from public.parent_student_links where parent_id = p_parent and student_id = p_student;
end;
$$;
revoke all on function public.admin_unlink_parent(uuid, uuid) from public, anon;
grant execute on function public.admin_unlink_parent(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Every parent of every student, for the admin list
-- ---------------------------------------------------------------------------
create or replace function public.admin_student_parents()
returns table (
  student_id uuid,
  student_name text,
  parent_id uuid,
  parent_name text,
  relationship text,
  can_manage boolean,
  confirmed boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG staff can see parent links' using errcode = '42501';
  end if;
  return query
    select s.id, s.full_name, l.parent_id, a.full_name, l.relationship, l.can_manage, l.verified_at is not null
    from public.parent_student_links l
    join public.students s on s.id = l.student_id
    join public.accounts a on a.id = l.parent_id
    order by s.full_name, a.full_name;
end;
$$;
revoke all on function public.admin_student_parents() from public, anon;
grant execute on function public.admin_student_parents() to authenticated;

-- ---------------------------------------------------------------------------
-- Possible duplicate children
-- ---------------------------------------------------------------------------
-- When CLG decides two records are different children, it says so once and
-- the pair stops showing.
create table if not exists public.student_duplicate_dismissals (
  student_a uuid not null references public.students (id) on delete cascade,
  student_b uuid not null references public.students (id) on delete cascade,
  dismissed_by uuid references public.accounts (id) on delete set null,
  dismissed_at timestamptz not null default now(),
  primary key (student_a, student_b),
  check (student_a < student_b)
);
alter table public.student_duplicate_dismissals enable row level security;
-- No direct access; only through the functions below.
revoke all on public.student_duplicate_dismissals from anon, authenticated;

-- The same name, ignoring case and extra spaces.
create or replace function private.same_child_name(a text, b text)
returns boolean language sql immutable
set search_path = ''
as $$
  select lower(regexp_replace(trim(a), '\s+', ' ', 'g')) = lower(regexp_replace(trim(b), '\s+', ' ', 'g'))
$$;

create or replace function public.admin_possible_duplicate_children()
returns table (
  student_id uuid,
  full_name text,
  date_of_birth date,
  parents text,
  added_at timestamptz,
  other_student_id uuid,
  other_full_name text,
  other_date_of_birth date,
  other_parents text,
  other_added_at timestamptz
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG staff can check for duplicate children' using errcode = '42501';
  end if;
  return query
    with parents as (
      select l.student_id, string_agg(a.full_name, ', ' order by a.full_name) as names
      from public.parent_student_links l
      join public.accounts a on a.id = l.parent_id
      group by l.student_id
    )
    select s1.id, s1.full_name, s1.date_of_birth, p1.names, s1.created_at,
           s2.id, s2.full_name, s2.date_of_birth, p2.names, s2.created_at
    from public.students s1
    join public.students s2
      on s1.id < s2.id
     and private.same_child_name(s1.full_name, s2.full_name)
     and (s1.date_of_birth = s2.date_of_birth or s1.date_of_birth is null or s2.date_of_birth is null)
    left join parents p1 on p1.student_id = s1.id
    left join parents p2 on p2.student_id = s2.id
    where not exists (
      select 1 from public.student_duplicate_dismissals d
      where d.student_a = s1.id and d.student_b = s2.id
    )
    order by s1.full_name;
end;
$$;
revoke all on function public.admin_possible_duplicate_children() from public, anon;
grant execute on function public.admin_possible_duplicate_children() to authenticated;

create or replace function public.admin_dismiss_duplicate(p_student uuid, p_other uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG staff can do this' using errcode = '42501';
  end if;
  if p_student = p_other then
    raise exception 'Choose two different students' using errcode = '22023';
  end if;
  insert into public.student_duplicate_dismissals (student_a, student_b, dismissed_by)
  values (least(p_student, p_other), greatest(p_student, p_other), auth.uid())
  on conflict do nothing;
  -- Links held back as a possible double-up are confirmed now.
  update public.parent_student_links set verified_at = now()
  where student_id in (p_student, p_other) and verified_at is null
    and not private.looks_like_duplicate(student_id);
end;
$$;
revoke all on function public.admin_dismiss_duplicate(uuid, uuid) from public, anon;
grant execute on function public.admin_dismiss_duplicate(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- No admin confirmation needed for a parent's own child (Carla, 3 Nov 2026)
-- ---------------------------------------------------------------------------
-- A link a parent makes by adding their child is confirmed straight away,
-- unless the child looks like one already in the app (same name, and same
-- birthday or one missing). Then CLG checks it first, because it may be a
-- second parent who should be linked instead, or someone who shouldn't have
-- access. An automatic confirmation has verified_at set and verified_by empty.
-- Runs after the "stamp" trigger (triggers run in name order).
create or replace function private.looks_like_duplicate(p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.students s
    join public.students o
      on o.id <> s.id
     and private.same_child_name(o.full_name, s.full_name)
     and (o.date_of_birth = s.date_of_birth or o.date_of_birth is null or s.date_of_birth is null)
    where s.id = p_student
      and not exists (
        select 1 from public.student_duplicate_dismissals d
        where d.student_a = least(s.id, o.id) and d.student_b = greatest(s.id, o.id)
      )
  )
$$;
revoke all on function private.looks_like_duplicate(uuid) from public;

create or replace function private.auto_confirm_parent_link()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if new.verified_at is null and not private.looks_like_duplicate(new.student_id) then
    new.verified_at := now();
    new.verified_by := null;
  end if;
  return new;
end;
$$;
revoke all on function private.auto_confirm_parent_link() from public;
drop trigger if exists stamp_auto_confirm on public.parent_student_links;
create trigger stamp_auto_confirm before insert on public.parent_student_links
  for each row execute function private.auto_confirm_parent_link();

-- Links already waiting are confirmed now, except possible duplicates.
-- (Run in the SQL editor, nobody is signed in, so verified_by stays empty.)
update public.parent_student_links
set verified_at = now()
where verified_at is null and not private.looks_like_duplicate(student_id);

-- ---------------------------------------------------------------------------
-- Merge a double-up into the record CLG keeps
-- ---------------------------------------------------------------------------
-- Moves the parents, subjects and parental consent from the double-up to the
-- record being kept, fills in any details the kept record is missing, then
-- deletes the double-up. To keep history safe, it refuses if the double-up
-- already has anything else (tutor, bookings, progress, invoices and so on);
-- merge the other way round, or ask for help.
create or replace function public.admin_merge_students(p_keep uuid, p_remove uuid)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_keep public.students;
  v_remove public.students;
  v_fk record;
  v_used boolean;
begin
  if not private.is_front_desk() then
    raise exception 'Only CLG staff can merge student records' using errcode = '42501';
  end if;
  if p_keep = p_remove then
    raise exception 'Choose two different student records' using errcode = '22023';
  end if;
  select * into v_keep from public.students where id = p_keep for update;
  select * into v_remove from public.students where id = p_remove for update;
  if v_keep.id is null or v_remove.id is null then
    raise exception 'That student could not be found' using errcode = '22023';
  end if;
  if v_remove.account_id is not null then
    raise exception 'The record to remove has its own login. Keep that one and merge the other into it'
      using errcode = '22023';
  end if;
  if v_keep.date_of_birth is not null and v_remove.date_of_birth is not null
     and v_keep.date_of_birth <> v_remove.date_of_birth then
    raise exception 'These two records have different dates of birth, so they may be different children'
      using errcode = '22023';
  end if;

  -- Anything else that points at the double-up stops the merge.
  for v_fk in
    select c.conrelid::regclass as tbl, a.attname as col
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and c.confrelid = 'public.students'::regclass
      and array_length(c.conkey, 1) = 1
      and c.conrelid not in (
        'public.parent_student_links'::regclass, 'public.student_subjects'::regclass,
        'public.consent_records'::regclass, 'public.student_duplicate_dismissals'::regclass
      )
  loop
    execute format('select exists (select 1 from %s where %I = $1)', v_fk.tbl, v_fk.col)
      into v_used using p_remove;
    if v_used then
      raise exception 'The record to remove already has history (%). Merge it the other way round, or ask for help',
        v_fk.tbl using errcode = '22023';
    end if;
  end loop;

  -- Parents: every parent of either record ends up on the kept one.
  insert into public.parent_student_links (parent_id, student_id, relationship, can_manage, verified_by, verified_at)
  select l.parent_id, p_keep, l.relationship, l.can_manage, auth.uid(), now()
  from public.parent_student_links l
  where l.student_id = p_remove
  on conflict (parent_id, student_id) do nothing;
  -- The kept record's own links are confirmed too: CLG has now checked them.
  update public.parent_student_links set verified_at = now()
  where student_id = p_keep and verified_at is null;

  -- Subjects the kept record doesn't have yet.
  insert into public.student_subjects (student_id, subject, working_level)
  select p_keep, s.subject, s.working_level
  from public.student_subjects s
  where s.student_id = p_remove
  on conflict do nothing;

  -- Parental consent given for the double-up is for the same child.
  update public.consent_records set student_id = p_keep where student_id = p_remove;

  -- Fill in what the kept record is missing.
  update public.students set
    date_of_birth = coalesce(date_of_birth, v_remove.date_of_birth),
    state = coalesce(state, v_remove.state),
    year_level = coalesce(year_level, v_remove.year_level),
    school = coalesce(nullif(trim(school), ''), v_remove.school),
    goals = coalesce(nullif(trim(goals), ''), v_remove.goals),
    extra_info = coalesce(nullif(trim(extra_info), ''), v_remove.extra_info),
    learning_needs = coalesce(nullif(trim(learning_needs), ''), v_remove.learning_needs),
    program = coalesce(nullif(trim(program), ''), v_remove.program)
  where id = p_keep;

  delete from public.students where id = p_remove;
end;
$$;
revoke all on function public.admin_merge_students(uuid, uuid) from public, anon;
grant execute on function public.admin_merge_students(uuid, uuid) to authenticated;
