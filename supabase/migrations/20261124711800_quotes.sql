-- Summary: quote of the day and quote of the month (Carla, 22 Nov 2026).
--
-- Carla's idea: a quote of the day at the top of the Overview, and a quote
-- of the month on the loading screen under "Confidently Learn and Grow".
-- The starting quotes come from the "CLG quotes: starter list" doc
-- (22 Nov 2026), with contractions written out in full.
--
-- What this adds (module: quotes, a small module of its own):
--   * public.quotes: the list (words, who said it, a theme, the order, and
--     whether it is in use). Loaded with the 20 starting quotes.
--   * public.quote_months: the quote Carla chose for a month.
--   * public.quotes_today(): today's quote (each day the next one in the
--     list, going through the whole list before any repeat) and this
--     month's quote (Carla's choice, or the next in the list if she has not
--     chosen). Anyone can call it, signed in or not, because the loading
--     screen shows before sign-in too.
--   * Owner-only functions to add, change, remove and choose quotes.
--
-- Safe to run more than once. Run after 20261124711000_quiet_hours_count_from_5am.sql.

-- ---------------------------------------------------------------------------
-- 1. The quotes
-- ---------------------------------------------------------------------------
create table if not exists public.quotes ( -- one row per quote
  id uuid primary key default gen_random_uuid(), -- the quote's id
  body text not null check (char_length(btrim(body)) between 3 and 400), -- the quote itself
  who text not null check (char_length(btrim(who)) between 2 and 120), -- who said it (or "Attributed to ...")
  theme text check (char_length(theme) <= 60), -- a one-word theme, for example Habits
  position integer not null default 0, -- the order the days go through
  active boolean not null default true, -- false keeps it but leaves it out
  created_at timestamptz not null default now(), -- when it was added
  updated_at timestamptz not null default now() -- when it last changed
); -- end of the table
create unique index if not exists quotes_body_unique on public.quotes (lower(btrim(body))); -- the same quote cannot be added twice
create table if not exists public.quote_months ( -- Carla's choice for a month
  month date primary key check (extract(day from month) = 1), -- the month (its first day)
  quote_id uuid not null references public.quotes (id) on delete cascade, -- the chosen quote
  set_by uuid references public.accounts (id) on delete set null, -- who chose it
  set_at timestamptz not null default now() -- when
); -- end of the table
do $$ -- the same access setup for both tables
declare -- working values
  t text; -- each table name
begin -- start
  foreach t in array array['quotes', 'quote_months'] loop -- each table:
    execute format('alter table public.%I enable row level security', t); -- access rules apply
    execute format('revoke all on public.%I from anon', t); -- signed-out visitors read only through quotes_today
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t); -- changes only through the functions below
    execute format('grant select on public.%I to authenticated', t); -- reading, limited by the rule below
    execute format('drop trigger if exists audit on public.%I', t); -- replaces the change log trigger if run again
    execute format('create trigger audit after insert or update or delete on public.%I for each row execute function private.audit_change()', t); -- logs every change
    execute format('drop policy if exists "owner reads quotes" on public.%I', t); -- replaces the rule if run again
    execute format('create policy "owner reads quotes" on public.%I for select to authenticated using ((select private.is_owner()))', t); -- the owner reads the whole list (everyone else uses quotes_today)
  end loop; -- next table
end; -- end of the block
$$; -- end of the setup

