// The Matching tab (scheduling module): one place for owner, operations and
// support admins to match students with tutors. The database decides who
// can see what; this page only shows it.

import type { ReactNode } from "react"; // The type for anything React can show.
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { redirect } from "next/navigation"; // Sends the person to another page.
import { BackButton, Card, Empty, Field, Select, TextLink } from "@/components/ui"; // Shared page parts: back button, card, empty line, field, drop-down and text link.
import { FRONT_DESK, FULL_ADMIN, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // Admin levels, the admin level reader, two-step sign-in check, and the signed-in person.
import { CHECK_NAMES, STATES, type CheckKind } from "@/lib/checks"; // Check names, Australian states, and the check type.
import { WEEKDAY_NAMES, addDays, clockTime, localToday, placeLabel, shortDate } from "@/lib/scheduling"; // Weekday names and date, time and place helpers.
import { YEAR_LEVELS } from "@/lib/students"; // The year levels.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { OfferForm, type OfferChoice, type StudentTerm } from "../schedule/forms"; // The offer form and its types.
import { CourseDetails, type CourseUnit } from "@/components/course-details"; // University and TAFE unit details, and their type.
import { CourseOverviewForm } from "../admin/course-overview-form"; // The admin's course overview form.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { UrgentRematchBox } from "@/components/urgent-rematch-box"; // The red "Urgent: needs a new tutor" box (from the child safety module).
import { AskFamilyButton, WaitingSinceForm } from "./forms"; // The "Ask the family" button and the "waiting since" date form.

type StageCount = { stage: string; subjects: number; oldest_days: number | null }; // How many subjects are at each stage, and the longest wait.
type QueueRow = { // One student-subject in the queue:
  student_id: string; // the student,
  student_name: string; // their name,
  year_level: string | null; // their year level (if known),
  working_level: string | null; // the level they are working at (if known),
  subject: string; // the subject,
  state: string; // their state,
  stage: string; // their stage,
  days: number; // days at this stage,
  tutor_name: string | null; // their tutor (if any),
  has_places: boolean; // whether places are set,
  total: number; // and how many in the whole list.
}; // End of QueueRow.
type Shortlist = { // One tutor on the shortlist:
  tutor_id: string; // the tutor,
  tutor_name: string; // their name,
  teaches_sibling: boolean; // whether they teach a sibling,
  sibling_names: string | null; // the siblings' names,
  times: number; // how many times suit,
  preferred_times: number; // how many of those are preferred,
  in_person_times: number; // how many are in person,
  best_weekday: number | null; // the best time's day,
  best_start: string | null; // start,
  best_end: string | null; // end,
  best_delivery: "online" | "library" | "home" | null; // where,
  best_library: string | null; // library,
  best_library_name: string | null; // library's name,
  booked_minutes: number; // minutes already booked each week,
  max_weekly_hours: number | null; // their most hours per week,
  at_max: boolean; // whether they are at that limit,
  learning_support: boolean; // whether they have learning support experience,
  check_kind: string | null; // a check expiring soon (if any),
  check_expires: string | null; // its expiry date,
  rank: number; // and their place in the list.
}; // End of Shortlist.
type Gap = { subject: string; level: string; state: string; waiting: number; longest_days: number }; // A subject and level students wait for that no tutor teaches.
type Missing = { student_id: string; item: string; last_asked: string | null }; // A detail still missing before an offer, and when the family was last asked.
type Wait = { student_id: string; subject: string; waiting_on: "tutor" | "family" | "both"; since: string }; // An offer waiting, and who it waits for.

// The details checked before an offer, in order (Carla, 16 Nov 2026), with
// the admin page that fills each one in.
const READY_ITEMS: { item: string; label: string; adminHref: (studentId: string) => string }[] = [ // Each detail:
  { item: "year_level", label: "Year level", adminHref: (id) => `/admin?section=families&student=${id}` }, // year level,
  { item: "school", label: "School", adminHref: (id) => `/admin?section=families&student=${id}` }, // school,
  { item: "session_places", label: "Session places (online, libraries or travel distance)", adminHref: (id) => `/schedule?as=admin&section=child-places&student=${id}` }, // session places,
  { item: "booking_length", label: "How long to book (end date and holidays)", adminHref: (id) => `/schedule?as=admin&section=booking-length&student=${id}` }, // how long to book.
]; // End of the details.

// The stage tabs, in order (Carla, 16 Nov 2026). "db" is the database's
// stage; the two "waiting for" tabs split offers by who has not answered.
const STAGES: { id: string; db: string; label: string; hint: string }[] = [ // The tabs:
  { id: "needs_tutor", db: "needs_tutor", label: "Needs a tutor", hint: "Asked for a subject, nothing offered yet." }, // needs a tutor,
  { id: "waiting_tutor", db: "tutor_to_confirm", label: "Waiting for tutor", hint: "An offer is waiting for the tutor to accept or decline." }, // waiting for the tutor,
  { id: "waiting_family", db: "tutor_to_confirm", label: "Waiting for family", hint: "The tutor said yes. The offer is waiting for the family to approve." }, // waiting for the family,
  { id: "waitlist", db: "waitlist", label: "Waitlist", hint: "No suitable tutor is available yet. These students wait here until one is." }, // waitlist,
  { id: "assigned", db: "assigned", label: "Assigned, no time", hint: "A tutor is assigned but no weekly time is booked." }, // assigned with no time,
  { id: "active", db: "active", label: "Active", hint: "Weekly sessions are running, including the first weeks with a new tutor." }, // active.
]; // End of the stages.
const PAGE_SIZE = 30; // Students per page.
const PARTS: Record<string, string> = { // The words for parts of the day:
  morning: "mornings", // mornings,
  midday: "middle of the day", // middle of the day,
  afternoon: "afternoons", // afternoons,
  evening: "evenings", // evenings.
}; // End of the words.
const CHANGE_REASON_NAMES: Record<string, string> = { // The words for why a suggestion was changed:
  family_request: "Family asked for something else", // family request,
  tutor_request: "Tutor asked for something else", // tutor request,
  tutor_fit: "Another tutor suited the student better", // tutor fit,
  time: "Better time for the tutor's day", // time,
  place: "Better place", // place,
  other: "Other", // other.
}; // End of the words.

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? ""; // Gives one value from the address (the first if there are several).
const hours = (minutes: number) => `${Math.round((minutes / 60) * 10) / 10} hr`; // Shows minutes as hours, like "1.5 hr".

export default async function MatchingPage({ searchParams }: PageProps<"/matching">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // The signed-in person.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step sign-in not set up: sends them to set it up.
  const level = viewer.roles.includes("admin") ? await getAdminLevel() : null; // Their admin level, if they are an admin.
  if (!level || !FRONT_DESK.includes(level)) redirect("/dashboard"); // Not a front-desk admin: sends them to their dashboard.
  const isFull = FULL_ADMIN.includes(level); // Whether they are a full admin.

  const params = await searchParams; // The address's settings.
  const view = ["reports", "gaps"].includes(one(params.view)) ? "reports" : "queue"; // Which view: reports (old "gaps" links too) or the queue.
  const stage = STAGES.find((s) => s.id === one(params.stage))?.id ?? "needs_tutor"; // Which stage (needs a tutor if none or unknown).
  const search = one(params.q).slice(0, 100); // The search words (up to 100 letters).
  const year = (YEAR_LEVELS as readonly string[]).includes(one(params.year)) ? one(params.year) : ""; // The year level filter (only a real year level).
  const state = (STATES as readonly string[]).includes(one(params.state)) ? one(params.state) : ""; // The state filter (only a real state).
  const page = Math.max(Number(one(params.page)) || 1, 1); // The page number (at least 1).
  const studentId = one(params.student); // The student chosen (if any).
  const subject = one(params.subject).slice(0, 100); // The subject chosen (up to 100 letters).

  const supabase = await createClient(); // Connects to the database.
  const current = STAGES.find((s) => s.id === stage)!; // The current tab.
  const split = current.db === "tutor_to_confirm"; // Whether this tab splits waiting offers by who has not answered.
  const [countsRes, queueRes, waitsRes] = await Promise.all([ // Reads three things at once:
    supabase.rpc("matching_stage_counts"), // the stage counts,
    supabase.rpc("matching_queue", { // the queue:
      p_stage: current.db, // at this stage,
      p_search: search || null, // matching the search,
      p_year: year || null, // the year level,
      p_state: state || null, // the state,
      p_limit: split ? 500 : PAGE_SIZE, // one page at a time (or all waiting offers, to split them here),
      p_offset: split ? 0 : (page - 1) * PAGE_SIZE, // starting at this page (or the start).
    }), // (end of the queue settings)
    supabase.rpc("matching_offer_waits"), // and who each waiting offer waits for.
  ]); // End of the reads.
  const waits = (waitsRes.data ?? []) as Wait[]; // The waiting offers.
  const waitKey = (studentId: string, subj: string) => `${studentId}|${subj.toLowerCase()}`; // A key for one student and subject.
  const waitingOn = new Map(waits.map((w) => [waitKey(w.student_id, w.subject), w.waiting_on])); // Who each offer waits for, by student and subject.
  const tabOf = (r: { student_id: string; subject: string }) => (waitingOn.get(waitKey(r.student_id, r.subject)) === "family" ? "waiting_family" : "waiting_tutor"); // Which waiting tab a row belongs in.
  const dbCounts = (countsRes.data ?? []) as StageCount[]; // The stage counts from the database.
  const counts: StageCount[] = [ // The counts for each tab:
    ...dbCounts.filter((c) => c.stage !== "tutor_to_confirm"), // the stages as they are,
    { stage: "waiting_tutor", subjects: waits.filter((w) => w.waiting_on !== "family").length, oldest_days: null }, // offers waiting for the tutor,
    { stage: "waiting_family", subjects: waits.filter((w) => w.waiting_on === "family").length, oldest_days: null }, // offers waiting for the family.
  ]; // End of the counts.
  const allRows = (queueRes.data ?? []) as QueueRow[]; // The queue rows from the database.
  const rows = split // The rows to show:
    ? allRows.filter((r) => tabOf(r) === stage).slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE) // this waiting tab's rows, one page,
    : allRows; // or as they came.
  const total = split ? allRows.filter((r) => tabOf(r) === stage).length : (allRows[0]?.total ?? 0); // How many in the whole list.
  // Details still missing for the students on this page (for the warning dot).
  const missingRes = rows.length // If there are rows, reads:
    ? await supabase.rpc("matching_missing", { p_students: [...new Set(rows.map((r) => r.student_id))] }) // what is missing for each student,
    : null; // otherwise nothing.
  const missingFor = new Set(((missingRes?.data ?? []) as Missing[]).map((m) => m.student_id)); // The students with something missing.
  const pages = Math.max(Math.ceil(total / PAGE_SIZE), 1); // How many pages.

  const filters = { // The current filters:
    stage, // the stage,
    ...(search ? { q: search } : {}), // the search (if any),
    ...(year ? { year } : {}), // the year level (if any),
    ...(state ? { state } : {}), // the state (if any).
  }; // End of the filters.
  const link = (over: Record<string, string>) => `/matching?${new URLSearchParams({ ...filters, ...over }).toString()}`; // Makes a link keeping the filters, with some settings changed.
  const currentIndex = rows.findIndex((r) => r.student_id === studentId && r.subject === subject); // Where the chosen student is in the list.
  const next = currentIndex >= 0 ? rows[currentIndex + 1] : undefined; // The next student (if any).

  return ( // Shows:
    <>{/* (a group) */}
      {/* The same admin menu as the rest of the admin area, so admins can move between tabs without leaving Matching: */}
      <DashboardFrame role="admin" roles={viewer.roles} current="matching">{/* (admin dashboard, on Matching) */}
        <div className="flex flex-wrap items-end justify-between gap-3">{/* the top row: */}
          <div>{/* (a group) */}
            <p className="text-sm text-zinc-600">{/* a grey line: */}
              Students waiting for a tutor, and the tutors who suit them best. Matching is on fit only.{/* what this page is for. */}
            </p>{/* End of the line. */}
          </div>{/* End of the group. */}
          <nav className="flex gap-2 text-sm" aria-label="Matching views">{/* the view switch: */}
            <Link // the queue link:
              href="/matching" // to the queue,
              className={`rounded-full border px-3 py-1 ${view === "queue" ? "border-teal-700 bg-teal-50" : "border-zinc-300 bg-white"}`} // highlighted when open.
            >{/* (end of the link's settings) */}
              Students waiting{/* its words, */}
            </Link>{/* end of the link. */}
            <Link // the reports link:
              href="/matching?view=reports" // to the reports,
              className={`rounded-full border px-3 py-1 ${view === "reports" ? "border-teal-700 bg-teal-50" : "border-zinc-300 bg-white"}`} // highlighted when open.
            >{/* (end of the link's settings) */}
              Reports{/* its words, */}
            </Link>{/* end of the link. */}
          </nav>{/* End of the view switch. */}
        </div>{/* End of the top row. */}

        <UrgentRematchBox />{/* Students who urgently need a new tutor, first (shows nothing when there are none). */}

        {view === "reports" ? ( // If the reports view is open:
          <div className="space-y-4">{/* the reports, one under another: */}
            <ResponseTimesCard />{/* how long tutors and families take to answer, */}
            <GapsView />{/* the gaps, */}
            {isFull && <ReasonsCard />}{/* and why suggestions were changed (full admins). */}
          </div> // End of the reports.
        ) : ( // otherwise:
          <>{/* (a group) */}
            <nav aria-label="Matching stages" className="flex flex-wrap gap-2 border-b border-zinc-200 pb-3 text-sm">{/* the stage tabs: */}
              {STAGES.map((s) => { // for each tab:
                const c = counts.find((x) => x.stage === s.id); // its count,
                const active = s.id === stage; // whether it is open,
                return ( // shows:
                  <Link // a tab:
                    key={s.id} // (its key in the list)
                    href={link({ stage: s.id, page: "1" })} // to that tab, page 1,
                    aria-current={active ? "page" : undefined} // marked as current when open,
                    title={s.hint} // what it means, on hover,
                    className={`rounded-full border px-3 py-1 ${active ? "border-teal-700 bg-teal-700 text-white" : "border-zinc-300 bg-white hover:border-teal-700"}`} // filled when open, outlined otherwise.
                  >{/* (end of the tab's settings) */}
                    {s.label} ({c?.subjects ?? 0}){/* its name and count. */}
                  </Link> // End of the tab.
                ); // End of what is shown for this tab.
              })}{/* End of the tabs. */}
            </nav>{/* End of the stage tabs. */}

            <div className="grid gap-6 lg:grid-cols-[20rem_1fr]">{/* two columns on wide screens (a narrower list, more room for the student): */}
              <div className={`space-y-4 ${studentId ? "order-2 lg:order-1" : ""}`}>{/* the list column (below the student on small screens if one is chosen): */}
                <Card title={`${current.label} (${total})`} description={current.hint}>{/* a card with the stage's name, count and hint: */}
                  <form method="get" action="/matching" className="mb-4 space-y-2">{/* the filter form: */}
                    <input type="hidden" name="stage" value={stage} />{/* the stage (hidden), */}
                    <Field label="Search by student or subject" name="q" defaultValue={search} maxLength={100} />{/* the search box, */}
                    <div className="grid grid-cols-2 gap-2">{/* two columns: */}
                      <Select label="Year level" name="year" defaultValue={year}>{/* the year level drop-down: */}
                        <option value="">Any</option>{/* any, */}
                        {YEAR_LEVELS.map((y) => ( // for each year level:
                          <option key={y} value={y}>{/* an option: */}
                            {y}{/* its name, */}
                          </option> // end of the option.
                        ))}{/* End of the loop. */}
                      </Select>{/* End of the drop-down. */}
                      <Select label="State" name="state" defaultValue={state}>{/* the state drop-down: */}
                        <option value="">Any</option>{/* any, */}
                        {STATES.map((s) => ( // for each state:
                          <option key={s} value={s}>{/* an option: */}
                            {s}{/* its name, */}
                          </option> // end of the option.
                        ))}{/* End of the loop. */}
                      </Select>{/* End of the drop-down. */}
                    </div>{/* End of the columns. */}
                    <button type="submit" className="rounded-full border border-zinc-300 bg-white px-4 py-1.5 text-sm">{/* the filter button: */}
                      Filter{/* its words, */}
                    </button>{/* end of the button. */}
                  </form>{/* End of the form. */}
                  {rows.length === 0 ? ( // if nobody at this stage:
                    <Empty>Nobody at this stage.</Empty> // says so.
                  ) : ( // otherwise:
                    <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                      {rows.map((r) => { // for each student-subject:
                        const active = r.student_id === studentId && r.subject === subject; // whether it is the chosen one,
                        return ( // shows:
                          <li key={`${r.student_id}-${r.subject}`}>{/* a row: */}
                            <Link // a link:
                              href={link({ page: String(page), student: r.student_id, subject: r.subject })} // to choose them,
                              aria-current={active ? "true" : undefined} // marked if chosen,
                              className={`block rounded-md px-2 py-2 ${active ? "bg-teal-50" : "hover:bg-zinc-50"}`} // highlighted if chosen.
                            >{/* (end of the link's settings) */}
                              <span className="flex items-baseline justify-between gap-2">{/* the top line: */}
                                <span className="font-medium">{/* in bold: */}
                                  {missingFor.has(r.student_id) && ( // if a detail is missing,
                                    <span className="mr-1.5 inline-block h-2 w-2 rounded-full bg-amber-500" title="Details missing before an offer" aria-label="Details missing" /> // an amber dot,
                                  )}{/* (end of the dot) */}
                                  {r.student_name}{/* their name. */}
                                </span>{/* End of the bold part. */}
                                <span className={`text-xs ${r.days >= 7 && stage !== "active" ? "text-amber-900" : "text-zinc-600"}`}>{/* days waiting (amber after a week): */}
                                  {r.days === 0 ? "today" : `${r.days} day${r.days === 1 ? "" : "s"}`}{/* today, or the number of days. */}
                                </span>{/* End of the days. */}
                              </span>{/* End of the top line. */}
                              <span className="block text-zinc-600">{/* a grey line: */}
                                {r.subject} · {r.year_level ?? "year not set"}{/* the subject and year level, */}
                                {r.working_level ? ` · working at ${r.working_level}` : ""} · {r.state}{/* working level (if any) and state, */}
                                {r.tutor_name ? ` · ${r.tutor_name}` : ""}{/* and the tutor (if any). */}
                              </span>{/* End of the line. */}
                            </Link>{/* End of the link. */}
                          </li> // End of the row.
                        ); // End of what is shown for this one.
                      })}{/* End of the loop. */}
                    </ul> // End of the list.
                  )}{/* End of this part. */}
                  {pages > 1 && ( // If more than one page:
                    <p className="mt-4 flex items-center gap-4 text-sm">{/* a line: */}
                      {page > 1 && ( // if not on page 1:
                        <Link className="underline" href={link({ page: String(page - 1) })}>{/* a link to the previous page: */}
                          Previous{/* its words, */}
                        </Link> // end of the link.
                      )}{/* End of this part. */}
                      <span className="text-zinc-600">{/* in grey: */}
                        Page {page} of {pages}{/* the page number. */}
                      </span>{/* End of the grey part. */}
                      {page < pages && ( // if not on the last page:
                        <Link className="underline" href={link({ page: String(page + 1) })}>{/* a link to the next page: */}
                          Next{/* its words, */}
                        </Link> // end of the link.
                      )}{/* End of this part. */}
                    </p> // End of the line.
                  )}{/* End of this part. */}
                </Card>{/* End of the card. */}
              </div>{/* End of the list column. */}

              <div className={studentId ? "order-1 lg:order-2" : ""}>{/* the student column (on top on small screens if one is chosen): */}
                {studentId && subject ? ( // if a student is chosen:
                  <>{/* (a group:) */}
                  <p className="mb-4 lg:hidden"><BackButton href={link({ page: String(page) })}>Back to the list</BackButton></p>{/* on phones (where the list is below), a button back up to the list, */}
                  <StudentPanel // their panel:
                    studentId={studentId} // the student,
                    subject={subject} // the subject,
                    stage={stage} // the tab they are in,
                    nextHref={next ? link({ page: String(page), student: next.student_id, subject: next.subject }) : null} // and a link to the next student (if any).
                  />{/* (end of the panel) */}
                  </> // End of the group.
                ) : ( // otherwise:
                  <Card title="Choose a student">{/* a card: */}
                    <Empty>Pick a student from the list to see the tutors who suit them.</Empty>{/* says to pick a student. */}
                  </Card> // End of the card.
                )}{/* End of this part. */}
              </div>{/* End of the student column. */}
            </div>{/* End of the columns. */}
          </> // End of the group.
        )}{/* End of this part. */}
      </DashboardFrame>{/* End of the dashboard frame. */}
    </> // End of the group.
  ); // End of what is shown.
} // End of MatchingPage.

