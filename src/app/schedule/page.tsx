import { redirect } from "next/navigation";
import { after } from "next/server";
import { leaveWaitlist, markNoticesRead, removeAwayDates, setLibraryActive } from "@/app/actions/scheduling";
import { Button, Card, Empty, Field, Select, SubHeading, TextLink } from "@/components/ui";
import { SectionShell } from "@/components/section-shell";
import { FRONT_DESK, FULL_ADMIN, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth";
import {
  BOOKING_STATUS_NAMES,
  SESSION_LENGTHS,
  SESSION_STATUS_NAMES,
  WEEKDAY_NAMES,
  addDays,
  TIME_CHECK_REASONS,
  clockTime,
  currentTime,
  localClock,
  localDate,
  lengthLabel,
  localToday,
  placeLabel,
  sessionWhen,
  shortDate,
} from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { runTeamsSyncQuietly } from "@/lib/teams/sync";
import {
  AnswerForm,
  AvailabilityCheckForm,
  AwayForm,
  BookForm,
  CancelForm,
  ConfirmTimesForm,
  EndTimeForm,
  LibraryForm,
  NoticeSettingsForm,
  OutcomeForm,
  PlacesForm,
  RenewalForm,
  SignOnForm,
  StudentPlacesForm,
  TermForm,
  WaitlistForm,
} from "./forms";

// The scheduling module's one page. Each person sees the sections that fit
// their roles; the database decides which bookings and sessions they see.

type Booking = {
  id: string;
  status: string;
  expired: boolean;
  student_id: string;
  student_name: string;
  year_level: string | null;
  tutor_id: string;
  tutor_name: string;
  subject: string;
  weekday: number;
  start_time: string;
  minutes: number;
  delivery: string;
  library_name: string | null;
  first_date: string;
  last_date: string;
  family_note: string | null;
  tutor_note: string | null;
  tutor_reply_by: string;
  sessions_left: number;
};

type Session = {
  id: string;
  status: string;
  student_name: string;
  tutor_id: string;
  tutor_name: string;
  subject: string;
  delivery: string;
  library_name: string | null;
  starts_at: string;
  ends_at: string;
  cancelled_by_role: string | null;
  meeting_url: string | null;
};

type TimeOption = {
  tutor_id: string;
  tutor_name: string;
  weekday: number;
  start_time: string;
  end_time: string;
  delivery: string;
  library_id: string | null;
  library_name: string | null;
  joins_other_sessions: boolean;
  learning_support: boolean;
};

const list = (v: string | string[] | undefined) => (v === undefined ? [] : Array.isArray(v) ? v : [v]);
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";

export default async function SchedulePage({ searchParams }: PageProps<"/schedule">) {
  const viewer = await requireViewer();
  if (needsTwoStep(viewer)) redirect("/mfa");
  const params = await searchParams;
  // Keep Teams links up to date (at most every few minutes; never slows the page).
  after(runTeamsSyncQuietly);

  // Admin levels: full admins (owner, operations) get every tool; support
  // admins can book, cancel and see sessions for any family.
  const adminLevel = viewer.roles.includes("admin") ? await getAdminLevel() : null;
  const isAdmin = adminLevel !== null && FULL_ADMIN.includes(adminLevel);
  const isDesk = adminLevel !== null && FRONT_DESK.includes(adminLevel);
  const isTutor = viewer.roles.includes("tutor");
  const canBook = isDesk || viewer.roles.includes("parent") || viewer.roles.includes("student");

  const sections = [
    { id: "sessions", label: "Sessions" },
    { id: "bookings", label: "Bookings" },
    ...(isAdmin ? [{ id: "matching", label: "Matching" }] : []),
    ...(canBook ? [{ id: "book", label: "Book a session" }] : []),
    ...(canBook ? [{ id: "child-places", label: "Session places" }] : []),
    { id: "away", label: "Away dates" },
    { id: "notices", label: "Notices" },
    ...(canBook ? [{ id: "next-term", label: "Next term" }] : []),
    ...(canBook ? [{ id: "waitlist", label: "Waitlist" }] : []),
    ...(isTutor ? [{ id: "places", label: "Where you teach" }] : []),
    ...(isAdmin ? [{ id: "times", label: "Times to check" }] : []),
    ...(isAdmin ? [{ id: "tutor-availability", label: "Tutor availability" }] : []),
    ...(isAdmin ? [{ id: "libraries", label: "Libraries" }] : []),
  ];
  const section = sections.find((s) => s.id === params.section)?.id ?? "sessions";

  const supabase = await createClient();
  const unreadRes = await supabase
    .from("session_notices")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);
  const unread = unreadRes.count ?? 0;
  const renewalsRes = canBook
    ? await supabase.from("term_renewals").select("id", { count: "exact", head: true }).is("answered_at", null)
    : null;
  const renewalsToAnswer = renewalsRes?.count ?? 0;
  // Admins: how many subjects are waiting for a tutor.
  const pipelineRes = isAdmin ? await supabase.rpc("matching_pipeline") : null;
  const pipeline = (pipelineRes?.data ?? []) as PipelineStage[];
  const needsTutor = pipeline.find((p) => p.stage === "needs_tutor")?.subjects ?? 0;
  // The tutor's own availability check for this term, if not yet answered.
  const myCheckRes = isTutor
    ? await supabase
        .from("availability_checks")
        .select("id")
        .eq("tutor_id", viewer.id)
        .is("confirmed_at", null)
        .order("asked_at", { ascending: false })
        .limit(1)
        .maybeSingle()
    : null;
  const myCheck = myCheckRes?.data as { id: string } | null | undefined;
  const [bookingsRes, sessionsRes] = await Promise.all([
    supabase.rpc("list_bookings"),
    supabase.rpc("list_sessions", { p_from: addDays(localToday(), -14), p_to: addDays(localToday(), 70) }),
  ]);
  const bookings = (bookingsRes.data ?? []) as Booking[];
  const sessions = (sessionsRes.data ?? []) as Session[];
  // Sign-on details for the tutor's own sessions.
  const mySessionIds = sessions.filter((s) => s.tutor_id === viewer.id).map((s) => s.id);
  const signRes = mySessionIds.length
    ? await supabase.from("sessions").select("id, signed_on_at, tutor_end_at, times_confirmed_at").in("id", mySessionIds)
    : null;
  const signOf = new Map(
    (signRes?.data ?? []).map((r) => [
      r.id as string,
      r as { signed_on_at: string | null; tutor_end_at: string | null; times_confirmed_at: string | null },
    ]),
  );
  const waitingForMe = bookings.filter((b) => b.status === "requested" && !b.expired && b.tutor_id === viewer.id);

  const now = currentTime();
  const upcoming = sessions.filter((s) => new Date(s.ends_at).getTime() >= now);
  const weekAgo = now - 7 * 24 * 3600 * 1000;
  const recentMine = sessions.filter(
    (s) =>
      s.tutor_id === viewer.id &&
      s.status === "completed" &&
      new Date(s.ends_at).getTime() < now &&
      new Date(s.ends_at).getTime() > weekAgo,
  );
  const toRecord = sessions.filter(
    (s) => s.status === "scheduled" && new Date(s.starts_at).getTime() <= now && (isAdmin || s.tutor_id === viewer.id),
  );

  return (
    <SectionShell
      basePath="/schedule"
      label="Scheduling"
      section={section}
      sections={sections.map((s) => ({
        ...s,
        count:
          s.id === "bookings" && waitingForMe.length
            ? waitingForMe.length
            : s.id === "notices" && unread
              ? unread
              : s.id === "next-term" && renewalsToAnswer
                ? renewalsToAnswer
                : s.id === "matching" && needsTutor
                  ? needsTutor
                  : undefined,
      }))}
    >
      {section === "sessions" && (
        <>
          {myCheck && (
            <Card
              title="Is your availability right for next term?"
              description="Families will soon be booking for next term. Please check your weekly availability, then let us know. Booked sessions aren't changed."
            >
              <p className="mb-3 text-sm">
                <TextLink href="/dashboard/tutor?section=hours">Check or update your availability</TextLink>
              </p>
              <AvailabilityCheckForm id={myCheck.id} />
            </Card>
          )}
          {waitingForMe.length > 0 && (
            <p className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
              You have {waitingForMe.length} booking request{waitingForMe.length > 1 ? "s" : ""} to answer.{" "}
              <TextLink href="/schedule?section=bookings">See requests</TextLink>
            </p>
          )}
          {toRecord.length > 0 && (
            <Card title="Did these sessions happen?" description="Mark each one done or a no-show.">
              <ul className="divide-y divide-zinc-100 text-sm">
                {toRecord.map((s) => (
                  <li key={s.id} className="flex flex-wrap items-center justify-between gap-3 py-3 first:pt-0">
                    <span>
                      <span className="font-medium">{sessionWhen(s.starts_at)}</span>
                      <span className="text-zinc-600">
                        {" "}
                        · {s.student_name} · {s.subject}
                      </span>
                    </span>
                    <OutcomeForm id={s.id} />
                  </li>
                ))}
              </ul>
            </Card>
          )}
          {recentMine.length > 0 && (
            <Card
              collapsible
              defaultOpen={false}
              title="Your recent sessions"
              description="You're signed off at the booked end time. If you finished at a different time, tell CLG here within a week."
            >
              <ul className="divide-y divide-zinc-100 text-sm">
                {recentMine.map((s) => {
                  const sign = signOf.get(s.id);
                  return (
                    <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0">
                      <span>
                        <span className="font-medium">{sessionWhen(s.starts_at)}</span>
                        <span className="text-zinc-600">
                          {" "}
                          · {s.student_name} · {s.subject}
                        </span>
                      </span>
                      {sign?.times_confirmed_at ? (
                        <span className="text-xs text-zinc-600">Times confirmed</span>
                      ) : sign?.tutor_end_at ? (
                        <span className="text-xs text-zinc-600">
                          Finished {clockTime(localClock(sign.tutor_end_at))}: waiting for CLG
                        </span>
                      ) : (
                        <EndTimeForm id={s.id} date={localDate(s.starts_at)} bookedEnd={localClock(s.ends_at)} />
                      )}
                    </li>
                  );
                })}
              </ul>
            </Card>
          )}
          <Card title="Upcoming sessions" description="Times are Adelaide time.">
            {upcoming.length === 0 ? (
              <Empty>
                No sessions booked yet.
                {canBook && (
                  <>
                    {" "}
                    <TextLink href="/schedule?section=book">Book a session</TextLink>
                  </>
                )}
              </Empty>
            ) : (
              <ul className="divide-y divide-zinc-100 text-sm">
                {upcoming.map((s) => (
                  <li key={s.id} className="flex flex-wrap items-baseline justify-between gap-2 py-3 first:pt-0">
                    <span>
                      <span className="font-medium">{sessionWhen(s.starts_at)}</span>
                      <span className="text-zinc-600">
                        {" "}
                        · {s.student_name} with {s.tutor_name} · {s.subject} · {placeLabel(s.delivery, s.library_name)}
                      </span>
                      {s.meeting_url && s.status === "scheduled" && (
                        <a href={s.meeting_url} className="ml-2 text-teal-800 underline" target="_blank" rel="noreferrer">
                          Join
                        </a>
                      )}
                    </span>
                    {s.status === "scheduled" ? (
                      <span className="flex flex-wrap items-center gap-3">
                        {s.tutor_id === viewer.id &&
                          new Date(s.starts_at).getTime() - 30 * 60 * 1000 <= now &&
                          (signOf.get(s.id)?.signed_on_at ? (
                            <span className="rounded-full bg-teal-50 px-3 py-0.5 text-xs text-teal-900">Signed on</span>
                          ) : (
                            <SignOnForm id={s.id} atLibrary={s.delivery === "library"} />
                          ))}
                        {new Date(s.starts_at).getTime() > now && (
                          <CancelForm id={s.id} kind="session" isAdmin={isDesk} />
                        )}
                      </span>
                    ) : (
                      <span className="rounded-full bg-zinc-100 px-3 py-0.5 text-xs text-zinc-600">
                        {SESSION_STATUS_NAMES[s.status] ?? s.status}
                        {s.cancelled_by_role && ` by ${s.cancelled_by_role === "admin" ? "CLG" : s.cancelled_by_role}`}
                      </span>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </>
      )}

      {section === "bookings" && (
        <Card title="Bookings" description="Each booking is the same time every week, up to its last date.">
          {bookings.length === 0 ? (
            <Empty>No bookings yet.</Empty>
          ) : (
            <ul className="divide-y divide-zinc-100 text-sm">
              {bookings.map((b) => {
                const live = b.status === "confirmed" || (b.status === "requested" && !b.expired);
                const forMe = b.status === "requested" && !b.expired && b.tutor_id === viewer.id;
                return (
                  <li key={b.id} className="space-y-2 py-4 first:pt-0">
                    <div className="flex flex-wrap items-baseline justify-between gap-2">
                      <span>
                        <span className="font-medium">
                          {WEEKDAY_NAMES[b.weekday - 1]}s, {clockTime(b.start_time)} ({lengthLabel(b.minutes)})
                        </span>
                        <span className="text-zinc-600">
                          {" "}
                          · {b.student_name}
                          {b.year_level && ` (${b.year_level})`} with {b.tutor_name} · {b.subject} ·{" "}
                          {placeLabel(b.delivery, b.library_name)}
                        </span>
                      </span>
                      <span
                        className={`rounded-full px-3 py-0.5 text-xs ${
                          b.status === "confirmed" ? "bg-teal-50 text-teal-900" : "bg-zinc-100 text-zinc-600"
                        }`}
                      >
                        {b.expired ? "Expired" : (BOOKING_STATUS_NAMES[b.status] ?? b.status)}
                      </span>
                    </div>
                    <p className="text-zinc-600">
                      {shortDate(b.first_date)} to {shortDate(b.last_date)}
                      {b.status === "confirmed" && ` · ${b.sessions_left} session${b.sessions_left === 1 ? "" : "s"} to come`}
                      {b.status === "requested" &&
                        !b.expired &&
                        ` · tutor to answer by ${new Date(b.tutor_reply_by).toLocaleString("en-AU", {
                          weekday: "short",
                          hour: "numeric",
                          minute: "2-digit",
                          timeZone: "Australia/Adelaide",
                        })}`}
                    </p>
                    {b.family_note && <p className="text-zinc-600">Family note: {b.family_note}</p>}
                    {b.tutor_note && <p className="text-zinc-600">Tutor note: {b.tutor_note}</p>}
                    {forMe && <AnswerForm bookingId={b.id} />}
                    {live && !forMe && <CancelForm id={b.id} kind="booking" isAdmin={isDesk} />}
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      )}

      {section === "book" && canBook && <BookSection params={params} viewerId={viewer.id} isAdmin={isDesk} />}

      {section === "places" && isTutor && <PlacesSection viewerId={viewer.id} />}

      {section === "libraries" && isAdmin && <LibrariesSection />}

      {section === "times" && isAdmin && <TimesSection />}

      {section === "tutor-availability" && isAdmin && <TutorAvailabilitySection />}

      {section === "notices" && <NoticesSection viewerId={viewer.id} unread={unread} />}

      {section === "away" && <AwaySection viewerId={viewer.id} isAdmin={isAdmin} isTutor={isTutor} />}

      {section === "waitlist" && canBook && <WaitlistSection isAdmin={isDesk} />}

      {section === "next-term" && canBook && <NextTermSection isAdmin={isDesk} />}

      {section === "matching" && isAdmin && <MatchingSection params={params} pipeline={pipeline} />}

      {section === "child-places" && canBook && <ChildPlacesSection viewerId={viewer.id} isAdmin={isAdmin} params={params} />}
    </SectionShell>
  );
}

// ---------------------------------------------------------------------------
// Book a session: choose the child, subject, length and places, then a time.
// ---------------------------------------------------------------------------
async function BookSection({
  params,
  viewerId,
  isAdmin,
}: {
  params: Record<string, string | string[] | undefined>;
  viewerId: string;
  isAdmin: boolean;
}) {
  const supabase = await createClient();
  const [studentsRes, linksRes, librariesRes] = await Promise.all([
    supabase.from("students").select("id, full_name, year_level, account_id").order("full_name"),
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId),
    supabase.from("libraries").select("id, name, suburb").eq("active", true).order("name"),
  ]);
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string));
  // Admins can book for anyone; families only for their own children.
  const students = (studentsRes.data ?? []).filter((s) => isAdmin || mine.has(s.id) || s.account_id === viewerId);
  const libraries = librariesRes.data ?? [];

  const studentId = one(params.student) || (students.length === 1 ? students[0].id : "");
  const student = students.find((s) => s.id === studentId);
  const subjectsRes = student
    ? await supabase.from("student_subjects").select("subject").eq("student_id", student.id).order("added_at")
    : null;
  const subjects = (subjectsRes?.data ?? []).map((r) => r.subject as string);

  const subject = one(params.subject) || subjects[0] || "";
  const minutes = Number(one(params.minutes)) || 60;
  const searched = one(params.go) === "1";
  // Before a search, start from the places saved for this child.
  const savedRes =
    student && !searched
      ? await supabase.from("student_places").select("online, library_ids").eq("student_id", student.id).maybeSingle()
      : null;
  const saved = savedRes?.data as { online: boolean; library_ids: string[] } | null | undefined;
  const online = searched ? one(params.online) === "1" : (saved?.online ?? true);
  const chosenLibs = searched ? list(params.lib) : (saved?.library_ids ?? []);
  const days = list(params.day).map(Number).filter((d) => d >= 1 && d <= 7);
  const earliest = one(params.from);
  const latest = one(params.to);
  const tomorrow = addDays(localToday(), 1);
  const start = one(params.start) >= tomorrow ? one(params.start) : tomorrow;

  let options: TimeOption[] = [];
  let searchError = "";
  if (searched && student && subject) {
    const { data, error } = await supabase.rpc("find_session_times", {
      p_student: student.id,
      p_subject: subject,
      p_minutes: minutes,
      p_online: online,
      p_libraries: chosenLibs,
      p_first_date: start,
      p_weekdays: days.length ? days : null,
      p_earliest: earliest || null,
      p_latest: latest || null,
    });
    if (error) searchError = /violates|syntax|relation|column|function/i.test(error.message) ? "Couldn't search. Please try again." : error.message;
    options = (data ?? []) as TimeOption[];
  }

  const box = "flex items-start gap-2 text-sm";
  return (
    <>
      <Card
        title="Book a session"
        description="Choose what's needed and where. You'll see only tutors who suit and are free, then pick a time."
      >
        {students.length === 0 ? (
          <Empty>
            Add your child first. <TextLink href="/dashboard/parent?section=add">Add a child</TextLink>
          </Empty>
        ) : (
          <form method="get" action="/schedule" className="space-y-5">
            <input type="hidden" name="section" value="book" />
            <input type="hidden" name="go" value="1" />
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Select label="Who is it for?" name="student" defaultValue={studentId} required>
                <option value="" disabled>
                  Choose…
                </option>
                {students.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.full_name}
                    {s.year_level ? ` (${s.year_level})` : ""}
                  </option>
                ))}
              </Select>
              {student && subjects.length > 0 ? (
                <Select label="Subject" name="subject" defaultValue={subject} required>
                  {subjects.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </Select>
              ) : student ? (
                <p className="self-end text-sm text-zinc-600">
                  No subjects asked for yet. Add them under &quot;See or change details&quot; on your dashboard.
                </p>
              ) : (
                <p className="self-end text-sm text-zinc-600">Choose who it&apos;s for, then press Find times.</p>
              )}
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <Select label="How long" name="minutes" defaultValue={String(minutes)}>
                {SESSION_LENGTHS.map((m) => (
                  <option key={m} value={m}>
                    {lengthLabel(m)}
                  </option>
                ))}
              </Select>
              <Field label="Starting from" name="start" type="date" defaultValue={start} min={tomorrow} />
            </div>

            <fieldset className="space-y-2">
              <legend className="mb-1 text-sm font-medium text-zinc-800">Where</legend>
              <label className={box}>
                <input type="checkbox" name="online" value="1" defaultChecked={online} className="mt-1" /> Online
              </label>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {libraries.map((l) => (
                  <label key={l.id} className={box}>
                    <input
                      type="checkbox"
                      name="lib"
                      value={l.id}
                      defaultChecked={chosenLibs.includes(l.id)}
                      className="mt-1"
                    />
                    <span>
                      {l.name}
                      {l.suburb && <span className="text-zinc-500"> · {l.suburb}</span>}
                    </span>
                  </label>
                ))}
              </div>
              <p className="text-xs text-zinc-600">
                In-person sessions are at public libraries. Ticking more places and times means more tutors can be
                offered, but no match is guaranteed.
              </p>
            </fieldset>

            <fieldset className="space-y-2">
              <legend className="mb-1 text-sm font-medium text-zinc-800">When suits (optional)</legend>
              <div className="flex flex-wrap gap-x-4 gap-y-2">
                {WEEKDAY_NAMES.map((d, i) => (
                  <label key={d} className={box}>
                    <input type="checkbox" name="day" value={i + 1} defaultChecked={days.includes(i + 1)} className="mt-1" />{" "}
                    {d.slice(0, 3)}
                  </label>
                ))}
              </div>
              <div className="grid grid-cols-2 gap-4 sm:w-2/3">
                <Field label="No earlier than" name="from" type="time" defaultValue={earliest} />
                <Field label="Finished by" name="to" type="time" defaultValue={latest} />
              </div>
            </fieldset>

            <Button type="submit">Find times</Button>
          </form>
        )}
      </Card>

      {searched && student && subject && (
        <Card title="Free times" description={`${subject} for ${student.full_name}, ${lengthLabel(minutes)} each week.`}>
          {searchError ? (
            <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
              {searchError}
            </p>
          ) : options.length === 0 ? (
            <>
              <Empty>
                No free times match. Try more days, a wider time, online, or more libraries, or join the waitlist and
                CLG will be in touch when a suitable tutor is free.
              </Empty>
              <div className="mt-4">
                <WaitlistForm
                  request={{
                    student_id: student.id,
                    subject,
                    minutes,
                    online: online ? "1" : "0",
                    libraries: chosenLibs.join(","),
                    weekdays: days.join(","),
                    earliest,
                    latest,
                  }}
                />
              </div>
            </>
          ) : (
            <ul className="divide-y divide-zinc-100 text-sm">
              {options.slice(0, 40).map((o) => (
                <li
                  key={`${o.tutor_id}-${o.weekday}-${o.start_time}-${o.delivery}-${o.library_id}`}
                  className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0"
                >
                  <span>
                    <span className="font-medium">
                      {WEEKDAY_NAMES[o.weekday - 1]} {clockTime(o.start_time)} to {clockTime(o.end_time)}
                    </span>
                    <span className="text-zinc-600">
                      {" "}
                      · {o.tutor_name} · {placeLabel(o.delivery, o.library_name)}
                    </span>
                    {o.learning_support && (
                      <span className="ml-2 rounded-full bg-teal-50 px-2 text-xs text-teal-900">
                        Learning support experience
                      </span>
                    )}
                    {isAdmin && o.joins_other_sessions && (
                      <span className="ml-2 rounded-full bg-amber-50 px-2 text-xs text-amber-900">Joins tutor&apos;s block</span>
                    )}
                  </span>
                  <BookForm
                    option={{
                      student_id: student.id,
                      subject,
                      tutor_id: o.tutor_id,
                      weekday: o.weekday,
                      start_time: o.start_time,
                      minutes,
                      delivery: o.delivery,
                      library_id: o.library_id,
                    }}
                    defaultFirst={start}
                    defaultLast={addDays(start, 70)}
                  />
                </li>
              ))}
            </ul>
          )}
          {options.length > 40 && (
            <p className="mt-3 text-xs text-zinc-600">Showing the first 40. Narrow the days or times to see others.</p>
          )}
        </Card>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// Tutors: online or in person, and which libraries
// ---------------------------------------------------------------------------
async function PlacesSection({ viewerId }: { viewerId: string }) {
  const supabase = await createClient();
  const [librariesRes, placesRes, settingsRes] = await Promise.all([
    supabase.from("libraries").select("id, name, suburb").eq("active", true).order("name"),
    supabase.from("tutor_places").select("library_id").eq("tutor_id", viewerId),
    supabase.from("tutor_session_settings").select("online, in_person, learning_support").eq("tutor_id", viewerId).maybeSingle(),
  ]);
  return (
    <Card
      title="Where you teach"
      description={
        <>
          Families only see times inside your availability and weekly hours (set in your{" "}
          <TextLink href="/dashboard/tutor?section=hours">tutor dashboard</TextLink>).
        </>
      }
    >
      <PlacesForm
        libraries={librariesRes.data ?? []}
        chosen={(placesRes.data ?? []).map((p) => p.library_id as string)}
        settings={settingsRes.data ?? { online: true, in_person: true, learning_support: false }}
      />
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Admins: libraries families and tutors can choose
// ---------------------------------------------------------------------------
async function LibrariesSection() {
  const supabase = await createClient();
  const { data } = await supabase.from("libraries").select("id, name, suburb, active").order("name");
  const libraries = data ?? [];
  return (
    <Card title="Libraries" description="Public libraries families and tutors can choose for in-person sessions.">
      {libraries.length === 0 ? (
        <Empty>No libraries yet.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {libraries.map((l) => (
            <li key={l.id} className="flex items-center justify-between gap-3 py-2.5 first:pt-0">
              <span className={l.active ? "" : "text-zinc-400"}>
                <span className="font-medium">{l.name}</span>
                {l.suburb && ` · ${l.suburb}`}
                {!l.active && " (hidden)"}
              </span>
              <form action={setLibraryActive}>
                <input type="hidden" name="id" value={l.id} />
                <input type="hidden" name="active" value={l.active ? "false" : "true"} />
                <button type="submit" className="text-xs text-teal-800 underline">
                  {l.active ? "Hide" : "Show"}
                </button>
              </form>
            </li>
          ))}
        </ul>
      )}
      <SubHeading>Add a library</SubHeading>
      <LibraryForm />
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Away dates: tutors for themselves, families for their children
// ---------------------------------------------------------------------------
async function AwaySection({ viewerId, isAdmin, isTutor }: { viewerId: string; isAdmin: boolean; isTutor: boolean }) {
  const supabase = await createClient();
  const [awayRes, studentsRes, linksRes, tutorsRes] = await Promise.all([
    supabase
      .from("away_dates")
      .select("id, tutor_id, student_id, from_date, to_date, reason")
      .gte("to_date", localToday())
      .order("from_date"),
    supabase.from("students").select("id, full_name, account_id").order("full_name"),
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId),
    isAdmin ? supabase.from("accounts").select("id, full_name") : Promise.resolve({ data: [] as { id: string; full_name: string }[] }),
  ]);
  const students = studentsRes.data ?? [];
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string));
  const myChildren = students.filter((s) => mine.has(s.id) || s.account_id === viewerId);
  const nameOf = new Map<string, string>([
    ...students.map((s) => [s.id, s.full_name] as [string, string]),
    ...(tutorsRes.data ?? []).map((a) => [a.id, a.full_name] as [string, string]),
  ]);
  const choices = [
    ...(isTutor ? [{ value: "me", label: "Me (as a tutor)" }] : []),
    ...myChildren.map((s) => ({ value: `student:${s.id}`, label: s.full_name })),
  ];
  const away = awayRes.data ?? [];

  return (
    <>
      <Card
        title="Away dates"
        description="Holidays, camps or exams. Sessions already booked on these dates are cancelled, and new bookings skip them."
      >
        {away.length === 0 ? (
          <Empty>No away dates coming up.</Empty>
        ) : (
          <ul className="divide-y divide-zinc-100 text-sm">
            {away.map((a) => {
              const who = a.tutor_id === viewerId ? "You" : (nameOf.get((a.tutor_id ?? a.student_id) as string) ?? "Tutor");
              const canRemove = isAdmin || a.tutor_id === viewerId || (a.student_id && myChildren.some((c) => c.id === a.student_id));
              return (
                <li key={a.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5 first:pt-0">
                  <span>
                    <span className="font-medium">{who}</span>
                    <span className="text-zinc-600">
                      {" "}
                      · {a.from_date === a.to_date ? shortDate(a.from_date) : `${shortDate(a.from_date)} to ${shortDate(a.to_date)}`}
                      {a.reason && ` · ${a.reason}`}
                    </span>
                  </span>
                  {canRemove && (
                    <form action={removeAwayDates}>
                      <input type="hidden" name="id" value={a.id} />
                      <button type="submit" className="text-xs text-red-700 underline">
                        Remove
                      </button>
                    </form>
                  )}
                </li>
              );
            })}
          </ul>
        )}
        {choices.length > 0 && (
          <>
            <SubHeading>Add away dates</SubHeading>
            <AwayForm choices={choices} today={localToday()} />
          </>
        )}
      </Card>
    </>
  );
}

// ---------------------------------------------------------------------------
// Waitlist: families see their places; admins see everyone waiting
// ---------------------------------------------------------------------------
type WaitPlace = {
  id: string;
  student_name: string;
  year_level: string | null;
  subject: string;
  minutes: number;
  online: boolean;
  library_names: string[];
  weekdays: number[] | null;
  earliest: string | null;
  latest: string | null;
  tutor_name: string | null;
  note: string | null;
  created_at: string;
  waited_4_weeks: boolean;
  times_now_free: number;
};

async function WaitlistSection({ isAdmin }: { isAdmin: boolean }) {
  const supabase = await createClient();
  const { data } = await supabase.rpc("list_waitlist");
  const places = (data ?? []) as WaitPlace[];
  return (
    <Card
      title="Waitlist"
      description={
        isAdmin
          ? "Everyone waiting for a tutor, oldest first. Check in with families who have waited 4 weeks."
          : "Your children waiting for a suitable tutor. CLG will be in touch when one is free."
      }
    >
      {places.length === 0 ? (
        <Empty>Nobody is on the waitlist.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {places.map((w) => (
            <li key={w.id} className="space-y-1 py-3 first:pt-0">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span>
                  <span className="font-medium">{w.student_name}</span>
                  <span className="text-zinc-600">
                    {w.year_level && ` (${w.year_level})`} · {w.subject} · {lengthLabel(w.minutes)}
                  </span>
                </span>
                <span className="flex items-center gap-2">
                  {w.waited_4_weeks && (
                    <span className="rounded-full bg-amber-50 px-2 text-xs text-amber-900">Waiting 4+ weeks</span>
                  )}
                  {w.times_now_free > 0 && (
                    <span className="rounded-full bg-teal-50 px-2 text-xs text-teal-900">
                      {w.times_now_free} time{w.times_now_free === 1 ? "" : "s"} free now
                    </span>
                  )}
                </span>
              </div>
              <p className="text-zinc-600">
                {[w.online ? "Online" : null, ...w.library_names].filter(Boolean).join(", ")}
                {w.weekdays?.length ? ` · ${w.weekdays.map((d) => WEEKDAY_NAMES[d - 1].slice(0, 3)).join(", ")}` : ""}
                {w.earliest && ` · from ${clockTime(w.earliest)}`}
                {w.latest && ` · finished by ${clockTime(w.latest)}`}
                {w.tutor_name && ` · waiting for ${w.tutor_name}`}
                {` · since ${shortDate(w.created_at)}`}
              </p>
              {w.note && <p className="text-zinc-600">Note: {w.note}</p>}
              <form action={leaveWaitlist}>
                <input type="hidden" name="id" value={w.id} />
                <button type="submit" className="text-xs text-red-700 underline">
                  Take off the waitlist
                </button>
              </form>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Admins: the matching pipeline
// ---------------------------------------------------------------------------
type PipelineStage = { stage: string; subjects: number; oldest_days: number | null };
type MatchRow = {
  student_id: string;
  student_name: string;
  year_level: string | null;
  working_level: string | null;
  subject: string;
  stage: string;
  since: string;
  days: number;
  tutor_name: string | null;
  has_places: boolean;
  total: number;
};

const STAGES: { id: string; label: string; hint: string }[] = [
  { id: "needs_tutor", label: "Needs a tutor", hint: "Asked for, nothing booked or waiting" },
  { id: "waitlist", label: "Waitlist", hint: "No suitable tutor free yet" },
  { id: "tutor_to_confirm", label: "Tutor to confirm", hint: "Booking request waiting for the tutor" },
  { id: "assigned", label: "Assigned, no time", hint: "Tutor assigned but no weekly time booked" },
  { id: "active", label: "Active", hint: "Weekly sessions running" },
];
const PAGE_SIZE = 50;

async function MatchingSection({
  params,
  pipeline,
}: {
  params: Record<string, string | string[] | undefined>;
  pipeline: PipelineStage[];
}) {
  const stage = STAGES.find((s) => s.id === one(params.stage))?.id ?? "needs_tutor";
  const search = one(params.q).slice(0, 100);
  const page = Math.max(Number(one(params.page)) || 1, 1);
  const supabase = await createClient();
  const { data } = await supabase.rpc("list_matching", {
    p_stage: stage,
    p_search: search || null,
    p_limit: PAGE_SIZE,
    p_offset: (page - 1) * PAGE_SIZE,
  });
  const rows = (data ?? []) as MatchRow[];
  const total = rows[0]?.total ?? 0;
  const pages = Math.max(Math.ceil(total / PAGE_SIZE), 1);
  const link = (over: Record<string, string>) => {
    const q = new URLSearchParams({ section: "matching", stage, ...(search ? { q: search } : {}), ...over });
    return `/schedule?${q.toString()}`;
  };
  const current = STAGES.find((s) => s.id === stage)!;

  return (
    <>
      <Card title="Matching" description="Every subject a student has asked for, by stage. Oldest first.">
        <ul className="grid grid-cols-2 gap-2 sm:grid-cols-5">
          {STAGES.map((s) => {
            const p = pipeline.find((x) => x.stage === s.id);
            const active = s.id === stage;
            return (
              <li key={s.id}>
                <a
                  href={link({ stage: s.id, page: "1" })}
                  className={`block rounded-lg border px-3 py-2 text-sm ${active ? "border-teal-700 bg-teal-50" : "border-zinc-200 bg-white hover:border-teal-700"}`}
                >
                  <span className="block text-2xl font-semibold">{p?.subjects ?? 0}</span>
                  <span className="block">{s.label}</span>
                  {p?.oldest_days != null && (
                    <span className="block text-xs text-zinc-600">longest {p.oldest_days} days</span>
                  )}
                </a>
              </li>
            );
          })}
        </ul>
        <form method="get" action="/schedule" className="mt-4 flex flex-wrap items-end gap-2">
          <input type="hidden" name="section" value="matching" />
          <input type="hidden" name="stage" value={stage} />
          <div className="min-w-0 flex-1">
            <Field label="Search by student or subject" name="q" defaultValue={search} maxLength={100} />
          </div>
          <Button type="submit">Search</Button>
        </form>
      </Card>

      <Card title={`${current.label} (${total})`} description={current.hint}>
        {rows.length === 0 ? (
          <Empty>Nobody at this stage.</Empty>
        ) : (
          <ul className="divide-y divide-zinc-100 text-sm">
            {rows.map((r) => (
              <li key={`${r.student_id}-${r.subject}`} className="flex flex-wrap items-baseline justify-between gap-2 py-3 first:pt-0">
                <span>
                  <span className="font-medium">{r.student_name}</span>
                  <span className="text-zinc-600">
                    {" "}
                    · {r.subject}
                    {r.working_level && r.working_level !== r.year_level
                      ? ` · working at ${r.working_level} (${r.year_level ?? "year not set"})`
                      : r.year_level
                        ? ` · ${r.year_level}`
                        : ""}
                    {r.tutor_name && ` · ${r.tutor_name}`}
                  </span>
                  {!r.has_places && (stage === "needs_tutor" || stage === "waitlist") && (
                    <span className="block text-xs text-amber-900">
                      No session places saved yet ·{" "}
                      <a className="underline" href={`/schedule?section=child-places&student=${r.student_id}`}>
                        add them
                      </a>
                    </span>
                  )}
                </span>
                <span className="flex items-center gap-3">
                  <span className={`text-xs ${r.days >= 7 && stage !== "active" ? "text-amber-900" : "text-zinc-600"}`}>
                    {r.days === 0 ? "today" : `${r.days} day${r.days === 1 ? "" : "s"}`}
                  </span>
                  {(stage === "needs_tutor" || stage === "waitlist" || stage === "assigned") && (
                    <TextLink
                      href={`/schedule?${new URLSearchParams({ section: "book", student: r.student_id, subject: r.subject }).toString()}`}
                    >
                      Find a tutor
                    </TextLink>
                  )}
                </span>
              </li>
            ))}
          </ul>
        )}
        {pages > 1 && (
          <p className="mt-4 flex items-center gap-4 text-sm">
            {page > 1 && <a className="underline" href={link({ page: String(page - 1) })}>Previous</a>}
            <span className="text-zinc-600">
              Page {page} of {pages}
            </span>
            {page < pages && <a className="underline" href={link({ page: String(page + 1) })}>Next</a>}
          </p>
        )}
      </Card>
    </>
  );
}

// ---------------------------------------------------------------------------
// Families: where each child can have sessions
// ---------------------------------------------------------------------------
async function ChildPlacesSection({
  viewerId,
  isAdmin,
  params,
}: {
  viewerId: string;
  isAdmin: boolean;
  params: Record<string, string | string[] | undefined>;
}) {
  const supabase = await createClient();
  const [studentsRes, linksRes, librariesRes, placesRes] = await Promise.all([
    supabase.from("students").select("id, full_name, account_id").order("full_name"),
    supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId),
    supabase.from("libraries").select("id, name, suburb").eq("active", true).order("name"),
    supabase.from("student_places").select("student_id, online, library_ids"),
  ]);
  const mine = new Set((linksRes.data ?? []).map((l) => l.student_id as string));
  const wanted = one(params.student);
  // Admins see one student at a time (from the matching list); families see their children.
  const all = studentsRes.data ?? [];
  const students =
    isAdmin && wanted
      ? all.filter((s) => s.id === wanted)
      : all.filter((s) => mine.has(s.id) || s.account_id === viewerId);
  const places = new Map(
    ((placesRes.data ?? []) as { student_id: string; online: boolean; library_ids: string[] }[]).map((p) => [p.student_id, p]),
  );
  return (
    <Card
      title="Session places"
      description="Where each child can have sessions: online, and the libraries that suit. Tutors are matched only where you both can go."
    >
      {students.length === 0 ? (
        <Empty>No children yet.</Empty>
      ) : (
        <div className="space-y-6">
          {students.map((s) => (
            <div key={s.id} className="space-y-2">
              <SubHeading>{s.full_name}</SubHeading>
              <StudentPlacesForm
                studentId={s.id}
                libraries={librariesRes.data ?? []}
                online={places.get(s.id)?.online ?? true}
                chosen={places.get(s.id)?.library_ids ?? []}
              />
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Next term: the renewal question for each booking ending this term, and
// school term dates (admins)
// ---------------------------------------------------------------------------
type Renewal = {
  id: string;
  booking_id: string;
  student_name: string;
  subject: string;
  tutor_name: string | null;
  weekday: number;
  start_time: string;
  minutes: number;
  last_date: string;
  term_label: string;
  term_ends_on: string;
  asked_at: string;
  answered_at: string | null;
  same_again: boolean | null;
  holidays: boolean | null;
  change_what: string | null;
  change_reason: string | null;
  feedback: string | null;
  testimonial_ok: boolean;
  next_status: string | null;
};

const CHANGE_NAMES: Record<string, string> = { time: "day and time", tutor: "tutor", both: "day, time and tutor" };

async function NextTermSection({ isAdmin }: { isAdmin: boolean }) {
  const supabase = await createClient();
  const [renewalsRes, termsRes] = await Promise.all([
    supabase.rpc("list_renewals"),
    isAdmin
      ? supabase
          .from("school_terms")
          .select("id, state, year, term, starts_on, ends_on")
          .gte("ends_on", addDays(localToday(), -120))
          .order("state")
          .order("starts_on")
      : Promise.resolve({ data: [] }),
  ]);
  const renewals = (renewalsRes.data ?? []) as Renewal[];
  const open = renewals.filter((r) => !r.answered_at);
  const answered = renewals.filter((r) => r.answered_at);
  const terms = (termsRes.data ?? []) as {
    id: string;
    state: string;
    year: number;
    term: number;
    starts_on: string;
    ends_on: string;
  }[];

  const bookingLine = (r: Renewal) =>
    `${r.student_name} · ${r.subject}${r.tutor_name ? ` with ${r.tutor_name}` : ""} · ${WEEKDAY_NAMES[r.weekday - 1]}s at ${clockTime(r.start_time)} · ${lengthLabel(r.minutes)}`;

  return (
    <>
      <Card
        title="Next term"
        description={
          isAdmin
            ? "Families are asked 2 weeks before term ends (4 weeks before the end of terms 1 and 3). Unanswered questions are listed first."
            : "Before each term ends, tell us whether you'd like the same again next term, and whether you'd like sessions in the holidays."
        }
      >
        {open.length === 0 ? (
          <Empty>Nothing to answer right now.</Empty>
        ) : (
          <ul className="divide-y divide-zinc-100 text-sm">
            {open.map((r) => (
              <li key={r.id} className="space-y-3 py-4 first:pt-0">
                <p>
                  <span className="font-medium">{bookingLine(r)}</span>
                  <span className="block text-zinc-600">
                    Last session {shortDate(r.last_date)} · {r.term_label} ends {shortDate(r.term_ends_on)}
                  </span>
                </p>
                <RenewalForm id={r.id} />
              </li>
            ))}
          </ul>
        )}
      </Card>

      {answered.length > 0 && (
        <Card collapsible defaultOpen={isAdmin} title="Answers">
          <ul className="divide-y divide-zinc-100 text-sm">
            {answered.map((r) => (
              <li key={r.id} className="space-y-1 py-3 first:pt-0">
                <p className="font-medium">{bookingLine(r)}</p>
                <p className="text-zinc-700">
                  {r.same_again
                    ? `Same again next term${r.next_status ? ` (${(BOOKING_STATUS_NAMES[r.next_status] ?? r.next_status).toLowerCase()})` : ""}`
                    : `Wants a different ${CHANGE_NAMES[r.change_what ?? ""] ?? "arrangement"}`}
                  {r.holidays ? " · with holiday sessions" : " · no holiday sessions"}
                </p>
                {r.change_reason && <p className="text-zinc-600">Why: {r.change_reason}</p>}
                {r.feedback && (
                  <p className="text-zinc-600">
                    Feedback: {r.feedback}
                    {isAdmin && (r.testimonial_ok ? " (may be used as a testimonial)" : " (not for sharing)")}
                  </p>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {isAdmin && (
        <>
          <Card title="School terms" description="Used for renewal questions and for skipping the holidays.">
            {terms.length === 0 ? (
              <Empty>No terms yet.</Empty>
            ) : (
              <ul className="divide-y divide-zinc-100 text-sm">
                {terms.map((t) => (
                  <li key={t.id} className="py-2">
                    <span>
                      <span className="font-medium">
                        {t.state} Term {t.term} {t.year}
                      </span>
                      <span className="text-zinc-600">
                        {" "}
                        · {shortDate(t.starts_on)} to {shortDate(t.ends_on)}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <Card collapsible defaultOpen={false} title="Add or correct a term">
            <TermForm />
          </Card>
        </>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// Admins: has each tutor checked their availability for next term?
// ---------------------------------------------------------------------------
type AvailabilityCheck = {
  id: string;
  tutor_id: string;
  tutor_name: string;
  term_label: string;
  term_ends_on: string;
  asked_at: string;
  confirmed_at: string | null;
  changed: boolean | null;
  removed_slots: string[];
  bookings_outside: number;
};

async function TutorAvailabilitySection() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("list_availability_checks");
  const rows = (data ?? []) as AvailabilityCheck[];
  const weekAgo = currentTime() - 7 * 24 * 3600 * 1000;
  return (
    <Card
      title="Tutor availability"
      description="Each tutor is asked 3 weeks before term ends (5 weeks for terms 1 and 3) to check their availability for next term. Tutors who haven't answered are listed first; they can still be booked."
    >
      {rows.length === 0 ? (
        <Empty>No tutors have been asked yet.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {rows.map((r) => (
            <li key={r.id} className="space-y-1 py-3 first:pt-0">
              <p className="flex flex-wrap items-baseline justify-between gap-2">
                <span>
                  <span className="font-medium">{r.tutor_name}</span>
                  <span className="text-zinc-600"> · before {r.term_label} ends</span>
                </span>
                {r.confirmed_at ? (
                  <span className="rounded-full bg-teal-50 px-2 text-xs text-teal-900">
                    {r.changed ? "Updated" : "No changes"} · {shortDate(r.confirmed_at)}
                  </span>
                ) : (
                  <span
                    className={`rounded-full px-2 text-xs ${new Date(r.asked_at).getTime() < weekAgo ? "bg-amber-50 text-amber-900" : "bg-zinc-100 text-zinc-700"}`}
                  >
                    Not answered · asked {shortDate(r.asked_at)}
                  </span>
                )}
              </p>
              {r.removed_slots.length > 0 && (
                <p className="text-amber-900">Removed since last term: {r.removed_slots.join(", ")}</p>
              )}
              {r.bookings_outside > 0 && (
                <p className="text-red-700">
                  {r.bookings_outside} booking{r.bookings_outside === 1 ? " is" : "s are"} now outside their availability.
                  Please talk it through with them.
                </p>
              )}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Admins: session times that need a look before pay
// ---------------------------------------------------------------------------
type TimeCheck = {
  id: string;
  starts_at: string;
  ends_at: string;
  student_name: string;
  tutor_name: string;
  subject: string;
  delivery: string;
  library_name: string | null;
  status: string;
  signed_on_at: string | null;
  tutor_end_at: string | null;
  tutor_time_note: string | null;
  reason: string;
};

async function TimesSection() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("list_times_to_check");
  const rows = (data ?? []) as TimeCheck[];
  return (
    <Card
      title="Times to check"
      description="Sessions whose times need a look before pay: a different end time, no sign-on, or a location check that didn't pass."
    >
      {rows.length === 0 ? (
        <Empty>Nothing to check.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {rows.map((r) => (
            <li key={r.id} className="space-y-2 py-4 first:pt-0">
              <p>
                <span className="font-medium">{sessionWhen(r.starts_at)}</span>
                <span className="text-zinc-600">
                  {" "}
                  · {r.tutor_name} with {r.student_name} · {r.subject} · {placeLabel(r.delivery, r.library_name)}
                </span>
              </p>
              <p className="text-amber-900">{TIME_CHECK_REASONS[r.reason] ?? r.reason}</p>
              <p className="text-zinc-600">
                Booked {clockTime(localClock(r.starts_at))} to {clockTime(localClock(r.ends_at))}
                {r.signed_on_at && ` · signed on ${clockTime(localClock(r.signed_on_at))}`}
                {r.tutor_end_at && ` · tutor says finished ${clockTime(localClock(r.tutor_end_at))}`}
              </p>
              {r.tutor_time_note && <p className="text-zinc-600">Tutor&apos;s note: {r.tutor_time_note}</p>}
              <ConfirmTimesForm
                id={r.id}
                date={localDate(r.starts_at)}
                from={localClock(
                  r.signed_on_at && new Date(r.signed_on_at) > new Date(r.starts_at) ? r.signed_on_at : r.starts_at,
                )}
                to={localClock(r.tutor_end_at ?? r.ends_at)}
              />
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Notices: reminders and booking news, and how each person wants them
// ---------------------------------------------------------------------------
async function NoticesSection({ viewerId, unread }: { viewerId: string; unread: number }) {
  const supabase = await createClient();
  const [noticesRes, settingsRes] = await Promise.all([
    supabase
      .from("session_notices")
      .select("id, title, body, deliver_at, read_at")
      .order("deliver_at", { ascending: false })
      .limit(50),
    supabase
      .from("notice_settings")
      .select("first_reminder_hours, by_email, by_text")
      .eq("account_id", viewerId)
      .maybeSingle(),
  ]);
  const notices = noticesRes.data ?? [];
  return (
    <>
      <Card title="Notices" description="Reminders before each session, and news about your bookings.">
        {notices.length === 0 ? (
          <Empty>No notices yet.</Empty>
        ) : (
          <>
            <ul className="divide-y divide-zinc-100 text-sm">
              {notices.map((n) => (
                <li key={n.id} className="py-3 first:pt-0">
                  <p className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className={n.read_at ? "font-medium text-zinc-700" : "font-semibold"}>
                      {!n.read_at && <span className="mr-2 inline-block h-2 w-2 rounded-full bg-teal-600" aria-label="New" />}
                      {n.title}
                    </span>
                    <span className="text-xs text-zinc-500">{sessionWhen(n.deliver_at)}</span>
                  </p>
                  <p className="mt-1 text-zinc-600">{n.body}</p>
                </li>
              ))}
            </ul>
            {unread > 0 && (
              <form action={markNoticesRead} className="mt-4">
                <button type="submit" className="text-sm text-teal-800 underline">
                  Mark all as read
                </button>
              </form>
            )}
          </>
        )}
      </Card>
      <Card collapsible defaultOpen={false} title="Reminder settings">
        <NoticeSettingsForm
          settings={settingsRes.data ?? { first_reminder_hours: 48, by_email: true, by_text: false }}
        />
      </Card>
    </>
  );
}
