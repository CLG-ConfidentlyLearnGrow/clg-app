-- A new kind of tutor record: a first aid certificate. Added on its own
-- because a new enum value must be saved before it can be used.
alter type public.tutor_check_kind add value if not exists 'first_aid';
