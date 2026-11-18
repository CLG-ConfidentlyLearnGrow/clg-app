-- Summary: pop-up notifications on phones and computers (shared core).
-- Carla, 18 Nov 2026: "People need to be able to see the notifications for
-- the app, so the app needs to send pop-up notifications (even when needing
-- to sign back in)".
--
-- How it works, in plain words:
--   1. When someone presses "Turn on pop-ups" in the app, their browser
--      gives the app a private delivery address for that one device (its
--      "subscription"). The app saves it in public.push_subscriptions,
--      linked to the person who was signed in.
--   2. The address belongs to the device, not to the sign-in. So pop-ups
--      keep arriving after the app signs someone out for being inactive
--      (the 8 hr timeout). Tapping a pop-up opens the app, which asks
--      them to sign in again first if needed.
--   3. Every minute the database checks whether any notice is waiting for
--      someone with a device turned on. If so, it wakes the app's sender
--      (src/app/api/push/cron), which collects them with push_claim and
--      sends them through the browser makers' push services.
--   4. Pop-ups never show a child's name, a tutor's name, a subject or any
--      other detail, because they can appear on a locked screen. They only
--      say what kind of notice is waiting ("Session reminder", "New help
--      chat message"). The details stay in the app, behind the sign-in.
--   5. Quiet hours (9pm to 5am in the person's own local time) apply. A
--      notice due in quiet hours pops up when they end. The one exception
--      is a child safety concern marked "immediate danger", which reaches
--      the Child Safety Officer straight away, as its email already does.
--
-- This module only reads other modules' notice tables (sessions, progress,
-- help chat, running late, child safety). It never writes them. It keeps
-- its own record of what it has sent in public.push_sent.
--
-- See docs/features/push-notifications.md. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Devices with pop-ups turned on
-- ---------------------------------------------------------------------------

-- One row per device (phone, tablet or computer browser) with pop-ups on.
create table if not exists public.push_subscriptions ( -- the table, made only if it is not there yet
  id uuid primary key default gen_random_uuid(), -- the row's id
  account_id uuid not null references public.accounts (id) on delete cascade, -- whose pop-ups go to this device (removed with their account)
  endpoint text not null unique, -- the device's private delivery address from its browser (one row per device)
  p256dh text not null, -- the device's public key, used to lock each pop-up so only that device can read it
  auth_secret text not null, -- the device's shared secret, also used to lock each pop-up
  device_label text not null default 'A device', -- a name for the device so people can tell them apart, e.g. "iPhone (Safari)"
  created_at timestamptz not null default now(), -- when pop-ups were first turned on for this device
  last_seen_at timestamptz not null default now(), -- when the person last opened the app on this device
  last_sent_at timestamptz, -- when a pop-up was last sent to this device
  failures integer not null default 0, -- how many sends in a row have failed (the device is removed after 5)
  constraint push_subscriptions_endpoint_https check (endpoint like 'https://%' and char_length(endpoint) between 20 and 1000), -- only real secure web addresses of a sensible length
  constraint push_subscriptions_key_size check (char_length(p256dh) between 20 and 200), -- the key is a sensible length
  constraint push_subscriptions_secret_size check (char_length(auth_secret) between 8 and 100), -- the secret is a sensible length
  constraint push_subscriptions_label_size check (char_length(device_label) between 1 and 80) -- the device name is a sensible length
); -- end of the table
create index if not exists push_subscriptions_account on public.push_subscriptions (account_id); -- finds a person's devices quickly
alter table public.push_subscriptions enable row level security; -- access rules apply to this table
revoke all on public.push_subscriptions from anon; -- signed-out visitors cannot see or change it
revoke insert, update, delete, truncate on public.push_subscriptions from authenticated; -- signed-in people change it only through the functions below
drop policy if exists "own devices" on public.push_subscriptions; -- replaces the rule if this is run again
create policy "own devices" on public.push_subscriptions -- each person sees only their own devices
  for select to authenticated using (account_id = (select auth.uid())); -- (nobody else, not even admins, needs another person's device addresses)

-- Turns pop-ups on for the device the person is using, or refreshes it.
-- A device can only belong to one person at a time: if someone else signs
-- in on a shared computer and turns pop-ups on, the device moves to them,
-- so the first person's notices stop appearing there.
create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_label text) -- takes the device's address, key, secret and name
returns uuid -- the device row's id
language plpgsql security definer -- writes the table after checking who is asking
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values
  v_me uuid := auth.uid(); -- the signed-in person
  v_id uuid; -- the device row's id
begin -- start
  if v_me is null then -- nobody is signed in:
    raise exception 'Please sign in to turn on pop-up notifications' using errcode = '42501'; -- plain message
  end if; -- checked who
  if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint) not between 20 and 1000 then -- the address does not look right:
    raise exception 'This device gave an address the app cannot use. Please try again, or try another browser' using errcode = '22023'; -- plain message
  end if; -- checked the address
  if char_length(coalesce(p_p256dh, '')) not between 20 and 200 or char_length(coalesce(p_auth, '')) not between 8 and 100 then -- the key or secret does not look right:
    raise exception 'This device did not give the details the app needs. Please try again, or try another browser' using errcode = '22023'; -- plain message
  end if; -- checked the key and secret
  insert into public.push_subscriptions (account_id, endpoint, p256dh, auth_secret, device_label) -- saves the device:
  values (v_me, p_endpoint, p_p256dh, p_auth, left(coalesce(nullif(btrim(p_label), ''), 'A device'), 80)) -- for this person, with its details and a name (cut to 80 letters)
  on conflict (endpoint) do update -- if the device is already saved:
    set account_id = excluded.account_id, -- it now belongs to whoever is signed in,
        p256dh = excluded.p256dh, -- with its latest key,
        auth_secret = excluded.auth_secret, -- its latest secret,
        device_label = excluded.device_label, -- its latest name,
        last_seen_at = now(), -- seen just now,
        failures = 0 -- and a fresh start on failed sends
  returning id into v_id; -- keeps the row's id
  delete from public.push_subscriptions s -- keeps each person to their 10 most recently used devices:
  where s.account_id = v_me -- this person's devices
    and s.id not in (select s2.id from public.push_subscriptions s2 where s2.account_id = v_me order by s2.last_seen_at desc limit 10); -- other than the 10 most recently seen
  return v_id; -- hands back the row's id
