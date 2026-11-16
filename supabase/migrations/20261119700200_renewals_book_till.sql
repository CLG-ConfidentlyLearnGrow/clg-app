-- Summary: renewal questions follow each student's own book-till date (Carla, 16 Nov 2026).
--
-- Carla chose: renewals run "off the student's own book-till date", not the
-- end of the school term. Before this change the app asked 3 weeks before
-- the end of the term that held a booking's last date, and then booked to
-- the end of next term. If a family's book-till date fell in the middle of
-- a term, the question could come too late or not at all.
--
-- How it works now:
--   * Each day, for every confirmed booking still running, the app works out
--     the date the sessions stop: the student's book-till date, or the
--     booking's own last date if that comes first (or if no book-till date
--     was ever set).
--   * 3 weeks before that date, the family is asked once (a notice to the
--     parents, and to the student if they have their own login).
--   * In the answer the family chooses a NEW book-till date and ticks again
--     whether sessions go ahead in the school holidays and on public
--     holidays. These answers are saved as the student's "How long to book"
--     answers, so CLG uses them for any new booking too.
--   * "Yes, the same again" sends the tutor a request for the same day,
--     time, place and length, from the day after the last session up to the
--     new book-till date. The tutor still has to confirm it.
--   * "No, something different" records what they want changed, and CLG
--     arranges it.
--
-- Scheduling module: writes only scheduling tables (term_renewals, bookings,
-- student_places, session_notices through add_notice).
-- Needs 20261111600500_booking_end_dates.sql and
-- 20261112600200_quarter_hour_starts.sql first. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. Renewal questions can be about a book-till date
-- ---------------------------------------------------------------------------
-- Older questions point at a school term or the student's own study period.
-- New questions point at neither, and record the date they are about.
alter table public.term_renewals add column if not exists book_until date; -- the date the sessions stop, that this question is about
alter table public.term_renewals add column if not exists new_book_until date; -- the new book-till date the family chose in their answer
alter table public.term_renewals add column if not exists public_holidays boolean; -- the family's answer: sessions on public holidays (yes or no)

-- Each question points at a school term, OR a study period, OR a book-till
-- date, and never at both a term and a study period.
alter table public.term_renewals drop constraint if exists term_renewals_one_term; -- removes the old rule (exactly one of term or study period)
alter table public.term_renewals add constraint term_renewals_one_term check ( -- adds the new rule:
  not (term_id is not null and own_term_id is not null) -- never both a term and a study period,
  and (term_id is not null or own_term_id is not null or book_until is not null) -- and at least one thing it is about.
); -- End of the rule.

-- A booking is asked about its book-till date only once.
create unique index if not exists term_renewals_book_till_once on public.term_renewals (booking_id) -- one row per booking
  where term_id is null and own_term_id is null; -- (only for book-till questions)

-- ---------------------------------------------------------------------------
-- 2. The daily question: 3 weeks before the sessions stop
-- ---------------------------------------------------------------------------
-- Runs each morning (the clg-queue-renewals job set up in
-- 20261027200500_scheduling_terms.sql calls this by name). Hands back how
-- many new questions it asked.
create or replace function private.queue_renewals()
returns integer language plpgsql security definer -- runs with full rights, so it can read every booking
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$
declare
  r record; -- one booking to ask about
  p record; -- one person to tell
  v_count integer := 0; -- how many questions were asked this run
  v_id uuid; -- the new question's id (blank if it already existed)
