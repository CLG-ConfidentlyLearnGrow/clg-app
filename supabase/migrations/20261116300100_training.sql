-- Training (module: training): tutor and staff training modules, quizzes,
-- completions, certificates, the tutor handbook, reminders and the matching
-- hold for compulsory safety modules.
--
-- Carla (12 and 16 Nov 2026):
--   * A starting course for every new tutor, then short ongoing modules and
--     short refreshers. Admins (owner and operations) write the modules.
--   * Each module says who it's for (tutors, admins or everyone), its set
--     time (what's paid), whether it's compulsory, whether it holds new
--     matches until done (the safety modules), whether it counts towards
--     the 3 hours a quarter that keep someone "CLG certified", and whether
--     it needs redoing every so many months.
--   * Quizzes need 100%, with unlimited retries. Answers are hidden from
--     the people doing the training.
--   * Tutors get 4 weeks (a setting) to finish the safety modules. After
--     that, new matches are refused. Students they already tutor stay.
--   * A searchable handbook, with "Something's happened" pinned at the top.
--   * Pay is worked out by the billing module, which reads completions
--     (see 20261116300200_billing_training_pay.sql). This module never
--     writes billing's tables.
--
-- Safe to run more than once. Run after 20261116100100_clear_no_concern_flags.sql.

-- ---------------------------------------------------------------------------
-- Settings: one row of training settings that admins can change.
-- ---------------------------------------------------------------------------
create table if not exists public.training_settings ( -- the one settings row
  id boolean primary key default true check (id), -- always "true", so there can only be one row
  grace_days int not null default 28 check (grace_days between 0 and 180), -- days to finish a compulsory module before it's overdue (4 weeks)
  quarter_minutes int not null default 180 check (quarter_minutes between 0 and 2400), -- training minutes needed each quarter to stay certified (3 hr)
  video_max_mb int not null default 500 check (video_max_mb between 1 and 5000), -- the largest video or PDF admins can upload, in MB
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed the settings
  updated_at timestamptz not null default now() -- when they were last changed
); -- end of the settings table
insert into public.training_settings (id) values (true) on conflict (id) do nothing; -- adds the one row with the starting values (only the first time)

-- ---------------------------------------------------------------------------
-- Modules: one piece of training (for example "Child safety and reporting").
-- ---------------------------------------------------------------------------
create table if not exists public.training_modules ( -- the training modules
  id uuid primary key default gen_random_uuid(), -- the module's id
  title text not null check (char_length(title) between 2 and 150), -- its name
  summary text not null default '' check (char_length(summary) <= 600), -- one or two lines on what it covers
  audience text not null default 'tutor' check (audience in ('tutor', 'admin', 'everyone')), -- who it's for
  stage text not null default 'ongoing' check (stage in ('starting', 'refresher', 'ongoing')), -- starting course, refresher, or ongoing learning (for grouping on screen)
  required boolean not null default false, -- compulsory for everyone it's for (and paid automatically)
  holds_matching boolean not null default false, -- new matches are refused until it's done (safety modules)
  counts_toward_certified boolean not null default true, -- counts towards the training hours each quarter
  minutes int not null default 30 check (minutes between 5 and 480), -- the set time it takes (what's paid)
  renew_months int check (renew_months is null or renew_months between 1 and 60), -- redo every so many months (blank: no redo)
  version int not null default 1 check (version >= 1), -- goes up when everyone is asked to redo it after a big change
  required_since date, -- the day it became compulsory, or was last changed in a big way (the 4 weeks count from here)
  status text not null default 'draft' check (status in ('draft', 'published', 'retired')), -- draft (admins only), published (in use) or retired (kept for records)
  position int not null default 100, -- order on screen (smaller first)
  created_by uuid references public.accounts (id) on delete set null, -- who made it
  created_at timestamptz not null default now(), -- when it was made
  updated_at timestamptz not null default now(), -- when it was last changed
  constraint training_modules_hold_needs_required check (not holds_matching or required) -- a module can only hold matches if it's compulsory
); -- end of the modules table

-- ---------------------------------------------------------------------------
-- Lessons: the parts of a module, in order (text, a video or PDF, a link).
-- ---------------------------------------------------------------------------
create table if not exists public.training_lessons ( -- the lessons
  id uuid primary key default gen_random_uuid(), -- the lesson's id
  module_id uuid not null references public.training_modules (id) on delete cascade, -- the module it belongs to (removed with it)
  position int not null default 1, -- its place in the module (smaller first)
  title text not null check (char_length(title) between 2 and 150), -- its heading
  body text not null default '' check (char_length(body) <= 20000), -- its text ("## " starts a heading, "- " starts a bullet point)
  file_path text check (file_path is null or file_path ~ '^lessons/[0-9a-f-]{36}\.(mp4|webm|mov|pdf)$'), -- a video or PDF in the training file store (random name)
  file_name text check (file_name is null or char_length(file_name) <= 200), -- the file's original name, shown to people
  link_url text check (link_url is null or (link_url ~ '^https://' and char_length(link_url) <= 500)), -- an outside link (secure web addresses only)
  link_label text check (link_label is null or char_length(link_label) <= 150), -- the words shown for the link
  updated_at timestamptz not null default now() -- when it was last changed
); -- end of the lessons table
create index if not exists training_lessons_module on public.training_lessons (module_id, position); -- finds a module's lessons quickly, in order

-- ---------------------------------------------------------------------------
-- Quiz questions: multiple choice, one right answer each.
-- ---------------------------------------------------------------------------
create table if not exists public.training_questions ( -- the quiz questions
  id uuid primary key default gen_random_uuid(), -- the question's id
  module_id uuid not null references public.training_modules (id) on delete cascade, -- the module it belongs to (removed with it)
  position int not null default 1, -- its place in the quiz (smaller first)
  prompt text not null check (char_length(prompt) between 3 and 600), -- the question
  options text[] not null check (cardinality(options) between 2 and 6), -- the choices (2 to 6)
  correct_option smallint not null, -- which choice is right (counting from 1); hidden from people doing the quiz
  explanation text check (explanation is null or char_length(explanation) <= 600), -- why it's right, shown to admins only
  constraint training_questions_correct_in_range check (correct_option between 1 and cardinality(options)) -- the right answer must be one of the choices
); -- end of the questions table
create index if not exists training_questions_module on public.training_questions (module_id, position); -- finds a module's questions quickly, in order

-- ---------------------------------------------------------------------------
-- Quiz attempts: every try, kept so CLG can see which questions are hard.
-- ---------------------------------------------------------------------------
create table if not exists public.training_attempts ( -- the quiz attempts
  id uuid primary key default gen_random_uuid(), -- the attempt's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- who tried (removed with their account)
  module_id uuid not null references public.training_modules (id) on delete cascade, -- which module
  module_version int not null, -- which version of the module
  score int not null check (score >= 0), -- how many were right
  total int not null check (total >= 0), -- how many questions there were
  wrong_positions int[] not null default '{}', -- which question numbers were wrong (to help people and to improve lessons)
  created_at timestamptz not null default now() -- when they tried
); -- end of the attempts table
create index if not exists training_attempts_person on public.training_attempts (account_id, module_id); -- finds a person's attempts quickly

-- ---------------------------------------------------------------------------
-- Completions: a person finished a module (passed its quiz).
-- ---------------------------------------------------------------------------
create table if not exists public.training_completions ( -- the completions
  id uuid primary key default gen_random_uuid(), -- the completion's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- who finished it (removed with their account)
  module_id uuid not null references public.training_modules (id) on delete restrict, -- which module (a module with completions can't be deleted, only retired)
  module_version int not null, -- which version they finished
  module_title text not null, -- the module's name when they finished it (for certificates)
  audience text not null check (audience in ('tutor', 'admin', 'everyone')), -- who the module was for (billing uses this to choose the pay rate)
  minutes int not null check (minutes > 0), -- the set time when they finished it
  paid boolean not null, -- true when it was compulsory for them, so it's paid automatically
  counts_toward_certified boolean not null, -- whether it counts towards the quarter's training hours
  completed_at timestamptz not null default now(), -- when they finished
  completed_on date not null, -- the day they finished (Adelaide)
  expires_on date, -- when it needs redoing (blank: no redo)
  certificate_no text not null unique -- the number printed on the certificate
); -- end of the completions table
create index if not exists training_completions_person on public.training_completions (account_id, module_id, completed_at desc); -- finds a person's latest completion of a module quickly

-- ---------------------------------------------------------------------------
-- Handbook pages: the go-to guide for tutors.
-- ---------------------------------------------------------------------------
create table if not exists public.handbook_pages ( -- the handbook pages
  id uuid primary key default gen_random_uuid(), -- the page's id
  title text not null check (char_length(title) between 2 and 150), -- its heading
  body text not null default '' check (char_length(body) <= 30000), -- its text (same simple format as lessons)
  urgent boolean not null default false, -- pinned at the top in red ("Something's happened")
  audience text not null default 'everyone' check (audience in ('tutor', 'admin', 'everyone')), -- who it's for
  status text not null default 'draft' check (status in ('draft', 'published')), -- draft (admins only) or published
  position int not null default 100, -- order on screen (smaller first)
  updated_by uuid references public.accounts (id) on delete set null, -- who last changed it
  updated_at timestamptz not null default now() -- when it was last changed
); -- end of the handbook table

-- ---------------------------------------------------------------------------
-- Reminders already sent, so each one goes only once.
-- ---------------------------------------------------------------------------
create table if not exists public.training_reminders ( -- the reminders sent
  account_id uuid not null references public.accounts (id) on delete cascade, -- who it was about
  kind text not null check (kind in ('renew_6w', 'renew_2w', 'due_1w', 'overdue', 'quarter_short')), -- which reminder
  ref text not null check (char_length(ref) <= 120), -- what it was for (a module and date, or a quarter)
  sent_at timestamptz not null default now(), -- when it was sent
  primary key (account_id, kind, ref) -- one of each per person per thing
); -- end of the reminders table

-- ---------------------------------------------------------------------------
-- Helpers (used inside the database only).
-- ---------------------------------------------------------------------------

-- Today's date in Adelaide, where CLG is.
create or replace function private.training_today() -- no inputs
returns date language sql stable -- gives back a date; the same within one statement
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ select (now() at time zone 'Australia/Adelaide')::date $$; -- the date in Adelaide right now
revoke all on function private.training_today() from public; -- not for signed-out visitors
grant execute on function private.training_today() to authenticated; -- the module dates step uses it while an admin is signed in

-- Whether a module made for "audience" is for this person (by their roles).
create or replace function private.training_fits(p_account uuid, p_audience text) -- takes a person and a module's audience
returns boolean language sql stable security definer -- gives back yes or no; reads roles with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the test:
  select exists ( -- true if the person has
    select 1 from public.account_roles r -- a role
    where r.account_id = p_account -- of their own
      and ((p_audience = 'tutor' and r.role::text = 'tutor') -- that is tutor, for a tutor module,
        or (p_audience = 'admin' and r.role::text = 'admin') -- admin, for an admin module,
        or (p_audience = 'everyone' and r.role::text in ('tutor', 'admin'))) -- or either, for everyone
  ) -- end of the test
$$; -- end of the function
revoke all on function private.training_fits(uuid, text) from public; -- for the database's own use (so nobody can look up other people's roles)

-- The same test for the signed-in person only (safe for access rules).
create or replace function private.training_fits_me(p_audience text) -- takes an audience
returns boolean language sql stable security definer -- gives back yes or no; reads roles with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ select private.training_fits(auth.uid(), p_audience) $$; -- whether it's for the signed-in person
revoke all on function private.training_fits_me(text) from public; -- not for everyone
grant execute on function private.training_fits_me(text) to authenticated; -- the handbook access rule uses it for signed-in people

-- Whether the signed-in person is a tutor or admin with two-step login.
create or replace function private.training_staff() -- no inputs
returns boolean language sql stable security definer -- gives back yes or no; reads roles with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ select private.has_aal2() and private.is_staff_account(auth.uid()) $$; -- two-step login, and a tutor or admin role
revoke all on function private.training_staff() from public; -- for the database's own use
grant execute on function private.training_staff() to authenticated; -- access rules below use it for signed-in people

-- Whether the signed-in person can see a module: admins see every module;
-- staff see published modules made for them.
create or replace function private.training_can_see(p_module uuid) -- takes a module
returns boolean language sql stable security definer -- gives back yes or no; reads modules with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the test:
  select private.is_admin() -- a full admin sees everything,
      or (private.training_staff() and exists ( -- or a tutor or admin with two-step login sees
        select 1 from public.training_modules m -- a module
        where m.id = p_module and m.status = 'published' -- that is published
          and private.training_fits(auth.uid(), m.audience))) -- and made for them
$$; -- end of the function
revoke all on function private.training_can_see(uuid) from public; -- for the database's own use
grant execute on function private.training_can_see(uuid) to authenticated; -- access rules below use it for signed-in people

-- Where a person is up to with one module:
--   done        finished the current version, nothing due soon
--   renew_soon  finished, but it needs redoing within 6 weeks
--   to_do       compulsory, not finished, still inside the time allowed
--   overdue     compulsory, not finished, time allowed has run out
--   optional    not compulsory and not finished
-- Also gives the due date, the last completion day, and when it expires.
create or replace function private.training_state(p_account uuid, p_module uuid) -- takes a person and a module
returns table (state text, due_on date, completed_on date, expires_on date, completion_id uuid) -- what it gives back
language plpgsql stable security definer -- runs steps; reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  m public.training_modules; -- the module
  c public.training_completions; -- the person's latest completion of it
  v_today date := private.training_today(); -- today in Adelaide
  v_grace int; -- the days allowed to finish
  v_joined date; -- when the person got a role this module is for
  v_current boolean; -- whether the latest completion still counts
begin -- start of the steps
  select * into m from public.training_modules where id = p_module; -- reads the module
  if not found then return; end if; -- no such module: gives back nothing
  select * into c from public.training_completions -- reads their latest completion
  where account_id = p_account and module_id = p_module -- for this person and module
  order by completed_at desc limit 1; -- the newest one
  v_current := c.id is not null and c.module_version = m.version -- it counts if it's for the current version
               and (c.expires_on is null or c.expires_on >= v_today); -- and hasn't run out
  if v_current then -- it still counts:
    return query select case when c.expires_on is not null and c.expires_on <= v_today + 42 then 'renew_soon' else 'done' end, -- done, or due to redo within 6 weeks
                        c.expires_on, c.completed_on, c.expires_on, c.id; -- due date is the expiry; plus the dates and id
    return; -- finished
  end if; -- end of the "still counts" case
  if not m.required then -- not compulsory:
    return query select 'optional'::text, null::date, c.completed_on, c.expires_on, c.id; -- optional, with any old completion's dates
    return; -- finished
  end if; -- end of the optional case
  select grace_days into v_grace from public.training_settings where id; -- reads the days allowed
  select min(r.granted_at at time zone 'Australia/Adelaide')::date into v_joined -- the first day they had a role this module is for
  from public.account_roles r -- from their roles
  where r.account_id = p_account -- for this person
    and ((m.audience = 'tutor' and r.role::text = 'tutor') or (m.audience = 'admin' and r.role::text = 'admin') -- the tutor or admin role, to match the module
      or (m.audience = 'everyone' and r.role::text in ('tutor', 'admin'))); -- or either, for everyone
  if c.id is not null and c.module_version = m.version and c.expires_on < v_today then -- they did it, but it ran out:
    return query select 'overdue'::text, c.expires_on, c.completed_on, c.expires_on, c.id; -- overdue from the expiry day (reminders went before)
    return; -- finished
  end if; -- end of the ran-out case
  return query select -- otherwise not done yet:
    case when v_today > greatest(coalesce(m.required_since, v_today), coalesce(v_joined, v_today)) + coalesce(v_grace, 28) then 'overdue' else 'to_do' end, -- overdue once the days allowed have passed
    greatest(coalesce(m.required_since, v_today), coalesce(v_joined, v_today)) + coalesce(v_grace, 28), -- due: days allowed after it became compulsory or they joined (whichever is later)
    c.completed_on, c.expires_on, c.id; -- plus any older completion's dates
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_state(uuid, uuid) from public; -- for the database's own use

-- Whether a tutor is up to date with every safety module that holds
-- matches (or still inside the time allowed).
create or replace function private.training_matching_ok(p_tutor uuid) -- takes a tutor
returns boolean language sql stable security definer -- gives back yes or no; reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the test:
  select not exists ( -- true when there's no
    select 1 from public.training_modules m -- module
    cross join lateral private.training_state(p_tutor, m.id) s -- (with where the tutor is up to)
    where m.status = 'published' and m.holds_matching -- that is published and holds matches,
      and private.training_fits(p_tutor, m.audience) -- is for this tutor,
      and m.audience <> 'admin' -- and isn't an admin-only module,
      and s.state = 'overdue' -- and is overdue
  ) -- end of the test
$$; -- end of the function
revoke all on function private.training_matching_ok(uuid) from public; -- for the database's own use

-- CLG certification for one person:
--   in_training  compulsory modules not all done yet
--   certified    all done, and enough hours each full quarter since (or caught up this quarter)
--   lapsed       a full quarter ended short of the hours, and not caught up yet
create or replace function private.training_cert(p_account uuid) -- takes a person
returns table (state text, certified_since date, quarter_minutes int, last_quarter_minutes int, target_minutes int, quarter_ends date) -- what it gives back
language plpgsql stable security definer -- runs steps; reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  v_today date := private.training_today(); -- today in Adelaide
  v_q date := date_trunc('quarter', v_today)::date; -- the first day of this quarter
  v_prev date := (date_trunc('quarter', v_today) - interval '3 months')::date; -- the first day of last quarter
  v_target int; -- the minutes needed each quarter
  v_needed int; -- how many compulsory modules are for this person
  v_done int; -- how many of those are done
  v_since date; -- the day they finished their last compulsory module for the first time
  v_this int; -- minutes that count, this quarter
  v_last int; -- minutes that count, last quarter
begin -- start of the steps
  select s.quarter_minutes into v_target from public.training_settings s where s.id; -- reads the minutes needed each quarter
  select count(*), count(*) filter (where st.state in ('done', 'renew_soon')) into v_needed, v_done -- counts the compulsory modules, and those done
  from public.training_modules m -- from the modules
  cross join lateral private.training_state(p_account, m.id) st -- with where the person is up to
  where m.status = 'published' and m.required and private.training_fits(p_account, m.audience); -- published, compulsory and for this person
  select coalesce(sum(c.minutes) filter (where c.completed_on >= v_q), 0), -- adds up minutes that count this quarter
         coalesce(sum(c.minutes) filter (where c.completed_on >= v_prev and c.completed_on < v_q), 0) -- and last quarter
    into v_this, v_last -- (kept here)
  from public.training_completions c -- from their completions
  where c.account_id = p_account and c.counts_toward_certified; -- that count towards certification
  if v_needed = 0 or v_done < v_needed then -- no compulsory modules yet, or not all done:
    return query select 'in_training'::text, null::date, v_this, v_last, v_target, (v_q + interval '3 months' - interval '1 day')::date; -- still in training
    return; -- finished
  end if; -- end of the in-training case
  select max(f.first_on) into v_since -- the latest of the first-completion days
  from ( -- for each compulsory module:
    select min(c.completed_on) as first_on -- the first day they finished it
    from public.training_modules m -- from the modules
    join public.training_completions c on c.module_id = m.id and c.account_id = p_account -- and their completions of it
    where m.status = 'published' and m.required and private.training_fits(p_account, m.audience) -- compulsory modules for this person
    group by m.id -- one row per module
  ) f; -- end of the per-module list
  return query select -- gives back:
    case when v_prev >= (date_trunc('quarter', v_since) + interval '3 months')::date -- last quarter was a full quarter after they qualified,
              and v_last < v_target and v_this < v_target then 'lapsed' -- it ended short, and they haven't caught up this quarter: lapsed
         else 'certified' end, -- otherwise certified
    v_since, v_this, v_last, v_target, (v_q + interval '3 months' - interval '1 day')::date; -- plus the dates and minutes
end; -- end of the steps
$$; -- end of the function
revoke all on function private.training_cert(uuid) from public; -- for the database's own use

-- ---------------------------------------------------------------------------
-- Keep module dates right.
-- ---------------------------------------------------------------------------
-- When a module is first published, its compulsory date is set to today.
-- Every change updates "last changed".
create or replace function private.training_module_dates() -- runs before a module is added or changed
returns trigger language plpgsql -- a trigger function
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if new.status = 'published' and new.required_since is null then -- published without a compulsory date:
    new.required_since := private.training_today(); -- starts the time allowed today
  end if; -- end of that case
  if tg_op = 'UPDATE' and new.required and not old.required then -- just made compulsory:
    new.required_since := private.training_today(); -- everyone gets the full time allowed from today
  end if; -- end of that case
  new.updated_at := now(); -- notes when it was changed
  return new; -- the change goes ahead
end; -- end of the steps
$$; -- end of the function
drop trigger if exists training_module_dates on public.training_modules; -- removes the old trigger (so this file can run twice)
create trigger training_module_dates before insert or update on public.training_modules -- runs before each module is added or changed
  for each row execute function private.training_module_dates(); -- using the steps above

-- ---------------------------------------------------------------------------
-- Access rules (row level security).
-- ---------------------------------------------------------------------------
alter table public.training_settings enable row level security; -- turns on access rules for settings
alter table public.training_modules enable row level security; -- for modules
alter table public.training_lessons enable row level security; -- for lessons
alter table public.training_questions enable row level security; -- for questions
alter table public.training_attempts enable row level security; -- for attempts
alter table public.training_completions enable row level security; -- for completions
alter table public.handbook_pages enable row level security; -- for handbook pages
alter table public.training_reminders enable row level security; -- for reminders sent
revoke all on public.training_settings, public.training_modules, public.training_lessons, public.training_questions, -- signed-out visitors get nothing
  public.training_attempts, public.training_completions, public.handbook_pages, public.training_reminders from anon; -- (continued)
revoke all on public.training_reminders from authenticated; -- reminders are for the database only

-- Settings: staff read them (to know the 4 weeks and quarter hours); full admins change them.
drop policy if exists "staff read training settings" on public.training_settings; -- removes the old rule (so this file can run twice)
create policy "staff read training settings" on public.training_settings -- staff and admins can read the settings
  for select to authenticated using (private.training_staff() or private.is_admin()); -- tutors and admins with two-step login
drop policy if exists "admins change training settings" on public.training_settings; -- removes the old rule
create policy "admins change training settings" on public.training_settings -- full admins can change them
  for update to authenticated using (private.is_admin() and private.has_aal2()) with check (private.is_admin() and private.has_aal2()); -- owner or operations, with two-step login
revoke insert, delete, truncate on public.training_settings from authenticated; -- nobody adds or removes the one row

-- Modules: seen by those it's for (published) and by full admins; written by full admins.
drop policy if exists "see training modules" on public.training_modules; -- removes the old rule
create policy "see training modules" on public.training_modules -- who can see a module
  for select to authenticated using (private.training_can_see(id)); -- admins, or staff it's published for
drop policy if exists "admins add training modules" on public.training_modules; -- removes the old rule
create policy "admins add training modules" on public.training_modules -- full admins can add modules
  for insert to authenticated with check (private.is_admin() and private.has_aal2()); -- with two-step login
drop policy if exists "admins change training modules" on public.training_modules; -- removes the old rule
create policy "admins change training modules" on public.training_modules -- full admins can change modules
  for update to authenticated using (private.is_admin() and private.has_aal2()) with check (private.is_admin() and private.has_aal2()); -- with two-step login
drop policy if exists "admins delete draft training modules" on public.training_modules; -- removes the old rule
create policy "admins delete draft training modules" on public.training_modules -- full admins can delete drafts only
  for delete to authenticated using (private.is_admin() and private.has_aal2() and status = 'draft'); -- published modules are retired instead
revoke truncate on public.training_modules from authenticated; -- nobody empties the whole table
revoke update on public.training_modules from authenticated; -- no columns can be changed directly (version and dates change only through the steps here), then allows these:
grant update (title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position) on public.training_modules to authenticated; -- the columns admins edit (rules above still apply)

-- Lessons: seen with their module; written by full admins.
drop policy if exists "see training lessons" on public.training_lessons; -- removes the old rule
create policy "see training lessons" on public.training_lessons -- who can see a lesson
  for select to authenticated using (private.training_can_see(module_id)); -- whoever can see its module
drop policy if exists "admins write training lessons" on public.training_lessons; -- removes the old rule
create policy "admins write training lessons" on public.training_lessons -- full admins add, change and remove lessons
  for all to authenticated using (private.is_admin() and private.has_aal2()) with check (private.is_admin() and private.has_aal2()); -- with two-step login
revoke truncate on public.training_lessons from authenticated; -- nobody empties the whole table

-- Questions: seen with their module, but the right answer and explanation
-- are hidden (column rules). Written by full admins.
drop policy if exists "see training questions" on public.training_questions; -- removes the old rule
create policy "see training questions" on public.training_questions -- who can see a question
  for select to authenticated using (private.training_can_see(module_id)); -- whoever can see its module
drop policy if exists "admins write training questions" on public.training_questions; -- removes the old rule
create policy "admins write training questions" on public.training_questions -- full admins add, change and remove questions
  for all to authenticated using (private.is_admin() and private.has_aal2()) with check (private.is_admin() and private.has_aal2()); -- with two-step login
revoke truncate on public.training_questions from authenticated; -- nobody empties the whole table
revoke select on public.training_questions from authenticated; -- nobody reads every column directly...
grant select (id, module_id, position, prompt, options) on public.training_questions to authenticated; -- ...only the question and its choices (admins read answers through a function)

-- Attempts and completions: the person and full admins can read them.
-- They are only written by the training_finish function.
drop policy if exists "own training attempts, admins all" on public.training_attempts; -- removes the old rule
create policy "own training attempts, admins all" on public.training_attempts -- who can see attempts
  for select to authenticated using ((account_id = auth.uid() and private.has_aal2()) or private.is_admin()); -- their own (two-step login), or a full admin
revoke insert, update, delete, truncate on public.training_attempts from authenticated; -- only the function writes them
drop policy if exists "own training completions, admins all" on public.training_completions; -- removes the old rule
create policy "own training completions, admins all" on public.training_completions -- who can see completions
  for select to authenticated using ((account_id = auth.uid() and private.has_aal2()) or private.is_admin()); -- their own (two-step login), or a full admin
revoke insert, update, delete, truncate on public.training_completions from authenticated; -- only the function writes them

-- Handbook: published pages for the staff they're for; full admins see and write all.
drop policy if exists "see handbook pages" on public.handbook_pages; -- removes the old rule
create policy "see handbook pages" on public.handbook_pages -- who can see a page
  for select to authenticated using (private.is_admin() -- a full admin sees every page,
    or (status = 'published' and private.training_staff() and private.training_fits_me(audience))); -- staff see published pages made for them
drop policy if exists "admins write handbook pages" on public.handbook_pages; -- removes the old rule
create policy "admins write handbook pages" on public.handbook_pages -- full admins add, change and remove pages
  for all to authenticated using (private.is_admin() and private.has_aal2()) with check (private.is_admin() and private.has_aal2()); -- with two-step login
revoke truncate on public.handbook_pages from authenticated; -- nobody empties the whole table

-- ---------------------------------------------------------------------------
-- Functions the app calls.
-- ---------------------------------------------------------------------------

-- Finish a module: marks the quiz (answers in question order, counting
-- each choice from 1). Every try is kept. All right (or no quiz) records a
-- completion, unless the current version is already done and not due.
-- Gives back: passed, score, total, which question numbers to look at
-- again, and the completion's id.
create or replace function public.training_finish(p_module uuid, p_answers int[] default '{}') -- takes the module and the answers
returns jsonb language plpgsql security definer -- gives back a small record; runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  m public.training_modules; -- the module
  v_total int; -- how many questions
  v_score int := 0; -- how many right
  v_wrong int[] := '{}'; -- which question numbers were wrong
  q record; -- one question at a time
  v_n int := 0; -- the question number
  st record; -- where the person is up to
  v_id uuid; -- the new completion's id
  v_today date := private.training_today(); -- today in Adelaide
begin -- start of the steps
  if not private.training_staff() then -- not a tutor or admin with two-step login:
    raise exception 'Please sign in with two-step login to do training' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select * into m from public.training_modules where id = p_module; -- reads the module
  if not found or m.status <> 'published' or not private.training_fits(auth.uid(), m.audience) then -- missing, not published, or not for them:
    raise exception 'This training isn''t available to you' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  select count(*) into v_total from public.training_questions where module_id = p_module; -- counts the questions
  if v_total > 0 then -- there is a quiz:
    if coalesce(cardinality(p_answers), 0) <> v_total then -- not every question answered:
      raise exception 'Please answer every question' using errcode = '22023'; -- asks for all answers
    end if; -- end of that check
    for q in select correct_option from public.training_questions where module_id = p_module order by position, id loop -- each question, in order
      v_n := v_n + 1; -- the next question number
      if p_answers[v_n] = q.correct_option then -- the answer is right:
        v_score := v_score + 1; -- counts it
      else -- it's wrong:
        v_wrong := v_wrong || v_n; -- notes the question number
      end if; -- end of the marking
    end loop; -- end of the questions
    insert into public.training_attempts (account_id, module_id, module_version, score, total, wrong_positions) -- keeps this try
    values (auth.uid(), p_module, m.version, v_score, v_total, v_wrong); -- who, which module and version, and the result
    if v_score < v_total then -- not all right:
      return jsonb_build_object('passed', false, 'score', v_score, 'total', v_total, 'wrong', to_jsonb(v_wrong)); -- says which to look at again
    end if; -- end of the not-passed case
  end if; -- end of the quiz
  select * into st from private.training_state(auth.uid(), p_module); -- where they're up to
  if st.state = 'done' then -- already finished this version and nothing due:
    return jsonb_build_object('passed', true, 'score', v_score, 'total', v_total, 'wrong', '[]'::jsonb, 'completion_id', st.completion_id, 'already', true); -- passes without another completion (so it isn't paid twice)
  end if; -- end of that case
  v_id := gen_random_uuid(); -- a new id for the completion
  insert into public.training_completions ( -- records the completion
    id, account_id, module_id, module_version, module_title, audience, minutes, paid, counts_toward_certified, completed_on, expires_on, certificate_no -- its details
  ) values ( -- the values:
    v_id, auth.uid(), p_module, m.version, m.title, m.audience, m.minutes, -- the id, who, which module and version, its name, audience and set time,
    m.required, -- paid automatically when it's compulsory
    m.counts_toward_certified, -- whether it counts towards the quarter's hours
    v_today, -- the day (Adelaide)
    case when m.renew_months is not null then (v_today + make_interval(months => m.renew_months))::date end, -- when it needs redoing (if it does)
    'CLG-' || to_char(v_today, 'YYYY') || '-' || upper(left(replace(v_id::text, '-', ''), 8)) -- a certificate number, for example CLG-2026-1A2B3C4D
  ); -- end of the values
  return jsonb_build_object('passed', true, 'score', v_score, 'total', v_total, 'wrong', '[]'::jsonb, 'completion_id', v_id); -- passed
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_finish(uuid, int[]) from public, anon; -- not for signed-out visitors
grant execute on function public.training_finish(uuid, int[]) to authenticated; -- signed-in people (checked inside)

-- Ask everyone to redo a module after a big change: the version goes up
-- and everyone gets the full time allowed from today.
create or replace function public.training_ask_redo(p_module uuid) -- takes the module
returns void language plpgsql security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not (private.is_admin() and private.has_aal2()) then -- not a full admin with two-step login:
    raise exception 'Only CLG owner or operations admins can do this' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  update public.training_modules -- changes the module:
  set version = version + 1, required_since = private.training_today() -- next version, and the time allowed starts today
  where id = p_module; -- this module
  if not found then -- no such module:
    raise exception 'That module wasn''t found' using errcode = '22023'; -- says so
  end if; -- end of that check
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_ask_redo(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.training_ask_redo(uuid) to authenticated; -- signed-in people (checked inside)

-- A module's questions with their right answers, for admins editing it.
create or replace function public.training_questions_for_admin(p_module uuid) -- takes the module
returns table (id uuid, question_position int, prompt text, options text[], correct_option smallint, explanation text) -- each question with its answer
language plpgsql stable security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not (private.is_admin() and private.has_aal2()) then -- not a full admin with two-step login:
    raise exception 'Only CLG owner or operations admins can see quiz answers' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  return query select q.id, q.position, q.prompt, q.options, q.correct_option, q.explanation -- every detail
  from public.training_questions q where q.module_id = p_module order by q.position, q.id; -- of this module's questions, in order
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_questions_for_admin(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.training_questions_for_admin(uuid) to authenticated; -- signed-in people (checked inside)

-- The signed-in person's training: each published module for them, with
-- where they're up to.
create or replace function public.training_my_modules() -- no inputs
returns table (module_id uuid, title text, summary text, stage text, required boolean, holds_matching boolean, counts_toward_certified boolean, -- the module's details,
               minutes int, renew_months int, module_position int, state text, due_on date, completed_on date, expires_on date, completion_id uuid) -- and where they're up to
language sql stable security definer -- reads with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the list:
  select m.id, m.title, m.summary, m.stage, m.required, m.holds_matching, m.counts_toward_certified, -- the module's details
         m.minutes, m.renew_months, m.position, s.state, s.due_on, s.completed_on, s.expires_on, s.completion_id -- and where they're up to
  from public.training_modules m -- from the modules
  cross join lateral private.training_state(auth.uid(), m.id) s -- with where this person is up to
  where private.training_staff() -- only for tutors and admins with two-step login
    and m.status = 'published' and private.training_fits(auth.uid(), m.audience) -- published modules made for them
  order by m.position, m.title -- in order
$$; -- end of the function
revoke all on function public.training_my_modules() from public, anon; -- not for signed-out visitors
grant execute on function public.training_my_modules() to authenticated; -- signed-in people (checked inside)

-- CLG certification for a person (themselves, or anyone for a full admin).
create or replace function public.training_certification(p_account uuid default null) -- takes a person (blank: the signed-in person)
returns table (state text, certified_since date, quarter_minutes int, last_quarter_minutes int, target_minutes int, quarter_ends date) -- their certification
language plpgsql stable security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  v_who uuid := coalesce(p_account, auth.uid()); -- the person asked about
begin -- start of the steps
  if not ((v_who = auth.uid() and private.training_staff()) or private.is_admin()) then -- not themselves (as staff) and not a full admin:
    raise exception 'Not allowed' using errcode = '42501'; -- refuses
  end if; -- end of that check
  return query select * from private.training_cert(v_who); -- gives back their certification
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_certification(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.training_certification(uuid) to authenticated; -- signed-in people (checked inside)

-- For full admins: every tutor and admin with where they're up to on each
-- compulsory module.
create or replace function public.training_progress() -- no inputs
returns table (account_id uuid, full_name text, module_id uuid, module_title text, state text, due_on date, completed_on date, expires_on date) -- one row per person per module
language plpgsql stable security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not private.is_admin() then -- not a full admin:
    raise exception 'Only CLG owner or operations admins can see training progress' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  return query -- gives back:
    select a.id, a.full_name, m.id, m.title, s.state, s.due_on, s.completed_on, s.expires_on -- each person, module and where they're up to
    from public.accounts a -- from the accounts
    cross join public.training_modules m -- and every module
    cross join lateral private.training_state(a.id, m.id) s -- with where the person is up to
    where private.is_staff_account(a.id) -- only tutors and admins
      and not exists (select 1 from public.tutor_profiles tp where tp.account_id = a.id and not tp.active -- not tutors marked inactive
                      and not private.account_has_role(a.id, 'admin')) -- (unless they're also admin staff)
      and m.status = 'published' and m.required and private.training_fits(a.id, m.audience) -- published compulsory modules for them
    order by a.full_name, m.position, m.title; -- by name, then module order
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_progress() from public, anon; -- not for signed-out visitors
grant execute on function public.training_progress() to authenticated; -- signed-in people (checked inside)

-- For full admins: each tutor and admin's certification and hold.
create or replace function public.training_people() -- no inputs
returns table (account_id uuid, full_name text, is_tutor boolean, is_admin boolean, cert_state text, certified_since date, -- each person and their certification,
               quarter_minutes int, last_quarter_minutes int, target_minutes int, matching_held boolean) -- their hours, and whether new matches are held
language plpgsql stable security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not private.is_admin() then -- not a full admin:
    raise exception 'Only CLG owner or operations admins can see training progress' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  return query -- gives back:
    select a.id, a.full_name, private.account_has_role(a.id, 'tutor'), private.account_has_role(a.id, 'admin'), -- the person and their roles
           c.state, c.certified_since, c.quarter_minutes, c.last_quarter_minutes, c.target_minutes, -- their certification
           private.account_has_role(a.id, 'tutor') and not private.training_matching_ok(a.id) -- held if they're a tutor with an overdue safety module
    from public.accounts a -- from the accounts
    cross join lateral private.training_cert(a.id) c -- with their certification
    where private.is_staff_account(a.id) -- only tutors and admins
      and not exists (select 1 from public.tutor_profiles tp where tp.account_id = a.id and not tp.active -- not tutors marked inactive
                      and not private.account_has_role(a.id, 'admin')) -- (unless they're also admin staff)
    order by a.full_name; -- by name
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_people() from public, anon; -- not for signed-out visitors
grant execute on function public.training_people() to authenticated; -- signed-in people (checked inside)

-- For the Matching page (front desk admins): tutors whose new matches are
-- held, and which modules are overdue.
create or replace function public.training_matching_holds() -- no inputs
returns table (tutor_id uuid, modules text) -- each held tutor and the overdue modules
language plpgsql stable security definer -- runs with the owner's rights (checks below)
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if not private.is_front_desk() then -- not owner, operations or support:
    raise exception 'Only CLG admins can see matching' using errcode = '42501'; -- refuses, in plain words
  end if; -- end of that check
  return query -- gives back:
    select tp.account_id, string_agg(m.title, ', ' order by m.position) -- each tutor and their overdue modules, as one line
    from public.tutor_profiles tp -- from the tutors
    cross join public.training_modules m -- and every module
    cross join lateral private.training_state(tp.account_id, m.id) s -- with where the tutor is up to
    where tp.active and m.status = 'published' and m.holds_matching and m.audience <> 'admin' -- active tutors, published modules that hold matches
      and private.training_fits(tp.account_id, m.audience) and s.state = 'overdue' -- made for them and overdue
    group by tp.account_id; -- one row per tutor
end; -- end of the steps
$$; -- end of the function
revoke all on function public.training_matching_holds() from public, anon; -- not for signed-out visitors
grant execute on function public.training_matching_holds() to authenticated; -- signed-in people (checked inside)

-- ---------------------------------------------------------------------------
-- The matching hold: a new match is refused while a tutor's safety module is
-- overdue. Students they already tutor stay (a current match with the same
-- student is fine). This reads the matches table; it never changes it.
-- ---------------------------------------------------------------------------
create or replace function private.training_check_new_match() -- runs before a match is added
returns trigger language plpgsql security definer -- a trigger, with the owner's rights to read training
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
begin -- start of the steps
  if private.is_backend() then return new; end if; -- the app's own background jobs skip this check
  if new.ends_on is not null and new.ends_on < current_date then return new; end if; -- recording a past match is allowed
  if exists ( -- they already tutor this student:
    select 1 from public.tutor_assignments ta -- a match
    where ta.tutor_id = new.tutor_id and ta.student_id = new.student_id -- with the same tutor and student
      and private.assignment_is_current(ta.starts_on, ta.ends_on) -- that is current
  ) then return new; end if; -- is allowed (students they tutor stay with them)
  if not private.training_matching_ok(new.tutor_id) then -- a safety module is overdue:
    raise exception 'This tutor needs to finish their compulsory child safety training before they can be matched with a new student. Students they already tutor aren''t affected.' -- refuses, in plain words
      using errcode = '23514'; -- (the "rule broken" error code)
  end if; -- end of the check
  return new; -- everything checks out: the match goes ahead
end; -- end of the steps
$$; -- end of the function
drop trigger if exists training_ready_for_new_match on public.tutor_assignments; -- removes the old trigger (so this file can run twice)
create trigger training_ready_for_new_match before insert on public.tutor_assignments -- runs before each new match is added
  for each row execute function private.training_check_new_match(); -- using the steps above

-- ---------------------------------------------------------------------------
-- Daily reminders: modules to redo (6 and 2 weeks before), compulsory
-- modules due within a week, overdue safety modules (admins told), and
-- quarters ending short of hours (2 weeks before). Each goes once.
-- Uses the notices the app already sends (quiet hours apply).
-- ---------------------------------------------------------------------------
create or replace function private.queue_training_reminders() -- no inputs
returns int language plpgsql security definer -- gives back how many were sent; runs with the owner's rights
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the steps:
declare -- working values:
  r record; -- one person and module at a time
  c record; -- one person's certification
  v_today date := private.training_today(); -- today in Adelaide
  n int := 0; -- how many were sent
  v_kind text; -- which reminder
  v_ref text; -- what it's for
begin -- start of the steps
  for r in -- each person and compulsory module with something coming up:
    select a.id as account_id, a.full_name, m.id as module_id, m.title, m.holds_matching, s.state, s.due_on, s.expires_on -- who, which module and where they're up to
    from public.accounts a -- from the accounts
    cross join public.training_modules m -- and every module
    cross join lateral private.training_state(a.id, m.id) s -- with where they're up to
    where private.is_staff_account(a.id) -- tutors and admins
      and not exists (select 1 from public.tutor_profiles tp where tp.account_id = a.id and not tp.active -- not tutors marked inactive
                      and not private.account_has_role(a.id, 'admin')) -- (unless they're also admin staff)
      and m.status = 'published' and m.required and private.training_fits(a.id, m.audience) -- published compulsory modules for them
      and s.state in ('renew_soon', 'to_do', 'overdue') -- with something to do
  loop -- for each one:
    v_kind := null; -- no reminder yet
    if r.state = 'renew_soon' and r.expires_on <= v_today + 14 then -- needs redoing within 2 weeks:
      v_kind := 'renew_2w'; v_ref := r.module_id::text || ':' || r.expires_on::text; -- the 2-week reminder, for this module and expiry
    elsif r.state = 'renew_soon' then -- needs redoing within 6 weeks:
      v_kind := 'renew_6w'; v_ref := r.module_id::text || ':' || r.expires_on::text; -- the 6-week reminder
    elsif r.state = 'to_do' and r.due_on <= v_today + 7 then -- due within a week:
      v_kind := 'due_1w'; v_ref := r.module_id::text || ':' || r.due_on::text; -- the 1-week reminder, for this module and due date
    elsif r.state = 'overdue' then -- overdue:
      v_kind := 'overdue'; v_ref := r.module_id::text || ':' || r.due_on::text; -- the overdue notice
    end if; -- end of choosing
    if v_kind is not null then -- there's a reminder to send:
      insert into public.training_reminders (account_id, kind, ref) values (r.account_id, v_kind, v_ref) -- notes it as sent
      on conflict do nothing; -- (already sent: nothing happens)
      if found then -- it's new:
        perform private.add_notice(r.account_id, null, null, 'check_renewal', -- a notice to the person
          case v_kind when 'overdue' then 'Training overdue: ' when 'due_1w' then 'Training due soon: ' else 'Time to redo: ' end || r.title, -- its title
          case v_kind -- its words:
            when 'overdue' then 'Your compulsory training "' || r.title || '" is overdue. Please finish it under Training.' -- overdue
              || case when r.holds_matching then ' Until it''s done, CLG can''t match you with new students.' else '' end -- (and matching is held, for safety modules)
            when 'due_1w' then 'Please finish "' || r.title || '" under Training by ' || to_char(r.due_on, 'FMDD FMMonth YYYY') || '.' -- due soon
            else 'Your training "' || r.title || '" needs redoing by ' || to_char(r.expires_on, 'FMDD FMMonth YYYY') || '. You''ll find it under Training.' -- to redo
          end, now()); -- sent now (quiet hours still apply)
        if v_kind in ('overdue', 'renew_2w') then -- overdue or 2 weeks from expiry:
          perform private.notify_admins('Training: ' || r.full_name, -- admins are told too
            r.full_name || ' ' || case when v_kind = 'overdue' then 'is overdue for' else 'needs to redo' end || ' "' || r.title || '"' -- who and what
            || case when v_kind = 'overdue' and r.holds_matching then '. New matches are held until it''s done.' else '. They have been reminded.' end); -- and what it means
        end if; -- end of telling admins
        n := n + 1; -- counts it
      end if; -- end of the new reminder
    end if; -- end of sending
  end loop; -- end of the people and modules

  for r in select a.id as account_id from public.accounts a where private.is_staff_account(a.id) loop -- each tutor and admin:
    select * into c from private.training_cert(r.account_id); -- their certification
    if c.state = 'certified' and c.quarter_ends - v_today between 0 and 14 and c.quarter_minutes < c.target_minutes then -- certified, quarter ends within 2 weeks, short of hours:
      insert into public.training_reminders (account_id, kind, ref) values (r.account_id, 'quarter_short', c.quarter_ends::text) -- notes it as sent
      on conflict do nothing; -- (already sent: nothing happens)
      if found then -- it's new:
        perform private.add_notice(r.account_id, null, null, 'check_renewal', 'Training hours this quarter', -- a notice to the person
          'To stay CLG certified, please finish ' || round((c.target_minutes - c.quarter_minutes) / 60.0, 1) || ' more hr of training by ' -- how many hours are left
          || to_char(c.quarter_ends, 'FMDD FMMonth YYYY') || '. You''ll find modules under Training.', now()); -- and by when
        n := n + 1; -- counts it
      end if; -- end of the new reminder
    end if; -- end of the quarter check
  end loop; -- end of the people
  return n; -- how many were sent
end; -- end of the steps
$$; -- end of the function
revoke all on function private.queue_training_reminders() from public; -- for the database's own use

-- Runs the reminders every day at about 9:15am Adelaide time (22:45 UTC),
-- where the database has the scheduler.
do $$ -- a block of steps:
begin -- start of the steps
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the scheduler is available:
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- turns it on if needed
    execute $job$ select cron.schedule('clg-training-reminders', '45 22 * * *', 'select private.queue_training_reminders()') $job$; -- schedules the daily reminders (same name replaces the old schedule)
  end if; -- end of that case
end; -- end of the steps
$$; -- end of the block

-- ---------------------------------------------------------------------------
-- File store for lesson videos and PDFs (private).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) -- adds the training file store
values ('training', 'training', false, 5368709120, -- private, with a 5 GB ceiling (the admin setting sets the real limit)
        array['video/mp4', 'video/webm', 'video/quicktime', 'application/pdf']) -- only videos and PDFs
on conflict (id) do update set public = false, allowed_mime_types = excluded.allowed_mime_types; -- already there: keeps it private with the same file types

drop policy if exists "training: admins manage files" on storage.objects; -- removes the old rule
create policy "training: admins manage files" on storage.objects -- full admins add, change and remove training files
  for all to authenticated -- for signed-in people
  using (bucket_id = 'training' and private.is_admin() and private.has_aal2()) -- in the training store, full admins with two-step login
  with check (bucket_id = 'training' and private.is_admin() and private.has_aal2()); -- (the same for new files)
drop policy if exists "training: staff open lesson files" on storage.objects; -- removes the old rule
create policy "training: staff open lesson files" on storage.objects -- staff can open a lesson's file
  for select to authenticated -- for signed-in people
  using (bucket_id = 'training' and exists ( -- in the training store, when there's
    select 1 from public.training_lessons l -- a lesson
    where l.file_path = storage.objects.name -- using this file
      and private.training_can_see(l.module_id))); -- whose module they can see
