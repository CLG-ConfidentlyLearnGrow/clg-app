-- A newly loaded curriculum stays a draft until an admin has looked over
-- what was loaded and confirmed it. Draft skills can't be used in goals or
-- set for a student, and a draft can be thrown away if the load went wrong.

alter table public.curriculum_frameworks
  add column confirmed_at timestamptz,
  add column confirmed_by uuid references public.accounts (id) on delete set null,
  -- Where it came from, for the licence credit, for example
  -- 'ACARA, Australian Curriculum website, downloaded 27 Oct 2026'.
  add column source text check (source is null or char_length(source) <= 500);

-- Curricula loaded before this change were already in use.
update public.curriculum_frameworks set confirmed_at = created_at where confirmed_at is null;

-- Only the confirm function sets confirmation.
revoke insert, update on public.curriculum_frameworks from authenticated;
grant insert (id, code, name, version, country, starts_on, active, source) on public.curriculum_frameworks to authenticated;
grant update (name, starts_on, active, source) on public.curriculum_frameworks to authenticated;

create function private.framework_confirmed(p_framework uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.curriculum_frameworks where id = p_framework and confirmed_at is not null
  )
$$;

create function private.skill_confirmed(p_skill uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.curriculum_skills s
    join public.curriculum_frameworks f on f.id = s.framework_id
    where s.id = p_skill and f.confirmed_at is not null
  )
$$;

drop policy "admins set a student's frameworks" on public.student_frameworks;
create policy "admins set a student's frameworks" on public.student_frameworks
  for all to authenticated
  using (private.is_admin())
  with check (private.is_admin() and private.framework_confirmed(framework_id));

drop policy "tutors and admins add goal skills" on public.goal_skills;
create policy "tutors and admins add goal skills" on public.goal_skills
  for insert to authenticated
  with check (
    (private.is_tutor_of(private.goal_student(goal_id)) or private.is_admin())
    and private.skill_confirmed(skill_id)
  );

-- Confirm a draft curriculum after checking the summary.
create function public.confirm_curriculum(p_framework uuid)
returns boolean language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can confirm a curriculum' using errcode = '42501';
  end if;
  if not exists (select 1 from public.curriculum_skills where framework_id = p_framework) then
    raise exception 'This curriculum has no skills loaded yet' using errcode = '22023';
  end if;
  update public.curriculum_frameworks
  set confirmed_at = now(), confirmed_by = auth.uid()
  where id = p_framework and confirmed_at is null;
  return found;
end;
$$;

-- Throw away a draft (for example, the wrong file was loaded). Confirmed
-- curricula are never deleted, so past progress keeps its wording.
create function public.discard_curriculum(p_framework uuid)
returns boolean language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Only admins can remove a draft curriculum' using errcode = '42501';
  end if;
  if not exists (select 1 from public.curriculum_frameworks where id = p_framework and confirmed_at is null) then
    return false;
  end if;
  delete from public.curriculum_skills where framework_id = p_framework;
  delete from public.curriculum_frameworks where id = p_framework;
  return true;
end;
$$;

revoke execute on function public.confirm_curriculum(uuid) from public, anon;
revoke execute on function public.discard_curriculum(uuid) from public, anon;
grant execute on function public.confirm_curriculum(uuid) to authenticated;
grant execute on function public.discard_curriculum(uuid) to authenticated;

-- What a curriculum holds, for checking a draft before confirming it:
-- number of skills for each subject and year level.
create function public.curriculum_summary(p_framework uuid)
returns table (subject text, level_band text, skills bigint)
language sql stable
set search_path = ''
as $$
  select s.subject, s.level_band, count(*)
  from public.curriculum_skills s
  where s.framework_id = p_framework
  group by s.subject, s.level_band
  order by s.subject, min(s.sort_order)
$$;
revoke execute on function public.curriculum_summary(uuid) from public, anon;
grant execute on function public.curriculum_summary(uuid) to authenticated;
