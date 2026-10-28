-- Materials in use (Carla, 28 Oct 2026). See docs/features/materials.md.
--
-- * "Booklet" is a kind of material.
-- * A tutor writing a session note picks the booklet(s) they worked
--   through; the note form fills in the skills from the booklet's tags, and
--   the app records which booklet was used with which student and when.
-- * Each student's page lists the materials that fit them automatically:
--   materials tagged with skills in their goals first, then materials for
--   their subjects at the level they work at.
-- * The skill picker for tagging can narrow by year level.
--
-- Safe to run twice: each step skips or replaces what is already there.

alter table public.materials drop constraint if exists materials_kind_check;
alter table public.materials add constraint materials_kind_check check (kind in (
  'booklet', 'worksheet', 'lesson_plan', 'activity', 'assessment', 'answers', 'slides', 'reference', 'game'
));

-- Which material was used with which student, and when. Written only by
-- public.record_material_use, from a session note. Staff only: families
-- don't see materials (they are CLG's teaching resources).
create table if not exists public.material_uses (
  id bigint generated always as identity primary key,
  material_id uuid not null references public.materials (id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  note_id uuid references public.session_notes (id) on delete cascade,
  used_on date not null,
  recorded_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (note_id, material_id)
);
create index if not exists material_uses_student on public.material_uses (student_id, used_on desc);
create index if not exists material_uses_material on public.material_uses (material_id);

alter table public.material_uses enable row level security;
revoke all on public.material_uses from anon;
revoke insert, update, delete, truncate on public.material_uses from authenticated;

drop policy if exists "staff see material use" on public.material_uses;
create policy "staff see material use" on public.material_uses
  for select to authenticated
  using (private.is_admin() or private.is_tutor_of(student_id));

-- Records the materials used in a session note. Only the note's own tutor
-- (or an admin), and only materials they can open.
create or replace function public.record_material_use(p_note uuid, p_materials uuid[])
returns integer language plpgsql security definer
set search_path = ''
as $$
declare
  v_note public.session_notes;
  v_material uuid;
  v_count int := 0;
begin
  select * into v_note from public.session_notes where id = p_note;
  if v_note.id is null
     or not (private.is_admin() or (v_note.tutor_id = auth.uid() and private.is_tutor_of(v_note.student_id))) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if cardinality(coalesce(p_materials, '{}')) > 10 then
    raise exception 'Choose up to 10 materials for one session' using errcode = '22023';
  end if;
  foreach v_material in array coalesce(p_materials, '{}') loop
    if not private.can_open_material(v_material) then
      raise exception 'One of those materials isn''t available to you' using errcode = '42501';
    end if;
    insert into public.material_uses (material_id, student_id, note_id, used_on, recorded_by)
    values (v_material, v_note.student_id, p_note, v_note.session_date, auth.uid())
    on conflict do nothing;
    if found then v_count := v_count + 1; end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.record_material_use(uuid, uuid[]) from public, anon;
grant execute on function public.record_material_use(uuid, uuid[]) to authenticated;

-- Materials that fit a student, for their tutor or an admin. A material
-- fits when it is tagged with a skill in the student's active goals, or it
-- is for one of the student's subjects at the level they work at in it (or
-- their school year if no level was given). Goal matches come first.
-- Returns each material's tagged skills that are in the goals, so the note
-- form can fill them in.
create or replace function public.materials_for_student(p_student uuid)
returns table (
  material_id uuid, title text, kind text, subject text, from_level text, to_level text,
  goal_skill_ids uuid[], fits_level boolean, times_used bigint, last_used date
)
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not (private.is_admin() or private.is_tutor_of(p_student)) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  return query
    with goal_skills as (
      select distinct gs.skill_id
      from public.learning_goals g
      join public.goal_skills gs on gs.goal_id = g.id
      where g.student_id = p_student and g.status = 'active'
    ),
    levels as (
      -- The level for each of the student's subjects.
      select ss.subject, coalesce(ss.working_level, st.year_level) as level
      from public.student_subjects ss
      join public.students st on st.id = ss.student_id
      where ss.student_id = p_student
    ),
    candidates as (
      select m.*,
        array(
          select ms.skill_id from public.material_skills ms
          where ms.material_id = m.id and ms.skill_id in (select skill_id from goal_skills)
        ) as goal_ids,
        exists (
          select 1 from levels l
          where private.norm_subject(l.subject) = private.norm_subject(m.subject)
            and private.year_level_rank(l.level)
                between private.year_level_rank(m.from_level) and private.year_level_rank(m.to_level)
        ) as level_ok
      from public.materials m
      where m.status = 'published'
    )
    select c.id, c.title, c.kind, c.subject, c.from_level, c.to_level,
           c.goal_ids, c.level_ok,
           (select count(*) from public.material_uses u where u.material_id = c.id and u.student_id = p_student),
           (select max(u.used_on) from public.material_uses u where u.material_id = c.id and u.student_id = p_student)
    from candidates c
    where (cardinality(c.goal_ids) > 0 or c.level_ok)
      and private.can_open_material(c.id)
    order by cardinality(c.goal_ids) desc, c.level_ok desc, c.subject, c.title
    limit 100;
end;
$$;
revoke all on function public.materials_for_student(uuid) from public, anon;
grant execute on function public.materials_for_student(uuid) to authenticated;

-- The skill picker for tagging, now with an optional year level: only
-- skills whose level includes that year (skills whose level can't be read
-- are still listed).
drop function if exists public.skills_for_material(text, text, text, text);
create or replace function public.skills_for_material(
  p_subject text, p_from text, p_to text, p_search text default null, p_year text default null
)
returns table (
  id uuid, framework text, subject text, level_band text, code text,
  description text, plain_description text
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_year int := private.year_level_rank(nullif(trim(p_year), ''));
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
      and (v_year is null or b.r is null or v_year between b.r[1] and b.r[2])
      and (coalesce(trim(p_search), '') = '' or (
            coalesce(s.code, '') || ' ' || s.description || ' ' || coalesce(s.plain_description, '')
          ) ilike '%' || trim(p_search) || '%')
    order by f.code, s.sort_order, s.code
    limit 300;
end;
$$;
revoke all on function public.skills_for_material(text, text, text, text, text) from public, anon;
grant execute on function public.skills_for_material(text, text, text, text, text) to authenticated;
