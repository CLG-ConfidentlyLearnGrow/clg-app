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

-- Child safety checks tutors must hold (South Australia).
create type public.tutor_check_kind as enum (
  'wwcc',                    -- Working With Children Check
  'rrhan_ec_fundamentals',   -- Responding to Risks of Harm, Abuse and Neglect: Fundamentals
  'rrhan_ec_masterclass'     -- RRHAN-EC Masterclass
);

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

-- WWCC and RRHAN-EC records. Entered and verified by an admin.
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

-- A student is a record, not necessarily a login. Under-15s have no login
-- and are managed through a parent's account.
create table public.students (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families (id) on delete set null,
  account_id uuid unique references public.accounts (id) on delete set null,
  full_name text not null check (char_length(full_name) between 1 and 200),
  date_of_birth date not null check (date_of_birth > date '1900-01-01'),
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
