-- Shared skill library: curricula stored as versioned frameworks, so a new
-- version or another country is loaded as data, not built into the app.
-- Read by progress tracking now, and by matching, materials and roadmaps
-- later. See docs/features/progress-tracking.md.

create table public.curriculum_frameworks (
  id uuid primary key default gen_random_uuid(),
  -- Short name, for example 'AC9' or 'SACE'.
  code text not null check (code ~ '^[A-Za-z0-9_.-]{1,30}$'),
  name text not null check (char_length(name) between 1 and 200),
  version text not null check (char_length(version) between 1 and 40),
  country text not null default 'AU' check (country ~ '^[A-Z]{2}$'),
  starts_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (code, version)
);

create table public.curriculum_skills (
  id uuid primary key default gen_random_uuid(),
  framework_id uuid not null references public.curriculum_frameworks (id) on delete restrict,
  subject text not null check (char_length(subject) between 1 and 100),
  -- Where the skill sits: 'Year 5', 'Foundation', 'Stage 1' and so on.
  -- Shown for context only; students work on the skills they are ready for.
  level_band text not null check (char_length(level_band) between 1 and 60),
  -- The framework's own code, for example 'AC9M5N01', when it has one.
  code text check (char_length(code) <= 40),
  -- The official wording, kept as published.
  description text not null check (char_length(description) between 1 and 2000),
  -- The same skill in words a parent understands.
  plain_description text check (char_length(plain_description) <= 500),
  sort_order integer not null default 0,
  -- When a new curriculum version replaces this skill: past progress keeps
  -- this row and its wording, and points to the new skill.
  replaced_by uuid references public.curriculum_skills (id) on delete set null,
  retired_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index curriculum_skills_code on public.curriculum_skills (framework_id, code) where code is not null;
create index curriculum_skills_browse on public.curriculum_skills (framework_id, subject, sort_order);

-- Which framework(s) apply to each student, for example AC9 for Years 2 to
-- 10 and SACE for Years 11 and 12. Set by an admin.
create table public.student_frameworks (
  student_id uuid not null references public.students (id) on delete cascade,
  framework_id uuid not null references public.curriculum_frameworks (id) on delete restrict,
  set_by uuid references public.accounts (id) on delete set null,
  set_at timestamptz not null default now(),
  primary key (student_id, framework_id)
);

alter table public.curriculum_frameworks enable row level security;
alter table public.curriculum_skills enable row level security;
alter table public.student_frameworks enable row level security;
revoke all on public.curriculum_frameworks, public.curriculum_skills, public.student_frameworks from anon;

create trigger audit after insert or update or delete on public.curriculum_frameworks
  for each row execute function private.audit_change();
create trigger audit after insert or update or delete on public.student_frameworks
  for each row execute function private.audit_change();

create function private.stamp_student_framework()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.set_by := auth.uid();
  new.set_at := now();
  return new;
end;
$$;
create trigger stamp before insert or update on public.student_frameworks
  for each row execute function private.stamp_student_framework();

-- The curriculum is public information: anyone signed in can read it.
create policy "signed-in read frameworks" on public.curriculum_frameworks
  for select to authenticated using (true);
create policy "admins manage frameworks" on public.curriculum_frameworks
  for all to authenticated using (private.is_admin()) with check (private.is_admin());

create policy "signed-in read skills" on public.curriculum_skills
  for select to authenticated using (true);
create policy "admins manage skills" on public.curriculum_skills
  for all to authenticated using (private.is_admin()) with check (private.is_admin());
-- Skills are retired or replaced, never deleted, so history stays true.
revoke delete, truncate on public.curriculum_skills from authenticated;

create policy "see a student's frameworks" on public.student_frameworks
  for select to authenticated using (private.can_view_student(student_id));
create policy "admins set a student's frameworks" on public.student_frameworks
  for all to authenticated using (private.is_admin()) with check (private.is_admin());
