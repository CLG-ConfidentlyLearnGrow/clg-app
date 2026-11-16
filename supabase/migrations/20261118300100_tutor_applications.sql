-- Tutor applications (module: tutor_applications). Carla, 16 Nov 2026.
--
-- "Would be really great if tutors could apply to be a tutor through the app."
--
-- Anyone can apply to tutor with CLG on the public "Apply to tutor" page.
-- Each application holds the person's contact details, what and when they
-- can teach, their qualifications and experience, their child safety check
-- details, two referees, a short statement and (optionally) a CV.
--
-- Only the owner and Operations admins (with two-step login) can see
-- applications. They record the child-safe recruitment steps for each one
-- (interview, two referee checks, Working with Children Check verified),
-- then approve or decline it. Approving is only allowed once the interview
-- and both referee checks are recorded; the app then sends the usual staff
-- invite link.
--
-- The public form never writes here directly: the app's server checks the
-- form (spam checks included) and saves it with the server's own key. The
-- save function can't be called with the public key, so the spam checks
-- can't be skipped.
--
-- Keeping records small (APP 11.2): declined or withdrawn applications are
-- deleted 12 months after the decision, never-decided ones 12 months after
-- they were sent, and approved ones 7 years after approval. CVs go with
-- them. The scrambled internet address used for spam limits is cleared
-- after 30 days. The app's daily job does the deleting.
--
-- This module writes only its own tables. See docs/features/tutor-applications.md.
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- The private file store for CVs: PDFs only, up to 3.5 MB each.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) -- adds the file store
values ('tutor-applications', 'tutor-applications', false, 3670016, array['application/pdf']) -- its id and name, private, 3.5 MB, PDFs only
on conflict (id) do nothing; -- leaves it alone if it's already there (so this file can run twice)

