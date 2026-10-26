-- CLG base schema: accounts, roles, profiles, families, links, enrolments,
-- consent and audit records.
--
-- Access rules live in the next migration. Every table here has row level
-- security turned on, so nothing is readable until a rule allows it.

create schema if not exists private;
revoke all on schema private from public;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type public.app_role as enum ('admin', 'tutor', 'parent', 'student');
create type public.admin_level as enum ('owner', 'staff');

-- Australian states and territories. Child safety rules differ by state.
create type public.au_state as enum ('SA', 'NSW', 'VIC', 'QLD', 'WA', 'TAS', 'ACT', 'NT');

-- Child safety checks and training a tutor can hold. Which ones a tutor
-- needs depends on where the student is (see check_requirements).
create type public.tutor_check_kind as enum (
  'wwcc_sa',                 -- SA Working With Children Check
  'wwcc_nsw',                -- NSW Working With Children Check
  'wwc_vic',                 -- VIC Working with Children Check
  'blue_card_qld',           -- QLD blue card
  'wwc_wa',                  -- WA Working with Children Check
  'rwvp_tas',                -- TAS Registration to Work with Vulnerable People
  'wwvp_act',                -- ACT Working with Vulnerable People registration
  'ochre_card_nt',           -- NT Working with Children Clearance (Ochre Card)
  'rrhan_ec_fundamentals',   -- SA RRHAN-EC Fundamentals
  'rrhan_ec_masterclass',    -- SA RRHAN-EC Masterclass
  'police_check'             -- National police check (valid 5 years from issue)
);

-- Whose location a requirement follows: the student's state, or the state
-- the tutor works from.
create type public.requirement_basis as enum ('student_state', 'tutor_state');

create type public.enrolment_status as enum ('pending_payment', 'active', 'ended');

create type public.consent_kind as enum (
  'privacy_policy',
  'terms_of_service',
  'child_safe_policy',
  'parental_consent',
  'marketing_email'
);

-- ---------------------------------------------------------------------------
-- Accounts and roles
-- ---------------------------------------------------------------------------