begin
  for r in -- goes through each booking that needs asking:
    select b.id as booking_id, b.student_id, b.tutor_id, b.subject, -- the booking, student, tutor and subject,
           s.full_name as student_name, -- the student's name for the notice,
           least(coalesce(sp.book_until, b.last_date), b.last_date) as stops_on -- and the date the sessions stop (book-till date, or the booking's last date if earlier or if no book-till date)
    from public.bookings b -- from the weekly bookings,
    join public.students s on s.id = b.student_id -- with the student,
    left join public.student_places sp on sp.student_id = b.student_id -- and the student's "How long to book" answers (if any).
    where b.status = 'confirmed' -- Only confirmed bookings,
      and b.last_date >= current_date -- that have not finished yet,
      and current_date >= least(coalesce(sp.book_until, b.last_date), b.last_date) - 21 -- and stop within the next 3 weeks.
      and not exists ( -- Not already renewed some other way:
        select 1 from public.bookings n -- (a newer booking
        where n.renews_booking = b.id and private.booking_is_live(n.status, n.tutor_reply_by) -- that carries this one on and is still live)
      ) -- (end of that check)
      and not exists ( -- And never asked before, under the old term rule or this one:
        select 1 from public.term_renewals x where x.booking_id = b.id -- (any question already about this booking)
      ) -- (end of that check)
  loop
    v_id := null; -- starts with no new question
    insert into public.term_renewals (booking_id, student_id, book_until) -- adds the question,
    values (r.booking_id, r.student_id, r.stops_on) -- about this booking and the date it stops,
    on conflict (booking_id) where term_id is null and own_term_id is null do nothing -- unless it was just added by another run,
    returning id into v_id; -- and keeps the new id.
    if v_id is not null then -- If a question was added:
      v_count := v_count + 1; -- counts it,
      for p in select * from private.session_people(r.student_id, r.tutor_id) where not is_tutor loop -- and for each parent (and the student with a login), not the tutor:
        perform private.add_notice(p.account_id, null, r.booking_id, 'renewal_due', 'Book again?', -- sends a notice titled "Book again?",
          split_part(r.student_name, ' ', 1) || '''s ' || r.subject -- naming the student and subject,
          || ' sessions are booked until ' || to_char(r.stops_on, 'FMDD FMMonth YYYY') -- and the date they stop,
          || '. Would you like to keep going? Please choose a new book-till date and tell us about school holidays and public holidays under Sessions, then Book again.', -- and what to do.
          now()); -- (sent now)
      end loop; -- End of the people.
    end if; -- End of the new question.
  end loop; -- End of the bookings.
  return v_count; -- Hands back how many were asked.
end;
$$;
revoke all on function private.queue_renewals() from public; -- only the database itself runs it

-- ---------------------------------------------------------------------------
-- 3. The family's answer: a new book-till date and the holiday ticks
-- ---------------------------------------------------------------------------
-- Works for every question, old or new. "Same again" sends the tutor a
-- request from the day after the last session to the new book-till date.
-- Hands back the new booking's id ("same again"), or blank.
create or replace function public.answer_book_again(
  p_renewal uuid, -- which question
  p_same_again boolean, -- yes: the same day, time and tutor again
  p_book_until date, -- the new book-till date
  p_school_holidays boolean, -- yes: sessions go ahead in the school holidays
  p_public_holidays boolean, -- yes: sessions go ahead on public holidays
  p_change_what text default null, -- if not the same: time, tutor or both
  p_change_reason text default null, -- why (optional)
  p_feedback text default null, -- how it is going (optional)
  p_testimonial_ok boolean default false -- may CLG quote the feedback (first name only)
)
returns uuid language plpgsql security definer -- runs with full rights, after its own checks below
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$
declare
  v_r public.term_renewals; -- the question
  v_b public.bookings; -- the booking it is about
  v_first date; -- the first session date of the new booking
  v_new uuid; -- the new booking's id (if any)
begin
  select * into v_r from public.term_renewals where id = p_renewal for update; -- reads the question and holds it, so two answers cannot cross
  if v_r.id is null or not private.can_book_for(v_r.student_id) then -- Only the family (or the student 16+) may answer:
    raise exception 'This question was not found' using errcode = 'P0002'; -- otherwise acts as if it is not there.
  end if; -- (end of the check)
  if v_r.answered_at is not null then -- Answered already:
    raise exception 'This has already been answered. Please contact CLG to change it.' using errcode = '22023'; -- says so.
  end if; -- (end of the check)
  if p_same_again is null then -- No answer to "same again?":
    raise exception 'Please say whether you would like the same again' using errcode = '22023'; -- asks for it.
  end if; -- (end of the check)
  if p_book_until is null or p_school_holidays is null or p_public_holidays is null then -- Missing the date or a holiday tick:
    raise exception 'Please choose a new book-till date and answer both holiday questions' using errcode = '22023'; -- asks for them.
  end if; -- (end of the check)
  if not p_same_again and p_change_what is null then -- "Something different" without saying what:
    raise exception 'Please say what you would like to change' using errcode = '22023'; -- asks for it.
  end if; -- (end of the check)
  if p_change_what is not null and p_change_what not in ('time', 'tutor', 'both') then -- An unknown kind of change:
    raise exception 'What to change must be time, tutor or both' using errcode = '22023'; -- says what is allowed.
  end if; -- (end of the check)

  select * into v_b from public.bookings where id = v_r.booking_id; -- reads the booking
  if p_book_until <= v_b.last_date then -- The new date must come after the last booked session:
    raise exception 'Please choose a new book-till date after the last booked session (%)', to_char(v_b.last_date, 'FMDD FMMonth YYYY') using errcode = '22023'; -- names that date.
  end if; -- (end of the check)

  -- Saves the answers as the student's "How long to book" answers, so any
  -- new booking CLG offers uses them. (The date is checked here too: from
  -- today and within a year.)
  insert into public.student_places (student_id, book_until, include_school_holidays, include_public_holidays) -- adds or updates the student's answers:
  values (v_r.student_id, p_book_until, p_school_holidays, p_public_holidays) -- the new date and both holiday ticks,
  on conflict (student_id) do update -- or, if the student already has a row,
    set book_until = excluded.book_until, -- replaces the date,
        include_school_holidays = excluded.include_school_holidays, -- the school holidays tick,
        include_public_holidays = excluded.include_public_holidays; -- and the public holidays tick.

  if p_same_again then -- "Yes, the same again":
    if private.family_paused(v_b.family_id) then -- Bookings paused for an overdue payment:
      raise exception 'This family''s bookings are paused for an overdue payment. CLG will be in touch.' using errcode = '23514'; -- stops, plainly.
    end if; -- (end of the check)
    v_first := v_b.last_date + 1; -- starts the day after the last session,
    v_first := v_first + ((v_b.weekday - extract(isodow from v_first)::int + 7) % 7); -- moved forward to the booking's weekday.
    if v_first > p_book_until then -- No such weekday before the new date:
      raise exception 'There is no session day between the last session and that date. Please choose a later book-till date.' using errcode = '22023'; -- asks for a later date.
    end if; -- (end of the check)
    if exists ( -- The same time must still be available:
      select 1 from public.bookings o -- (another live booking
      where o.id <> v_b.id and private.booking_is_live(o.status, o.tutor_reply_by) -- that is not this one,
        and (o.tutor_id = v_b.tutor_id or o.student_id = v_b.student_id) -- for the same tutor or student,
        and o.weekday = v_b.weekday -- on the same weekday,
        and o.first_date <= p_book_until and o.last_date >= v_first -- over the same weeks,
        and o.start_time < v_b.start_time + make_interval(mins => v_b.minutes) + private.summary_gap(o.tutor_id = v_b.tutor_id) -- starting before this one ends (plus the tutor's summary time),
        and o.start_time + make_interval(mins => o.minutes) + private.summary_gap(o.tutor_id = v_b.tutor_id) > v_b.start_time -- and ending (plus summary time) after this one starts)
    ) then -- If so:
      raise exception 'That time is no longer available. Please choose "something different" and CLG will find another time.' using errcode = '23514'; -- says so.
    end if; -- (end of the check)

    insert into public.bookings ( -- Adds the new booking, as a request to the tutor:
      student_id, tutor_id, family_id, subject, weekday, start_time, minutes, delivery, library_id, -- the same student, tutor, subject, day, time, length and place,
      first_date, last_date, family_note, requested_by, skip_holidays, skip_public_holidays, renews_booking -- the new dates, a note, who asked, the holiday ticks, and the booking it carries on
    ) values (
      v_b.student_id, v_b.tutor_id, v_b.family_id, v_b.subject, v_b.weekday, v_b.start_time, v_b.minutes, -- copies the student, tutor, family, subject, day, time and length,
      v_b.delivery, v_b.library_id, v_first, p_book_until, -- copies the place, and runs from the first session day to the new book-till date,
      'Same again, booked until ' || to_char(p_book_until, 'FMDD FMMonth YYYY') -- a note for the tutor with the new date,
        || case when p_school_holidays then ', with school holiday sessions' else ', no school holiday sessions' end -- whether school holidays go ahead,
        || case when p_public_holidays then ', with public holiday sessions' else ', no public holiday sessions' end || '.', -- and whether public holidays go ahead,
      auth.uid(), not p_school_holidays, not p_public_holidays, v_b.id -- who asked, skip school holidays unless ticked, skip public holidays unless ticked, and the old booking.
    )
    returning id into v_new; -- keeps the new booking's id
  end if; -- End of "same again".

  update public.term_renewals -- Saves the answer on the question:
  set answered_at = now(), answered_by = auth.uid(), -- when and who,
      same_again = p_same_again, -- same again or not,
      holidays = p_school_holidays, -- the school holidays tick,
      public_holidays = p_public_holidays, -- the public holidays tick,
      new_book_until = p_book_until, -- the new book-till date,
      change_what = case when p_same_again then null else p_change_what end, -- what to change (only if not the same),
      change_reason = nullif(left(trim(p_change_reason), 1000), ''), -- why (trimmed, blank if empty),
      feedback = nullif(left(trim(p_feedback), 2000), ''), -- feedback (trimmed, blank if empty),
      testimonial_ok = coalesce(p_testimonial_ok, false) and nullif(trim(p_feedback), '') is not null, -- testimonial permission, only when there is feedback,
      next_booking_id = v_new -- and the new booking (if any).
  where id = p_renewal; -- (this question)
  return v_new; -- Hands back the new booking's id, or blank.
end;
$$;
revoke all on function public.answer_book_again(uuid, boolean, date, boolean, boolean, text, text, text, boolean) from public, anon; -- nobody by default, and never someone signed out
grant execute on function public.answer_book_again(uuid, boolean, date, boolean, boolean, text, text, text, boolean) to authenticated; -- signed-in people (the checks inside decide)

-- The old answer (next term, by term dates) is replaced by the one above.
-- It stays in the database so older update files still run, but nobody
-- signed in can use it any more.
revoke execute on function public.answer_renewal(uuid, boolean, boolean, text, text, text, boolean) from authenticated; -- turns the old answer off for signed-in people

-- ---------------------------------------------------------------------------
-- 4. The list for the screens, now with the book-till dates
-- ---------------------------------------------------------------------------
-- Adds the student's id and three answer columns, so the old list is
-- removed first.
drop function if exists public.list_renewals(); -- removes the old list (its columns change)
create function public.list_renewals()
returns table (
  id uuid, booking_id uuid, student_id uuid, student_name text, subject text, tutor_name text, -- the question, booking, student (id and name), subject and tutor,
  weekday smallint, start_time time, minutes integer, last_date date, -- the booking's day, time, length and last session,
  term_label text, term_ends_on date, -- the term or study period (older questions only),
  book_until date, new_book_until date, -- the date the sessions stop, and the new date chosen,
  asked_at timestamptz, answered_at timestamptz, -- when asked and answered,
  same_again boolean, holidays boolean, public_holidays boolean, -- the answers: same again, school holidays, public holidays,
  change_what text, change_reason text, -- what to change, and why,
  feedback text, testimonial_ok boolean, next_status public.booking_status -- feedback, testimonial permission, and the new booking's status
)
language sql stable security definer -- reads with full rights, then filters to what this person may see
set search_path = '' -- uses full names only, so nothing can be swapped in
as $$
  select r.id, r.booking_id, r.student_id, s.full_name, b.subject, a.full_name, -- the question, booking, student (id and name), subject and tutor,
         b.weekday, b.start_time, b.minutes, b.last_date, -- the booking's day, time, length and last session,
         st.label, st.ends_on, -- the term or study period (if any),
         coalesce(r.book_until, st.ends_on), r.new_book_until, -- the date the sessions stop (older questions: the term's end), and the new date,
         r.asked_at, r.answered_at, -- when asked and answered,
         r.same_again, r.holidays, r.public_holidays, -- the answers,
         r.change_what, r.change_reason, -- what to change, and why,
         r.feedback, r.testimonial_ok, n.status -- feedback, testimonial permission, and the new booking's status
  from public.term_renewals r -- from the questions,
  join public.bookings b on b.id = r.booking_id -- with the booking,
  join public.students s on s.id = r.student_id -- the student,
  left join lateral ( -- the term or study period the question points at (older questions only):
    select t.label, t.ends_on from private.student_terms(r.student_id) t -- from the student's terms,
    where (r.term_id is not null or r.own_term_id is not null) -- (only when it points at one)
      and t.school_term_id is not distinct from r.term_id and t.own_term_id is not distinct from r.own_term_id -- (the matching one)
    limit 1 -- (just one)
  ) st on true -- (blank when there is none)
  left join public.accounts a on a.id = b.tutor_id -- the tutor (if any),
  left join public.bookings n on n.id = r.next_booking_id -- and the new booking (if any).
  where private.is_front_desk() or private.can_book_for(r.student_id) -- Only CLG admins (including support) and the family see them.
  order by r.answered_at is not null, coalesce(r.book_until, st.ends_on), s.full_name -- Unanswered first, then soonest date, then name.
$$;
revoke all on function public.list_renewals() from public, anon; -- nobody by default, and never someone signed out
grant execute on function public.list_renewals() to authenticated; -- signed-in people (the filter inside decides)
