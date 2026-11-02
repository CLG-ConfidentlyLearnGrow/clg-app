-- Privacy rights baseline: the parts of privacy law that apply in every
-- region CLG plans to work in (Australia, New Zealand, the UK, the EU,
-- Canada and the US). Where the regions differ, the strictest rule is used.
-- See docs/features/privacy-laws-baseline.md.
--
-- What this adds:
--   1. Privacy requests. Anyone can ask to see, correct or delete their
--      information, object, withdraw consent or complain. Each request gets
--      a due date 28 days after it arrives. That fits every region: the EU
--      and UK allow 1 month, Australia and Canada 30 days, New Zealand 20
--      working days (never less than 28 days). Complaints must be
--      acknowledged (UK rule since June 2026: within 30 days).
--   2. Download my information. my_data_export() gathers everything the
--      signed-in person is allowed to see about themselves and the children
--      they manage, as one file (access and portability rights). It runs
--      with the person's own access rules, so it can never show more than
--      the app already shows them.
--   3. Breach register. Every suspected breach is recorded, even small ones
--      (Canada keeps all breach records for at least 24 months). The app
--      shows the two clocks: 72 hr to decide whether to tell regulators (EU
--      and UK rule), and 30 days at most to finish the assessment
--      (Australian rule).
--   4. Parental consent for each child, renewed every 12 months (Australia's
--      draft Children's Online Privacy Code caps consent at 12 months; COPPA
--      and the GDPR need a parent's consent for young children).
--   5. Marketing emails off unless the person turns them on (Spam Act,
--      CASL, GDPR, NZ Unsolicited Electronic Messages Act).
--
-- Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Privacy requests
-- ---------------------------------------------------------------------------

create table if not exists public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  -- Kept if the person's account is later deleted, as proof the request
  -- was handled (but without their name).
  account_id uuid references public.accounts (id) on delete set null,
  student_id uuid references public.students (id) on delete set null,
  kind text not null check (kind in (
    'access',       -- see my information
    'correction',   -- fix something wrong
    'deletion',     -- delete my or my child's information
    'restriction',  -- stop using it for a while, or object to a use
    'consent',      -- withdraw a consent
    'complaint',    -- complain about how CLG handled information
    'other'
  )),
  details text not null check (char_length(btrim(details)) between 3 and 2000),
  status text not null default 'received'
    check (status in ('received', 'in_progress', 'done', 'refused')),
  received_at timestamptz not null default now(),
  due_on date not null default (current_date + 28),
  acknowledged_at timestamptz,
  -- Allowed in the EU, UK and NZ for complex requests, with a reason given
  -- to the person before the first due date.
  extended_to date,
  extension_reason text check (extension_reason is null or char_length(extension_reason) <= 500),
  -- What CLG did, or why it refused. Shown to the person.
  outcome text check (outcome is null or char_length(outcome) <= 2000),
  handled_by uuid references public.accounts (id) on delete set null,
  closed_at timestamptz,
  check (extended_to is null or extension_reason is not null),
  check ((status in ('done', 'refused')) = (closed_at is not null)),
  check (status <> 'refused' or outcome is not null)
);
create index if not exists privacy_requests_account on public.privacy_requests (account_id);
create index if not exists privacy_requests_open on public.privacy_requests (due_on) where closed_at is null;

alter table public.privacy_requests enable row level security;
revoke all on public.privacy_requests from anon;
-- Only the functions below write requests.
revoke insert, update, delete, truncate on public.privacy_requests from authenticated;

drop policy if exists "see own privacy requests, admins see all" on public.privacy_requests;
create policy "see own privacy requests, admins see all" on public.privacy_requests
  for select to authenticated using (account_id = auth.uid() or private.is_admin());

drop trigger if exists audit on public.privacy_requests;
create trigger audit after insert or update or delete on public.privacy_requests
  for each row execute function private.audit_change();

-- Anyone signed in makes a request about themselves, or about a child they
-- manage.
create or replace function public.make_privacy_request(p_kind text, p_details text, p_student uuid default null)
returns uuid language plpgsql security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first' using errcode = '42501';
  end if;
  if p_student is not null
     and not (private.can_manage_student(p_student) or private.is_student_self(p_student)) then
    raise exception 'You can only ask about yourself or a child you look after' using errcode = '42501';
  end if;
  if (select count(*) from public.privacy_requests
      where account_id = auth.uid() and received_at > now() - interval '1 day') >= 10 then
    raise exception 'You have sent a lot of requests today. CLG will reply to the ones already sent.'
      using errcode = '54000';
  end if;
  insert into public.privacy_requests (account_id, student_id, kind, details)
  values (auth.uid(), p_student, p_kind, btrim(p_details))
  returning id into v_id;
  return v_id;
end;
$$;