end; -- finish
$$; -- end of the function
revoke all on function public.push_subscribe(text, text, text, text) from public, anon; -- not for signed-out visitors
grant execute on function public.push_subscribe(text, text, text, text) to authenticated; -- signed-in people turn on their own device

-- Turns pop-ups off for one of the person's own devices.
create or replace function public.push_remove_device(p_id uuid) -- takes the device row's id
returns void -- nothing back
language sql security definer -- removes the row; the check is inside
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  delete from public.push_subscriptions s -- removes the device
  where s.id = p_id and s.account_id = auth.uid() -- only if it is the signed-in person's own
$$; -- end of the function
revoke all on function public.push_remove_device(uuid) from public, anon; -- not for signed-out visitors
grant execute on function public.push_remove_device(uuid) to authenticated; -- signed-in people remove their own devices

-- Turns pop-ups off for the device the person is using, by its address
-- (used by "Turn off pop-ups on this device").
create or replace function public.push_unsubscribe(p_endpoint text) -- takes the device's address
returns void -- nothing back
language sql security definer -- removes the row; the check is inside
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  delete from public.push_subscriptions s -- removes the device
  where s.endpoint = p_endpoint and s.account_id = auth.uid() -- only if it is the signed-in person's own
$$; -- end of the function
revoke all on function public.push_unsubscribe(text) from public, anon; -- not for signed-out visitors
grant execute on function public.push_unsubscribe(text) to authenticated; -- signed-in people turn off their own device

