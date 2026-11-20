-- Summary: let people tick off each notice as seen, or as done (Carla, 20 Nov 2026).
--
-- Carla asked: "How [do I] tick off I have seen these things, or that they
-- have been done?" Until now the Notices list only had one "Mark all as
-- read" button at the bottom, which is easy to miss.
--
-- What changes:
--   * session_notices gets a done_at column: when the person said the notice
--     is done (for example a library they were asked to confirm).
--   * public.tick_off_notice(id, action) lets a person tick off ONE of their
--     own notices: 'seen' (marks it read), 'done' (marks it done, and read),
--     or 'not_done' (puts a done notice back in the list, if ticked by mistake).
--   * Done notices move to a folded "Done" list on the page, so the main list
--     only shows what still needs a look.
--   * A small index makes counting unread notices (the number on the Notices
--     menu item and the folded Sessions heading) fast as notices build up.
--   * The "own delivered notices" access rule is re-made with auth.uid()
--     wrapped in (select ...), so it is worked out once per query, not per row.
--
-- People can still only see and change their own notices. Nobody can edit a
-- notice's words: only the read and done times change.
-- Scheduling module (session_notices). Safe to run more than once.
-- Run after 20261122300100_term_review_pay.sql.

-- ---------------------------------------------------------------------------
-- 1. When a notice was ticked off as done (blank until then).
-- ---------------------------------------------------------------------------
alter table public.session_notices add column if not exists done_at timestamptz; -- when the person ticked it off as done (blank if not done)

-- ---------------------------------------------------------------------------
-- 2. Fast unread counts: only unread rows are kept in this index, so it stays
--    small even when people have hundreds of old notices.
-- ---------------------------------------------------------------------------
create index if not exists session_notices_unread -- the index name
  on public.session_notices (account_id, deliver_at) -- by person, then by when the notice is delivered
  where read_at is null; -- only notices not yet read

-- ---------------------------------------------------------------------------
-- 3. The access rule for reading notices, re-made the fast way (same rule:
--    a person sees only their own notices, once they are delivered).
-- ---------------------------------------------------------------------------
drop policy if exists "own delivered notices" on public.session_notices; -- removes the old version of the rule
create policy "own delivered notices" on public.session_notices -- adds it back:
  for select to authenticated -- for reading, by signed-in people,
  using (account_id = (select auth.uid()) and deliver_at <= now()); -- only their own notices that have been delivered

-- ---------------------------------------------------------------------------
-- 4. Tick off one notice: seen, done, or not done after all.
-- ---------------------------------------------------------------------------
create or replace function public.tick_off_notice(p_id uuid, p_action text) -- the notice, and what to do ('seen', 'done' or 'not_done')
returns void -- gives nothing back
language plpgsql -- written as a small program
security definer -- runs with the owner's rights, as people cannot change notices directly
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$ -- the program:
begin -- start
  if (select auth.uid()) is null then -- if nobody is signed in:
    raise exception 'Please sign in first.'; -- stops with a plain message
  end if; -- end of the sign-in check
  if p_action is null or p_action not in ('seen', 'done', 'not_done') then -- if the action is not one of the three:
    raise exception 'Please choose seen, done or not done.'; -- stops with a plain message
  end if; -- end of the action check
  update public.session_notices n set -- changes the notice:
    read_at = coalesce(n.read_at, now()), -- marks it read (keeps the first read time if already read)
    done_at = case -- and the done time:
      when p_action = 'done' then coalesce(n.done_at, now()) -- done: now (keeps the first done time if already done)
      when p_action = 'not_done' then null -- not done: clears it
      else n.done_at -- seen: leaves it as it was
    end -- end of the done time
  where n.id = p_id -- only this notice
    and n.account_id = (select auth.uid()) -- only if it is the signed-in person's own
    and n.deliver_at <= now(); -- only once it has been delivered
  if not found then -- if no notice was changed:
    raise exception 'That notice could not be found. Please refresh the page.'; -- stops with a plain message
  end if; -- end of the found check
end; -- end of the program
$$; -- end of the function
revoke all on function public.tick_off_notice(uuid, text) from public, anon; -- nobody signed out can use it
grant execute on function public.tick_off_notice(uuid, text) to authenticated; -- signed-in people can use it (on their own notices only)
