// The Matching tab (scheduling module): one place for owner, operations and
// support admins to match students with tutors. The database decides who
// can see what; this page only shows it.

import type { ReactNode } from "react"; // The type for anything React can show.
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { redirect } from "next/navigation"; // Sends the person to another page.
import { Card, Empty, Field, Select, TextLink } from "@/components/ui"; // Shared page parts: card, empty line, field, drop-down and text link.
import { FRONT_DESK, FULL_ADMIN, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth"; // Admin levels, the admin level reader, two-step sign-in check, and the signed-in person.
import { CHECK_NAMES, STATES, type CheckKind } from "@/lib/checks"; // Check names, Australian states, and the check type.
import { WEEKDAY_NAMES, addDays, clockTime, localToday, placeLabel, shortDate } from "@/lib/scheduling"; // Weekday names and date, time and place helpers.
import { YEAR_LEVELS } from "@/lib/students"; // The year levels.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { OfferForm, type OfferChoice, type StudentTerm } from "../schedule/forms"; // The offer form and its types.
import { CourseDetails, type CourseUnit } from "@/components/course-details"; // University and TAFE unit details, and their type.
import { CourseOverviewForm } from "../admin/course-overview-form"; // The admin's course overview form.
import { ADMIN_SECTIONS } from "../admin/sections"; // The admin side menu's sections.
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { SectionShell } from "@/components/section-shell"; // The page frame with a side menu.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.

type StageCount = { stage: string; subjects: number; oldest_days: number | null }; // How many subjects are at each stage, and the longest wait.
type QueueRow = { // One student-subject in the queue:
  student_id: string; // the student,
  student_name: string; // their name,
  year_level: string | null; // their year level (if known),
  working_level: string | null; // the level they're working at (if known),
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
  at_max: boolean; // whether they're at that limit,
  learning_support: boolean; // whether they have learning support experience,
  check_kind: string | null; // a check expiring soon (if any),
  check_expires: string | null; // its expiry date,
  rank: number; // and their place in the list.
}; // End of Shortlist.
type Gap = { subject: string; level: string; state: string; waiting: number; longest_days: number }; // A subject and level students wait for that no tutor teaches.

const STAGES: { id: string; label: string; hint: string }[] = [ // The stages, in order:
  { id: "needs_tutor", label: "Needs a tutor", hint: "Asked for, nothing booked or waiting" }, // needs a tutor,
  { id: "waitlist", label: "Waitlist", hint: "No suitable tutor available yet" }, // waitlist,
  { id: "tutor_to_confirm", label: "Waiting for confirmation", hint: "Offer waiting for the tutor (and family) to approve" }, // waiting for confirmation,
  { id: "assigned", label: "Assigned, no time", hint: "Tutor assigned but no weekly time booked" }, // assigned with no time,
  { id: "active", label: "Active", hint: "Weekly sessions running" }, // active.
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
  const level = viewer.roles.includes("admin") ? await getAdminLevel() : null; // Their admin level, if they're an admin.
  if (!level || !FRONT_DESK.includes(level)) redirect("/dashboard"); // Not a front-desk admin: sends them to their dashboard.
  const isFull = FULL_ADMIN.includes(level); // Whether they're a full admin.

  const params = await searchParams; // The address's settings.
  const view = one(params.view) === "gaps" ? "gaps" : "queue"; // Which view: gaps or the queue.
  const stage = STAGES.find((s) => s.id === one(params.stage))?.id ?? "needs_tutor"; // Which stage (needs a tutor if none or unknown).
  const search = one(params.q).slice(0, 100); // The search words (up to 100 letters).
  const year = (YEAR_LEVELS as readonly string[]).includes(one(params.year)) ? one(params.year) : ""; // The year level filter (only a real year level).
  const state = (STATES as readonly string[]).includes(one(params.state)) ? one(params.state) : ""; // The state filter (only a real state).
  const page = Math.max(Number(one(params.page)) || 1, 1); // The page number (at least 1).
  const studentId = one(params.student); // The student chosen (if any).
  const subject = one(params.subject).slice(0, 100); // The subject chosen (up to 100 letters).

  const supabase = await createClient(); // Connects to the database.
  const [countsRes, queueRes] = await Promise.all([ // Reads two things at once:
    supabase.rpc("matching_stage_counts"), // the stage counts,
    supabase.rpc("matching_queue", { // the queue:
      p_stage: stage, // at this stage,
      p_search: search || null, // matching the search,
      p_year: year || null, // the year level,
      p_state: state || null, // the state,
      p_limit: PAGE_SIZE, // one page at a time,
      p_offset: (page - 1) * PAGE_SIZE, // starting at this page.
    }), // (end of the queue settings)
  ]); // End of the reads.
  const counts = (countsRes.data ?? []) as StageCount[]; // The stage counts.
  const rows = (queueRes.data ?? []) as QueueRow[]; // The queue rows.
  // Numbers on the admin menu, the same as on the other admin pages.
  const todo = await getToDoCounts(viewer.roles); // The to-do numbers.
  const total = rows[0]?.total ?? 0; // How many in the whole list.
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
  const current = STAGES.find((s) => s.id === stage)!; // The current stage.

  // Same admin side menu as the rest of the admin area, so admins can move
  // between sections without leaving Matching. It can be hidden.
  const adminSections = isFull // The admin sections this admin sees:
    ? ADMIN_SECTIONS // all of them for full admins,
    : ADMIN_SECTIONS.filter((s) => s.id === "families" || s.id === "matching"); // otherwise just families and matching.

  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={viewer.roles} active="admin" />{/* the dashboard tabs, with Admin open, */}
      <SectionShell // the page frame:
        basePath="/admin" // under the admin address,
        label="Admin" // labelled "Admin",
        role="admin" // in the admin colours,
        section="matching" // on the matching section,
        sections={adminSections.map((s) => ({ id: s.id, label: s.label, count: todo.get("admin", s.id) }))} // with each section's to-do number on the menu.
      >{/* (end of the frame's settings) */}
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
            <Link // the gaps link:
              href="/matching?view=gaps" // to the gaps,
              className={`rounded-full border px-3 py-1 ${view === "gaps" ? "border-teal-700 bg-teal-50" : "border-zinc-300 bg-white"}`} // highlighted when open.
            >{/* (end of the link's settings) */}
              Gaps{/* its words, */}
            </Link>{/* end of the link. */}
          </nav>{/* End of the view switch. */}
        </div>{/* End of the top row. */}

        {view === "gaps" ? ( // If the gaps view is open:
          <GapsView /> // the gaps list.
        ) : ( // otherwise:
          <>{/* (a group) */}
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-5">{/* the stage boxes: */}
              {STAGES.map((s) => { // for each stage:
                const c = counts.find((x) => x.stage === s.id); // its count,
                const active = s.id === stage; // whether it's open,
                return ( // shows:
                  <li key={s.id}>{/* a box: */}
                    <Link // a link:
                      href={link({ stage: s.id, page: "1" })} // to that stage, page 1,
                      className={`block rounded-lg border px-3 py-2 text-sm ${active ? "border-teal-700 bg-teal-50" : "border-zinc-200 bg-white hover:border-teal-700"}`} // highlighted when open.
                    >{/* (end of the link's settings) */}
                      <span className="block text-2xl font-semibold">{c?.subjects ?? 0}</span>{/* the number of subjects, */}
                      <span className="block">{s.label}</span>{/* the stage's name, */}
                      {c?.oldest_days != null && <span className="block text-xs text-zinc-600">longest {c.oldest_days} days</span>}{/* and the longest wait (if any). */}
                    </Link>{/* End of the link. */}
                  </li> // End of the box.
                ); // End of what's shown for this stage.
              })}{/* End of the loop. */}
            </ul>{/* End of the stage boxes. */}

            <div className="grid gap-6 lg:grid-cols-[22rem_1fr]">{/* two columns on wide screens: */}
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
                        const active = r.student_id === studentId && r.subject === subject; // whether it's the chosen one,
                        return ( // shows:
                          <li key={`${r.student_id}-${r.subject}`}>{/* a row: */}
                            <Link // a link:
                              href={link({ page: String(page), student: r.student_id, subject: r.subject })} // to choose them,
                              aria-current={active ? "true" : undefined} // marked if chosen,
                              className={`block rounded-md px-2 py-2 ${active ? "bg-teal-50" : "hover:bg-zinc-50"}`} // highlighted if chosen.
                            >{/* (end of the link's settings) */}
                              <span className="flex items-baseline justify-between gap-2">{/* the top line: */}
                                <span className="font-medium">{r.student_name}</span>{/* their name, */}
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
                        ); // End of what's shown for this one.
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
                {isFull && <ReasonsCard />}{/* Why suggestions were changed (full admins). */}
              </div>{/* End of the list column. */}

              <div className={studentId ? "order-1 lg:order-2" : ""}>{/* the student column (on top on small screens if one is chosen): */}
                {studentId && subject ? ( // if a student is chosen:
                  <StudentPanel // their panel:
                    studentId={studentId} // the student,
                    subject={subject} // the subject,
                    nextHref={next ? link({ page: String(page), student: next.student_id, subject: next.subject }) : null} // and a link to the next student (if any).
                  /> // (end of the panel)
                ) : ( // otherwise:
                  <Card title="Choose a student">{/* a card: */}
                    <Empty>Pick a student from the list to see the tutors who suit them.</Empty>{/* says to pick a student. */}
                  </Card> // End of the card.
                )}{/* End of this part. */}
              </div>{/* End of the student column. */}
            </div>{/* End of the columns. */}
          </> // End of the group.
        )}{/* End of this part. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of MatchingPage.

// ---------------------------------------------------------------------------
// One student: everything about them, and the tutor shortlist
// ---------------------------------------------------------------------------
async function StudentPanel({ studentId, subject, nextHref }: { studentId: string; subject: string; nextHref: string | null }) { // The panel for one student and subject (with a link to the next student).
  const supabase = await createClient(); // Connects to the database.
  const [studentRes, subjectsRes, placesRes, librariesRes, shortlistRes, notOfferedRes, termsRes] = await Promise.all([ // Reads everything at once:
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
      .select("online, library_ids, preferred_days, preferred_parts, preferred_school_hours, tutor_preferences, book_until, include_school_holidays, include_public_holidays") // places, preferred times and how long to book,
      .eq("student_id", studentId) // for this student,
      .maybeSingle(), // if any.
    supabase.from("libraries").select("id, name, active, confirmed_at").order("name"), // the libraries, by name,
    supabase.rpc("matching_shortlist", { p_student: studentId, p_subject: subject }), // the tutor shortlist,
    supabase.rpc("matching_not_offered", { p_student: studentId, p_subject: subject }), // tutors who don't fit, and why,
    supabase.rpc("student_term_dates", { p_student: studentId }), // and their term dates.
  ]); // End of the reads.
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
    ); // End of what's shown.
  } // End of this part.
  const subjects = (subjectsRes.data ?? []) as (CourseUnit & { working_level: string | null })[]; // Their subjects.
  const places = placesRes.data as { // Their session places:
    online: boolean; // online or not,
    library_ids: string[]; // libraries,
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
  const shortlist = (shortlistRes.data ?? []) as Shortlist[]; // The tutor shortlist.
  const notOffered = (notOfferedRes.data ?? []) as { tutor_id: string; tutor_name: string; reason: string }[]; // Tutors who don't fit.
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
  const top = shortlist.find((t) => t.times > 0); // The top tutor: the first with a time that suits.
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

  return ( // Shows:
    <div className="space-y-4">{/* a list of cards: */}
      <Card // the student card:
        title={`${student.full_name} · ${subject}`} // the name and subject,
        description={ // links under the title:
          <span className="flex flex-wrap gap-3">{/* (a row) */}
            <TextLink href={`/schedule?section=child-places&student=${student.id}`}>Session places</TextLink>{/* to their session places, */}
            <TextLink href={`/schedule?${new URLSearchParams({ section: "book", student: student.id, subject, auto: "1" }).toString()}`}>{/* to all available times: */}
              All available times{/* its words, */}
            </TextLink>{/* end of the link. */}
            {nextHref && <TextLink href={nextHref}>Next student →</TextLink>}{/* to the next student (if any). */}
          </span> // End of the row.
        } // (end of the links)
      >{/* (end of the card's settings) */}
        <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">{/* a details list in two columns: */}
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
              <span className="text-amber-800">Family hasn&apos;t said yet</span> // not said yet, in amber.
            )}{" "}{/* End of this part, then a space. */}
            <TextLink href={`/schedule?section=booking-length&student=${student.id}`}>Change</TextLink>{/* a link to change it. */}
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
        {/* University and TAFE students: degree, unit codes, course pages and CLG's overview. */}
        <div className="mt-3 text-sm">{/* a box: */}
          <CourseDetails // the unit details:
            program={student.program} // their course or degree,
            units={subjects} // their units,
            overviewForm={(u) => <CourseOverviewForm subjectId={u.id} overview={u.course_overview} />} // with the overview form for each.
          />{/* End of the unit details. */}
        </div>{/* End of the box. */}
      </Card>{/* End of the card. */}

      <Card // the shortlist card:
        title="Tutors who suit" // its title,
        description="Best fit tutor: teaches the subject at the level the student is working at, then a tutor who already teaches a sibling, then spare hours, then a place that suits, then a time that suits. Pay rates are not shown." // how tutors are ranked.
      >{/* (end of the card's settings) */}
        {shortlistRes.error ? ( // if the shortlist couldn't be read:
          <Empty>{shortlistRes.error.message}</Empty> // the reason.
        ) : shortlist.length === 0 ? ( // if no tutors:
          <Empty>No tutor teaches {subject} at this level for {student.state} yet. See the Gaps view.</Empty> // says so.
        ) : ( // otherwise:
          <ol className="space-y-3">{/* a numbered list: */}
            {shortlist.map((t) => ( // for each tutor:
              <li key={t.tutor_id} className={`rounded-lg border p-3 text-sm ${t === top ? "border-teal-700 bg-teal-50" : "border-zinc-200"}`}>{/* a box (highlighted for the top tutor): */}
                <p className="flex flex-wrap items-baseline justify-between gap-2">{/* the top line: */}
                  <span className="font-medium">{/* in bold: */}
                    {t.rank}. {t.tutor_name}{/* their place and name, */}
                    {t === top && ( // if they're the top tutor:
                      <span className="ml-2 text-xs font-semibold uppercase tracking-wide text-teal-800">Suggested</span> // "Suggested".
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
                    At their weekly maximum{t.max_weekly_hours != null ? ` (${t.max_weekly_hours} hr)` : ""}. They can&apos;t be
                    booked past it; if they&apos;re the only option, ask them first.{/* (end of the text) */}
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
                {t.times > 0 && t.best_weekday && t.best_start && t.best_end && ( // If there's a best time:
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
                    startOpen={t === top} // open to start for the top tutor.
                  /> // End of the form.
                )}{/* End of this part. */}
              </li> // End of the box.
            ))}{/* End of the loop. */}
          </ol> // End of the list.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}

      {notOffered.length > 0 && ( // If some tutors don't fit:
        <Card collapsible defaultOpen={false} title={`Tutors who don't fit (${notOffered.length})`}>{/* a fold-up card with the count: */}
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
  ); // End of what's shown.
} // End of StudentPanel.

function Detail({ label, children }: { label: string; children: ReactNode }) { // One detail: a label and its value.
  return ( // Shows:
    <div>{/* (a group) */}
      <dt className="text-xs font-medium text-zinc-500">{label}</dt>{/* the label, */}
      <dd className="whitespace-pre-line">{children}</dd>{/* the value (keeping line breaks). */}
    </div> // End of the group.
  ); // End of what's shown.
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
  ); // End of what's shown.
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
  ); // End of what's shown.
} // End of ReasonsCard.

export const metadata = { title: "Matching · CLG Tutoring" }; // The browser tab title.