-- An admin (owner or operations) records progress on a request.
create or replace function public.update_privacy_request(
  p_id uuid,
  p_status text,
  p_outcome text default null,
  p_extend_to date default null,
  p_extension_reason text default null
)
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  r public.privacy_requests;
begin
  if not private.is_admin() then
    raise exception 'Only an owner or operations admin can handle privacy requests' using errcode = '42501';
  end if;
  select * into r from public.privacy_requests where id = p_id for update;
  if r.id is null then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if r.closed_at is not null then
    raise exception 'This request is already closed' using errcode = '23514';
  end if;
  if p_status not in ('in_progress', 'done', 'refused') then
    raise exception 'Choose in progress, done or refused' using errcode = '22023';
  end if;
  if p_status = 'refused' and nullif(btrim(p_outcome), '') is null then
    raise exception 'Write the reason for refusing. The person will see it, and they can complain to the privacy regulator.'
      using errcode = '23514';
  end if;
  if p_extend_to is not null then
    if r.extended_to is not null then
      raise exception 'A request can only be extended once' using errcode = '23514';
    end if;
    if current_date > r.due_on then
      raise exception 'It is too late to extend: extend before the due date' using errcode = '23514';
    end if;
    -- The GDPR allows up to two extra months; the shortest region limit
    -- for the whole request is 3 months from receipt.
    if p_extend_to <= r.due_on or p_extend_to > (r.received_at::date + 90) then
      raise exception 'The new date must be after the due date and within 90 days of the request' using errcode = '22023';
    end if;
    if nullif(btrim(p_extension_reason), '') is null then
      raise exception 'Write why more time is needed. The person must be told.' using errcode = '23514';
    end if;
  end if;

  update public.privacy_requests set
    status = p_status,
    outcome = coalesce(nullif(btrim(p_outcome), ''), outcome),
    acknowledged_at = coalesce(acknowledged_at, now()),
    extended_to = coalesce(p_extend_to, extended_to),
    extension_reason = coalesce(nullif(btrim(p_extension_reason), ''), extension_reason),
    handled_by = auth.uid(),
    closed_at = case when p_status in ('done', 'refused') then now() end
  where id = p_id;
end;
$$;

revoke all on function public.make_privacy_request(text, text, uuid) from public, anon;
revoke all on function public.update_privacy_request(uuid, text, text, date, text) from public, anon;
grant execute on function public.make_privacy_request(text, text, uuid) to authenticated;
grant execute on function public.update_privacy_request(uuid, text, text, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Download my information
-- ---------------------------------------------------------------------------

-- Runs with the signed-in person's own rights (not security definer), so
-- every table's access rules still apply. For each table it picks the rows
-- about this person: their own rows (account_id, parent_id, tutor_id,
-- payer_id, bill_payer_id, requested_by), rows about the children they
-- manage (student_id) and rows about their family (family_id). New modules
-- are included automatically when they use these column names.
create or replace function public.my_data_export()
returns jsonb language plpgsql stable
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_students uuid[];
  v_families uuid[];
  v_out jsonb := '{}';
  v_skipped text[] := '{}';
  t record;
  v_cols text;
  v_where text;
  v_rows jsonb;
begin
  if v_me is null then
    raise exception 'Please sign in first' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct s.id), '{}'), coalesce(array_agg(distinct s.family_id) filter (where s.family_id is not null), '{}')
  into v_students, v_families
  from public.students s
  where s.account_id = v_me
     or exists (select 1 from public.parent_student_links l where l.parent_id = v_me and l.student_id = s.id);

  for t in
    select c.oid, c.relname,
           array_agg(a.attname::text) filter (where a.attname in
             ('account_id', 'parent_id', 'tutor_id', 'payer_id', 'bill_payer_id', 'requested_by')) as self_cols,
           bool_or(a.attname = 'student_id') as has_student,
           bool_or(a.attname = 'family_id') as has_family
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    where n.nspname = 'public' and c.relkind in ('r', 'p')
      and c.relname not in ('audit_log', 'privacy_incidents', 'retention_log')
    group by c.oid, c.relname
    order by c.relname
  loop
    -- Who the rows are about.
    v_where := case t.relname
      when 'accounts' then format('id = %L', v_me)
      when 'students' then format('id = any (%L::uuid[])', v_students)
      when 'families' then format('id = any (%L::uuid[])', v_families)
      else null end;
    if v_where is null then
      select string_agg(x, ' or ') into v_where from (
        select format('%I = %L', col, v_me) as x from unnest(coalesce(t.self_cols, '{}')) col
        union all
        select format('student_id = any (%L::uuid[])', v_students) where t.has_student
        union all
        select format('family_id = any (%L::uuid[])', v_families) where t.has_family
      ) w;
    end if;
    continue when v_where is null;

    -- Only the columns this person may read (some tables hide some columns).
    select string_agg(format('%I', a.attname), ', ' order by a.attnum) into v_cols
    from pg_catalog.pg_attribute a
    where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
      and pg_catalog.has_column_privilege(t.oid, a.attnum, 'SELECT');
    continue when v_cols is null;

    begin
      execute format('select coalesce(jsonb_agg(to_jsonb(r)), ''[]'') from (select %s from public.%I where %s) r',
                     v_cols, t.relname, v_where)
        into v_rows;
      if jsonb_array_length(v_rows) > 0 then
        v_out := v_out || jsonb_build_object(t.relname, v_rows);
      end if;
    exception when insufficient_privilege then
      v_skipped := v_skipped || t.relname::text;
    end;
  end loop;

  return jsonb_build_object(
    'about', 'Everything the CLG app holds about you and the children you look after, that you are allowed to see. '
             || 'Learning-needs notes, staff notes and anything else not shown here can be asked for through a privacy request.',
    'made_at', now(),
    'account_id', v_me,
    'records', v_out,
    'not_included', to_jsonb(v_skipped)
  );
