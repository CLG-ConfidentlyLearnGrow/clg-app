// Summary: the Tutor applications page for the owner and Operations admins:
// the queue of applications (filtered by where they're up to), and one
// application in full with its CV, the child-safe screening record, the
// interview and referee questions, and the decline and approve forms.
// See docs/features/tutor-applications.md.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: back button, card, empty note, small heading, table and text link.
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The owner-and-Operations group, and the admin check.
import { STATE_NAMES, type AuState } from "@/lib/checks"; // State names.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import {
  APPLICATION_STATUSES, // Where an application can be up to.
  APPLICATION_STATUS_NAMES, // Their words.
  DECLINE_REASON_NAMES, // The decline reasons' words.
  FIRST_AID_STATUS_NAMES, // The first aid answers' words.
  INTERVIEW_QUESTIONS, // Child-safe interview questions.
  REFEREE_QUESTIONS, // Questions for referees.
  RRHAN_STATUS_NAMES, // The RRHAN-EC answers' words.
  TEACH_MODE_NAMES, // How someone can teach, in words.
  WWCC_STATUS_NAMES, // The check answers' words.
  type ApplicationStatus, // The status type.
  type DeclineReason, // The decline reason type.
} from "@/lib/tutor-applications"; // (shared words for applications)
import { ApproveForm, DeclineForm, ScreeningForm, type ScreeningRecord } from "./forms"; // The admin forms.

// One application, as read from the database.
type Application = ScreeningRecord & {
  created_at: string; // when it was sent,
  first_name: string; // first name,
  last_name: string; // last name,
  email: string; // email,
  phone: string; // phone,
  state: AuState; // state,
  suburb: string; // suburb or town,
  teach_mode: keyof typeof TEACH_MODE_NAMES; // in person, online or both,
  right_to_work: boolean; // right to work,
  subjects: string; // subjects and year levels,
  availability: string; // availability,
  weekly_hours: number | null; // hours a week,
  qualifications: string; // qualifications,
  teacher_registration: string | null; // teacher registration,
  experience: string; // experience,
  wwcc_status: keyof typeof WWCC_STATUS_NAMES; // check status,
  wwcc_number: string | null; // check number,
  wwcc_state: AuState | null; // check state,
  wwcc_expiry: string | null; // check expiry,
  rrhan_ec_status: keyof typeof RRHAN_STATUS_NAMES; // RRHAN-EC,
  first_aid_status: keyof typeof FIRST_AID_STATUS_NAMES; // first aid,
  referees: { name: string; relationship: string; email: string; phone: string }[]; // the two referees,
  statement: string; // why CLG,
  helped_example: string; // a time they helped,
  heard_from: string | null; // how they heard,
  cv_path: string | null; // their CV, if any,
  decline_reason: DeclineReason | null; // why declined,
  decline_note: string | null; // decline note,
  decided_at: string | null; // when decided,
  invited_at: string | null; // when the invite went.
}; // End of the shape.

// The filters along the top of the queue: open applications (the default),
// each status on its own, or everything.
const FILTERS = [ // Each filter's id, words, and the statuses it shows:
  { id: "open", label: "Open", statuses: ["new", "shortlisted"] }, // still needing a decision,
  ...APPLICATION_STATUSES.map((s) => ({ id: s, label: APPLICATION_STATUS_NAMES[s], statuses: [s] })), // one per status,
  { id: "all", label: "All", statuses: [...APPLICATION_STATUSES] }, // and everything.
] as { id: string; label: string; statuses: ApplicationStatus[] }[]; // (the shape of each filter)