-- The 20 starting quotes, in the starter list's order. Quotes already there
-- (the same words) are left alone, so Carla's changes are kept.
insert into public.quotes (body, who, theme, position) values -- the rows:
  ('The impediment to action advances action. What stands in the way becomes the way.', 'Marcus Aurelius, Meditations', 'Problems', 10), -- quote 1
  ('Waste no more time arguing about what a good man should be. Be one.', 'Marcus Aurelius, Meditations', 'Standards', 20), -- quote 2
  ('We suffer more often in imagination than in reality.', 'Seneca, Letters', 'Calm', 30), -- quote 3
  ('Luck is what happens when preparation meets opportunity.', 'Attributed to Seneca', 'Preparation', 40), -- quote 4
  ('It is not what happens to you, but how you react to it that matters.', 'Attributed to Epictetus', 'Ownership', 50), -- quote 5
  ('We are what we repeatedly do. Excellence, then, is not an act, but a habit.', 'Will Durant, summing up Aristotle', 'Habits', 60), -- quote 6
  ('You do not rise to the level of your goals. You fall to the level of your systems.', 'James Clear, Atomic Habits', 'Systems', 70), -- quote 7
  ('The obstacle is the way.', 'Ryan Holiday', 'Problems', 80), -- quote 8
  ('Discipline equals freedom.', 'Jocko Willink', 'Discipline', 90), -- quote 9
  ('Volume negates luck.', 'Alex Hormozi', 'Effort', 100), -- quote 10
  ('Desire is a contract that you make with yourself to be unhappy until you get what you want.', 'Naval Ravikant', 'Mindset', 110), -- quote 11
  ('Saving money is the gap between your ego and your income.', 'Morgan Housel, The Psychology of Money', 'Money', 120), -- quote 12
  ('Clarity about what matters provides clarity about what does not.', 'Cal Newport, Deep Work', 'Focus', 130), -- quote 13
  ('Becoming is better than being.', 'Carol Dweck, Mindset', 'Growth', 140), -- quote 14
  ('Do the best you can until you know better. Then when you know better, do better.', 'Maya Angelou', 'Learning', 150), -- quote 15
  ('Discipline is the bridge between goals and accomplishment.', 'Jim Rohn', 'Discipline', 160), -- quote 16
  ('It takes 20 years to build a reputation and five minutes to ruin it.', 'Warren Buffett', 'Reputation', 170), -- quote 17
  ('The main thing is to keep the main thing the main thing.', 'Stephen Covey', 'Focus', 180), -- quote 18
  ('Do what you can, with what you have, where you are.', 'Attributed to Theodore Roosevelt', 'Action', 190), -- quote 19
  ('It does not matter how slowly you go as long as you do not stop.', 'Attributed to Confucius', 'Persistence', 200) -- quote 20
on conflict (lower(btrim(body))) do nothing; -- keeps any quote already there

-- ---------------------------------------------------------------------------
-- 2. Today's quote and this month's quote
-- ---------------------------------------------------------------------------
create or replace function public.quotes_today() -- no inputs
returns table (day_body text, day_who text, month_body text, month_who text) -- the two quotes
language sql stable security definer -- reads the list for anyone
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the answer
  with today as (select (now() at time zone 'Australia/Adelaide')::date as d), -- today in Adelaide
  list as (select q.id, q.body, q.who, row_number() over (order by q.position, q.created_at, q.id) - 1 as n, count(*) over () as total from public.quotes q where q.active), -- the quotes in use, numbered from 0
  day_pick as (select l.body, l.who from list l, today t where l.n = mod(t.d - date '2026-01-01', l.total)), -- the day's turn: the next one each day, round the whole list
  month_start as (select date_trunc('month', t.d)::date as m from today t), -- this month (its first day)
  chosen as (select q.body, q.who from public.quote_months qm join public.quotes q on q.id = qm.quote_id, month_start ms where qm.month = ms.m), -- Carla's choice for this month, if any
  month_turn as (select l.body, l.who from list l, month_start ms where l.n = mod(((extract(year from ms.m) - 2026) * 12 + extract(month from ms.m) - 1)::bigint, l.total)) -- otherwise the month's turn in the list
  select (select body from day_pick), (select who from day_pick), -- the day's quote,
    coalesce((select body from chosen), (select body from month_turn)), coalesce((select who from chosen), (select who from month_turn)) -- and the month's quote
$$; -- end of the answer
revoke all on function public.quotes_today() from public; -- starts closed
grant execute on function public.quotes_today() to anon, authenticated; -- then open to everyone (the loading screen shows before sign-in)