-- ---------------------------------------------------------------------------
-- 2. What has been sent
-- ---------------------------------------------------------------------------

-- One row per notice per person that has been sent as a pop-up, so nothing
-- pops up twice. Only the server reads or writes it. Rows go after 30 days.
create table if not exists public.push_sent ( -- the table, made only if it is not there yet
  source text not null check (source in ('session', 'progress', 'help_chat', 'lateness', 'safety_concern')), -- which kind of notice
  source_id uuid not null, -- the notice's own id in its module's table
  account_id uuid not null references public.accounts (id) on delete cascade, -- who it was for (removed with their account)
  sent_at timestamptz not null default now(), -- when it was handed to the sender
  primary key (source, source_id, account_id) -- each notice once per person
); -- end of the table
create index if not exists push_sent_when on public.push_sent (sent_at); -- finds old rows quickly for tidying up
alter table public.push_sent enable row level security; -- access rules apply (there are none, so only the server can use it)
revoke all on public.push_sent from anon, authenticated; -- nobody signed in or out can see or change it

-- ---------------------------------------------------------------------------
-- 3. Which pop-ups are due
-- ---------------------------------------------------------------------------

-- Lists every pop-up due at the given moment: notices that have arrived,
-- have not been read or sent yet, are for someone with a device turned on,
-- and are outside that person's quiet hours. The words are fixed and never
-- include names or details. The moment is an input so tests can check
-- quiet hours at any time of day.
create or replace function private.push_due(p_now timestamptz) -- takes the moment to check
returns table (source text, source_id uuid, account_id uuid, title text, body text, link text, urgent boolean) -- one row per pop-up
language sql stable security definer -- reads the notice tables whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the list
  with notices as ( -- every notice that has arrived recently, from each module:
    select 'session'::text as source, n.id as source_id, n.account_id, -- session notices (reminders, bookings, cancellations):
      case -- a title by kind, with no details:
        when n.kind in ('reminder_first', 'reminder_final') then 'Session reminder' -- reminders
        when n.kind like 'booking%' then 'Booking update' -- booking news
        else 'Session update' -- anything else about sessions
      end as title, -- (end of the title)
      case -- the message by kind, with no details:
        when n.kind in ('reminder_first', 'reminder_final') then 'You have a session coming up. Open the CLG app for the details.' -- reminders
        else 'There is news about your sessions. Open the CLG app for the details.' -- everything else
      end as body, -- (end of the message)
      '/schedule?section=notices'::text as link, -- opens the Notices section of Sessions
      false as urgent -- never skips quiet hours
    from public.session_notices n -- from the session notices
    left join public.sessions x on x.id = n.session_id -- with the session, if there is one
    where n.deliver_at <= p_now and n.deliver_at > p_now - interval '2 hours' -- arrived in the last 2 hours
      and n.read_at is null -- not read yet
      and (n.kind not in ('reminder_first', 'reminder_final') or (x.status = 'scheduled' and x.starts_at > p_now)) -- a reminder only while its session is still on and still to come
    union all -- and
    select 'progress', n.id, n.account_id, -- progress notices (session updates and note reminders):
      'Progress update', -- the title
      'There is a new progress notice. Open the CLG app for the details.', -- the message
      '/dashboard', -- opens the dashboard, where progress notices show
      false -- never skips quiet hours
    from public.progress_notices n -- from the progress notices
    where n.deliver_at <= p_now and n.deliver_at > p_now - interval '2 hours' -- arrived in the last 2 hours
      and n.read_at is null -- not read yet
    union all -- and
    select 'help_chat', e.id, e.account_id, -- help chat "new message" notices:
      'New help chat message', -- the title
      'You have a new message in the CLG help chat. Open the CLG app to read it.', -- the message (never the message itself)
      '/help/' || e.chat_id::text, -- opens that chat
      false -- never skips quiet hours
    from public.help_chat_emails e -- from the help chat's notice queue
    where e.send_after <= p_now and e.send_after > p_now - interval '12 hours' -- due, and not more than 12 hours ago (so ones held overnight still go at 5am)
      and not exists (select 1 from public.help_chat_reads r where r.chat_id = e.chat_id and r.account_id = e.account_id and r.last_read_at >= e.created_at) -- not read in the app since
      and (exists (select 1 from public.help_chat_members m where m.chat_id = e.chat_id and m.account_id = e.account_id) -- still in the chat,
        or exists (select 1 from public.admin_profiles ap join public.account_roles ar on ar.account_id = ap.account_id and ar.role = 'admin' where ap.account_id = e.account_id)) -- or still an admin
    union all -- and
    select 'lateness', e.id, e.account_id, -- "your tutor is running late" notices:
      'Your tutor is running late', -- the title (no names)
      'Your tutor has let CLG know they are running late. Open the CLG app for the details.', -- the message
      '/dashboard', -- opens the dashboard
      false -- never skips quiet hours
    from public.session_lateness_emails e -- from the running-late queue
    where e.created_at <= p_now and e.created_at > p_now - interval '1 hour' -- told in the last hour (after that it is too late to help)
    union all -- and
    select 'safety_concern', c.id, c.recipient_id, -- child safety concerns, to the person they were sent to:
      case when c.immediate_danger then 'Urgent child safety alert' else 'Child safety alert' end, -- the title
      'A child safety concern was sent to you. Open the CLG app to read it.', -- the message (no details)
      '/safety/concerns', -- opens the concerns page
      c.immediate_danger -- "immediate danger" goes straight away, even in quiet hours
    from public.safety_concerns c -- from the concerns
    where c.recipient_id is not null -- sent to someone
      and c.created_at <= p_now and c.created_at > p_now - interval '12 hours' -- raised in the last 12 hours (so ones held overnight still go at 5am)
  ) -- end of the notices
  select n.source, n.source_id, n.account_id, n.title, n.body, n.link, n.urgent -- hands back each pop-up
  from notices n -- from the notices above
  where exists (select 1 from public.push_subscriptions s where s.account_id = n.account_id) -- only for people with a device turned on
    and not exists (select 1 from public.push_sent ps where ps.source = n.source and ps.source_id = n.source_id and ps.account_id = n.account_id) -- not sent already
    and (n.urgent or private.outside_quiet_hours_for(n.account_id, p_now) = p_now) -- outside that person's quiet hours (unless urgent)
