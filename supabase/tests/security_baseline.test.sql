-- Security baseline: checks the whole database, not one feature. Fails if a
-- future change forgets one of the app's standing safety rules:
--   1. every table in the public schema has access rules (row level
--      security) switched on, so nothing is readable by default;
--   2. every view in the public schema checks the reader's own access rules
--      (security_invoker), so a view can't be used to get round them;
--   3. every function that runs with extra rights (security definer) has a
--      fixed search path, so nobody can trick it into running their own code;
--   4. every file store (storage bucket) is private.
-- Based on Supabase's Security Advisor checks and OWASP ASVS 4.0 (V1.4, V4.1).

do $$
declare
  v_list text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_list
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if v_list is not null then
    raise exception 'FAIL: tables without access rules (row level security): %', v_list;
  end if;

  select string_agg(c.relname, ', ' order by c.relname) into v_list
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v'
    and not coalesce(c.reloptions @> array['security_invoker=true'], false);
  if v_list is not null then
    raise exception 'FAIL: views that skip the reader''s access rules (add security_invoker = true): %', v_list;
  end if;

  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname) into v_list
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosecdef
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, '{}')) s where s like 'search_path=%'
    );
  if v_list is not null then
    raise exception 'FAIL: security definer functions without a fixed search_path: %', v_list;
  end if;

  select string_agg(id, ', ' order by id) into v_list
  from storage.buckets where public;
  if v_list is not null then
    raise exception 'FAIL: public file stores (must be private): %', v_list;
  end if;

  raise notice 'PASS security baseline';
end;
$$;