-- ---------------------------------------------------------------------------
-- 3. Carla (CLG's owner) looks after the list
-- ---------------------------------------------------------------------------
-- Does the text hold a short form such as "don't" or "it's"? (CLG writes words out in full.)
create or replace function private.has_short_form(p_text text) -- takes the text
returns boolean language sql immutable -- only looks at the text
set search_path = '' -- no hidden schema lookups (safety)
as $$ select coalesce(p_text, '') ~* ('(\m[a-z]+n(?:' || chr(39) || '|’)t\M|\m(you|we|they|i|what|who|there|it|that)(?:' || chr(39) || '|’)(re|ve|ll|m|d)\M|\m(it|that|there|what|who|here|let)(?:' || chr(39) || '|’)s\M)') $$; -- looks for any short form, ignoring capitals
revoke all on function private.has_short_form(text) from public; -- inside use only

create or replace function public.quote_save(p_id uuid, p_body text, p_who text, p_theme text, p_active boolean) -- adds a quote, or changes one
returns uuid language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_id uuid; -- the quote
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) changes the quotes.' using errcode = '42501'; end if; -- owner only
  if char_length(btrim(coalesce(p_body, ''))) < 3 or char_length(btrim(coalesce(p_who, ''))) < 2 then raise exception 'Please write the quote and who said it.' using errcode = '22023'; end if; -- words needed
  if private.has_short_form(p_body) or private.has_short_form(p_who) then raise exception 'Please write short forms out in full, for example "do not" instead of the short form.' using errcode = '22023'; end if; -- CLG writes words out in full
  if exists (select 1 from public.quotes where lower(btrim(body)) = lower(btrim(p_body)) and id is distinct from p_id) then raise exception 'That quote is already in the list.' using errcode = '22023'; end if; -- no repeats
  if p_id is null then -- a new quote:
    insert into public.quotes (body, who, theme, position) values (left(btrim(p_body), 400), left(btrim(p_who), 120), nullif(left(btrim(coalesce(p_theme, '')), 60), ''), coalesce((select max(position) from public.quotes), 0) + 10) returning id into v_id; -- added at the end of the list
  else -- a change:
    update public.quotes set body = left(btrim(p_body), 400), who = left(btrim(p_who), 120), theme = nullif(left(btrim(coalesce(p_theme, '')), 60), ''), active = coalesce(p_active, true), updated_at = now() where id = p_id returning id into v_id; -- the new words
    if v_id is null then raise exception 'That quote could not be found.' using errcode = 'P0002'; end if; -- not there
  end if; -- end of the choice
  return v_id; -- hands back its id
end; -- end of the code
$$; -- end of the function
revoke all on function public.quote_save(uuid, text, text, text, boolean) from public, anon; -- not for signed-out visitors
grant execute on function public.quote_save(uuid, text, text, text, boolean) to authenticated; -- signed-in people (the check is inside)

create or replace function public.quote_remove(p_id uuid) -- removes a quote (and any month it was chosen for)
returns void language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) changes the quotes.' using errcode = '42501'; end if; -- owner only
  delete from public.quotes where id = p_id; -- removes it
  if not found then raise exception 'That quote could not be found.' using errcode = 'P0002'; end if; -- not there
end; -- end of the code
$$; -- end of the function
revoke all on function public.quote_remove(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.quote_remove(uuid) to authenticated; -- signed-in people (the check is inside)

create or replace function public.quote_set_month(p_month date, p_quote uuid) -- chooses the quote of the month (blank quote clears the choice)
returns void language plpgsql security definer -- writes for the owner; checks who is asking below
set search_path = '' -- no hidden schema lookups (safety)
as $$ -- the code
declare -- working values
  v_month date := date_trunc('month', p_month)::date; -- the month's first day
begin -- start
  if not private.is_owner() then raise exception 'Only Carla (CLG''s owner) changes the quotes.' using errcode = '42501'; end if; -- owner only
  if v_month is null or v_month < date_trunc('month', (now() at time zone 'Australia/Adelaide')::date)::date then raise exception 'Please choose this month or a later one.' using errcode = '22023'; end if; -- not a past month
  if p_quote is null then delete from public.quote_months where month = v_month; return; end if; -- clears the choice
  if not exists (select 1 from public.quotes where id = p_quote and active) then raise exception 'Please choose a quote that is in use.' using errcode = '22023'; end if; -- a quote in use
  insert into public.quote_months (month, quote_id, set_by) values (v_month, p_quote, auth.uid()) -- saves the choice
  on conflict (month) do update set quote_id = excluded.quote_id, set_by = excluded.set_by, set_at = now(); -- or changes it
end; -- end of the code
$$; -- end of the function
revoke all on function public.quote_set_month(date, uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.quote_set_month(date, uuid) to authenticated; -- signed-in people (the check is inside)
