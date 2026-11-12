// Summary: the tutor dashboard: students (with notes, uploads and reviews to do),
// what they teach, child safety checks, and hours and availability.
//
import { redirect } from "next/navigation"; // Sends the person to another page.
import { removeAvailability, removeTeaching } from "@/app/actions/tutor"; // The tutor actions: remove an available time, remove a subject.
import { Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: card, empty line, small heading, table and text link.
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { SectionShell } from "@/components/section-shell"; // The page frame with a side menu.
import { SessionAnswersCard, getOffersToAnswer } from "@/components/session-answers-card"; // The "waiting for your answer" card and its count.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Whether two-step sign-in is still needed, and the signed-in person.
import { STATE_NAMES, WEEKDAYS, checkName, type AuState } from "@/lib/checks"; // State names, weekday names, check names, and the state type.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { NOTE_DUE_HOURS, STALLED_AFTER_SESSIONS, hoursAgo } from "@/lib/progress"; // When notes are due, when progress counts as stalled, and "x hr ago" wording.
import { addDays, currentTime, sessionWhen, shortDate } from "@/lib/scheduling"; // Date helpers: add days, the time now, session time wording, short dates.
import { AvailabilityForm, MaxHoursForm, MyCheckForm, TeachingForm } from "../tutor-forms"; // The tutor forms.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

const SECTIONS = [ // The side menu's sections:
  { id: "students", label: "Your students" }, // their students,
  { id: "teaching", label: "What you teach" }, // what they teach,
  { id: "checks", label: "Child safety checks" }, // their checks,
  { id: "hours", label: "Hours and availability" }, // hours and availability.
] as const; // End of the sections.

type DueNote = { session_id: string; tutor_id: string; student_id: string; student_name: string; starts_at: string; hours_since_end: number }; // A session note still to write: session, tutor, student, start time and hours since it ended.
type Caseload = { // A student's progress summary:
  student_id: string; // the student,
  active_goals: number; // how many goals are active,
  last_note_on: string | null; // the date of the last note (if any),
  notes_since_movement: number; // and notes since a skill last moved.
}; // End of Caseload.

type CheckStatus = { kind: string; expires_on: string | null; status: string }; // A check's current standing: type, expiry and status.
type MyCheck = { // A check the tutor sent:
  id: string; // its id,
  kind: string; // its type,
  reference: string | null; // its number (if any),
  completed_on: string | null; // the date done (if known),
  expires_on: string; // its expiry date,
  submitted_at: string | null; // when it was sent,
  verified_at: string | null; // when CLG confirmed it (if yet),
  declined_at: string | null; // when CLG sent it back (if it did),
  declined_reason: string | null; // why it was sent back,
  document_path: string | null; // and where the copy is stored.
}; // End of MyCheck.

const STATUS_NAMES: Record<string, string> = { // The words for each check status:
  current: "Current", // current,
  expiring_soon: "Renew soon", // renew soon,
  expired: "Expired", // expired,
  missing: "Missing", // missing.
}; // End of the words.

const day = (iso: string | null) => // Shows a date like "5 Nov 2026":
  iso ? new Date(iso).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" }) : "-"; // or a dash if there's none.

export default async function TutorDashboard({ searchParams }: PageProps<"/dashboard/tutor">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // The signed-in person.
  if (!viewer.roles.includes("tutor")) redirect("/dashboard"); // Not a tutor: sends them to their main dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step sign-in not set up: sends them to set it up.
  const params = await searchParams; // The address's settings.
  const requested = SECTIONS.find((s) => s.id === params.section)?.id ?? "students"; // Which section was asked for (students if none or unknown).

  const supabase = await createClient(); // Connects to the database.
  const teaching = await supabase // Reads what they teach:
    .from("tutor_teaching") // from tutor_teaching,
    .select("id, subject, from_level, to_level") // these details,
    .eq("tutor_id", viewer.id) // for this tutor,
    .order("subject"); // by subject.
  const teachingRows = (teaching.data ?? []) as { id: string; subject: string; from_level: string; to_level: string }[]; // The subjects.
  // New tutors are asked what they teach before anything else.
  const firstTime = teachingRows.length === 0; // Whether they haven't added any subjects yet.
  const section = firstTime ? "teaching" : requested; // The open section (what they teach, for new tutors).

  const [assigned, checks, mine, states, settings, slots, dueRes, caseRes, reviewsRes, uploadsRes, pausesRes, libsRes] = await Promise.all([ // Reads everything else at once:
    supabase // their students:
      .from("tutor_assignments") // from tutor_assignments,
      .select("id, subject, student:students(id, full_name, year_level)") // the subject and the student's details,
      .eq("tutor_id", viewer.id), // for this tutor.
    supabase.from("tutor_check_status").select("kind, expires_on, status").eq("tutor_id", viewer.id), // each check's current standing,
    supabase // the checks they sent:
      .from("tutor_checks") // from tutor_checks,
      .select("id, kind, reference, completed_on, expires_on, submitted_at, verified_at, declined_at, declined_reason, document_path") // these details,
      .eq("tutor_id", viewer.id) // for this tutor,
      .order("submitted_at", { ascending: false }), // newest first.
    supabase.from("tutor_cleared_states").select("state").eq("tutor_id", viewer.id), // the states they're cleared for,
    supabase.from("tutor_work_settings").select("max_weekly_hours").eq("tutor_id", viewer.id).maybeSingle(), // their most hours per week,
    supabase // their available times:
      .from("tutor_availability") // from tutor_availability,
      .select("id, weekday, starts_at, ends_at, in_person, online, library_id, library:libraries(name)") // these details and the library's name,
      .eq("tutor_id", viewer.id) // for this tutor,
      .order("weekday") // by day,
      .order("starts_at"), // then start time.
    supabase.rpc("list_notes_due"), // notes still to write,
    supabase.rpc("progress_students_to_check"), // each student's progress summary,
    supabase // term reviews to write:
      .from("term_reviews") // from term_reviews,
      .select("id, student_id, term_label, term_ends_on, status, student:students(full_name)") // these details and the student's name,
      .eq("tutor_id", viewer.id) // for this tutor,
      .in("status", ["draft", "returned"]) // drafts or sent back,
      .order("term_ends_on"), // soonest first.
    // Reports and work the family uploaded that the tutor hasn't opened yet.
    supabase // family uploads:
      .from("progress_notices") // from progress_notices,
      .select("id, student_id, title, body") // these details,
      .eq("account_id", viewer.id) // for this tutor,
      .eq("kind", "evidence_added") // uploads only,
      .is("read_at", null) // not yet opened,
      .order("deliver_at", { ascending: false }) // newest first,
      .limit(20), // up to 20.
    // Sessions put on hold or back on in the last 2 weeks. These used to be
    // emailed; since 2 Nov 2026 they are shown here instead (app notices only).
    supabase // on hold and back on notices:
      .from("billing_tutor_notices") // from billing_tutor_notices,
      .select("id, kind, created_at, student:students(full_name)") // these details and the student's name,
      .eq("tutor_id", viewer.id) // for this tutor,
      .gte("created_at", new Date(currentTime() - 14 * 24 * 3600 * 1000).toISOString()) // from the last 14 days,
      .order("created_at", { ascending: false }) // newest first,
      .limit(20), // up to 20.
    // Libraries a tutor can pick for a time: confirmed ones, and any they suggested.
    supabase // libraries:
      .from("libraries") // from libraries,
      .select("id, name, suburb") // these details,
      .eq("active", true) // still in use,
      .or(`confirmed_at.not.is.null,suggested_by.eq.${viewer.id}`) // confirmed, or suggested by this tutor,
      .order("name"), // by name.
  ]); // End of the reads.
  const pauses = (pausesRes.data ?? []) as unknown as { // The on hold notices:
    id: string; // each has an id,
    kind: "on_hold" | "back_on"; // on hold or back on,
    created_at: string; // when,
    student: { full_name: string } | null; // and the student.
  }[]; // (end of the type)
  const newUploads = (uploadsRes.data ?? []) as { id: string; student_id: string; title: string; body: string }[]; // The new uploads.
  const reviewsToWrite = (reviewsRes.data ?? []) as unknown as { // The term reviews to write:
    id: string; // each has an id,
    student_id: string; // the student,
    term_label: string; // the term's name,
    term_ends_on: string; // the term's last day,
    status: string; // its status,
    student: { full_name: string } | null; // and the student's name.
  }[]; // (end of the type)
  // Admins get everyone's; this list is only the tutor's own.
  const notesDue = ((dueRes.data ?? []) as DueNote[]).filter((d) => d.tutor_id === viewer.id); // Just this tutor's notes to write.
  const caseload = new Map(((caseRes.data ?? []) as Caseload[]).map((c) => [c.student_id, c])); // Each student's progress summary, by student.

  const statusRows = (checks.data ?? []) as CheckStatus[]; // Each check's standing.
  const myChecks = (mine.data ?? []) as MyCheck[]; // The checks they sent.
  const students = ((assigned.data ?? []) as unknown as { // Their students:
    id: string; // each has an id,
    subject: string; // a subject,
    student: { id: string; full_name: string; year_level: string | null } | null; // and the student's details,
  }[]).filter((a) => a.student); // keeping only rows where the student could be read.
  const clearedStates = (states.data ?? []).map((s) => STATE_NAMES[s.state as AuState] ?? s.state); // The names of the states they're cleared for.
  const problems = statusRows.filter((c) => c.status !== "current").length; // How many checks aren't current.
  // Numbers on the menu: notes, reviews and uploads to look at, what you
  // teach if it's empty, and checks to renew.
  const todo = await getToDoCounts(viewer.roles); // The to-do numbers.
  const offers = await getOffersToAnswer(); // Session times waiting for this tutor's answer.

  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={viewer.roles} active="tutor" />{/* the dashboard tabs, with Tutor open, */}
      <SectionShell // the page frame:
        basePath="/dashboard/tutor" // at this address,
        label="Tutor" // labelled "Tutor",
        role="tutor" // in the tutor colours,
        section={section} // on the open section,
        sections={SECTIONS.map((s) => ({ ...s, count: todo.get("tutor", s.id) }))} // with each section's to-do number on the menu.
      >{/* (end of the frame's settings) */}
        {/* Session times to accept or decline, and new notices, on every section so they aren't missed. */}
        <SessionAnswersCard waiting={offers.as_tutor} notices={todo.get("sessions", "notices") ?? 0} who="tutor" />
        <p className="text-sm">{/* a line of links: */}
          <TextLink href="/pay">My pay</TextLink>{/* their pay, */}
          {" · "}{/* a dot between, */}
          <TextLink href="/materials">CLG materials</TextLink>{/* CLG materials. */}
        </p>{/* End of the line. */}
        {section === "students" && pauses.length > 0 && ( // On the students section, if there are on hold notices:
          <Card title="Sessions on hold or back on" description="From the last 2 weeks. Your schedule shows what's on.">{/* a card: */}
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {pauses.map((p) => ( // for each notice:
                <li key={p.id} className="py-2.5 first:pt-0">{/* a row: */}
                  <span className="font-medium">{p.student?.full_name ?? "A student"}</span>{/* the student's name, */}
                  <span className="text-zinc-600">{/* in grey: */}
                    {" · "}{/* a dot, */}
                    {p.kind === "on_hold" // if on hold:
                      ? "on hold for now. Please don't run these sessions until CLG says they're back on." // says not to run sessions,
                      : "back on."}{/* otherwise back on. */}
                    {" · "}{/* a dot, */}
                    {shortDate(p.created_at.slice(0, 10))}{/* the date. */}
                  </span>{/* End of the grey part. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {section === "students" && notesDue.length > 0 && ( // On the students section, if notes are due:
          <Card // a card:
            title="Session notes to write" // its title,
            description={`Notes are due within ${NOTE_DUE_HOURS} hr of the session. About three minutes each.`} // when notes are due.
          >{/* (end of the card's settings) */}
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {notesDue.map((d) => ( // for each note:
                <li key={d.session_id} className="flex flex-wrap items-baseline justify-between gap-2 py-2.5 first:pt-0">{/* a row: */}
                  <span>{/* (a group) */}
                    <span className="font-medium">{d.student_name}</span>{/* the student's name, */}
                    <span className="text-zinc-600"> · {sessionWhen(d.starts_at)}</span>{/* the session's time, */}
                    {d.hours_since_end >= NOTE_DUE_HOURS && ( // if it's overdue:
                      <span className="ml-2 text-xs text-red-700">ended {hoursAgo(d.hours_since_end)}</span> // how long ago it ended, in red.
                    )}{/* End of this part. */}
                  </span>{/* End of the group. */}
                  <TextLink href={`/students/${d.student_id}/progress?session=${d.session_id}`}>Write note</TextLink>{/* a link to write the note. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {section === "students" && newUploads.length > 0 && ( // On the students section, if there are new uploads:
          <Card title="New uploads from families" description="School reports and marked work. Link any skills they show.">{/* a card: */}
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {newUploads.map((u) => ( // for each upload:
                <li key={u.id} className="flex flex-wrap items-baseline justify-between gap-2 py-2.5 first:pt-0">{/* a row: */}
                  <span>{/* (a group) */}
                    <span className="font-medium">{u.title}</span>{/* its title, */}
                    <span className="block text-zinc-600">{u.body}</span>{/* its description. */}
                  </span>{/* End of the group. */}
                  <TextLink href={`/students/${u.student_id}/progress`}>Have a look</TextLink>{/* a link to the student's progress page. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {section === "students" && reviewsToWrite.length > 0 && ( // On the students section, if reviews are due:
          <Card title="Term reviews to write" description="CLG checks each one before the family sees it.">{/* a card: */}
            <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
              {reviewsToWrite.map((r) => ( // for each review:
                <li key={r.id} className="flex flex-wrap items-baseline justify-between gap-2 py-2.5 first:pt-0">{/* a row: */}
                  <span>{/* (a group) */}
                    <span className="font-medium">{r.student?.full_name ?? "Student"}</span>{/* the student's name, */}
                    <span className="text-zinc-600">{/* in grey: */}
                      {" "}{/* a space, */}
                      · {r.term_label} · send by {shortDate(addDays(r.term_ends_on, -14))}{/* the term and the send-by date (2 weeks before term ends). */}
                    </span>{/* End of the grey part. */}
                    {r.status === "returned" && <span className="ml-2 text-xs text-amber-800">sent back for a change</span>}{/* if sent back, says so. */}
                  </span>{/* End of the group. */}
                  <TextLink href={`/students/${r.student_id}/progress`}>Write review</TextLink>{/* a link to write it. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {section === "students" && ( // The students section:
          <Card title="Your students">{/* the "Your students" card: */}
            {problems > 0 && ( // if any checks aren't current:
              <p className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{/* a red notice: */}
                Some of your checks are missing, expired or due soon. Students who need them are hidden until they are
                current. <TextLink href="/dashboard/tutor?section=checks">See your checks</TextLink>{/* with a link to their checks. */}
              </p> // End of the notice.
            )}{/* End of this part. */}
            {students.length === 0 ? ( // if no students:
              <Empty>No students assigned yet.</Empty> // says so.
            ) : ( // otherwise:
              <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                {students.map((a) => ( // for each student:
                  <li key={a.id} className="flex flex-wrap items-baseline justify-between gap-2 py-3 first:pt-0">{/* a row: */}
                    <span>{/* (a group) */}
                      <span className="font-medium">{a.student!.full_name}</span>{/* the student's name, */}
                      <span className="text-zinc-600">{/* in grey: */}
                        {a.student!.year_level && ` · ${a.student!.year_level}`} · {a.subject}{/* their year level (if known) and subject. */}
                      </span>{/* End of the grey part. */}
                    </span>{/* End of the group. */}
                    <TextLink href={`/students/${a.student!.id}/progress`}>Progress and notes</TextLink>{/* a link to their progress page, */}
                    <CaseloadLine info={caseload.get(a.student!.id)} />{/* and their progress summary line. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul> // End of the list.
            )}{/* End of this part. */}
          </Card> // End of the card.
        )}{/* End of the students section. */}

        {section === "teaching" && ( // The "what you teach" section:
          <>{/* (a group) */}
            {firstTime && ( // For new tutors:
              <p className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">{/* a welcome notice: */}
                Welcome! Before anything else, add each subject you can tutor and the year levels you teach it for.
                CLG uses this to match you with students.{/* explaining why. */}
              </p> // End of the notice.
            )}{/* End of this part. */}
            <Card // the "What you teach" card:
              title="What you teach" // its title,
              description="Add each subject with its own year levels, for example Maths from Year 3 to Year 10 and English from Year 7 to Year 12." // its help text.
            >{/* (end of the card's settings) */}
              {teachingRows.length === 0 ? ( // if none:
                <Empty>No subjects added yet.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                  {teachingRows.map((t) => ( // for each subject:
                    <li key={t.id} className="flex items-center justify-between gap-3 py-2.5 first:pt-0">{/* a row: */}
                      <span>{/* (a group) */}
                        <span className="font-medium">{t.subject}</span>{/* the subject, */}
                        <span className="text-zinc-600">{/* in grey: */}
                          {" "}{/* a space, */}
                          · {t.from_level === t.to_level ? t.from_level : `${t.from_level} to ${t.to_level}`}{/* the year level, or the range. */}
                        </span>{/* End of the grey part. */}
                      </span>{/* End of the group. */}
                      <form action={removeTeaching}>{/* a remove form: */}
                        <input type="hidden" name="id" value={t.id} />{/* the subject (hidden), */}
                        <BusyButton type="submit" className="text-xs text-red-700 underline">{/* the remove button: */}
                          Remove{/* its words, */}
                        </BusyButton>{/* end of the button. */}
                      </form>{/* End of the form. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
              <SubHeading>Add a subject</SubHeading>{/* a small heading, */}
              <TeachingForm />{/* the add-a-subject form. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the teaching section. */}

        {section === "checks" && ( // The checks section:
          <>{/* (a group) */}
            <Card // the "Where you stand" card:
              title="Where you stand" // its title,
              description={ // its description:
                <>{/* (a group) */}
                  You can currently be matched with students in:{" "}{/* the words, then a space, */}
                  <strong>{clearedStates.length ? clearedStates.join(", ") : "no states yet"}</strong>.{/* the states they're cleared for (or none yet). */}
                </> // End of the group.
              } // (end of the description)
            >{/* (end of the card's settings) */}
              {statusRows.length === 0 ? ( // if no checks confirmed:
                <Empty>No checks confirmed yet. Add your checks below.</Empty> // says so.
              ) : ( // otherwise:
                <Table headings={["Check", "Due again", "Status"]}>{/* a table: */}
                  {statusRows.map((c) => ( // for each check:
                    <tr key={c.kind} className={c.status === "current" ? "" : "text-red-700"}>{/* a row (red if not current): */}
                      <td className="font-medium">{checkName(c.kind)}</td>{/* the check's name, */}
                      <td>{day(c.expires_on)}</td>{/* when it's due again, */}
                      <td>{STATUS_NAMES[c.status] ?? c.status}</td>{/* its status. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of this part. */}
              <p className="mt-4 text-xs text-zinc-600">{/* a help paragraph about which checks are needed: */}
                Each state needs its own working with children check, and every tutor needs RRHAN-EC Fundamentals and
                Masterclass, wherever the student is. Upload each certificate with the date it was done or expires. The app
                reminds you 6 weeks and 2 weeks before a check expires. You can also add a first aid certificate or a police check. These are optional. The more states you are cleared for, the
                more students you can be matched with when a suitable match comes up. No number of students or hours is
                guaranteed.{/* (end of the text) */}
              </p>{/* End of the paragraph. */}
            </Card>{/* End of the card. */}

            <Card title="Add or renew a check">{/* the "Add or renew" card: */}
              <MyCheckForm />{/* the check form. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="What you've sent" description="Every check you add is logged here with its dates.">{/* the "What you've sent" fold-up card: */}
              {myChecks.length === 0 ? ( // if nothing sent:
                <Empty>Nothing sent yet.</Empty> // says so.
              ) : ( // otherwise:
                <Table headings={["Check", "Done", "Due again", "Sent", "Status"]}>{/* a table: */}
                  {myChecks.map((c) => ( // for each check sent:
                    <tr key={c.id}>{/* a row: */}
                      <td className="font-medium">{/* the check cell: */}
                        {checkName(c.kind)}{/* its name, */}
                        {c.reference && <span className="block text-xs text-zinc-500">{c.reference}</span>}{/* its number (if any), */}
                        {c.document_path && ( // if there's a copy:
                          <a // a link:
                            href={`/checks/${c.id}/document`} // to open the copy,
                            target="_blank" // in a new tab,
                            rel="noreferrer" // without passing on this page's address,
                            className="block text-xs text-teal-800 underline" // styled as a small link.
                          >{/* (end of the link's settings) */}
                            Your copy{/* its words, */}
                          </a> // end of the link.
                        )}{/* End of this part. */}
                      </td>{/* End of the cell. */}
                      <td>{day(c.completed_on)}</td>{/* the date done, */}
                      <td>{day(c.expires_on)}</td>{/* when it's due again, */}
                      <td>{day(c.submitted_at)}</td>{/* when it was sent, */}
                      <td>{/* the status cell: */}
                        {c.verified_at ? ( // if confirmed:
                          <span className="text-teal-800">Confirmed</span> // says so.
                        ) : c.declined_at ? ( // if sent back:
                          <span className="text-red-700">{/* in red: */}
                            Sent back{/* says so, */}
                            {c.declined_reason && <span className="block text-xs">{c.declined_reason}</span>}{/* and why (if given). */}
                          </span> // End of the red part.
                        ) : ( // otherwise:
                          <span className="text-zinc-600">Waiting for CLG</span> // waiting for CLG.
                        )}{/* End of this part. */}
                      </td>{/* End of the cell. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the checks section. */}

        {section === "hours" && ( // The hours section:
          <Card // a fold-up card:
            collapsible defaultOpen={false} title="Your hours and availability" // folded to start, with its title,
            description={ // its description:
              <>{/* (a group) */}
                These are separate: your availability is when you could teach, and your weekly limit is the most hours
                you can work in total.{/* (end of the text) */}
              </> // End of the group.
            } // (end of the description)
          >{/* (end of the card's settings) */}
            <MaxHoursForm current={settings.data?.max_weekly_hours ?? null} />{/* the most hours form. */}
            <SubHeading>Times you are available</SubHeading>{/* a small heading, */}
            <ul className="mb-4 space-y-1 text-sm">{/* a list: */}
              {(slots.data ?? []).length === 0 && <li className="text-zinc-500">None added yet.</li>}{/* none yet, if there are none, */}
              {(slots.data ?? []).map((slot) => ( // for each time:
                <li key={slot.id} className="flex items-center gap-3">{/* a row: */}
                  <span>{/* (a group) */}
                    {WEEKDAYS[slot.weekday - 1]} {slot.starts_at.slice(0, 5)} to {slot.ends_at.slice(0, 5)}{/* the day, from and to times, */}
                    <span className="text-zinc-600">{/* in grey: */}
                      {" · "}{/* a dot, */}
                      {slotPlace(slot)}{/* where. */}
                    </span>{/* End of the grey part. */}
                  </span>{/* End of the group. */}
                  <form action={removeAvailability}>{/* a remove form: */}
                    <input type="hidden" name="id" value={slot.id} />{/* the time (hidden), */}
                    <BusyButton type="submit" className="text-xs text-red-700 underline">{/* the remove button: */}
                      Remove{/* its words, */}
                    </BusyButton>{/* end of the button. */}
                  </form>{/* End of the form. */}
                </li> // End of the row.
              ))}{/* End of the loop. */}
            </ul>{/* End of the list. */}
            <AvailabilityForm libraries={(libsRes.data ?? []) as { id: string; name: string; suburb: string | null }[]} />{/* the add-a-time form, with the libraries. */}
            <p className="mt-3 text-sm text-zinc-600">{/* a line: */}
              Library not in the list? Suggest it under <TextLink href="/schedule?section=places">Where you teach</TextLink>.{/* where to suggest a library. */}
            </p>{/* End of the line. */}
          </Card> // End of the card.
        )}{/* End of the hours section. */}
        {!viewer.roles.includes("student") && ( // If they aren't a student too:
          <p className="text-sm text-zinc-600">{/* a line: */}
            Want to learn with CLG yourself? <TextLink href="/dashboard/learn">Add a student profile</TextLink>{/* offering to add a student profile for themselves. */}
          </p> // End of the line.
        )}{/* End of this part. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of TutorDashboard.

// One line under each student: last note, and anything worth a look.
function CaseloadLine({ info }: { info: Caseload | undefined }) { // The line under a student (given their progress summary).
  if (!info) return null; // No summary: shows nothing.
  return ( // Shows:
    <p className="w-full text-xs text-zinc-600">{/* a small grey line: */}
      {info.last_note_on ? `Last note ${shortDate(info.last_note_on)}` : "No notes yet"}{/* the last note's date, or no notes yet, */}
      {info.active_goals === 0 && <span className="ml-2 text-red-700">No goals set</span>}{/* no goals set (in red), if so, */}
      {info.notes_since_movement >= STALLED_AFTER_SESSIONS && ( // if nothing has moved for a while:
        <span className="ml-2 text-amber-800">{/* in amber: */}
          No skill has moved in {info.notes_since_movement} sessions: time to adjust the goals or approach?{/* suggests a change. */}
        </span> // End of the amber part.
      )}{/* End of this part. */}
    </p> // End of the line.
  ); // End of what's shown.
} // End of CaseloadLine.

// Where a weekly time can be taught, in words.
function slotPlace(slot: { in_person: boolean; online: boolean; library: unknown }) { // Takes the time's places.
  const lib = (Array.isArray(slot.library) ? slot.library[0] : slot.library) as { name: string } | null; // The library (the database can give one or a list).
  if (!slot.in_person) return "Online only"; // Not in person: online only.
  const where = lib?.name ?? "any of your libraries (please re-add this time with one library)"; // The library's name, or a note to re-add the time.
  return slot.online ? `Online or at ${where}` : `At ${where}`; // Online and a library, or just the library.
} // End of slotPlace.