// One question and answer, shown as a small heading and the words.
function Answer({ label, children }: { label: string; children: ReactNode }) {
  return ( // Shows:
    <div>{/* a block: */}
      <p className="text-xs font-semibold tracking-wide text-zinc-500 uppercase">{label}</p>{/* the question, small and grey, */}
      <div className="mt-0.5 text-sm whitespace-pre-line">{children}</div>{/* and the answer (keeping line breaks). */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of Answer.

// A tick or a dash for a screening step, with its date.
function Step({ done, label }: { done: string | null; label: string }) {
  return ( // Shows:
    <li className={done ? "text-teal-800" : "text-zinc-500"}>{/* a line, green when done: */}
      {done ? "✓" : "○"} {label}{done ? ` (${shortDate(done)})` : ""}{/* a tick or circle, the step, and its date. */}
    </li> // End of the line.
  ); // End of what's shown.
} // End of Step.

// Shows the page (owner and Operations admins only).
export default async function TutorApplicationsPage({ searchParams }: PageProps<"/admin/applications">) {
  const viewer = await requireAdminLevel(FULL_ADMIN); // Must be the owner or an Operations admin, with two-step login.
  const params = await searchParams; // Reads the address settings.
  const supabase = await createClient(); // Connects to the database.
  const filter = FILTERS.find((f) => f.id === params.status) ?? FILTERS[0]; // The filter chosen (open applications by default).
  const id = typeof params.id === "string" && /^[0-9a-f-]{36}$/.test(params.id) ? params.id : null; // The application to open, if any.

  // One application in full.
  if (id) { // An application is open:
    const { data } = await supabase.from("tutor_applications").select("*").eq("id", id).maybeSingle(); // reads it (only if this admin may),
    const app = data as Application | null; // (or nothing if not found).
    return ( // shows:
      <DashboardFrame role="admin" roles={viewer.roles} current="applications">{/* the dashboard frame, */}
        {!app ? ( // Not found:
          <Card title="Application not found">{/* a card saying so: */}
            <p className="text-sm">It may have been deleted at the end of its keeping period. <TextLink href="/admin/applications">Back to all applications</TextLink></p>{/* with a link back. */}
          </Card> // End of the card.
        ) : ( // Found:
          <>{/* (a group:) */}
            <p className="mb-4"><BackButton href="/admin/applications">Back to all applications</BackButton></p>{/* A button back to the queue. */}
            <Card title={`${app.first_name} ${app.last_name}`} description={`Sent ${shortDate(app.created_at)} · ${APPLICATION_STATUS_NAMES[app.status as ApplicationStatus]}`}>{/* the application card: */}
              <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
                <Answer label="Email"><a href={`mailto:${app.email}`} className="text-teal-700 underline">{app.email}</a></Answer>{/* email (tap to write), */}
                <Answer label="Phone"><a href={`tel:${app.phone.replace(/\s/g, "")}`} className="text-teal-700 underline">{app.phone}</a></Answer>{/* phone (tap to call), */}
                <Answer label="Lives in">{app.suburb}, {STATE_NAMES[app.state]}</Answer>{/* where they live, */}
                <Answer label="Would tutor">{TEACH_MODE_NAMES[app.teach_mode]}</Answer>{/* how they'd teach, */}
                <Answer label="Right to work in Australia">{app.right_to_work ? "Yes" : "No"}</Answer>{/* right to work, */}
                <Answer label="Hours a week">{app.weekly_hours ? `${app.weekly_hours} hr` : "Not given"}</Answer>{/* hours a week. */}
              </div>{/* End of the columns. */}
              <SubHeading>What and when they can teach</SubHeading>{/* A heading: */}
              <div className="space-y-3">{/* the answers: */}
                <Answer label="Subjects and year levels">{app.subjects}</Answer>{/* subjects, */}
                <Answer label="When they are free">{app.availability}</Answer>{/* availability. */}
              </div>{/* End of the answers. */}
              <SubHeading>Qualifications and experience</SubHeading>{/* A heading: */}
              <div className="space-y-3">{/* the answers: */}
                <Answer label="Qualifications">{app.qualifications}</Answer>{/* qualifications, */}
                {app.teacher_registration && <Answer label="Teacher registration">{app.teacher_registration}</Answer>}{/* registration (if given), */}
                <Answer label="Experience">{app.experience}</Answer>{/* experience, */}
                <Answer label="CV">{app.cv_path ? <a href={`/admin/applications/cv/${app.id}`} target="_blank" rel="noreferrer" className="text-teal-700 underline">Open CV (PDF)</a> : "No CV attached"}</Answer>{/* the CV link (or none). */}
              </div>{/* End of the answers. */}
              <SubHeading>Child safety checks (as they told us)</SubHeading>{/* A heading: */}
              <div className="grid gap-4 sm:grid-cols-3">{/* three columns on wider screens: */}
                <Answer label="Working with Children Check">{WWCC_STATUS_NAMES[app.wwcc_status]}{app.wwcc_number ? `: ${app.wwcc_number}` : ""}{app.wwcc_state ? ` (${app.wwcc_state})` : ""}{app.wwcc_expiry ? `, expires ${shortDate(app.wwcc_expiry)}` : ""}</Answer>{/* the check, */}
                <Answer label="RRHAN-EC">{RRHAN_STATUS_NAMES[app.rrhan_ec_status]}</Answer>{/* RRHAN-EC, */}
                <Answer label="First aid">{FIRST_AID_STATUS_NAMES[app.first_aid_status]}</Answer>{/* first aid. */}
              </div>{/* End of the columns. */}
              <SubHeading>Referees</SubHeading>{/* A heading: */}
              <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
                {app.referees.map((r, i) => ( // for each referee:
                  <Answer key={i} label={`Referee ${i + 1}`}>{/* a block: */}
                    {r.name}{"\n"}{r.relationship}{"\n"}{[r.email, r.phone].filter(Boolean).join(" · ")}{/* their name, how they know them, and contact details. */}
                  </Answer> // End of the block.
                ))}{/* End of the referees. */}
              </div>{/* End of the columns. */}
              <SubHeading>In their own words</SubHeading>{/* A heading: */}
              <div className="space-y-3">{/* the answers: */}
                <Answer label="Why they would like to tutor with CLG">{app.statement}</Answer>{/* why CLG, */}
                <Answer label="A time they helped a young person">{app.helped_example}</Answer>{/* a time they helped, */}
                {app.heard_from && <Answer label="How they heard about CLG">{app.heard_from}</Answer>}{/* how they heard (if given). */}
              </div>{/* End of the answers. */}
            </Card>{/* End of the application card. */}

            <Card title="Screening record" description="Child-safe recruitment steps. Approving needs the interview and both referee checks.">{/* the screening card: */}
              <ul className="mb-5 space-y-1 text-sm">{/* the steps so far: */}
                <Step done={app.interview_on} label="Interview" />{/* interview, */}
                <Step done={app.referee_1_checked_on} label="Referee 1 checked" />{/* referee 1, */}
                <Step done={app.referee_2_checked_on} label="Referee 2 checked" />{/* referee 2, */}
                <Step done={app.wwcc_verified_on} label="Working with Children Check verified (can also be done after they join)" />{/* check verified. */}
              </ul>{/* End of the steps. */}
              <ScreeningForm app={app} />{/* the form. */}
            </Card>{/* End of the screening card. */}

            <Card title="Questions to use" description="Ask about real past behaviour. Note their answers in the record above." collapsible defaultOpen={false}>{/* the questions card (closed to start): */}
              <SubHeading>Interview (child-safe questions)</SubHeading>{/* a heading, */}
              <ol className="list-decimal space-y-1 pl-5 text-sm">{INTERVIEW_QUESTIONS.map((q) => <li key={q}>{q}</li>)}</ol>{/* the interview questions, */}
              <p className="mt-2 text-sm text-zinc-600">Also ask them to explain a topic they would teach, as if to a student, to see how clearly they explain and check for understanding.</p>{/* a teaching task, */}
              <SubHeading>Referees (ideally by phone)</SubHeading>{/* a heading, */}
              <ol className="list-decimal space-y-1 pl-5 text-sm">{REFEREE_QUESTIONS.map((q) => <li key={q}>{q}</li>)}</ol>{/* and the referee questions. */}
            </Card>{/* End of the questions card. */}

            {app.status === "approved" ? ( // Already approved:
              <Card title="Approved" description={`${app.decided_at ? `Approved ${shortDate(app.decided_at)}. ` : ""}${app.invited_at ? `Invite sent ${shortDate(app.invited_at)}.` : "The invite has not gone yet."}`}>{/* a card saying so: */}
                <ApproveForm id={app.id} again />{/* with a button to send the invite again. */}
              </Card> // End of the card.
            ) : app.status === "declined" ? ( // Declined:
              <Card title="Declined" description={app.decided_at ? `Declined ${shortDate(app.decided_at)}. Deleted 12 months after that.` : undefined}>{/* a card saying so: */}
                <p className="text-sm">Reason: {app.decline_reason ? DECLINE_REASON_NAMES[app.decline_reason] : "Not recorded"}{app.decline_note ? `. ${app.decline_note}` : ""}</p>{/* with the reason and note. */}
              </Card> // End of the card.
            ) : app.status === "withdrawn" ? ( // Withdrawn:
              <Card title="Withdrawn">{/* a card saying so: */}
                <p className="text-sm">To reopen it, set the status back to New or Shortlisted above. It is deleted 12 months after it was withdrawn.</p>{/* with how to reopen it. */}
              </Card> // End of the card.
            ) : ( // Still open:
              <div className="grid gap-6 lg:grid-cols-2">{/* two cards side by side on wide screens: */}
                <Card title="Approve">{/* the approve card, */}
                  <ApproveForm id={app.id} again={false} />{/* with its form, */}
                </Card>{/* End of the card. */}
                <Card title="Decline">{/* the decline card, */}
                  <DeclineForm id={app.id} />{/* with its form. */}
                </Card>{/* End of the card. */}
              </div> // End of the cards.
            )}{/* End of the decision part. */}
            <p><BackButton href="/admin/applications">Back to all applications</BackButton></p>{/* The same back button at the bottom, so it's there after scrolling down. */}
          </> // End of the group.
        )}{/* End of the choice. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the open application.

  // The queue.
  const { data } = await supabase // Reads the applications:
    .from("tutor_applications") // from the applications table,
    .select("id, created_at, first_name, last_name, state, subjects, status, interview_on, referee_1_checked_on, referee_2_checked_on") // with what the list needs,
    .in("status", filter.statuses) // in the chosen statuses,
    .order("created_at", { ascending: false }) // newest first,
    .limit(200); // at most 200.
  const apps = (data ?? []) as Pick<Application, "id" | "created_at" | "first_name" | "last_name" | "state" | "subjects" | "status" | "interview_on" | "referee_1_checked_on" | "referee_2_checked_on">[]; // The applications listed.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="applications">{/* the dashboard frame, */}
      <Card title="Tutor applications" description="Applications from the public Apply to tutor page. Open one to record the interview and referee checks, then approve (which sends the tutor invite) or decline.">{/* the queue card: */}
        <div className="mb-4 flex flex-wrap gap-2">{/* the filter buttons (wrap on small screens): */}
          {FILTERS.map((f) => ( // for each filter:
            <TextLink // a link:
              key={f.id} // (its id)
              href={f.id === "open" ? "/admin/applications" : `/admin/applications?status=${f.id}`} // to the queue with that filter,
              aria-current={f.id === filter.id ? "page" : undefined} // marked as current when chosen,
              className={`rounded-full border px-3 py-1 text-sm ${f.id === filter.id ? "border-brand bg-brand text-white" : "border-zinc-300 text-zinc-700 hover:border-brand"}`} // filled in when chosen.
            >{/* (end of the link's settings) */}
              {f.label}{/* its words. */}
            </TextLink> // End of the link.
          ))}{/* End of the filters loop. */}
        </div>{/* End of the filters. */}
        {apps.length === 0 ? ( // None:
          <Empty>No applications here.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Sent", "Name", "State", "Subjects", "Status", "Checks", ""]}>{/* a table: */}
            {apps.map((a) => ( // for each application:
              <tr key={a.id}>{/* a row: */}
                <td className="whitespace-nowrap">{shortDate(a.created_at)}</td>{/* when it was sent, */}
                <td>{a.first_name} {a.last_name}</td>{/* their name, */}
                <td>{a.state}</td>{/* their state, */}
                <td><p className="line-clamp-2">{a.subjects}</p></td>{/* the start of their subjects, */}
                <td className="whitespace-nowrap">{APPLICATION_STATUS_NAMES[a.status as ApplicationStatus]}</td>{/* where it's up to, */}
                <td className="whitespace-nowrap text-xs text-zinc-600">{[a.interview_on && "Interview", a.referee_1_checked_on && "Ref 1", a.referee_2_checked_on && "Ref 2"].filter(Boolean).join(", ") || "None yet"}</td>{/* screening steps done, */}
                <td className="text-right"><TextLink href={`/admin/applications?id=${a.id}`}>Open</TextLink></td>{/* and a link to open it. */}
              </tr> // End of the row.
            ))}{/* End of the applications loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
        <p className="mt-4 text-xs text-zinc-500">Share the public page with people who want to tutor: <span className="font-medium">app.clgtutoring.com/apply</span>. Declined and withdrawn applications are deleted 12 months after the decision; approved ones after 7 years.</p>{/* Where to send applicants, and the keeping periods. */}
      </Card>{/* End of the queue card. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of TutorApplicationsPage.
