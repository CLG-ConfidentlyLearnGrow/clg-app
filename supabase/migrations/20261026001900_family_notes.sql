-- Notes from the family: feedback, or how learning is going at home.
-- Written by the student or a parent who manages them, at any time (not
-- only after a session). Read by the family, the student's current tutors
-- and admins. Families never write session notes; those stay with tutors.
-- See docs/features/support-requests.md. Safe to run more than once.

create table if not exists public.family_notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  kind text not null check (kind in ('feedback', 'home_progress')),
  body text not null check (char_length(body) between 1 and 2000),
  written_by uuid references public.accounts (id) on delete set null,
  written_at timestamptz not null default now()
);
create index if not exists family_notes_student on public.family_notes (student_id, written_at desc);

alter table public.family_notes enable row level security;
revoke all on public.family_notes from anon;

drop trigger if exists audit on public.family_notes;
create trigger audit after insert or update or delete on public.family_notes
  for each row execute function private.audit_change();

create or replace function private.stamp_family_note()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.body := trim(new.body);
  new.written_by := auth.uid();
  new.written_at := now();
  return new;
end;
$$;
drop trigger if exists stamp on public.family_notes;
create trigger stamp before insert on public.family_notes
  for each row execute function private.stamp_family_note();

drop policy if exists "see family notes" on public.family_notes;
create policy "see family notes" on public.family_notes
  for select to authenticated using (private.can_view_student(student_id));
drop policy if exists "student or parent writes family note" on public.family_notes;
create policy "student or parent writes family note" on public.family_notes
  for insert to authenticated
  with check (private.is_student_self(student_id) or private.can_manage_student(student_id));
drop policy if exists "admins remove family notes" on public.family_notes;
create policy "admins remove family notes" on public.family_notes
  for delete to authenticated using (private.is_admin());
revoke update on public.family_notes from authenticated;