$$; -- end of the function
revoke all on function private.push_due(timestamptz) from public; -- only used inside other functions

-- Hands the server the pop-ups due now and records them as sent, so they
-- are never sent twice. Also tidies up records older than 30 days.
create or replace function public.push_claim(p_limit integer default 200) -- takes how many at most
returns table (source text, source_id uuid, account_id uuid, title text, body text, link text, urgent boolean) -- one row per pop-up
language sql volatile security definer -- records what is handed over
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
  delete from public.push_sent ps where ps.sent_at < now() - interval '30 days'; -- first, removes records older than 30 days (APP 11: keep only what is needed)
  with due as ( -- the pop-ups due now:
    select d.* from private.push_due(now()) d -- from the list above
    limit least(greatest(coalesce(p_limit, 200), 1), 500) -- at most the number asked for (1 to 500)
  ), recorded as ( -- records each one as sent:
    insert into public.push_sent (source, source_id, account_id) -- in the sent record
    select d.source, d.source_id, d.account_id from due d -- each due pop-up
    on conflict do nothing -- skipping any another sender took a moment ago
    returning push_sent.source, push_sent.source_id, push_sent.account_id -- the ones this sender now owns
  ) -- end of the steps
  select d.source, d.source_id, d.account_id, d.title, d.body, d.link, d.urgent -- hands back each pop-up
  from due d -- from the due list
  join recorded r on r.source = d.source and r.source_id = d.source_id and r.account_id = d.account_id; -- only the ones this sender recorded
