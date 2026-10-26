-- Adds the national police check to the kinds of tutor check. Kept in its
-- own file because Postgres only lets a new enum value be used once it has
-- been saved; the next migration uses it.
alter type public.tutor_check_kind add value if not exists 'police_check';
