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

do $$ -- Runs a block of checks:
declare -- (its working values)
  v_list text; -- a list of names that fail a check.
begin -- Starts the checks.
  select string_agg(c.relname, ', ' order by c.relname) into v_list -- Lists tables in public with no access rules (row level security):
  from pg_catalog.pg_class c -- (from the list of tables)
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace -- (with their schema)
  where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity; -- (ordinary or split tables in public with security off).
  if v_list is not null then -- If any were found,
    raise exception 'FAIL: tables without access rules (row level security): %', v_list; -- stops with their names.
  end if; -- End of the check.

  select string_agg(c.relname, ', ' order by c.relname) into v_list -- Lists views in public that don't use the reader's access rules:
  from pg_catalog.pg_class c -- (from the list of tables)
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace -- (with their schema)
  where n.nspname = 'public' and c.relkind = 'v' -- (views in public)
    and not coalesce(c.reloptions @> array['security_invoker=true'], false); -- (without security_invoker turned on).
  if v_list is not null then -- If any were found,
    raise exception 'FAIL: views that skip the reader''s access rules (add security_invoker = true): %', v_list; -- stops with their names.
  end if; -- End of the check.

  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname) into v_list -- Lists security definer functions with no fixed search path:
  from pg_catalog.pg_proc p -- (from the list of functions)
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace -- (with their schema)
  where n.nspname in ('public', 'private') and p.prosecdef -- (in public or private, running with their owner's rights)
    and not exists ( -- (where there is no setting)
      select 1 from unnest(coalesce(p.proconfig, '{}')) s where s like 'search_path=%' -- (that fixes the search path)
    ); -- (end of the setting check).
  if v_list is not null then -- If any were found,
    raise exception 'FAIL: security definer functions without a fixed search_path: %', v_list; -- stops with their names.
  end if; -- End of the check.

  select string_agg(id, ', ' order by id) into v_list -- Lists file stores that are public:
  from storage.buckets where public; -- (from storage).
  if v_list is not null then -- If any were found,
    raise exception 'FAIL: public file stores (must be private): %', v_list; -- stops with their names.
  end if; -- End of the check.

  raise notice 'PASS security baseline'; -- Prints that the baseline passed.
end; -- End of the checks.
$$; -- (end of the block)