// ---------------------------------------------------------------------------
// One student: everything about them, and the tutor shortlist
// ---------------------------------------------------------------------------
async function StudentPanel({ studentId, subject, stage, nextHref }: { studentId: string; subject: string; stage: string; nextHref: string | null }) { // The panel for one student and subject (the tab they are in, and a link to the next student).
  const supabase = await createClient(); // Connects to the database.
  const [studentRes, subjectsRes, placesRes, librariesRes, shortlistRes, notOfferedRes, termsRes, holdsRes, missingRes, sinceRes] = await Promise.all([ // Reads everything at once:
    supabase // the student:
      .from("students") // from students,
      .select("id, full_name, family_id, year_level, school, state, goals, learning_needs, program") // these details,
      .eq("id", studentId) // this one,
      .maybeSingle(), // if any.
    supabase // their subjects:
      .from("student_subjects") // from student_subjects,
      .select("id, subject, working_level, course_code, course_url, course_overview") // these details,
      .eq("student_id", studentId) // for this student,
      .order("added_at"), // oldest first.
    supabase // their session places:
      .from("student_places") // from student_places,
      .select("online, library_ids, travel_km, preferred_days, preferred_parts, preferred_school_hours, tutor_preferences, book_until, include_school_holidays, include_public_holidays") // places, preferred times and how long to book,
      .eq("student_id", studentId) // for this student,
      .maybeSingle(), // if any.
    supabase.from("libraries").select("id, name, active, confirmed_at").order("name"), // the libraries, by name,
    supabase.rpc("matching_shortlist", { p_student: studentId, p_subject: subject }), // the tutor shortlist,
    supabase.rpc("matching_not_offered", { p_student: studentId, p_subject: subject }), // tutors who do not fit, and why,
    supabase.rpc("student_term_dates", { p_student: studentId }), // their term dates,
    supabase.rpc("training_matching_holds"), // tutors whose new matches wait for overdue safety training,
    supabase.rpc("matching_missing", { p_students: [studentId] }), // details still missing before an offer,
    supabase // and any "waiting since" date set by hand:
      .from("matching_waiting_since") // from matching_waiting_since,
      .select("subject, since") // the subject and date,
      .eq("student_id", studentId), // for this student.
  ]); // End of the reads.
  const missing = new Map(((missingRes.data ?? []) as Missing[]).map((m) => [m.item, m.last_asked])); // Each missing detail and when the family was last asked.
  const sinceRow = ((sinceRes.data ?? []) as { subject: string; since: string }[]).find((r) => r.subject.toLowerCase() === subject.toLowerCase()); // The date set for this subject (if any).
  const sinceDate = sinceRow ? new Date(sinceRow.since).toLocaleDateString("en-CA", { timeZone: "Australia/Adelaide" }) : ""; // That date as YYYY-MM-DD in Adelaide (or empty).
  const waitingTab = stage === "needs_tutor" || stage === "waitlist"; // Whether the student is still waiting for a tutor.
  const student = studentRes.data as { // The student:
    id: string; // their id,
    full_name: string; // name,
    family_id: string | null; // family (if any),
    year_level: string | null; // year level (if known),
    school: string | null; // school (if known),
    state: string; // state,
    goals: string | null; // goals (if any),
    learning_needs: string | null; // learning needs (if any),
    program: string | null; // and course or degree (if any).
  } | null; // (end of the type)
  if (!student) { // Not found:
    return ( // shows:
      <Card title="Student not found">{/* a card: */}
        <Empty>This student may have been removed.</Empty>{/* says they may have been removed. */}
      </Card> // End of the card.
    ); // End of what is shown.
  } // End of this part.
  const subjects = (subjectsRes.data ?? []) as (CourseUnit & { working_level: string | null })[]; // Their subjects.
  const places = placesRes.data as { // Their session places:
    online: boolean; // online or not,
    library_ids: string[]; // libraries,
    travel_km: number | null; // how far a tutor may travel to them (if set),
    preferred_days: number[] | null; // preferred days (if any),
    preferred_parts: string[] | null; // preferred parts of the day (if any),
    preferred_school_hours: boolean; // whether school hours suit,
    tutor_preferences: string | null; // tutor preferences (if any),
    book_until: string | null; // book until (if set),
    include_school_holidays: boolean | null; // include school holidays (if said),
    include_public_holidays: boolean | null; // include public holidays (if said).
  } | null; // (end of the type)
  const terms = (termsRes.data ?? []) as StudentTerm[]; // Their term dates.
  const libraryName = new Map((librariesRes.data ?? []).map((l) => [l.id as string, l.name as string])); // Each library's name, by id.
  // Tutors with overdue compulsory safety training can't take new students
  // (the database refuses the match), so they move off the shortlist into
  // "Tutors who do not fit", with the reason (Carla, 16 Nov 2026).
  const held = new Map(((holdsRes.data ?? []) as { tutor_id: string; modules: string }[]).map((h) => [h.tutor_id, h.modules])); // Each held tutor and their overdue modules.
  const fullShortlist = (shortlistRes.data ?? []) as Shortlist[]; // The tutor shortlist from the database.
  const shortlist = fullShortlist.filter((t) => !held.has(t.tutor_id)); // The shortlist without held tutors.
  const notOffered = [ // Tutors who do not fit:
    ...fullShortlist.filter((t) => held.has(t.tutor_id)).map((t) => ({ tutor_id: t.tutor_id, tutor_name: t.tutor_name, reason: `Compulsory safety training overdue (${held.get(t.tutor_id)}), so no new students until it is done` })), // held tutors, with the reason,
    ...((notOfferedRes.data ?? []) as { tutor_id: string; tutor_name: string; reason: string }[]), // then the rest, from the database.
  ]; // End of the list.
  const thisSubject = subjects.find((s) => s.subject.toLowerCase() === subject.toLowerCase()); // This subject's details.

  // Siblings, past tutors, and every suitable time for each tutor.
  const [siblingsRes, pastRes, optionsRes] = await Promise.all([ // Reads three more things at once:
    student.family_id // if they have a family,
      ? supabase.from("students").select("id, full_name").eq("family_id", student.family_id).neq("id", student.id) // their siblings,
      : Promise.resolve({ data: [] as { id: string; full_name: string }[] }), // otherwise none.
    supabase // their past tutors:
      .from("tutor_assignments") // from tutor_assignments,
      .select("subject, ends_on, accounts:tutor_id (full_name)") // subject, end date and tutor's name,
      .eq("student_id", student.id) // for this student,
      .lt("ends_on", localToday()), // ended before today.
    supabase.rpc("offer_options", { // every suitable time:
      p_student: student.id, // for this student,
      p_subject: subject, // this subject,
      p_minutes: 60, // one hour,
      p_online: places?.online ?? true, // online if their places allow (or not set),
      p_libraries: places?.library_ids ?? [], // and their libraries.
    }), // (end of the settings)
  ]); // End of the reads.
  const choicesFor = new Map<string, OfferChoice[]>(); // Each tutor's suitable times.
  for (const o of (optionsRes.data ?? []) as (OfferChoice & { tutor_id: string })[]) { // For each suitable time:
    const list = choicesFor.get(o.tutor_id) ?? []; // that tutor's list so far,
    list.push(o); // adds this time,
    choicesFor.set(o.tutor_id, list); // and saves the list.
  } // End of the loop.
  const confirmedLibraries = ((librariesRes.data ?? []) as { id: string; name: string; active: boolean; confirmed_at: string | null }[]) // The confirmed libraries in use:
    .filter((l) => l.active && l.confirmed_at) // in use and confirmed,
    .map((l) => ({ id: l.id, name: l.name })); // each as an id and name.
  const siblings = (siblingsRes.data ?? []) as { id: string; full_name: string }[]; // Their siblings.
  const past = (pastRes.data ?? []) as unknown as { subject: string; ends_on: string; accounts: { full_name: string } | null }[]; // Their past tutors.

  const today = localToday(); // Today's date.
  const first = addDays(today, 7); // The first session date to suggest (a week from today).
  const top = shortlist.find((t) => t.times > 0 && !t.at_max); // The recommended tutor: the first with a time that suits and spare hours.
  const optionFor = (t: Shortlist) => ({ // Makes the suggested offer for a tutor:
    student_id: student.id, // the student,
    subject, // the subject,
    tutor_id: t.tutor_id, // the tutor,
    weekday: t.best_weekday ?? 1, // their best day (Monday if none),
    start_time: t.best_start ?? "", // their best start time,
    minutes: 60, // one hour,
    delivery: t.best_delivery ?? "online", // where (online if none),
    library_id: t.best_library, // and the library.
  }); // End of optionFor.
  const preferred = [ // Their preferred times, in words:
    places?.preferred_days?.length ? places.preferred_days.map((d) => WEEKDAY_NAMES[d - 1].slice(0, 3)).join(", ") : "", // the days,
    places?.preferred_parts?.length ? places.preferred_parts.map((p) => PARTS[p] ?? p).join(", ") : "", // the parts of the day,
    places?.preferred_school_hours ? "school hours" : "", // school hours,
  ].filter(Boolean); // leaving out any not given.

  const others = shortlist.filter((t) => t !== top); // The other tutors who suit.
  // One tutor's box: who they are, why they suit, and the offer form.
  const renderTutor = (t: Shortlist) => ( // Shows, for one tutor:
              <li key={t.tutor_id} className={`rounded-lg border p-3 text-sm ${t === top ? "border-teal-700 bg-teal-50" : "border-zinc-200"}`}>{/* a box (highlighted for the recommended tutor): */}
                <p className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                  <span className="font-medium">{/* in bold: */}
                    {t.rank}. {t.tutor_name}{/* their place and name, */}
                    {t === top && ( // if they are the recommended tutor:
                      <span className="ml-2 text-xs font-semibold uppercase tracking-wide text-teal-800">Recommended</span> // "Recommended".
                    )}{/* End of this part. */}
                  </span>{/* End of the bold part. */}
                  <span className="text-xs text-zinc-600">{/* in grey: */}
                    {hours(t.booked_minutes)} booked{/* hours booked, */}
                    {t.max_weekly_hours != null ? ` of ${t.max_weekly_hours} hr` : ""}{/* of their most hours (if set). */}
                  </span>{/* End of the grey part. */}
                </p>{/* End of the top line. */}
                <ul className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-zinc-700">{/* the reasons they suit: */}
                  {t.teaches_sibling && <li>✓ Teaches {t.sibling_names} (sibling)</li>}{/* teaches a sibling (if so), */}
                  <li>{/* (a reason) */}
                    ✓ Teaches {subject} at {thisSubject?.working_level ?? student.year_level}{/* teaches this subject at this level. */}
                  </li>{/* End of the reason. */}
                  <li>✓ Checks current for {student.state}</li>{/* checks current for the state. */}
                  {t.times > 0 && ( // If times suit:
                    <li>{/* (a reason) */}
                      ✓ {t.times} time{t.times === 1 ? "" : "s"} that suit{/* how many times suit, */}
                      {t.preferred_times > 0 ? ` (${t.preferred_times} preferred)` : ""}{/* and how many are preferred. */}
                    </li> // End of the reason.
                  )}{/* End of this part. */}
                  {t.in_person_times > 0 && <li>✓ In person available</li>}{/* in person (if so), */}
                  {t.learning_support && <li>✓ Learning support experience</li>}{/* learning support experience (if so). */}
                </ul>{/* End of the reasons. */}
                {t.at_max && ( // If at their limit:
                  <p className="mt-1 text-amber-900">{/* an amber line: */}
                    At their weekly maximum{t.max_weekly_hours != null ? ` (${t.max_weekly_hours} hr)` : ""}. They cannot be{/* their limit, */}
                    booked past it. If they are the only option, ask them first.{/* (end of the text) */}
                  </p> // End of the line.
                )}{/* End of this part. */}
                {!t.at_max && t.times === 0 && ( // Not at their limit but no time suits:
                  <p className="mt-1 text-amber-900">No available times match this student&apos;s places right now.</p> // says so.
                )}{/* End of this part. */}
                {t.check_kind && t.check_expires && ( // If a check expires soon:
                  <p className="mt-1 text-amber-900">{/* an amber line: */}
                    {CHECK_NAMES[t.check_kind as CheckKind] ?? t.check_kind} expires {shortDate(t.check_expires)}.{/* which check and when. */}
                  </p> // End of the line.
                )}{/* End of this part. */}
                {t.times > 0 && t.best_weekday && t.best_start && t.best_end && ( // If there is a best time:
                  <p className="mt-2">{/* a line: */}
                    Best time: {WEEKDAY_NAMES[t.best_weekday - 1]} {clockTime(t.best_start)} to {clockTime(t.best_end)} ·{" "}{/* the day, times, and, */}
                    {placeLabel(t.best_delivery ?? "online", t.best_library_name)}{/* where. */}
                  </p> // End of the line.
                )}{/* End of this part. */}
                {!t.at_max && ( // If not at their limit:
                  <OfferForm // the offer form:
                    student_id={student.id} // the student,
                    subject={subject} // the subject,
                    tutor_id={t.tutor_id} // the tutor,
                    choices={choicesFor.get(t.tutor_id) ?? []} // their suitable times,
                    libraries={confirmedLibraries} // the confirmed libraries,
                    suggested={top ? optionFor(top) : null} // the suggested offer,
                    defaultFirst={first} // the first date to suggest,
                    defaultLast={places?.book_until ?? ""} // the last date (book until),
                    terms={terms} // their term dates,
                    bookUntil={places?.book_until ?? null} // how long to book,
                    startOpen={t === top} // open to start for the recommended tutor (others open with "Offer").
                  /> // End of the form.
                )}{/* End of this part. */}
              </li> // End of the box.
  ); // End of renderTutor.
  const missingCount = READY_ITEMS.filter((r) => missing.has(r.item)).length; // How many details are missing.

  return ( // Shows:
    <div className="space-y-4">{/* a list of cards: */}
      {/* Ready check: the details a tutor needs, so they are not chasing them later (Carla, 16 Nov 2026). */}
      <Card // the ready check card:
        title={missingCount === 0 ? "Ready to offer" : `${missingCount} detail${missingCount === 1 ? "" : "s"} missing before an offer`} // ready, or how many are missing,
        description={missingCount === 0 ? undefined : "Fill it in yourself, or ask the family. Asking sends them an app notice and an email, with a link to fill it in and to the help chat for questions."} // what to do when something is missing.
      >{/* (end of the card's settings) */}
        <ul className="space-y-2 text-sm">{/* a list: */}
          {READY_ITEMS.map((r) => { // for each detail:
            const isMissing = missing.has(r.item); // whether it is missing,
            const asked = missing.get(r.item); // and when the family was last asked (if ever).
            return ( // shows:
              <li key={r.item} className="flex flex-wrap items-center gap-x-3 gap-y-1">{/* a row: */}
                <span className={isMissing ? "text-amber-800" : "text-teal-800"} aria-hidden>{isMissing ? "✗" : "✓"}</span>{/* a cross or tick, */}
                <span className={isMissing ? "font-medium" : "text-zinc-700"}>{r.label}</span>{/* the detail's name, */}
                {isMissing && ( // if missing:
                  <>{/* (a group) */}
                    <TextLink href={r.adminHref(student.id)}>Fill in</TextLink>{/* a link to fill it in, */}
                    <AskFamilyButton studentId={student.id} item={r.item} />{/* the "Ask the family" button, */}
                    {asked && ( // if asked before,
                      <span className="text-xs text-zinc-500">Asked {daysAgo(asked)}</span> // when.
                    )}{/* (end of the asked note) */}
                  </> // End of the group.
                )}{/* End of this part. */}
              </li> // End of the row.
            ); // End of what is shown for this detail.
          })}{/* End of the list. */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card // the student card:
        title={`${student.full_name} · ${subject}`} // the name and subject,
        description={ // links under the title:
          <span className="flex flex-wrap gap-3">{/* (a row) */}
            <TextLink href={`/schedule?as=admin&section=child-places&student=${student.id}`}>Session places</TextLink>{/* to their session places, */}
            <TextLink href={`/schedule?${new URLSearchParams({ as: "admin", section: "book", student: student.id, subject, auto: "1" }).toString()}`}>{/* to all available times: */}
              All available times{/* its words, */}
            </TextLink>{/* end of the link. */}
            {nextHref && <TextLink href={nextHref}>Next student →</TextLink>}{/* to the next student (if any). */}
          </span> // End of the row.
        } // (end of the links)
      >{/* (end of the card's settings) */}
        {/* One summary line, so the key facts are seen at a glance. */}
        <p className="text-sm text-zinc-700">{/* a grey line: */}
          {[ // the facts:
            student.year_level ?? "Year not set", // year level,
            student.school || "School not set", // school,
            student.state, // state,
            `working at ${thisSubject?.working_level ?? "level not sure"}`, // working level,
            places ? [places.online ? "online" : null, ...places.library_ids.map((id) => libraryName.get(id) ?? "a library"), places.travel_km ? `travels up to ${places.travel_km} km` : null].filter(Boolean).join(", ") || "no places set" : "no places set", // places,
            preferred.length ? `prefers ${preferred.join(", ")}` : null, // preferred times,
          ].filter(Boolean).join(" · ")}{/* joined with dots. */}
        </p>{/* End of the line. */}
        <details className="mt-3 rounded-lg border border-zinc-200 px-3 py-2">{/* a fold-out box: */}
          <summary className="cursor-pointer text-sm font-medium">More details</summary>{/* its title, */}
        <dl className="mt-2 grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">{/* a details list in two columns: */}
          <Detail label="School year">{/* school year: */}
            {student.year_level ?? "Not set"}{/* the year level, */}
            {student.school ? ` at ${student.school}` : ""} · {student.state}{/* school and state. */}
          </Detail>{/* End of this detail. */}
          <Detail label="Working level">{thisSubject?.working_level ?? "Not sure"}</Detail>{/* working level. */}
          <Detail label="Other subjects">{/* other subjects: */}
            {subjects // their other subjects:
              .filter((s) => s !== thisSubject) // leaving out this one,
              .map((s) => `${s.subject}${s.working_level ? ` (${s.working_level})` : ""}`) // each with its level,
              .join(", ") || "None"}{/* joined with commas (or none). */}
          </Detail>{/* End of this detail. */}
          <Detail label="Goal">{student.goals || "None given"}</Detail>{/* goal. */}
          <Detail label="Learning needs">{student.learning_needs || "None given"}</Detail>{/* learning needs. */}
          <Detail label="Tutor preferences">{places?.tutor_preferences || "None given"}</Detail>{/* tutor preferences. */}
          <Detail label="How long to book">{/* how long to book: */}
            {places?.book_until ? ( // if set:
              <>{/* (a group) */}
                Until {shortDate(places.book_until)}{/* until when, */}
                {places.include_school_holidays !== null && // if said,
                  `, ${places.include_school_holidays ? "including" : "not in"} school holidays`}{/* whether school holidays are included, */}
                {places.include_public_holidays !== null && // if said,
                  `, ${places.include_public_holidays ? "including" : "not on"} public holidays`}{/* whether public holidays are included. */}
              </> // End of the group.
            ) : ( // otherwise:
              <span className="text-amber-800">Family has not said yet</span> // not said yet, in amber.
            )}{" "}{/* End of this part, then a space. */}
            <TextLink href={`/schedule?as=admin&section=booking-length&student=${student.id}`}>Change</TextLink>{/* a link to change it. */}
          </Detail>{/* End of this detail. */}
          <Detail label="Places">{/* places: */}
            {places // if set,
              ? [places.online ? "Online" : null, ...places.library_ids.map((id) => libraryName.get(id) ?? "a library")] // online and their libraries,
                  .filter(Boolean) // leaving out blanks,
                  .join(", ") // joined with commas,
              : "Not set yet (online assumed)"}{/* otherwise not set yet. */}
          </Detail>{/* End of this detail. */}
          <Detail label="Preferred times">{preferred.length ? preferred.join(" · ") : "None given"}</Detail>{/* preferred times. */}
          <Detail label="Siblings">{siblings.map((s) => s.full_name).join(", ") || "None"}</Detail>{/* siblings. */}
          <Detail label="Past tutors">{/* past tutors: */}
            {past.map((p) => `${p.accounts?.full_name ?? "A tutor"} (${p.subject}, to ${shortDate(p.ends_on)})`).join(", ") || "None"}{/* each with subject and end date (or none). */}
          </Detail>{/* End of this detail. */}
        </dl>{/* End of the details list. */}
        </details>{/* End of the fold-out box. */}
        {waitingTab && ( // If still waiting for a tutor:
          <details className="mt-3 rounded-lg border border-zinc-200 px-3 py-2">{/* a fold-out box: */}
            <summary className="cursor-pointer text-sm font-medium">{/* its title: */}
              Waiting since{sinceDate ? `: ${shortDate(sinceDate)} (set by hand)` : ""}{/* "Waiting since" and any date set by hand. */}
            </summary>{/* End of the title. */}
            <p className="mt-2 text-xs text-zinc-600">{/* a grey hint: */}
              If this student was on CLG&apos;s waitlist before they were added to the app, set the day they first asked. The list puts the longest waiting at the top.{/* (the hint's words) */}
            </p>{/* End of the hint. */}
            <WaitingSinceForm studentId={student.id} subject={subject} current={sinceDate} />{/* the date form. */}
          </details> // End of the fold-out box.
        )}{/* End of this part. */}
        {/* University and TAFE students: degree, unit codes, course pages and CLG's overview. */}
        <div className="mt-3 text-sm">{/* a box: */}
          <CourseDetails // the unit details:
            program={student.program} // their course or degree,
            units={subjects} // their units,
            overviewForm={(u) => <CourseOverviewForm subjectId={u.id} overview={u.course_overview} />} // with the overview form for each.
          />{/* End of the unit details. */}
        </div>{/* End of the box. */}
      </Card>{/* End of the card. */}

      {/* The recommended offer: one tutor, ready to send (Carla, 16 Nov 2026). */}
      <Card // the recommended offer card:
        title="Recommended offer" // its title,
        description="Best fit: teaches the subject at the level the student is working at, then a tutor who already teaches a sibling, then spare hours, then a place that suits, then a time that suits. Pay rates are not shown." // how tutors are ranked.
      >{/* (end of the card's settings) */}
        {shortlistRes.error ? ( // if the shortlist could not be read:
          <Empty>{shortlistRes.error.message}</Empty> // the reason.
        ) : shortlist.length === 0 ? ( // if no tutors:
          <Empty>No tutor teaches {subject} at this level for {student.state} yet. See Reports, then Gaps.</Empty> // says so.
        ) : top ? ( // if there is a recommended tutor:
          <ol>{renderTutor(top)}</ol> // their box, with the offer open.
        ) : ( // otherwise:
          <Empty>No tutor who suits has a matching time with spare hours right now. Check the other tutors below, or the student&apos;s places.</Empty> // says so.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      {others.length > 0 && ( // If other tutors suit:
        <Card collapsible defaultOpen={!top} title={`Other tutors who suit (${others.length})`}>{/* a fold-up card with the count (open if there is no recommendation): */}
          <ol className="space-y-3">{others.map(renderTutor)}</ol>{/* each tutor's box. */}
        </Card> // End of the card.
      )}{/* End of this part. */}

      {notOffered.length > 0 && ( // If some tutors do not fit:
        <Card collapsible defaultOpen={false} title={`Tutors who do not fit (${notOffered.length})`}>{/* a fold-up card with the count: */}
          <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
            {notOffered.map((t) => ( // for each:
              <li key={t.tutor_id} className="py-2">{/* a row: */}
                <span className="font-medium">{t.tutor_name}</span>{/* their name, */}
                <span className="text-zinc-600"> · {t.reason}</span>{/* and why. */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of this part. */}
    </div> // End of the list of cards.
  ); // End of what is shown.
} // End of StudentPanel.

// How long ago a time was, in plain words ("today", "1 day ago", "5 days ago").
function daysAgo(iso: string): string { // Takes a time.
  const days = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000); // Whole days since then.
  return days <= 0 ? "today" : `${days} day${days === 1 ? "" : "s"} ago`; // Today, or how many days.
} // End of daysAgo.

function Detail({ label, children }: { label: string; children: ReactNode }) { // One detail: a label and its value.
  return ( // Shows:
    <div>{/* (a group) */}
      <dt className="text-xs font-medium text-zinc-500">{label}</dt>{/* the label, */}
      <dd className="whitespace-pre-line">{children}</dd>{/* the value (keeping line breaks). */}
    </div> // End of the group.
  ); // End of what is shown.
} // End of Detail.

// ---------------------------------------------------------------------------
// Gaps: what waiting students need that no tutor offers yet
// ---------------------------------------------------------------------------
async function GapsView() { // The gaps list.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("matching_gaps"); // Reads the gaps.
  const gaps = (data ?? []) as Gap[]; // The gaps.
  return ( // Shows:
    <Card // a card:
      title="Gaps" // its title,
      description="Subjects and levels that students are waiting for, where no tutor with current checks teaches them. This shows who to recruit next." // its help text.
    >{/* (end of the card's settings) */}
      {gaps.length === 0 ? ( // if none:
        <Empty>No gaps: every waiting student has at least one tutor who teaches their subject and level.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {gaps.map((g) => ( // for each gap:
            <li key={`${g.subject}-${g.level}-${g.state}`} className="flex flex-wrap items-baseline justify-between gap-2 py-2">{/* a row: */}
              <span>{/* (a group) */}
                <span className="font-medium">{g.subject}</span>{/* the subject, */}
                <span className="text-zinc-600">{/* in grey: */}
                  {" "}{/* a space, */}
                  · {g.level} · {g.state}{/* the level and state. */}
                </span>{/* End of the grey part. */}
              </span>{/* End of the group. */}
              <span className="text-zinc-600">{/* in grey: */}
                {g.waiting} waiting · longest {g.longest_days} day{g.longest_days === 1 ? "" : "s"}{/* how many waiting and the longest wait. */}
              </span>{/* End of the grey part. */}
            </li> // End of the row.
          ))}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of GapsView.

// ---------------------------------------------------------------------------
// Why suggestions were changed (full admins)
// ---------------------------------------------------------------------------
async function ReasonsCard() { // The "why suggestions were changed" card.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("offer_change_reasons", { p_days: 90 }); // Reads the reasons from the last 90 days.
  const reasons = (data ?? []) as { reason: string; changes: number; recent_notes: string[] | null }[]; // The reasons, with counts and recent notes.
  return ( // Shows:
    <Card // a card:
      collapsible // can fold,
      defaultOpen={false} // folded to start,
      title="Why suggestions were changed" // its title,
      description="Last 90 days. If the same reason keeps coming up, the suggestions can be improved to allow for it." // its help text.
    >{/* (end of the card's settings) */}
      {reasons.length === 0 ? ( // if none:
        <Empty>No changes recorded yet.</Empty> // says so.
      ) : ( // otherwise:
        <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
          {reasons.map((r) => ( // for each reason:
            <li key={r.reason} className="py-2">{/* a row: */}
              <span className="font-medium">{CHANGE_REASON_NAMES[r.reason] ?? r.reason}</span>{/* its words, */}
              <span className="text-zinc-600"> · {r.changes}</span>{/* how many times, */}
              {r.recent_notes?.length ? <span className="block text-zinc-600">{r.recent_notes.join(" · ")}</span> : null}{/* and recent notes (if any). */}
            </li> // End of the row.
          ))}{/* End of the loop. */}
        </ul> // End of the list.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of ReasonsCard.

// ---------------------------------------------------------------------------
// Response times: how long tutors and families take to answer offers
// ---------------------------------------------------------------------------
async function ResponseTimesCard() { // The response times card.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("matching_response_times", { p_days: 180 }); // Reads the last 180 days.
  const rows = (data ?? []) as { who: string; tutor_id: string | null; tutor_name: string; answered: number; avg_hours: number | null; not_answered: number }[]; // One row per tutor, plus families.
  const families = rows.find((r) => r.who === "family"); // The families row.
  const tutors = rows.filter((r) => r.who === "tutor"); // The tutor rows.
  const hrs = (h: number | null) => (h == null ? "no answers yet" : h < 1 ? "under 1 hr" : `${Math.round(h)} hr`); // An average in plain words.
  return ( // Shows:
    <Card // a card:
      title="Response times" // its title,
      description="Average time from an offer being sent to a yes or no, over the last 180 days. Offers that ran out with no answer are counted separately." // its help text.
    >{/* (end of the card's settings) */}
      {error ? ( // if it could not be read:
        <Empty>{error.message}</Empty> // the reason.
      ) : rows.length === 0 ? ( // if nothing yet:
        <Empty>No offers in the last 180 days.</Empty> // says so.
      ) : ( // otherwise:
        <div className="overflow-x-auto">{/* a box that scrolls sideways only if the table is too wide: */}
          <table className="w-full text-left text-sm">{/* a table: */}
            <thead className="text-xs text-zinc-500">{/* the headings: */}
              <tr>{/* one row: */}
                <th className="py-1 pr-3 font-medium">Who</th>{/* who, */}
                <th className="py-1 pr-3 font-medium">Average time to answer</th>{/* average time, */}
                <th className="py-1 pr-3 font-medium">Answered</th>{/* how many answered, */}
                <th className="py-1 font-medium">Ran out with no answer</th>{/* how many ran out. */}
              </tr>{/* End of the row. */}
            </thead>{/* End of the headings. */}
            <tbody className="divide-y divide-zinc-100">{/* the rows: */}
              {[...(families ? [families] : []), ...tutors].map((r) => ( // families first, then each tutor:
                <tr key={r.tutor_id ?? "family"} className={r.who === "family" ? "font-medium" : ""}>{/* a row (families in bold): */}
                  <td className="py-1.5 pr-3">{r.tutor_name}</td>{/* the name, */}
                  <td className="py-1.5 pr-3">{hrs(r.avg_hours)}</td>{/* the average, */}
                  <td className="py-1.5 pr-3">{r.answered}</td>{/* how many answered, */}
                  <td className={`py-1.5 ${r.not_answered > 0 ? "text-amber-800" : ""}`}>{r.not_answered}</td>{/* how many ran out (amber if any). */}
                </tr> // End of the row.
              ))}{/* End of the rows. */}
            </tbody>{/* End of the rows. */}
          </table>{/* End of the table. */}
        </div> // End of the box.
      )}{/* End of this part. */}
    </Card> // End of the card.
  ); // End of what is shown.
} // End of ResponseTimesCard.

export const metadata = { title: "Matching · CLG Tutoring" }; // The browser tab title.
