-- Minimal stand-in for the parts of Supabase the migrations rely on, so the
-- access rules can be tested against plain Postgres (see scripts/test-db.sh).
-- Not used in production: Supabase provides the real versions.

create role anon nologin noinherit; -- The "not signed in" role.
create role authenticated nologin noinherit; -- The "signed in" role.
create role service_role nologin noinherit bypassrls; -- The server's own role, which skips access rules.

create schema auth; -- A stand-in for Supabase's sign-in schema.
grant usage on schema auth to anon, authenticated, service_role; -- Lets all three roles use it.

create table auth.users ( -- A stand-in for Supabase's users table:
  id uuid primary key default gen_random_uuid(), -- each user's id,
  email text not null unique, -- their email (one account per email),
  raw_user_meta_data jsonb not null default '{}', -- details given at sign-up,
  raw_app_meta_data jsonb not null default '{}', -- details set by the app,
  invited_at timestamptz, -- when they were invited,
  email_confirmed_at timestamptz, -- when they confirmed their email,
  last_sign_in_at timestamptz, -- when they last signed in,
  created_at timestamptz not null default now() -- and when the account was made.
); -- End of the table.

create function auth.jwt() returns jsonb language sql stable as $$ -- A stand-in for Supabase's "who is signed in" details:
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb -- reads them from the test setting (or nothing).
$$; -- (end of the function)

create function auth.uid() returns uuid language sql stable as $$ -- A stand-in for Supabase's "signed-in user's id":
  select nullif(auth.jwt() ->> 'sub', '')::uuid -- takes it from those details.
$$; -- (end of the function)

grant usage on schema public to anon, authenticated, service_role; -- Lets all three roles use the public schema.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role; -- New tables there can be used by all three (access rules still apply).
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role; -- The same for number counters.
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role; -- The same for functions.

-- Storage (files). Only the parts the migrations use.
create schema storage; -- A stand-in for Supabase's file storage schema.
grant usage on schema storage to anon, authenticated, service_role; -- Lets all three roles use it.
create table storage.buckets ( -- The list of file stores:
  id text primary key, -- each one's id,
  name text not null, -- its name,
  public boolean default false, -- whether it's public,
  file_size_limit bigint, -- its largest file size,
  allowed_mime_types text[], -- the file types it allows,
  created_at timestamptz default now() -- and when it was made.
); -- End of the table.
create table storage.objects ( -- The list of stored files:
  id uuid primary key default gen_random_uuid(), -- each one's id,
  bucket_id text references storage.buckets (id), -- its file store,
  name text, -- its path,
  owner uuid, -- who uploaded it,
  metadata jsonb, -- details about it,
  created_at timestamptz default now(), -- when it was added,
  unique (bucket_id, name) -- (one file per path in each store).
); -- End of the table.
alter table storage.objects enable row level security; -- Turns on access rules for stored files.
grant all on storage.objects to anon, authenticated, service_role; -- Lets all three roles use the files (access rules decide what they see).
grant select on storage.buckets to anon, authenticated, service_role; -- Lets all three roles read the list of stores.
create function storage.foldername(name text) returns text[] language sql immutable as $$ -- A stand-in for Supabase's "folders in a path":
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] -- gives every part of the path except the file name.
$$; -- (end of the function)