end;
$$;

-- The download is logged (who and when, not what), like other sensitive views.
create or replace function public.log_my_data_export()
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in first' using errcode = '42501';
  end if;
  perform private.log_event('export_own_data', 'accounts', auth.uid()::text);
end;
$$;

revoke all on function public.my_data_export() from public, anon;
revoke all on function public.log_my_data_export() from public, anon;
grant execute on function public.my_data_export() to authenticated;
grant execute on function public.log_my_data_export() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Breach register
-- ---------------------------------------------------------------------------

create table if not exists public.privacy_incidents (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 3 and 200),
  -- When CLG first knew. Both clocks start here.
  found_at timestamptz not null default now(),
  what_happened text not null check (char_length(btrim(what_happened)) between 3 and 4000),
  data_involved text check (data_involved is null or char_length(data_involved) <= 1000),
  people_affected integer check (people_affected is null or people_affected >= 0),
  children_affected boolean not null default false,
  -- Where the people affected live: decides which regulators may need telling.
  regions text[] not null default '{AU}'
    check (regions <@ array['AU', 'NZ', 'UK', 'EU', 'CA', 'US'] and cardinality(regions) > 0),
  contained_at timestamptz,
  -- The assessment: is serious harm likely? Null until decided.
  serious_harm_likely boolean,
  assessed_at timestamptz,
  decision_reason text check (decision_reason is null or char_length(decision_reason) <= 2000),
  regulators_told_at timestamptz,
  regulators_told text check (regulators_told is null or char_length(regulators_told) <= 500),
  people_told_at timestamptz,
  lessons text check (lessons is null or char_length(lessons) <= 4000),
  closed_at timestamptz,
  recorded_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  check (assessed_at is null or serious_harm_likely is not null),
  -- If serious harm is likely, regulators must be told before closing.
  check (closed_at is null or (assessed_at is not null and (serious_harm_likely = false or regulators_told_at is not null)))
);
create index if not exists privacy_incidents_open on public.privacy_incidents (found_at) where closed_at is null;

alter table public.privacy_incidents enable row level security;
revoke all on public.privacy_incidents from anon;
revoke delete, truncate on public.privacy_incidents from authenticated;

drop policy if exists "admins read breach register" on public.privacy_incidents;
create policy "admins read breach register" on public.privacy_incidents
  for select to authenticated using (private.is_admin());
drop policy if exists "admins record breaches" on public.privacy_incidents;
create policy "admins record breaches" on public.privacy_incidents
  for insert to authenticated with check (private.is_admin());
drop policy if exists "admins update breaches" on public.privacy_incidents;
create policy "admins update breaches" on public.privacy_incidents
  for update to authenticated using (private.is_admin() and closed_at is null) with check (private.is_admin());

-- Who recorded it is stamped; when it was found can't be moved later, so the
-- clocks can't be reset. Closed records can't change.
create or replace function private.stamp_privacy_incident()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.recorded_by := auth.uid();
    new.created_at := now();
    if new.found_at > now() + interval '5 minutes' then
      raise exception 'The date found can''t be in the future' using errcode = '22023';
    end if;
  else
    if new.found_at is distinct from old.found_at
       or new.recorded_by is distinct from old.recorded_by
       or new.created_at is distinct from old.created_at then
      raise exception 'When a breach was found can''t be changed after it is recorded' using errcode = '42501';
    end if;
  end if;
  if new.serious_harm_likely is not null and new.assessed_at is null then
    new.assessed_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists stamp on public.privacy_incidents;
create trigger stamp before insert or update on public.privacy_incidents
  for each row execute function private.stamp_privacy_incident();

drop trigger if exists audit on public.privacy_incidents;
create trigger audit after insert or update or delete on public.privacy_incidents
  for each row execute function private.audit_change();

