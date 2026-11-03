// Sections of the Schedule page for the 2 Nov 2026 changes: study periods,
// requests and public holidays, blocks, and libraries with opening hours.
// The database decides what each person can see.

import { removeLibraryHours, removeOwnTerm, liftBlock } from "@/app/actions/scheduling-extra";
import { setLibraryActive } from "@/app/actions/scheduling";
import { Card, Empty, SubHeading } from "@/components/ui";
import { WEEKDAY_NAMES, clockTime, localToday, shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";
import { LibraryForm } from "./forms";
import {
  BlockFollowUpForm,
  BlockForm,
  CloseRequestForm,
  ConfirmLibraryForm,
  LibraryHoursForm,
  OfferOneOffForm,
  OwnTermForm,
  SessionRequestForm,
  SkipPublicHolidaysForm,
  StudyPeriodForm,
  Term4LastDayForm,
} from "./extra-forms";
import { BusyButton } from "@/components/busy-button";

const STUDY_PERIOD_NAMES: Record<string, string> = {
  public: "SA government school terms",
  private: "SA private school terms",
  own: "Own study dates",
};

// ---------------------------------------------------------------------------
// Study period for one child (inside Session places)
// ---------------------------------------------------------------------------
export async function StudyPeriodBlock({ studentId, yearLevel }: { studentId: string; yearLevel: string | null }) {
  const supabase = await createClient();
  const thisYear = Number(localToday().slice(0, 4));
  const [periodRes, ownRes, endRes] = await Promise.all([
    supabase.from("student_study_periods").select("calendar").eq("student_id", studentId).maybeSingle(),
    supabase.from("student_own_terms").select("id, label, starts_on, ends_on").eq("student_id", studentId).order("starts_on"),
    supabase.from("student_term_ends").select("last_day").eq("student_id", studentId).eq("year", thisYear).maybeSingle(),
  ]);
  const tertiary = yearLevel === "University or TAFE" || yearLevel === "Adult learner";
  const calendar = (periodRes.data?.calendar as string | undefined) ?? (tertiary ? "own" : "public");
  const own = (ownRes.data ?? []) as { id: string; label: string | null; starts_on: string; ends_on: string }[];
  return (
    <div className="space-y-3 rounded-lg border border-zinc-200 p-3">
      <StudyPeriodForm studentId={studentId} calendar={calendar} />
      {calendar === "own" ? (
        <>
          {own.length === 0 ? (
            <p className="text-sm text-amber-800">No study dates yet. Please add each semester, trimester or term.</p>
          ) : (
            <ul className="divide-y divide-zinc-100 text-sm">
              {own.map((o) => (
                <li key={o.id} className="flex items-center justify-between gap-3 py-2">
                  <span>
                    <span className="font-medium">{o.label ?? "Study period"}</span> · {shortDate(o.starts_on)} to{" "}
                    {shortDate(o.ends_on)}
                  </span>
                  <form action={removeOwnTerm}>
                    <input type="hidden" name="id" value={o.id} />
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">
                      Remove
                    </BusyButton>
                  </form>
                </li>
              ))}
            </ul>
          )}
          <OwnTermForm studentId={studentId} />
        </>
      ) : (
        <Term4LastDayForm studentId={studentId} current={(endRes.data?.last_day as string | undefined) ?? ""} />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Admins: study dates still to check (inside Next term)
// ---------------------------------------------------------------------------
export async function StudyDatesToCheck() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("list_study_dates_to_check");
  const rows = (data ?? []) as { student_id: string; student_name: string; calendar: string; problem: string }[];
  return (
    <Card
      title="Study dates to check"
      description="Students with a booking whose dates aren't loaded yet: tertiary students with no study dates, and school students whose last day of Term 4 isn't confirmed. Ask the family, or add it under Session places."
    >
      {rows.length === 0 ? (
        <Empty>Nothing to check.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {rows.map((r) => (
            <li key={r.student_id} className="py-2">
              <span className="font-medium">{r.student_name}</span>
              <span className="text-zinc-600">
                {" "}
                · {STUDY_PERIOD_NAMES[r.calendar] ?? r.calendar} · {r.problem}
              </span>{" "}
              <a className="text-xs text-teal-800 underline" href={`/schedule?section=child-places&student=${r.student_id}`}>
                Open
              </a>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Requests and public holidays
// ---------------------------------------------------------------------------
type SessionRequest = {
  id: string;
  student_id: string;
  student_name: string;
  kind: string;
  subject: string;
  tutor_id: string | null;
  tutor_name: string | null;
  event_on: string | null;
  event_label: string | null;
  wants: string | null;
  note: string | null;
  status: string;
  staff_note: string | null;
  created_at: string;
  offered_booking_id: string | null;
  offered_status: string | null;
};

const KIND_NAMES: Record<string, string> = {
  extra: "Extra session",
  public_holiday: "Public holiday one-off",
  away_cover: "Cover while the tutor is away",
};
const WANTS_NAMES: Record<string, string> = { time: "another time", tutor: "a different tutor", either: "another time or tutor" };
const REQUEST_STATUS: Record<string, string> = {
  open: "Waiting for a time",
  offered: "Time offered, waiting for approval",
  done: "Booked",
  declined: "Couldn't be arranged",
  withdrawn: "Withdrawn",
};

export async function RequestsSection({
  viewerId,
  isAdmin,
  isTutor,
  canAsk,
}: {
  viewerId: string;
  isAdmin: boolean;
  isTutor: boolean;
  canAsk: boolean;
}) {
  const supabase = await createClient();
  const today = localToday();
  const [reqRes, phRes, studentsRes, linksRes, tutorsRes, libsRes] = await Promise.all([
    supabase.rpc("list_session_requests"),
    canAsk ? supabase.rpc("list_public_holiday_weeks") : Promise.resolve({ data: [] }),
    canAsk ? supabase.from("students").select("id, full_name, account_id, student_subjects(subject)").order("full_name") : Promise.resolve({ data: [] }),
    canAsk ? supabase.from("parent_student_links").select("student_id").eq("parent_id", viewerId) : Promise.resolve({ data: [] }),
    isAdmin ? supabase.from("tutor_profiles").select("account_id, active, account:accounts(full_name)").eq("active", true) : Promise.resolve({ data: [] }),
    supabase.from("libraries").select("id, name").eq("active", true).not("confirmed_at", "is", null).order("name"),
  ]);
  const requests = (reqRes.data ?? []) as SessionRequest[];
  const open = requests.filter((r) => r.status === "open" || r.status === "offered");
  const closed = requests.filter((r) => !(r.status === "open" || r.status === "offered"));
  const holidays = (phRes.data ?? []) as {
    booking_id: string;
    student_name: string;
    subject: string;
    holiday_on: string;
    holiday_name: string;
    skipping: boolean;
    session_id: string | null;
  }[];
  const mine = new Set(((linksRes.data ?? []) as { student_id: string }[]).map((l) => l.student_id));
  const children = (
    (studentsRes.data ?? []) as { id: string; full_name: string; account_id: string | null; student_subjects: { subject: string }[] }[]
  )
    .filter((s) => isAdmin || mine.has(s.id) || s.account_id === viewerId)
    .map((s) => ({ id: s.id, name: s.full_name, subjects: s.student_subjects.map((x) => x.subject) }))
    .filter((s) => s.subjects.length > 0);
  const tutors = ((tutorsRes.data ?? []) as unknown as { account_id: string; account: { full_name: string } | null }[]).map((t) => ({
    id: t.account_id,
    name: t.account?.full_name ?? "Tutor",
  }));
  const libraries = (libsRes.data ?? []) as { id: string; name: string }[];

  const line = (r: SessionRequest) =>
    `${r.student_name} · ${r.subject} · ${KIND_NAMES[r.kind] ?? r.kind}` +
    (r.kind === "extra" && r.event_on ? ` before ${r.event_label ?? "an event"} on ${shortDate(r.event_on)}` : "") +
    (r.kind !== "extra" && r.event_on ? ` · ${shortDate(r.event_on)}` : "") +
    (r.wants ? ` · wants ${WANTS_NAMES[r.wants] ?? r.wants}` : "");

  // A day before the event is the latest an extra session can be.
  const dayBefore = (iso: string) => {
    const d = new Date(`${iso}T00:00:00`);
    d.setDate(d.getDate() - 1);
    return d.toISOString().slice(0, 10);
  };

  return (
    <>
      {canAsk && holidays.length > 0 && (
        <Card
          title="Public holiday weeks"
          description="Sessions that fall on a public holiday in the next few months. You can skip public holidays for a booking and ask for a one-off at another time that week."
        >
          <ul className="divide-y divide-zinc-100 text-sm">
            {holidays.map((h) => (
              <li key={`${h.booking_id}-${h.holiday_on}`} className="space-y-2 py-3 first:pt-0">
                <p>
                  <span className="font-medium">
                    {h.holiday_name}, {shortDate(h.holiday_on)}
                  </span>
                  <span className="text-zinc-600">
                    {" "}
                    · {h.student_name} · {h.subject} ·{" "}
                    {h.skipping ? "skipped (no session that day)" : h.session_id ? "session booked that day" : "no session that day"}
                  </span>
                </p>
                <SkipPublicHolidaysForm bookingId={h.booking_id} skipping={h.skipping} />
              </li>
            ))}
          </ul>
        </Card>
      )}

      {canAsk && children.length > 0 && (
        <Card collapsible defaultOpen={false} title="Ask for a session" description="An extra session before a big event, a one-off for a public holiday week, or cover while your tutor is away.">
          <SessionRequestForm students={children} today={today} />
        </Card>
      )}

      <Card
        title="Requests"
        description={
          isAdmin
            ? "Families' requests for one-off sessions, oldest first. The student's tutor can offer a time too."
            : isTutor
              ? "Requests from your students' families. If you can, offer a time; the family then approves it."
              : "Your requests and where they are up to."
        }
      >
        {open.length === 0 ? (
          <Empty>No open requests.</Empty>
        ) : (
          <ul className="divide-y divide-zinc-100 text-sm">
            {open.map((r) => {
              const isTheirTutor = r.tutor_id === viewerId;
              return (
                <li key={r.id} className="space-y-2 py-4 first:pt-0">
                  <p className="font-medium">{line(r)}</p>
                  <p className="text-zinc-600">
                    {REQUEST_STATUS[r.status] ?? r.status} · asked {shortDate(r.created_at.slice(0, 10))}
                    {r.tutor_name && ` · tutor ${r.tutor_name}`}
                  </p>
                  {r.note && <p className="text-zinc-600">Note: {r.note}</p>}
                  {r.status === "open" && (isAdmin || isTheirTutor) && (
                    <OfferOneOffForm
                      requestId={r.id}
                      isAdmin={isAdmin}
                      tutors={r.tutor_id ? [{ id: r.tutor_id, name: r.tutor_name ?? "Usual tutor" }, ...tutors.filter((t) => t.id !== r.tutor_id)] : tutors}
                      libraries={libraries}
                      today={today}
                      before={r.kind === "extra" && r.event_on ? dayBefore(r.event_on) : null}
                    />
                  )}
                  {isAdmin && <CloseRequestForm id={r.id} status="declined" label="Couldn't arrange it" />}
                  {!isAdmin && !isTutor && <CloseRequestForm id={r.id} status="withdrawn" label="Withdraw" />}
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      {closed.length > 0 && (
        <Card collapsible defaultOpen={false} title="Earlier requests">
          <ul className="divide-y divide-zinc-100 text-sm">
            {closed.map((r) => (
              <li key={r.id} className="py-2">
                <span className="font-medium">{line(r)}</span>
                <span className="text-zinc-600"> · {REQUEST_STATUS[r.status] ?? r.status}</span>
                {r.staff_note && <span className="block text-zinc-600">{r.staff_note}</span>}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------
type Block = {
  id: string;
  tutor_name: string;
  student_name: string;
  blocked_by_role: string;
  reason: string;
  created_at: string;
  followed_up_at: string | null;
  follow_up_note: string | null;
  lifted_at: string | null;
};

export async function BlocksSection({
  viewerId,
  isAdmin,
  isTutor,
  bookings,
}: {
  viewerId: string;
  isAdmin: boolean;
  isTutor: boolean;
  bookings: { tutor_id: string; tutor_name: string; student_id: string; student_name: string }[];
}) {
  const supabase = await createClient();
  const { data } = await supabase.rpc("list_blocks");
  const blocks = (data ?? []) as Block[];
  // Who each person can block: tutors their students they have had; families
  // the tutors their children have had.
  const seen = new Set<string>();
  const choices: { value: string; label: string }[] = [];
  for (const b of bookings) {
    const asTutor = isTutor && b.tutor_id === viewerId;
    if (!isAdmin && !asTutor && b.tutor_id === viewerId) continue;
    const key = `${b.tutor_id}:${b.student_id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    choices.push({ value: key, label: asTutor ? b.student_name : `${b.tutor_name} (for ${b.student_name})` });
  }
  const tutorChoices = choices.filter((c) => c.value.startsWith(`${viewerId}:`));
  const familyChoices = choices.filter((c) => !c.value.startsWith(`${viewerId}:`));

  return (
    <>
      {!isAdmin && (isTutor ? tutorChoices.length > 0 : familyChoices.length > 0) && (
        <Card
          collapsible
          defaultOpen={false}
          title={isTutor ? "Block a student" : "Block a tutor"}
          description="If a match isn't working and shouldn't be suggested again. A reason is required, and CLG will follow up with you."
        >
          <BlockForm choices={isTutor ? tutorChoices : familyChoices} asTutor={isTutor} />
        </Card>
      )}
      <Card
        title="Blocks"
        description={
          isAdmin
            ? "Each block needs a follow-up with the person who made it, to understand what happened and help it not happen again. The other person isn't told."
            : "Blocks you have made. Only CLG sees the reason."
        }
      >
        {blocks.length === 0 ? (
          <Empty>No blocks.</Empty>
        ) : (
          <ul className="divide-y divide-zinc-100 text-sm">
            {blocks.map((b) => (
              <li key={b.id} className={`space-y-2 py-4 first:pt-0 ${b.lifted_at ? "text-zinc-400" : ""}`}>
                <p>
                  <span className="font-medium">
                    {b.blocked_by_role === "tutor" ? `${b.tutor_name} blocked ${b.student_name}` : `${b.student_name}'s family blocked ${b.tutor_name}`}
                  </span>
                  <span className="text-zinc-600">
                    {" "}
                    · {shortDate(b.created_at.slice(0, 10))}
                    {b.lifted_at ? " · lifted" : b.followed_up_at ? " · followed up" : isAdmin ? " · to follow up" : ""}
                  </span>
                </p>
                <p className="text-zinc-600">Reason: {b.reason}</p>
                {isAdmin && b.follow_up_note && <p className="text-zinc-600">Follow-up: {b.follow_up_note}</p>}
                {isAdmin && !b.lifted_at && !b.followed_up_at && <BlockFollowUpForm id={b.id} />}
                {isAdmin && !b.lifted_at && (
                  <form action={liftBlock}>
                    <input type="hidden" name="id" value={b.id} />
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">
                      Lift this block
                    </BusyButton>
                  </form>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}

// ---------------------------------------------------------------------------
// Admins: libraries, with confirmation and opening hours
// ---------------------------------------------------------------------------
export async function LibrariesAdminSection() {
  const supabase = await createClient();
  const [libsRes, hoursRes] = await Promise.all([
    supabase.from("libraries").select("id, name, suburb, active, confirmed_at, suggested_by").order("name"),
    supabase.from("library_hours").select("library_id, weekday, opens, closes").order("weekday").order("opens"),
  ]);
  const libraries = (libsRes.data ?? []) as {
    id: string;
    name: string;
    suburb: string | null;
    active: boolean;
    confirmed_at: string | null;
  }[];
  const hours = (hoursRes.data ?? []) as { library_id: string; weekday: number; opens: string; closes: string }[];
  const hoursOf = (id: string) => hours.filter((h) => h.library_id === id);
  return (
    <Card
      title="Libraries"
      description="Public libraries for in-person sessions. Confirm each library and add its opening hours: sessions are only offered at confirmed libraries, inside opening hours."
    >
      {libraries.length === 0 ? (
        <Empty>No libraries yet.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {libraries.map((l) => {
            const h = hoursOf(l.id);
            return (
              <li key={l.id} className="space-y-2 py-4 first:pt-0">
                <div className="flex items-center justify-between gap-3">
                  <span className={l.active ? "" : "text-zinc-400"}>
                    <span className="font-medium">{l.name}</span>
                    {l.suburb && ` · ${l.suburb}`}
                    {!l.active && " (hidden)"}
                    {!l.confirmed_at && <span className="ml-2 text-xs text-amber-800">to confirm</span>}
                    {l.confirmed_at && h.length === 0 && <span className="ml-2 text-xs text-amber-800">opening hours missing</span>}
                  </span>
                  <form action={setLibraryActive}>
                    <input type="hidden" name="id" value={l.id} />
                    <input type="hidden" name="active" value={l.active ? "false" : "true"} />
                    <BusyButton type="submit" className="text-xs text-teal-800 underline">
                      {l.active ? "Hide" : "Show"}
                    </BusyButton>
                  </form>
                </div>
                {h.length > 0 && (
                  <div className="text-zinc-600">
                    {h.map((x) => `${WEEKDAY_NAMES[x.weekday - 1].slice(0, 3)} ${clockTime(x.opens)}–${clockTime(x.closes)}`).join(" · ")}{" "}
                    <form action={removeLibraryHours} className="inline">
                      <input type="hidden" name="library_id" value={l.id} />
                      <BusyButton type="submit" className="text-xs text-teal-800 underline">
                        Clear hours
                      </BusyButton>
                    </form>
                  </div>
                )}
                <details>
                  <summary className="cursor-pointer text-xs text-teal-800 underline">Add opening hours</summary>
                  <div className="mt-2">
                    <LibraryHoursForm libraryId={l.id} />
                  </div>
                </details>
                {!l.confirmed_at && h.length > 0 && <ConfirmLibraryForm libraryId={l.id} />}
              </li>
            );
          })}
        </ul>
      )}
      <SubHeading>Add a library</SubHeading>
      <LibraryForm />
    </Card>
  );
}