-- ---------------------------------------------------------------------------
-- The applications themselves.
-- ---------------------------------------------------------------------------
create table if not exists public.tutor_applications ( -- one row per application
  id uuid primary key default gen_random_uuid(), -- its id
  created_at timestamptz not null default now(), -- when it was sent
  updated_at timestamptz not null default now(), -- when an admin last changed it
  -- About the person.
  first_name text not null check (char_length(btrim(first_name)) between 1 and 100), -- their first name
  last_name text not null check (char_length(btrim(last_name)) between 1 and 100), -- their last name
  email text not null check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254), -- their email, in lower case
  phone text not null check (char_length(phone) between 6 and 30), -- their phone number
  state text not null check (state in ('SA', 'NSW', 'VIC', 'QLD', 'WA', 'TAS', 'ACT', 'NT')), -- the state they live in
  suburb text not null check (char_length(btrim(suburb)) between 1 and 100), -- their suburb or town
  teach_mode text not null check (teach_mode in ('in_person', 'online', 'both')), -- in person, online, or both
  right_to_work boolean not null, -- whether they can work in Australia (yes or no only)
  -- What and when they can teach.
  subjects text not null check (char_length(btrim(subjects)) between 3 and 2000), -- subjects and year levels, in their words
  availability text not null check (char_length(btrim(availability)) between 3 and 1000), -- days and times they're free
  weekly_hours integer check (weekly_hours between 1 and 40), -- hours a week they'd like (optional)
  -- Qualifications and experience.
  qualifications text not null check (char_length(btrim(qualifications)) between 3 and 3000), -- degrees, current study and the like
  teacher_registration text check (char_length(teacher_registration) <= 100), -- teacher registration number, if they have one (optional)
  experience text not null check (char_length(btrim(experience)) between 3 and 3000), -- teaching or tutoring experience
  -- Child safety checks, as they describe them (admins verify them later).
  wwcc_status text not null check (wwcc_status in ('held', 'applied', 'not_yet')), -- Working with Children Check: held, applied for, or not yet
  wwcc_number text check (char_length(wwcc_number) <= 50), -- its number, if held (optional)
  wwcc_state text check (wwcc_state in ('SA', 'NSW', 'VIC', 'QLD', 'WA', 'TAS', 'ACT', 'NT')), -- the state that issued it (optional)
  wwcc_expiry date, -- when it runs out (optional)
  rrhan_ec_status text not null check (rrhan_ec_status in ('done', 'not_yet')), -- RRHAN-EC training done or not yet
  first_aid_status text not null check (first_aid_status in ('current', 'not_yet')), -- first aid certificate current or not yet
  -- Two referees: a list of two {name, relationship, email, phone}.
  referees jsonb not null check (jsonb_typeof(referees) = 'array' and jsonb_array_length(referees) = 2), -- exactly two referees
  -- In their own words.
  statement text not null check (char_length(btrim(statement)) between 30 and 3000), -- why they'd like to tutor with CLG
  helped_example text not null check (char_length(btrim(helped_example)) between 30 and 3000), -- a time they helped a young person understand something difficult
  heard_from text check (char_length(heard_from) <= 200), -- how they heard about CLG (optional)
  cv_path text unique check (cv_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$'), -- where their CV is kept (a random name the app makes; optional)
  -- What they agreed to.
  declared_true boolean not null check (declared_true), -- the information is true, and CLG may contact referees and verify checks
  declared_suitable boolean not null check (declared_suitable), -- not prohibited from working with children, and no known reason they'd be unsuitable
  privacy_version text not null check (char_length(privacy_version) <= 40), -- which version of the privacy notice they saw
  -- Spam limits: a scrambled copy of their internet address (never the address itself), cleared after 30 days.
  ip_hash text check (ip_hash ~ '^[0-9a-f]{64}$'), -- (empty once cleared)
  -- Where it's up to.
  status text not null default 'new' check (status in ('new', 'shortlisted', 'approved', 'declined', 'withdrawn')), -- new, shortlisted, approved, declined or withdrawn
  -- The screening record admins keep (child-safe recruitment steps).
  interview_on date, -- when they were interviewed (empty until then)
  interview_notes text check (char_length(interview_notes) <= 4000), -- notes from the interview
  referee_1_checked_on date, -- when the first referee was contacted and checked
  referee_2_checked_on date, -- when the second referee was contacted and checked
  referee_notes text check (char_length(referee_notes) <= 4000), -- what the referees said
  wwcc_verified_on date, -- when the Working with Children Check was verified with the screening unit
  admin_notes text check (char_length(admin_notes) <= 4000), -- any other private notes
  -- The decision.
  decline_reason text check (decline_reason in ('not_needed', 'location_times', 'experience', 'referees', 'child_safety', 'no_reply', 'other')), -- why it was declined (empty unless declined)
  decline_note text check (char_length(decline_note) <= 1000), -- more about the decline (optional, private)
  decided_at timestamptz, -- when it was approved, declined or withdrawn (empty while open)
  decided_by uuid references public.accounts (id) on delete set null, -- the admin who decided
  invited_at timestamptz, -- when the staff invite was sent (approved only)
  reviewed_by uuid references public.accounts (id) on delete set null -- the admin who last changed it
); -- end of tutor_applications
create index if not exists tutor_applications_queue on public.tutor_applications (status, created_at desc); -- quick queue: by status, newest first
create index if not exists tutor_applications_email on public.tutor_applications (email); -- quick "already applied?" check
create index if not exists tutor_applications_ip on public.tutor_applications (ip_hash, created_at) where ip_hash is not null; -- quick spam limit check
alter table public.tutor_applications enable row level security; -- turns on access rules
revoke all on public.tutor_applications from anon; -- people who aren't signed in get nothing
revoke insert, update, delete, truncate on public.tutor_applications from authenticated; -- changes only go through the functions below

-- CV files waiting to be removed from the file store by the daily job.
create table if not exists public.tutor_application_file_removals ( -- one row per file to remove
  file_path text primary key, -- the file's path
  queued_at timestamptz not null default now() -- when it was queued
); -- end of tutor_application_file_removals
alter table public.tutor_application_file_removals enable row level security; -- turns on access rules (with no rules, nobody signed in can see it)
revoke all on public.tutor_application_file_removals from anon, authenticated; -- only the server's own role uses it

-- Every change to an application is logged in the shared activity log.
drop trigger if exists audit on public.tutor_applications; -- removes the old trigger (so this file can run twice)
create trigger audit after insert or update or delete on public.tutor_applications -- logs each change
  for each row execute function private.audit_change(); -- using the shared change log

-- ---------------------------------------------------------------------------
-- Access rules: only the owner and Operations admins, with two-step login.
-- ---------------------------------------------------------------------------
drop policy if exists "full admins see tutor applications" on public.tutor_applications; -- removes the old rule (so this file can run twice)
create policy "full admins see tutor applications" on public.tutor_applications -- reading applications
  for select to authenticated using (private.is_admin()); -- owner or Operations admin (this also checks two-step login)