-- The deadlines for each breach, and what to do next, in plain words.
create or replace view public.privacy_incident_deadlines
with (security_invoker = true) as
select
  i.id,
  i.found_at + interval '72 hours' as decide_by,
  i.found_at + interval '30 days' as assess_by,
  case
    when i.closed_at is not null then 'Closed'
    when i.contained_at is null then 'Contain it: stop the leak, change passwords, get the information back'
    when i.assessed_at is null then 'Decide whether serious harm is likely'
    when i.serious_harm_likely and i.regulators_told_at is null then 'Tell the regulators and the people affected now'
    when i.serious_harm_likely and i.people_told_at is null then 'Tell the people affected'
    else 'Write what was learned, then close it'
  end as next_step,
  (i.closed_at is null and i.assessed_at is null and now() > i.found_at + interval '72 hours') as decision_overdue
from public.privacy_incidents i;
revoke all on public.privacy_incident_deadlines from anon;

-- ---------------------------------------------------------------------------
-- 4. Parental consent for each child, renewed every 12 months
-- ---------------------------------------------------------------------------

-- Children (under 18, no login of their own) that this parent looks after
-- and who have no parental consent from any of their parents in the last
-- 12 months.
create or replace function public.children_needing_consent()
returns table (student_id uuid, full_name text, last_given timestamptz)
language sql stable security definer
set search_path = ''
as $$
  select s.id, s.full_name,
         (select max(c.given_at) from public.consent_records c
          where c.student_id = s.id and c.kind = 'parental_consent' and c.withdrawn_at is null)
  from public.parent_student_links l
  join public.students s on s.id = l.student_id
  where l.parent_id = auth.uid()
    and l.can_manage
    and s.account_id is null
    and s.date_of_birth > (current_date - interval '18 years')::date
    and not exists (
      select 1 from public.consent_records c
      where c.student_id = s.id and c.kind = 'parental_consent'
        and c.withdrawn_at is null and c.given_at > now() - interval '12 months'
    )
  order by s.full_name
$$;

-- A parent gives consent for one child.
create or replace function public.give_parental_consent(p_student uuid, p_version text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if not private.can_manage_student(p_student) then
    raise exception 'Only a parent who looks after this child can give consent' using errcode = '42501';
  end if;
  if nullif(btrim(p_version), '') is null then
    raise exception 'Missing policy version' using errcode = '22023';
  end if;
  insert into public.consent_records (account_id, student_id, kind, document_version)
  values (auth.uid(), p_student, 'parental_consent', left(btrim(p_version), 40));
end;
$$;

revoke all on function public.children_needing_consent() from public, anon;
revoke all on function public.give_parental_consent(uuid, text) from public, anon;
grant execute on function public.children_needing_consent() to authenticated;
grant execute on function public.give_parental_consent(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Marketing emails: off unless turned on
-- ---------------------------------------------------------------------------

create or replace function public.my_marketing_email()
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.consent_records
    where account_id = auth.uid() and kind = 'marketing_email' and withdrawn_at is null
  )
$$;

create or replace function public.set_marketing_email(p_on boolean, p_version text)
returns void language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in first' using errcode = '42501';
  end if;
  if p_on then
    if not public.my_marketing_email() then
      insert into public.consent_records (account_id, kind, document_version)
      values (auth.uid(), 'marketing_email', left(coalesce(nullif(btrim(p_version), ''), 'unknown'), 40));
    end if;
  else
    update public.consent_records set withdrawn_at = now()
    where account_id = auth.uid() and kind = 'marketing_email' and withdrawn_at is null;
  end if;
end;
$$;

revoke all on function public.my_marketing_email() from public, anon;
revoke all on function public.set_marketing_email(boolean, text) from public, anon;
grant execute on function public.my_marketing_email() to authenticated;
grant execute on function public.set_marketing_email(boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. How long these records are kept
-- ---------------------------------------------------------------------------

-- Closed privacy requests and breach records are kept for the activity log
-- period (7 years, the owner can change it), then deleted. Canada needs
-- breach records for at least 24 months; 7 years also covers claims.
create or replace function private.purge_privacy_records()
returns void language plpgsql security definer
set search_path = ''
as $$
declare
  v_keep interval := coalesce(private.keep_for('activity_log'), interval '7 years');
begin
  delete from public.privacy_requests where closed_at < now() - v_keep;
  delete from public.privacy_incidents where closed_at < now() - v_keep;
end;
$$;
revoke all on function private.purge_privacy_records() from public;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute 'create extension if not exists pg_cron with schema pg_catalog';
    if not exists (select 1 from cron.job where jobname = 'clg-privacy-records-nightly') then
      execute $job$
        select cron.schedule('clg-privacy-records-nightly', '15 17 * * *', 'select private.purge_privacy_records()')
      $job$;
    end if;
  end if;
end;
$$;