$$; -- end of the function
revoke all on function public.push_claim(integer) from public, anon, authenticated; -- the server only
grant execute on function public.push_claim(integer) to service_role; -- the pop-up sender

-- Puts pop-ups back if every device failed to take them for a passing
-- reason, so the next run tries again (only ones taken in the last hour).
create or replace function public.push_release(p_sources text[], p_ids uuid[], p_accounts uuid[]) -- takes matching lists: kinds, notice ids and people
returns void -- nothing back
language sql security definer -- changes the sent record
set search_path = '' -- only fully named tables, for safety
as $$ -- the change
  delete from public.push_sent ps -- removes the sent record
  using unnest(p_sources, p_ids, p_accounts) as r(source, source_id, account_id) -- for each pop-up given
  where ps.source = r.source and ps.source_id = r.source_id and ps.account_id = r.account_id -- that matches it
    and ps.sent_at > now() - interval '1 hour' -- and was taken in the last hour
$$; -- end of the function
revoke all on function public.push_release(text[], uuid[], uuid[]) from public, anon, authenticated; -- the server only
grant execute on function public.push_release(text[], uuid[], uuid[]) to service_role; -- the pop-up sender

-- ---------------------------------------------------------------------------
-- 4. Waking the sender every minute (only when something is waiting)
-- ---------------------------------------------------------------------------

-- True when at least one pop-up is due now.
create or replace function private.pushes_waiting() -- no inputs
returns boolean -- yes or no
language sql stable security definer -- reads the list whoever asks
set search_path = '' -- only fully named tables, for safety
as $$ -- the answer
  select exists (select 1 from private.push_due(now())) -- any pop-up due now
$$; -- end of the function
revoke all on function private.pushes_waiting() from public; -- only used inside other functions

-- Calls the app's pop-up sender. Uses the same two saved values in
-- Supabase's Vault as the email sender (clg_app_url and clg_cron_secret),
-- and does nothing where they, pg_net or Vault are missing.
create or replace function private.wake_push_sender() -- no inputs
returns boolean -- true when the sender was called
language plpgsql security definer -- reads the Vault
set search_path = '' -- only fully named tables, for safety
as $$ -- the steps
declare -- working values
  v_url text; -- the app's web address
  v_secret text; -- the shared secret that proves the call comes from CLG's database
begin -- start
  if to_regnamespace('net') is null or to_regclass('vault.decrypted_secrets') is null then -- pg_net or Vault is missing:
    return false; -- nothing to do
  end if; -- checked the tools
  if not private.pushes_waiting() then -- nothing is waiting:
    return false; -- no need to wake the sender
  end if; -- checked for waiting pop-ups
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'clg_app_url' limit 1$q$ into v_url; -- reads the app's address
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'clg_cron_secret' limit 1$q$ into v_secret; -- reads the shared secret
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then -- either is missing:
    return false; -- cannot call the app
  end if; -- checked the values
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 30000)' -- calls the app's sender:
    using rtrim(v_url, '/') || '/api/push/cron', -- at the pop-up sender's address,
          '{}'::jsonb, -- with nothing in the body,
          jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'); -- and the secret to prove who is calling
  return true; -- the sender was called
end; -- finish
$$; -- end of the function
revoke all on function private.wake_push_sender() from public; -- only run by the scheduled job

-- Schedules the check every minute, where Supabase's scheduler (pg_cron) is
-- available. Running the same name again replaces the job, not doubles it.
do $$ -- a small block of code
begin -- start
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then -- pg_net is available:
    execute 'create extension if not exists pg_net'; -- makes sure it is turned on
  end if; -- checked pg_net
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then -- the scheduler is available:
    execute 'create extension if not exists pg_cron with schema pg_catalog'; -- makes sure it is turned on
    execute $job$select cron.schedule('clg-send-pop-ups', '* * * * *', 'select private.wake_push_sender()')$job$; -- checks every minute
  end if; -- checked the scheduler
end; -- finish
$$; -- end of the block
