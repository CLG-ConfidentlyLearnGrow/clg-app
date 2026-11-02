-- Add-ons (shared core), starting with study plans (module: progress).
-- See docs/features/add-ons.md.
--
-- An add-on is an extra a family can have on top of tutoring. Each one has
-- a switch the owner controls:
--   * free  - everyone has it (study plans start here; nothing changes now)
--   * paid  - only students the admin has given it to (a subscription)
--   * off   - nobody has it
-- Turning an add-on to "paid" does not charge anyone by itself. Charging
-- is a later billing step: billing will read who has the add-on and add a
-- line to the family's invoice. Until then an admin gives the add-on to
-- each student who pays for it.
--
-- Study plans are the parts of the roadmap that go beyond tutoring:
-- adding assessments and goals, "Plan study steps for me", and the family
-- adding their own steps. Without the add-on, the tutor's steps and each
-- session's next step still appear, can still be ticked off, and
-- everything already planned stays visible.
--
-- Needs: 20261029500100_progress_roadmaps.sql and
-- 20261029900200_admin_levels.sql. Safe to run more than once, and safe to
-- re-run the roadmap migration afterwards (it doesn't touch these).

-- ---------------------------------------------------------------------------
-- The list of add-ons (shared core)
-- ---------------------------------------------------------------------------
create table if not exists public.add_ons (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  name text not null check (char_length(name) between 1 and 100),
  description text check (char_length(description) <= 1000),
  mode text not null default 'free' check (mode in ('free', 'paid', 'off')),
  -- The price families will see, including GST if it applies. Only needed
  -- once the add-on is paid.
  price_cents int check (price_cents is null or price_cents between 0 and 10000000),
  price_period text not null default 'month' check (price_period in ('week', 'month', 'term')),
  gst_applies boolean not null default true,
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now(),
  -- A paid add-on needs a price first.
  constraint add_ons_paid_needs_price check (mode <> 'paid' or coalesce(price_cents, 0) > 0)
);

insert into public.add_ons (code, name, description, mode, price_period, gst_applies) values
  ('study_plans', 'Study plans',
   'Assessments and goals on the roadmap, study steps planned for each assessment, and steps the family adds. Free while it is being tested.',
   'free', 'month', false)
on conflict (code) do nothing;

-- Who has a paid add-on. Ignored while the add-on is free.
create table if not exists public.add_on_members (
  add_on text not null references public.add_ons (code) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  starts_on date not null default ((now() at time zone 'Australia/Adelaide')::date),
  -- Blank means it keeps going until someone ends it.
  ends_on date,
  note text check (char_length(note) <= 300),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (add_on, student_id),
  constraint add_on_members_dates check (ends_on is null or ends_on >= starts_on)
);
create index if not exists add_on_members_student on public.add_on_members (student_id);

alter table public.add_ons enable row level security;
alter table public.add_on_members enable row level security;
revoke all on public.add_ons, public.add_on_members from anon;
revoke truncate on public.add_ons, public.add_on_members from authenticated;
-- Add-ons are listed by migrations, never added or removed in the app.
revoke insert, delete on public.add_ons from authenticated;
revoke update on public.add_ons from authenticated;
grant update (mode, price_cents, price_period, gst_applies, description) on public.add_ons to authenticated;

drop trigger if exists audit on public.add_ons;
create trigger audit after insert or update or delete on public.add_ons
  for each row execute function private.audit_change();
drop trigger if exists audit on public.add_on_members;
create trigger audit after insert or update or delete on public.add_on_members
  for each row execute function private.audit_change();

-- Anyone signed in can see the add-ons and their prices.
drop policy if exists "see add-ons" on public.add_ons;
create policy "see add-ons" on public.add_ons
  for select to authenticated using (true);
-- Only the owner turns an add-on on, off or to paid, and sets its price.
drop policy if exists "owner changes add-ons" on public.add_ons;
create policy "owner changes add-ons" on public.add_ons
  for update to authenticated using (private.is_owner()) with check (private.is_owner());

-- Families see their own child's add-ons; admins who handle money manage them.
drop policy if exists "see add-on members" on public.add_on_members;
create policy "see add-on members" on public.add_on_members
  for select to authenticated using (private.is_finance_admin() or private.can_view_student(student_id));
drop policy if exists "give add-ons" on public.add_on_members;
create policy "give add-ons" on public.add_on_members
  for insert to authenticated with check (private.is_finance_admin());
drop policy if exists "change add-ons" on public.add_on_members;
create policy "change add-ons" on public.add_on_members
  for update to authenticated using (private.is_finance_admin()) with check (private.is_finance_admin());
drop policy if exists "end add-ons" on public.add_on_members;
create policy "end add-ons" on public.add_on_members
  for delete to authenticated using (private.is_finance_admin());

create or replace function private.stamp_add_on()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists stamp on public.add_ons;
create trigger stamp before update on public.add_ons
  for each row execute function private.stamp_add_on();

create or replace function private.stamp_add_on_member()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
  elsif new.add_on is distinct from old.add_on or new.student_id is distinct from old.student_id then
    raise exception 'Give the add-on to the other student instead' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists stamp on public.add_on_members;
create trigger stamp before insert or update on public.add_on_members
  for each row execute function private.stamp_add_on_member();

-- Does this student have this add-on today?
create or replace function private.has_add_on(p_code text, p_student uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select case a.mode
    when 'free' then true
    when 'off' then false
    else exists (
      select 1 from public.add_on_members m
      where m.add_on = a.code and m.student_id = p_student
        and m.starts_on <= (now() at time zone 'Australia/Adelaide')::date
        and (m.ends_on is null or m.ends_on >= (now() at time zone 'Australia/Adelaide')::date)
    )
  end
  from public.add_ons a
  where a.code = p_code
$$;
revoke execute on function private.has_add_on(text, uuid) from public;
grant execute on function private.has_add_on(text, uuid) to authenticated, service_role;

-- For the app: whether the student has the add-on, and how it's set up,
-- so the page can show or hide those parts. Only for people who can see
-- the student.
create or replace function public.add_on_for_student(p_code text, p_student uuid)
returns table (has_it boolean, mode text, name text, price_cents int, price_period text)
language sql stable security definer
set search_path = ''
as $$
  select coalesce(private.has_add_on(a.code, p_student), false), a.mode, a.name, a.price_cents, a.price_period
  from public.add_ons a
  where a.code = p_code and private.can_view_student(p_student)
$$;
revoke all on function public.add_on_for_student(text, uuid) from public, anon;
grant execute on function public.add_on_for_student(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Study plans (module: progress): what needs the add-on
-- ---------------------------------------------------------------------------
-- Runs after the roadmap's own "guard" triggers (triggers run in name
-- order), so a step's source is already set.
create or replace function private.require_study_plans()
returns trigger language plpgsql security definer
set search_path = ''
as $$
begin
  -- The tutor's steps and each session's next step are part of tutoring.
  -- (Checked in two steps: targets have no source.)
  if tg_table_name = 'roadmap_steps' then
    if (to_jsonb(new) ->> 'source') in ('tutor', 'next_step') then
      return new;
    end if;
  end if;
  -- The database's own jobs (no one signed in) are never stopped.
  if auth.uid() is null then
    return new;
  end if;
  if not coalesce(private.has_add_on('study_plans', new.student_id), false) then
    raise exception 'Study plans are an add-on this student doesn''t have yet. Ask CLG to add it.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists study_plan_add_on on public.roadmap_targets;
create trigger study_plan_add_on before insert on public.roadmap_targets
  for each row execute function private.require_study_plans();
drop trigger if exists study_plan_add_on on public.roadmap_steps;
create trigger study_plan_add_on before insert on public.roadmap_steps
  for each row execute function private.require_study_plans();