-- CV files: full admins can open them. Nobody signed in can add, change or
-- remove them (the server adds and removes them with its own key).
drop policy if exists "tutor application files: open" on storage.objects; -- removes the old rule
create policy "tutor application files: open" on storage.objects -- opening a CV
  for select to authenticated -- for signed-in people
  using (bucket_id = 'tutor-applications' and private.is_admin()); -- only in this file store, only full admins

-- ---------------------------------------------------------------------------
-- Sending an application (the app's server only).
-- ---------------------------------------------------------------------------
-- Takes the form's answers as one bundle (p) and the scrambled internet
-- address (p_ip_hash). Checks the spam limits, then saves the application
-- and gives back its id.
create or replace function public.tutor_application_submit(p jsonb, p_ip_hash text) -- the answers and the scrambled address
returns uuid language plpgsql security definer -- gives back the new id; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_email text := lower(btrim(coalesce(p ->> 'email', ''))); -- their email, tidied
  v_cv text := nullif(btrim(coalesce(p ->> 'cv_path', '')), ''); -- their CV's path (or nothing)
  v_ip text := nullif(btrim(coalesce(p_ip_hash, '')), ''); -- the scrambled address (or nothing)
  v_ref jsonb; -- one referee, while checking them
  v_id uuid; -- the new application's id
begin
  if jsonb_typeof(p) is distinct from 'object' then -- the answers aren't a bundle
    raise exception 'Your application didn''t come through. Please try again.' using errcode = '22023'; -- plain message
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then -- the email doesn't look right
    raise exception 'Please enter a valid email address.' using errcode = '22023'; -- says so
  end if;
  if coalesce((p ->> 'declared_true')::boolean, false) is false or coalesce((p ->> 'declared_suitable')::boolean, false) is false then -- a declaration wasn't ticked
    raise exception 'Please tick both declarations to send your application.' using errcode = '22023'; -- asks for them
  end if;
  if jsonb_typeof(p -> 'referees') is distinct from 'array' or jsonb_array_length(p -> 'referees') <> 2 then -- not exactly two referees
    raise exception 'Please give two referees.' using errcode = '22023'; -- asks for two
  end if;
  for v_ref in select value from jsonb_array_elements(p -> 'referees') loop -- for each referee
    if char_length(btrim(coalesce(v_ref ->> 'name', ''))) < 2 -- no name,
       or char_length(btrim(coalesce(v_ref ->> 'relationship', ''))) < 2 -- or no "how they know you",
       or (char_length(btrim(coalesce(v_ref ->> 'email', ''))) < 5 and char_length(btrim(coalesce(v_ref ->> 'phone', ''))) < 6) then -- or no way to contact them
      raise exception 'Please give each referee''s name, how they know you, and an email or phone number.' using errcode = '22023'; -- says what's needed
    end if;
  end loop; -- end of the referees

  -- Spam and mistake limits.
  if exists (select 1 from public.tutor_applications a where a.email = v_email and a.status in ('new', 'shortlisted')) then -- they already have an open application
    raise exception 'You already have an application with CLG. We''ll be in touch soon. To add something, reply to our email.' using errcode = '23505'; -- says so kindly
  end if;
  if v_ip is not null and (select count(*) from public.tutor_applications a where a.ip_hash = v_ip and a.created_at > now() - interval '1 day') >= 3 then -- 3 or more today from the same place
    raise exception 'Too many applications have come from your connection today. Please try again tomorrow.' using errcode = '23514'; -- says why
  end if;
  if (select count(*) from public.tutor_applications a where a.created_at > now() - interval '1 day') >= 100 then -- 100 or more today in total (a flood)
    raise exception 'We''re receiving a lot of applications right now. Please try again tomorrow.' using errcode = '23514'; -- says why
  end if;
  if v_cv is not null and not exists (select 1 from storage.objects o where o.bucket_id = 'tutor-applications' and o.name = v_cv) then -- the CV isn't in the file store
    raise exception 'Your CV didn''t upload. Please try again.' using errcode = '23514'; -- asks to try again
  end if;

  insert into public.tutor_applications ( -- saves the application
    first_name, last_name, email, phone, state, suburb, teach_mode, right_to_work, -- about them,
    subjects, availability, weekly_hours, qualifications, teacher_registration, experience, -- what they teach and their background,
    wwcc_status, wwcc_number, wwcc_state, wwcc_expiry, rrhan_ec_status, first_aid_status, -- their checks,
    referees, statement, helped_example, heard_from, cv_path, -- referees, their words and CV,
    declared_true, declared_suitable, privacy_version, ip_hash -- what they agreed to, and the spam limit address
  ) values ( -- with:
    btrim(p ->> 'first_name'), btrim(p ->> 'last_name'), v_email, btrim(p ->> 'phone'), -- name, email and phone,
    p ->> 'state', btrim(p ->> 'suburb'), p ->> 'teach_mode', (p ->> 'right_to_work')::boolean, -- state, suburb, how they teach, right to work,
    btrim(p ->> 'subjects'), btrim(p ->> 'availability'), nullif(p ->> 'weekly_hours', '')::integer, -- subjects, availability, hours a week,
    btrim(p ->> 'qualifications'), nullif(btrim(coalesce(p ->> 'teacher_registration', '')), ''), btrim(p ->> 'experience'), -- qualifications, registration, experience,
    p ->> 'wwcc_status', nullif(btrim(coalesce(p ->> 'wwcc_number', '')), ''), nullif(p ->> 'wwcc_state', ''), nullif(p ->> 'wwcc_expiry', '')::date, -- Working with Children Check,
    p ->> 'rrhan_ec_status', p ->> 'first_aid_status', -- RRHAN-EC and first aid,
    p -> 'referees', btrim(p ->> 'statement'), btrim(p ->> 'helped_example'), nullif(btrim(coalesce(p ->> 'heard_from', '')), ''), v_cv, -- referees, statement, example, how they heard, CV,
    true, true, coalesce(p ->> 'privacy_version', 'unknown'), v_ip -- both declarations, the notice version, and the scrambled address
  ) returning id into v_id; -- keeps the new id (the table's own checks refuse anything out of range)
  return v_id; -- gives back the new id
end;
$$;
revoke execute on function public.tutor_application_submit(jsonb, text) from public, anon, authenticated; -- not callable with the public key, so the app's spam checks can't be skipped
grant execute on function public.tutor_application_submit(jsonb, text) to service_role; -- only the app's server

-- ---------------------------------------------------------------------------
-- Admins: save the screening record and move an application along.
-- ---------------------------------------------------------------------------
-- Saves the interview, referee checks, Working with Children Check
-- verification and notes, and sets the status to new, shortlisted or
-- withdrawn. (Approving and declining have their own functions below.)
create or replace function public.tutor_application_save(p_id uuid, p jsonb) -- which application, and the screening record as a bundle
returns void language plpgsql security definer -- gives nothing back; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_status text := coalesce(p ->> 'status', 'shortlisted'); -- the status asked for (shortlisted if not given)
  v_now text; -- the application's current status
begin
  if not private.is_admin() then -- not the owner or an Operations admin
    raise exception 'Only the owner and Operations admins can review tutor applications.' using errcode = '42501'; -- refuses
  end if;
  if v_status not in ('new', 'shortlisted', 'withdrawn') then -- not one of the statuses this function sets
    raise exception 'Choose New, Shortlisted or Withdrawn here. Use Approve or Decline to decide.' using errcode = '22023'; -- explains
  end if;
  select a.status into v_now from public.tutor_applications a where a.id = p_id for update; -- reads (and holds) the current status
  if v_now is null then -- no such application
    raise exception 'That application wasn''t found.' using errcode = '02000'; -- says so
  end if;
  if v_now in ('approved', 'declined') then -- already decided: only the screening record and notes change
    v_status := v_now; -- so it keeps its status (approving and declining can't be undone here)
  end if;
  update public.tutor_applications a set -- saves the screening record:
    status = v_status, -- the status (decided ones keep theirs, see above),
    interview_on = nullif(p ->> 'interview_on', '')::date, -- interview date,
    interview_notes = nullif(btrim(coalesce(p ->> 'interview_notes', '')), ''), -- interview notes,
    referee_1_checked_on = nullif(p ->> 'referee_1_checked_on', '')::date, -- first referee checked,
    referee_2_checked_on = nullif(p ->> 'referee_2_checked_on', '')::date, -- second referee checked,
    referee_notes = nullif(btrim(coalesce(p ->> 'referee_notes', '')), ''), -- referee notes,
    wwcc_verified_on = nullif(p ->> 'wwcc_verified_on', '')::date, -- check verified with the screening unit,
    admin_notes = nullif(btrim(coalesce(p ->> 'admin_notes', '')), ''), -- other notes,
    decided_at = case when v_status = 'withdrawn' and v_now <> 'withdrawn' then now() when v_status in ('new', 'shortlisted') then null else a.decided_at end, -- stamps when it was withdrawn (cleared if reopened; kept for decided ones),
    decided_by = case when v_status = 'withdrawn' and v_now <> 'withdrawn' then auth.uid() when v_status in ('new', 'shortlisted') then null else a.decided_by end, -- and who withdrew it,
    reviewed_by = auth.uid(), -- who changed it,
    updated_at = now() -- and when
  where a.id = p_id; -- only this application
end;
$$;
revoke execute on function public.tutor_application_save(uuid, jsonb) from public, anon; -- not for people who aren't signed in
grant execute on function public.tutor_application_save(uuid, jsonb) to authenticated; -- signed-in people (the function checks for a full admin)

-- Declines an application with a reason from the list (and an optional note).
create or replace function public.tutor_application_decline(p_id uuid, p_reason text, p_note text) -- which application, why, and any note
returns text language plpgsql security definer -- gives back the applicant's email (for a polite email); runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_row public.tutor_applications; -- the application
begin
  if not private.is_admin() then -- not the owner or an Operations admin
    raise exception 'Only the owner and Operations admins can review tutor applications.' using errcode = '42501'; -- refuses
  end if;
  if p_reason is null or p_reason not in ('not_needed', 'location_times', 'experience', 'referees', 'child_safety', 'no_reply', 'other') then -- no reason, or not one on the list
    raise exception 'Choose a reason for declining.' using errcode = '22023'; -- asks for one
  end if;
  select * into v_row from public.tutor_applications a where a.id = p_id for update; -- reads (and holds) the application
  if v_row.id is null then -- no such application
    raise exception 'That application wasn''t found.' using errcode = '02000'; -- says so
  end if;
  if v_row.status = 'approved' then -- already approved
    raise exception 'This application has already been approved.' using errcode = '22023'; -- refuses
  end if;
  update public.tutor_applications a set -- records the decline:
    status = 'declined', -- the status,
    decline_reason = p_reason, -- the reason,
    decline_note = nullif(left(btrim(coalesce(p_note, '')), 1000), ''), -- any note (cut to 1,000 characters),
    decided_at = now(), decided_by = auth.uid(), -- when and who,
    reviewed_by = auth.uid(), updated_at = now() -- and who last changed it
  where a.id = p_id; -- only this application
  return v_row.email; -- gives back their email
end;
$$;
revoke execute on function public.tutor_application_decline(uuid, text, text) from public, anon; -- not for people who aren't signed in
grant execute on function public.tutor_application_decline(uuid, text, text) to authenticated; -- signed-in people (the function checks for a full admin)

-- Approves an application. Only allowed once the interview and both
-- referee checks are recorded, and the person said they have the right to
-- work in Australia (child-safe recruitment). Gives back their email so the
-- app can send the staff invite link.
create or replace function public.tutor_application_approve(p_id uuid) -- which application
returns text language plpgsql security definer -- gives back the applicant's email; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_row public.tutor_applications; -- the application
begin
  if not private.is_admin() then -- not the owner or an Operations admin
    raise exception 'Only the owner and Operations admins can review tutor applications.' using errcode = '42501'; -- refuses
  end if;
  select * into v_row from public.tutor_applications a where a.id = p_id for update; -- reads (and holds) the application
  if v_row.id is null then -- no such application
    raise exception 'That application wasn''t found.' using errcode = '02000'; -- says so
  end if;
  if v_row.status = 'approved' then -- already approved
    return v_row.email; -- nothing more to do; gives back the email so the invite can be sent again
  end if;
  if v_row.status in ('declined', 'withdrawn') then -- closed
    raise exception 'This application is closed. The person can apply again if things have changed.' using errcode = '22023'; -- explains
  end if;
  if v_row.interview_on is null then -- no interview recorded
    raise exception 'Record the interview before approving.' using errcode = '22023'; -- says what's missing
  end if;
  if v_row.referee_1_checked_on is null or v_row.referee_2_checked_on is null then -- referees not both checked
    raise exception 'Record both referee checks before approving.' using errcode = '22023'; -- says what's missing
  end if;
  if not v_row.right_to_work then -- said no to right to work
    raise exception 'This person said they don''t have the right to work in Australia, so they can''t be employed.' using errcode = '22023'; -- explains
  end if;
  update public.tutor_applications a set -- records the approval:
    status = 'approved', -- the status,
    decline_reason = null, decline_note = null, -- clears any earlier decline details,
    decided_at = now(), decided_by = auth.uid(), -- when and who,
    reviewed_by = auth.uid(), updated_at = now() -- and who last changed it
  where a.id = p_id; -- only this application
  return v_row.email; -- gives back their email for the invite
end;
$$;
revoke execute on function public.tutor_application_approve(uuid) from public, anon; -- not for people who aren't signed in
grant execute on function public.tutor_application_approve(uuid) to authenticated; -- signed-in people (the function checks for a full admin)

-- Notes that the staff invite has been sent for an approved application.
create or replace function public.tutor_application_invited(p_id uuid) -- which application
returns void language plpgsql security definer -- gives nothing back; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
begin
  if not private.is_admin() then -- not the owner or an Operations admin
    raise exception 'Only the owner and Operations admins can review tutor applications.' using errcode = '42501'; -- refuses
  end if;
  update public.tutor_applications a set invited_at = now(), updated_at = now() -- stamps when the invite went
  where a.id = p_id and a.status = 'approved'; -- only for this application, and only if approved
end;
$$;
revoke execute on function public.tutor_application_invited(uuid) from public, anon; -- not for people who aren't signed in
grant execute on function public.tutor_application_invited(uuid) to authenticated; -- signed-in people (the function checks for a full admin)

-- ---------------------------------------------------------------------------
-- The daily tidy-up (the app's server only).
-- ---------------------------------------------------------------------------
-- Deletes applications past their keeping period, queues their CVs for
-- removal, and clears scrambled addresses older than 30 days. Gives back
-- how many applications were deleted.
create or replace function public.tutor_applications_tidy() -- no inputs
returns integer language plpgsql security definer -- gives back a count; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$
declare
  v_count integer; -- how many were deleted
begin
  with gone as ( -- the applications to delete:
    delete from public.tutor_applications a -- deletes from the applications
    where (a.status in ('declined', 'withdrawn') and a.decided_at < now() - interval '12 months') -- declined or withdrawn more than 12 months ago,
       or (a.status in ('new', 'shortlisted') and a.created_at < now() - interval '12 months') -- never decided, sent more than 12 months ago,
       or (a.status = 'approved' and a.decided_at < now() - interval '7 years') -- or approved more than 7 years ago
    returning a.cv_path -- keeping each one's CV path
  ), queued as ( -- then queues the CVs:
    insert into public.tutor_application_file_removals (file_path) -- into the removal list
    select cv_path from gone where cv_path is not null -- each CV there was
    on conflict (file_path) do nothing -- (once each)
    returning 1 -- (needed so this step runs)
  )
  select count(*) into v_count from gone; -- counts what was deleted
  update public.tutor_applications a set ip_hash = null -- clears the scrambled address
  where a.ip_hash is not null and a.created_at < now() - interval '30 days'; -- once it's more than 30 days old
  return v_count; -- gives back the count
end;
$$;
revoke execute on function public.tutor_applications_tidy() from public, anon, authenticated; -- not for anyone signed in
grant execute on function public.tutor_applications_tidy() to service_role; -- only the app's server

-- The CV files waiting to be removed (for the daily job).
create or replace function public.tutor_application_files_to_remove() -- no inputs
returns text[] language sql stable security definer -- gives back a list of paths; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ select coalesce(array_agg(file_path order by queued_at), '{}') from public.tutor_application_file_removals $$; -- every queued path, oldest first
revoke execute on function public.tutor_application_files_to_remove() from public, anon, authenticated; -- not for anyone signed in
grant execute on function public.tutor_application_files_to_remove() to service_role; -- only the app's server

-- The daily job says these CV files are gone; takes them off the list.
create or replace function public.tutor_application_files_removed(p_paths text[]) -- the removed paths
returns void language sql security definer -- gives nothing back; runs with the owner's rights
set search_path = '' -- no hidden schema lookups (safety)
as $$ delete from public.tutor_application_file_removals where file_path = any (p_paths) $$; -- takes them off the list
revoke execute on function public.tutor_application_files_removed(text[]) from public, anon, authenticated; -- not for anyone signed in
grant execute on function public.tutor_application_files_removed(text[]) to service_role; -- only the app's server