-- One row per login. Only names live here, so other people can be shown a
-- name without ever seeing contact details.
create table public.accounts (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (char_length(full_name) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Contact details: visible only to the person and to admins.
create table public.account_private (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  email text not null,
  phone text check (phone is null or char_length(phone) <= 40),
  updated_at timestamptz not null default now()
);

create table public.account_roles (
  account_id uuid not null references public.accounts (id) on delete cascade,
  role public.app_role not null,
  granted_by uuid references public.accounts (id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (account_id, role)
);

-- Tutors and admins join by invitation only. An admin records the
-- invitation here, then the app sends the invite email.
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(email)),
  role public.app_role not null check (role in ('admin', 'tutor')),
  invited_by uuid not null references public.accounts (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz
);
create unique index invitations_one_open_per_email
  on public.invitations (email) where accepted_at is null;

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.admin_profiles (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  level public.admin_level not null default 'staff'
);

create table public.tutor_profiles (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  subjects text[] not null default '{}',
  bio text check (bio is null or char_length(bio) <= 2000),
  active boolean not null default true
);

-- Where a tutor works from and how many hours a week they can work. Kept
-- apart from the public profile, so families never see it.
create table public.tutor_work_settings (
  tutor_id uuid primary key references public.tutor_profiles (account_id) on delete cascade,
  work_state public.au_state,
  max_weekly_hours numeric(4, 1) check (max_weekly_hours is null or max_weekly_hours between 0 and 60),
  updated_at timestamptz not null default now()
);

-- When a tutor is available, as weekly time slots. Separate from their
-- maximum weekly hours: a tutor may be available for more hours than they
-- can work.
create table public.tutor_availability (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 7), -- 1 = Monday
  starts_at time not null,
  ends_at time not null,
  check (ends_at > starts_at)
);
create index tutor_availability_tutor on public.tutor_availability (tutor_id, weekday);

-- Child safety checks and training records. Entered and verified by an admin.
create table public.tutor_checks (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  kind public.tutor_check_kind not null,
  reference text check (reference is null or char_length(reference) <= 100),
  completed_on date,
  expires_on date not null,
  verified_by uuid references public.accounts (id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index tutor_checks_tutor on public.tutor_checks (tutor_id, kind, expires_on);

-- Which checks are needed for each state. Admins can change these rows as
-- rules change, without a code change.
create table public.check_requirements (
  state public.au_state not null,
  kind public.tutor_check_kind not null,
  basis public.requirement_basis not null,
  primary key (state, kind, basis)
);

insert into public.check_requirements (state, kind, basis) values
  -- A tutor needs the check for the state where the student is...
  ('SA', 'wwcc_sa', 'student_state'),
  ('NSW', 'wwcc_nsw', 'student_state'),
  ('VIC', 'wwc_vic', 'student_state'),
  ('QLD', 'blue_card_qld', 'student_state'),
  ('WA', 'wwc_wa', 'student_state'),
  ('TAS', 'rwvp_tas', 'student_state'),
  ('ACT', 'wwvp_act', 'student_state'),
  ('NT', 'ochre_card_nt', 'student_state'),
  -- ...plus CLG's SA training for SA students...
  ('SA', 'rrhan_ec_fundamentals', 'student_state'),
  ('SA', 'rrhan_ec_masterclass', 'student_state'),
  -- ...plus CLG's own rule: a police check issued in the last 5 years, for
  -- every tutor, whatever the state...
  ('SA', 'police_check', 'student_state'),
  ('NSW', 'police_check', 'student_state'),
  ('VIC', 'police_check', 'student_state'),
  ('QLD', 'police_check', 'student_state'),
  ('WA', 'police_check', 'student_state'),
  ('TAS', 'police_check', 'student_state'),
  ('ACT', 'police_check', 'student_state'),
  ('NT', 'police_check', 'student_state'),
  -- ...and, per CLG's child safe policy, the check for the state the tutor
  -- works from (for example, a tutor in Victoria teaching online).
  ('SA', 'wwcc_sa', 'tutor_state'),
  ('NSW', 'wwcc_nsw', 'tutor_state'),
  ('VIC', 'wwc_vic', 'tutor_state'),
  ('QLD', 'blue_card_qld', 'tutor_state'),
  ('WA', 'wwc_wa', 'tutor_state'),
  ('TAS', 'rwvp_tas', 'tutor_state'),
  ('ACT', 'wwvp_act', 'tutor_state'),
  ('NT', 'ochre_card_nt', 'tutor_state');

create table public.parent_profiles (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  emergency_contact_name text check (char_length(emergency_contact_name) <= 200),
  emergency_contact_phone text check (char_length(emergency_contact_phone) <= 40),
  stripe_customer_id text
);

-- ---------------------------------------------------------------------------
-- Families and students
-- ---------------------------------------------------------------------------

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 200),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now()
);

-- A student is a record, not necessarily a login. Under-16s have no login
-- and are managed through a parent's account.
create table public.students (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families (id) on delete set null,
  account_id uuid unique references public.accounts (id) on delete set null,
  full_name text not null check (char_length(full_name) between 1 and 200),
  date_of_birth date not null check (date_of_birth > date '1900-01-01'),
  -- Where the student lives: decides which tutor checks apply.
  state public.au_state not null,
  year_level text check (char_length(year_level) <= 40),
  school text check (char_length(school) <= 200),
  goals text check (char_length(goals) <= 4000),
  -- Last lesson or enrolment activity; drives the 2-year retention rule.
  last_activity_at timestamptz not null default now(),
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index students_family on public.students (family_id);

-- Learning needs sit apart, readable only through read_student_sensitive(),
-- which records every view in the audit log.
create table public.student_sensitive (
  student_id uuid primary key references public.students (id) on delete cascade,
  learning_needs text check (char_length(learning_needs) <= 8000),
  support_strategies text check (char_length(support_strategies) <= 8000),
  updated_by uuid references public.accounts (id) on delete set null,
  updated_at timestamptz not null default now()
);

create table public.parent_student_links (
  parent_id uuid not null references public.parent_profiles (account_id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  relationship text not null default 'parent' check (char_length(relationship) <= 60),
  can_manage boolean not null default true,
  -- An admin confirms the link before any tutor is assigned.
  verified_by uuid references public.accounts (id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);
create index parent_student_links_student on public.parent_student_links (student_id);

create table public.tutor_assignments (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutor_profiles (account_id) on delete cascade,
  student_id uuid not null references public.students (id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  starts_on date not null default current_date,
  ends_on date,
  created_by uuid references public.accounts (id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on)
);
create index tutor_assignments_tutor on public.tutor_assignments (tutor_id, student_id);
create index tutor_assignments_student on public.tutor_assignments (student_id);

-- ---------------------------------------------------------------------------
-- Programs and enrolments (self-service and tutored support)
-- ---------------------------------------------------------------------------

create table public.programs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 200),
  description text check (char_length(description) <= 4000),
  self_service boolean not null default false,
  price_cents integer check (price_cents is null or price_cents >= 0),
  currency text not null default 'AUD' check (currency ~ '^[A-Z]{3}$'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.enrolments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id) on delete cascade,
  program_id uuid not null references public.programs (id) on delete restrict,
  status public.enrolment_status not null default 'pending_payment',
  starts_on date,
  ends_on date,
  stripe_subscription_id text,
  created_at timestamptz not null default now()
);
create index enrolments_student on public.enrolments (student_id);

-- ---------------------------------------------------------------------------
-- Consent and audit
-- ---------------------------------------------------------------------------

create table public.consent_records (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  student_id uuid references public.students (id) on delete cascade,
  kind public.consent_kind not null,
  document_version text not null check (char_length(document_version) <= 40),
  given_at timestamptz not null default now(),
  withdrawn_at timestamptz
);
create index consent_records_account on public.consent_records (account_id);

-- Append-only. Written by triggers and functions, readable by admins.
create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid,
  action text not null,
  table_name text not null,
  record_id text,
  details jsonb not null default '{}'
);
create index audit_log_record on public.audit_log (table_name, record_id);

-- Failed-login tracking for account lock. Private schema: not reachable
-- through the public API at all.
create table private.login_attempts (
  id bigint generated always as identity primary key,
  email text not null,
  succeeded boolean not null,
  attempted_at timestamptz not null default now()
);
create index login_attempts_email on private.login_attempts (email, attempted_at desc);

create table private.account_locks (
  email text primary key,
  locked_until timestamptz not null,
  locked_at timestamptz not null default now()
);

-- Row level security on for every public table.
alter table public.accounts enable row level security;
alter table public.account_private enable row level security;
alter table public.account_roles enable row level security;
alter table public.invitations enable row level security;
alter table public.admin_profiles enable row level security;
alter table public.tutor_profiles enable row level security;
alter table public.tutor_checks enable row level security;
alter table public.tutor_work_settings enable row level security;
alter table public.tutor_availability enable row level security;
alter table public.check_requirements enable row level security;
alter table public.parent_profiles enable row level security;
alter table public.families enable row level security;
alter table public.students enable row level security;
alter table public.student_sensitive enable row level security;
alter table public.parent_student_links enable row level security;
alter table public.tutor_assignments enable row level security;
alter table public.programs enable row level security;
alter table public.enrolments enable row level security;
alter table public.consent_records enable row level security;
alter table public.audit_log enable row level security;

-- Signed-out visitors get nothing from any table.
revoke all on all tables in schema public from anon;
