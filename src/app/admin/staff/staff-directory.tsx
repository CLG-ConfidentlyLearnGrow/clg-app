// Summary: the staff directory: search and filter staff and invitations, and (for owner and
// operations admins) manage each person's job title, links and roles.
//
"use client"; // Runs in the browser, so search and filters work as you type.

import { useActionState, useMemo, useState } from "react"; // Lets the page remember searches, filters and form replies.
import { cancelInvitation } from "@/app/actions/admin"; // The server action that cancels an invitation.
import { addRole, removeRole, resendStaffInvite, sendStaffLoginLink, setJobTitle } from "@/app/actions/staff-directory"; // The server actions for roles, links and job titles.
import { Empty } from "@/components/ui"; // The "nothing yet" note.
import { initialFormState, type FormState } from "@/lib/forms"; // The starting (empty) form reply, and the reply type.
import { SetLevelForm } from "../level-forms"; // The drop-down for changing an admin's level.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

// A staff member as the database gives it.
export type StaffMember = {
  account_id: string; // their account,
  full_name: string; // full name,
  email: string | null; // email (if known),
  job_title: string | null; // job title (if set),
  is_tutor: boolean; // whether they're a tutor,
  is_admin: boolean; // an admin,
  is_parent: boolean; // a parent,
  is_student: boolean; // a student,
  admin_level: "owner" | "operations" | "support" | "finance" | null; // their admin level (if an admin),
  tutor_active: boolean | null; // whether they still tutor (if a tutor),
  work_state: string | null; // the state they work from (if set),
  subjects: string[]; // the subjects they teach,
  last_sign_in_at: string | null; // and when they last signed in (if ever).
}; // End of the shape.

// A waiting invitation.
export type Invitation = {
  id: string; // its id,
  email: string; // the email,
  role: "tutor" | "admin"; // tutor or admin,
  admin_level: string | null; // the admin level (if an admin),
  expires_at: string; // and when it expires.
}; // End of the shape.

const LEVEL_NAMES: Record<string, string> = { // Words for each admin level:
  owner: "Owner", // owner,
  operations: "Operations admin", // operations,
  support: "Support admin", // support,
  finance: "Finance admin", // finance.
}; // End of the list.

// Job titles offered as suggestions when typing, alongside any already used.
const SUGGESTED_TITLES = ["Director", "Child Safety Officer", "Operations coordinator", "Office support", "Bookkeeper", "Tutor", "Senior tutor"]; // The suggested titles.

const NO_TITLE = "__none__"; // The filter value for "no job title yet".

// A tutor who has finished with CLG and has no admin role.
function isFinished(p: StaffMember) {
  return !p.is_admin && p.is_tutor && p.tutor_active === false; // True if not an admin, a tutor, and no longer tutoring.
} // End of isFinished.

// What the person does in the app, in plain words.
function appRoles(p: StaffMember): string[] {
  const out: string[] = []; // The list of roles in words.
  if (p.is_admin) out.push(p.admin_level ? LEVEL_NAMES[p.admin_level] : "Admin"); // Admins: their level.
  if (p.is_tutor) out.push(p.tutor_active === false ? "Tutor (finished)" : "Tutor"); // Tutors: whether they've finished.
  if (p.is_parent) out.push("Parent"); // Parents.
  if (p.is_student) out.push("Student"); // Students.
  return out; // Gives back the list.
} // End of appRoles.

// The role an invitation is for, in words.
function invitationRole(i: Invitation) {
  return i.role === "admin" ? `${LEVEL_NAMES[i.admin_level ?? "operations"] ?? "Admin"}` : "Tutor"; // Admins: their level; otherwise "Tutor".
} // End of invitationRole.

// A date in Adelaide time, e.g. 3/11/2026.
function plainDate(iso: string) {
  return new Date(iso).toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide" }); // Writes the date.
} // End of plainDate.

const inputClass = // The style for a plain input box:
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"; // (matching the other boxes).
const smallButton = // The style for a small filled button:
  "rounded-full bg-teal-700 px-4 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-teal-900 disabled:opacity-50"; // (teal, greyed out when disabled).
const plainButton = "rounded-full border border-zinc-300 px-4 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50 disabled:opacity-50"; // The style for a small outlined button.
const linkButton = "text-sm font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700"; // The style for a button that looks like a link.
const pill = "inline-block rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-800"; // The style for a small grey label.

// A labelled drop-down for the filters.
function FilterSelect({
  label, // its label,
  value, // the current choice,
  onChange, // what to do when it changes,
  children, // and its options.
}: { // (their types:)
  label: string; // text,
  value: string; // text,
  onChange: (v: string) => void; // a function,
  children: React.ReactNode; // anything that can be shown.
}) { // (end of the settings)
  return ( // Shows:
    <label className="block space-y-1">{/* a label: */}
      <span className="text-sm font-medium text-zinc-800">{label}</span>{/* the label's words, */}
      <select className={inputClass} value={value} onChange={(e) => onChange(e.target.value)}>{/* a drop-down that reports changes: */}
        {children}{/* the options. */}
      </select>{/* End of the drop-down. */}
    </label> // End of the label.
  ); // End of what's shown.
} // End of FilterSelect.

// The result of an action, shown under its form. Long messages (such as a
// link to copy) wrap.
function Result({ state }: { state: FormState }) {
  if (state.error) // If there's an error:
    return ( // shows:
      <p role="alert" className="text-sm text-red-700">{/* a red message: */}
        {state.error}{/* the error. */}
      </p> // (end of the message)
    ); // (end of what's shown)
  if (state.message) // If there's a message:
    return ( // shows:
      <p role="status" className="text-sm text-teal-800 [overflow-wrap:anywhere]">{/* a teal message that wraps long words: */}
        {state.message}{/* the message. */}
      </p> // (end of the message)
    ); // (end of what's shown)
  return null; // Otherwise nothing.
} // End of Result.

// The directory: search, filters, invitations and staff cards.
export function StaffDirectory({
  staff, // the staff,
  invitations, // the invitations,
  canEdit, // whether this person can edit,
  isOwner, // whether they're the owner,
  viewerId, // and who they are.
}: { // (their types:)
  staff: StaffMember[]; // a list of staff,
  invitations: Invitation[]; // a list of invitations,
  canEdit: boolean; // true or false,
  isOwner: boolean; // true or false,
  viewerId: string; // an id.
}) { // (end of the settings)
  const [search, setSearch] = useState(""); // The search words.
  const [role, setRole] = useState("all"); // The role filter.
  const [title, setTitle] = useState("all"); // The job title filter.
  const [status, setStatus] = useState("current"); // The status filter (working now to start).
  const [state, setState] = useState("all"); // The state filter.
  const [subject, setSubject] = useState("all"); // The subject filter.

  const titles = useMemo( // The job titles in use (worked out once per staff list):
    () => [...new Set(staff.map((p) => p.job_title).filter((t): t is string => Boolean(t)))].sort((a, b) => a.localeCompare(b)), // each title once, in order,
    [staff], // (recomputed when the staff list changes).
  ); // (end of titles)
  const states = useMemo( // The states in use:
    () => [...new Set(staff.map((p) => p.work_state).filter((s): s is string => Boolean(s)))].sort(), // each state once, in order,
    [staff], // (recomputed when the staff list changes).
  ); // (end of states)
  const subjects = useMemo( // The subjects taught:
    () => [...new Set(staff.flatMap((p) => p.subjects))].sort((a, b) => a.localeCompare(b)), // each subject once, in order,
    [staff], // (recomputed when the staff list changes).
  ); // (end of subjects)
  const suggestions = useMemo(() => [...new Set([...titles, ...SUGGESTED_TITLES])], [titles]); // Job title suggestions: those in use plus the usual ones.
  const words = search.trim().toLowerCase().split(/\s+/).filter(Boolean); // The search words, split up, in lower case.

  const shown = staff.filter((p) => { // The staff to show:
    if (status === "invited") return false; // none when showing only invitations,
    if (status === "current" && isFinished(p)) return false; // "working now" hides those finished,
    if (status === "finished" && !isFinished(p)) return false; // "finished" shows only those finished,
    if (status === "never" && p.last_sign_in_at) return false; // "never signed in" hides anyone who has,
    if (role === "tutor" && !p.is_tutor) return false; // the tutor filter,
    if (role === "admin" && !p.is_admin) return false; // the admin filter,
    if (role === "parent" && !p.is_parent) return false; // the parent filter,
    if (["owner", "operations", "support", "finance"].includes(role) && p.admin_level !== role) return false; // an admin level filter,
    if (title === NO_TITLE && p.job_title) return false; // "no job title" hides anyone with one,
    if (title !== "all" && title !== NO_TITLE && p.job_title !== title) return false; // a job title filter,
    if (state !== "all" && p.work_state !== state) return false; // the state filter,
    if (subject !== "all" && !p.subjects.includes(subject)) return false; // the subject filter,
    if (words.length) { // if there are search words:
      const text = [p.full_name, p.email ?? "", p.job_title ?? "", ...appRoles(p), ...p.subjects, p.work_state ?? ""] // the person's searchable words,
        .join(" ") // (joined)
        .toLowerCase(); // (in lower case)
      if (!words.every((w) => text.includes(w))) return false; // hides them unless every word is found.
    } // End of the search.
    return true; // Otherwise shows them.
  }); // End of the filter.

  // Invitations have no job title, state or subject yet, so those filters hide them.
  const shownInvites = invitations.filter((i) => { // The invitations to show:
    if (!["current", "invited", "all"].includes(status)) return false; // only for these statuses,
    if (title !== "all" || state !== "all" || subject !== "all") return false; // hidden by title, state or subject filters,
    if (role === "tutor" && i.role !== "tutor") return false; // the tutor filter,
    if (role === "admin" && i.role !== "admin") return false; // the admin filter,
    if (role === "parent" || role === "owner") return false; // hidden for parent or owner filters,
    if (["operations", "support", "finance"].includes(role) && (i.role !== "admin" || i.admin_level !== role)) return false; // an admin level filter,
    if (words.length) { // if there are search words:
      const text = `${i.email} ${invitationRole(i)} invited`.toLowerCase(); // the invitation's searchable words,
      if (!words.every((w) => text.includes(w))) return false; // hides it unless every word is found.
    } // End of the search.
    return true; // Otherwise shows it.
  }); // End of the filter.

  const filtered = search.trim() !== "" || role !== "all" || title !== "all" || status !== "current" || state !== "all" || subject !== "all"; // True if any search or filter is in use.
  // Clears the search and every filter.
  function clear() {
    setSearch(""); // The search,
    setRole("all"); // role,
    setTitle("all"); // job title,
    setStatus("current"); // status (back to working now),
    setState("all"); // state,
    setSubject("all"); // and subject.
  } // End of clear.

  return ( // Shows:
    <div className="space-y-6">{/* a block with space between parts: */}
      <section className="rounded-2xl border border-zinc-200/80 bg-white p-6 shadow-[0_1px_3px_rgba(65,64,66,0.06),0_8px_24px_-12px_rgba(65,64,66,0.12)]">{/* a white panel: */}
        <label className="block space-y-1">{/* a label: */}
          <span className="text-sm font-medium text-zinc-800">Search</span>{/* "Search", */}
          <input // a search box:
            type="search" // (a search box)
            value={search} // showing the words,
            onChange={(e) => setSearch(e.target.value)} // updates them as you type,
            placeholder="Name, email, job title or subject" // an example,
            className={inputClass} // styled like the other boxes.
          />{/* (end of the box) */}
        </label>{/* End of the label. */}
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">{/* A grid of filters: */}
          <FilterSelect label="Role in the app" value={role} onChange={setRole}>{/* role: */}
            <option value="all">Everyone</option>{/* everyone, */}
            <option value="tutor">Tutors</option>{/* tutors, */}
            <option value="admin">All admins</option>{/* all admins, */}
            <option value="owner">Owner</option>{/* owner, */}
            <option value="operations">Operations admins</option>{/* operations, */}
            <option value="support">Support admins</option>{/* support, */}
            <option value="finance">Finance admins</option>{/* finance, */}
            <option value="parent">Also a parent</option>{/* also a parent. */}
          </FilterSelect>{/* End of the role filter. */}
          <FilterSelect label="Job title" value={title} onChange={setTitle}>{/* Job title: */}
            <option value="all">Any job title</option>{/* any, */}
            {titles.map((t) => ( // for each title in use:
              <option key={t} value={t}>{/* an option: */}
                {t}{/* the title. */}
              </option> // (end of the option)
            ))}{/* End of the loop. */}
            <option value={NO_TITLE}>No job title yet</option>{/* no job title yet. */}
          </FilterSelect>{/* End of the job title filter. */}
          <FilterSelect label="Status" value={status} onChange={setStatus}>{/* Status: */}
            <option value="current">Working now</option>{/* working now, */}
            {canEdit && <option value="invited">Invited, not joined yet</option>}{/* invited (only for editors), */}
            <option value="never">Never signed in</option>{/* never signed in, */}
            <option value="finished">Finished</option>{/* finished, */}
            <option value="all">Everyone</option>{/* everyone. */}
          </FilterSelect>{/* End of the status filter. */}
          <FilterSelect label="Works in (tutors)" value={state} onChange={setState}>{/* Works in: */}
            <option value="all">Any state</option>{/* any state, */}
            {states.map((s) => ( // for each state:
              <option key={s} value={s}>{/* an option: */}
                {s}{/* the state. */}
              </option> // (end of the option)
            ))}{/* End of the loop. */}
          </FilterSelect>{/* End of the state filter. */}
          <FilterSelect label="Teaches (tutors)" value={subject} onChange={setSubject}>{/* Teaches: */}
            <option value="all">Any subject</option>{/* any subject, */}
            {subjects.map((s) => ( // for each subject:
              <option key={s} value={s}>{/* an option: */}
                {s}{/* the subject. */}
              </option> // (end of the option)
            ))}{/* End of the loop. */}
          </FilterSelect>{/* End of the subject filter. */}
        </div>{/* End of the grid. */}
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm text-zinc-600">{/* A row: */}
          <p role="status">{/* a count read out to screen readers: */}
            Showing {shown.length} of {staff.length} staff{/* how many staff are shown, */}
            {canEdit && invitations.length > 0 ? `, and ${shownInvites.length} of ${invitations.length} invited` : ""}{/* and how many invitations, for editors. */}
          </p>{/* End of the count. */}
          {filtered && ( // If filters are in use:
            <button type="button" onClick={clear} className={linkButton}>{/* a button that clears them: */}
              Clear search and filters{/* (its words) */}
            </button> // (end of the button)
          )}{/* End of that part. */}
        </div>{/* End of the row. */}
      </section>{/* End of the panel. */}

      {canEdit && ( // For editors:
        <datalist id="job-title-suggestions">{/* the job title suggestions list: */}
          {suggestions.map((t) => ( // for each suggestion:
            <option key={t} value={t} /> // an option.
          ))}{/* End of the loop. */}
        </datalist> // End of the list.
      )}{/* End of that part. */}

      {shownInvites.length > 0 && ( // If there are invitations to show:
        <section>{/* a section: */}
          <h2 className="mb-3 text-sm font-semibold text-zinc-800">Invited, not joined yet</h2>{/* its heading, */}
          <ul className="grid items-start gap-4 md:grid-cols-2">{/* a grid: */}
            {shownInvites.map((i) => ( // for each invitation:
              <InvitationCard key={i.id} invitation={i} /> // its card.
            ))}{/* End of the loop. */}
          </ul>{/* End of the grid. */}
        </section> // End of the section.
      )}{/* End of that part. */}

      {staff.length === 0 ? ( // If there are no staff:
        <Empty>No staff yet. Add tutors and admins in Staff and accounts.</Empty> // says so,
      ) : shown.length === 0 ? ( // if nobody matches:
        status === "invited" ? null : <Empty>Nobody matches. Try fewer words or clear the filters.</Empty> // says so (unless only invitations were asked for),
      ) : ( // otherwise:
        <section>{/* a section: */}
          {shownInvites.length > 0 && <h2 className="mb-3 text-sm font-semibold text-zinc-800">Staff</h2>}{/* a "Staff" heading when invitations are shown too, */}
          <ul className="grid items-start gap-4 md:grid-cols-2">{/* a grid: */}
            {shown.map((p) => ( // for each person:
              <StaffCard key={p.account_id} person={p} canEdit={canEdit} isOwner={isOwner} isMe={p.account_id === viewerId} /> // their card.
            ))}{/* End of the loop. */}
          </ul>{/* End of the grid. */}
        </section> // End of the section.
      )}{/* End of the choice. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of StaffDirectory.

// A waiting invitation's card, with buttons to send a new one or cancel it.
function InvitationCard({ invitation: i }: { invitation: Invitation }) {
  const [state, formAction, pending] = useActionState(resendStaffInvite, initialFormState); // The reply, the action to send, and whether it's sending.
  const expired = new Date(i.expires_at) <= new Date(); // True if the link has run out.
  return ( // Shows:
    <li className="rounded-2xl border border-dashed border-zinc-300 bg-white p-5">{/* a dashed card: */}
      <p className="text-base font-semibold tracking-tight [overflow-wrap:anywhere]">{i.email}</p>{/* the email, */}
      <div className="mt-2 flex flex-wrap gap-1.5">{/* a row of labels: */}
        <span className={pill}>{invitationRole(i)}</span>{/* the role, */}
        <span className={pill}>{expired ? "Link ran out" : `Link works until ${plainDate(i.expires_at)}`}</span>{/* and when the link works until (or that it ran out). */}
      </div>{/* End of the row. */}
      <div className="mt-3 flex flex-wrap gap-2">{/* A row of buttons: */}
        <form action={formAction}>{/* a form that sends a new invite: */}
          <input type="hidden" name="id" value={i.id} />{/* which invitation (hidden), */}
          <BusyButton type="submit" disabled={pending} className={smallButton}>{/* a small button: */}
            {pending ? "Sending…" : "Send a new invite"}{/* its words change while sending. */}
          </BusyButton>{/* End of the button. */}
        </form>{/* End of the form. */}
        <form action={cancelInvitation}>{/* A form that cancels it: */}
          <input type="hidden" name="id" value={i.id} />{/* which invitation (hidden), */}
          <BusyButton type="submit" className={plainButton}>{/* an outlined button: */}
            Cancel invite{/* "Cancel invite". */}
          </BusyButton>{/* End of the button. */}
        </form>{/* End of the form. */}
      </div>{/* End of the row. */}
      <p className="mt-2 text-xs text-zinc-500">A new invite works once, for 7 days. The old link stops working.</p>{/* A note on how new invites work. */}
      <div className="mt-2">{/* A block: */}
        <Result state={state} />{/* the reply. */}
      </div>{/* End of the block. */}
    </li> // End of the card.
  ); // End of what's shown.
} // End of InvitationCard.

// A staff member's card, with a Manage panel for editors.
function StaffCard({
  person: p, // the person,
  canEdit, // whether this person can edit,
  isOwner, // whether they're the owner,
  isMe, // and whether the card is their own.
}: { // (their types:)
  person: StaffMember; // a staff member,
  canEdit: boolean; // true or false,
  isOwner: boolean; // true or false,
  isMe: boolean; // true or false.
}) { // (end of the settings)
  const [open, setOpen] = useState(false); // Whether the Manage panel is open.
  return ( // Shows:
    <li className="rounded-2xl border border-zinc-200/80 bg-white p-5 shadow-[0_1px_3px_rgba(65,64,66,0.06)]">{/* a white card: */}
      <div className="flex flex-wrap items-start justify-between gap-2">{/* a row: */}
        <div className="min-w-0">{/* a block: */}
          <p className="text-base font-semibold tracking-tight">{p.full_name}</p>{/* their name, */}
          <p className={`text-sm ${p.job_title ? "text-zinc-800" : "text-zinc-500 italic"}`}>{p.job_title ?? "No job title yet"}</p>{/* their job title (or "No job title yet" in grey). */}
        </div>{/* End of the block. */}
        {canEdit && ( // For editors:
          <button // a button:
            type="button" // (a plain button)
            onClick={() => setOpen((o) => !o)} // that opens or closes the panel,
            className={linkButton} // styled as a link,
            aria-expanded={open} // says whether the panel is open,
            aria-label={`${open ? "Close" : "Manage"} ${p.full_name}`} // with words for screen readers.
          >{/* (end of its settings) */}
            {open ? "Close" : "Manage"}{/* "Close" or "Manage". */}
          </button> // End of the button.
        )}{/* End of that part. */}
      </div>{/* End of the row. */}
      <div className="mt-3 flex flex-wrap gap-1.5">{/* A row of labels: */}
        {appRoles(p).map((r) => ( // for each role:
          <span key={r} className={pill}>{/* a label: */}
            {r}{/* the role. */}
          </span> // (end of the label)
        ))}{/* End of the loop. */}
        {p.work_state && <span className={pill}>{p.work_state}</span>}{/* The state they work from, if set, */}
        {!p.last_sign_in_at && <span className="inline-block rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-900">Never signed in</span>}{/* and "Never signed in" if so. */}
      </div>{/* End of the row. */}
      {p.subjects.length > 0 && <p className="mt-2 text-sm text-zinc-600">Teaches: {p.subjects.join(", ")}</p>}{/* The subjects they teach, if any. */}
      {p.email && ( // If there's an email:
        <p className="mt-2 text-sm [overflow-wrap:anywhere]">{/* a line: */}
          <a href={`mailto:${p.email}`} className="text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700">{/* an email link: */}
            {p.email}{/* the address. */}
          </a>{/* End of the link. */}
        </p> // End of the line.
      )}{/* End of that part. */}
      {open && ( // If the panel is open:
        <div className="mt-4 space-y-5 border-t border-zinc-100 pt-4">{/* a block: */}
          <JobTitleForm person={p} />{/* the job title form, */}
          <LoginLinkForm person={p} />{/* the login link form, */}
          <RolesPanel person={p} isOwner={isOwner} isMe={isMe} />{/* and the roles panel. */}
        </div> // End of the block.
      )}{/* End of the panel. */}
    </li> // End of the card.
  ); // End of what's shown.
} // End of StaffCard.

// The form for changing a person's job title.
function JobTitleForm({ person }: { person: StaffMember }) {
  const [state, formAction, pending] = useActionState(setJobTitle, initialFormState); // The reply, the action to send, and whether it's sending.
  return ( // Shows:
    <form action={formAction} className="space-y-2">{/* a form: */}
      <input type="hidden" name="account_id" value={person.account_id} />{/* who (hidden), */}
      <label className="block space-y-1">{/* a label: */}
        <span className="text-sm font-medium text-zinc-800">Job title</span>{/* "Job title", */}
        <span className="flex gap-2">{/* a row: */}
          <input name="job_title" defaultValue={person.job_title ?? ""} maxLength={80} list="job-title-suggestions" className={inputClass} />{/* the title box, with suggestions, */}
          <BusyButton type="submit" disabled={pending} className={smallButton}>{/* a small button: */}
            {pending ? "Saving…" : "Save"}{/* its words change while saving. */}
          </BusyButton>{/* End of the button. */}
        </span>{/* End of the row. */}
        <span className="block text-xs text-zinc-500">For example: Tutor, Operations coordinator. Leave blank to remove.</span>{/* A hint. */}
      </label>{/* End of the label. */}
      <Result state={state} />{/* The reply. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of JobTitleForm.

// The form for emailing a person a login or password link.
function LoginLinkForm({ person }: { person: StaffMember }) {
  const [state, formAction, pending] = useActionState(sendStaffLoginLink, initialFormState); // The reply, the action to send, and whether it's sending.
  return ( // Shows:
    <form action={formAction} className="space-y-2">{/* a form: */}
      <input type="hidden" name="account_id" value={person.account_id} />{/* who (hidden), */}
      <p className="text-sm font-medium text-zinc-800">Login link</p>{/* the heading, */}
      <p className="text-xs text-zinc-500">{/* a small grey note: */}
        {person.last_sign_in_at // if they've signed in before,
          ? "Emails them a link to set a new password, for example if they're locked out." // a password reset link,
          : "They haven't signed in yet. Emails them a new link to choose a password."}{/* otherwise a new login link. */}
      </p>{/* End of the note. */}
      <BusyButton type="submit" disabled={pending} className={plainButton}>{/* An outlined button: */}
        {pending ? "Sending…" : person.last_sign_in_at ? "Send a password link" : "Send a new login link"}{/* its words change while sending, and to match. */}
      </BusyButton>{/* End of the button. */}
      <Result state={state} />{/* The reply. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of LoginLinkForm.

// Each role the person has, with Remove (owner only), and roles that can be
// added. Removing asks for the person's name to be typed, as elsewhere.
function RolesPanel({ person: p, isOwner, isMe }: { person: StaffMember; isOwner: boolean; isMe: boolean }) {
  const held: { role: "admin" | "tutor" | "parent" | "student"; label: string; canRemove: boolean; why?: string }[] = []; // The roles they hold, each with whether it can be removed and why not.
  if (p.is_admin) // Admins:
    held.push({ // adds the admin role:
      role: "admin", // (the role)
      label: p.admin_level ? LEVEL_NAMES[p.admin_level] : "Admin", // with their level,
      canRemove: isOwner && !isMe && p.admin_level !== "owner", // removable by the owner, but not their own or the owner's,
      why: p.admin_level === "owner" ? "The owner's admin role can't be removed." : isMe ? "You can't remove your own admin role." : undefined, // and why not, if it can't be.
    }); // (end of the role)
  if (p.is_tutor) held.push({ role: "tutor", label: p.tutor_active === false ? "Tutor (finished)" : "Tutor", canRemove: isOwner && p.tutor_active !== false }); // Tutors: removable by the owner unless already finished.
  if (p.is_parent) held.push({ role: "parent", label: "Parent", canRemove: isOwner }); // Parents: removable by the owner.
  if (p.is_student) held.push({ role: "student", label: "Student", canRemove: isOwner }); // Students: removable by the owner.

  return ( // Shows:
    <div className="space-y-3">{/* a block: */}
      <p className="text-sm font-medium text-zinc-800">Roles</p>{/* the heading, */}
      <ul className="space-y-2">{/* a list: */}
        {held.map((h) => ( // for each role held:
          <HeldRole key={h.role} person={p} role={h.role} label={h.label} canRemove={h.canRemove} why={h.why} isOwner={isOwner} /> // its row.
        ))}{/* End of the loop. */}
      </ul>{/* End of the list. */}
      {!isOwner && <p className="text-xs text-zinc-500">Only the owner can remove roles or add admins.</p>}{/* A note for non-owners. */}
      <AddRoleForm person={p} isOwner={isOwner} />{/* The form for adding a role. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of RolesPanel.

// One role a person holds: its name, the level drop-down, and Remove with a typed name.
function HeldRole({
  person, // the person,
  role, // the role,
  label, // its name,
  canRemove, // whether it can be removed,
  why, // why not (if it can't),
  isOwner, // and whether this person is the owner.
}: { // (their types:)
  person: StaffMember; // a staff member,
  role: "admin" | "tutor" | "parent" | "student"; // one of the four roles,
  label: string; // text,
  canRemove: boolean; // true or false,
  why?: string; // text (optional),
  isOwner: boolean; // true or false.
}) { // (end of the settings)
  const [confirming, setConfirming] = useState(false); // Whether the remove step is showing.
  const [state, formAction, pending] = useActionState(removeRole, initialFormState); // The reply, the action to send, and whether it's sending.
  const showLevel = role === "admin" && isOwner && person.admin_level && person.admin_level !== "owner" && canRemove; // True if the level drop-down should show (owner, for other admins).
  const effects: Record<string, string> = { // What removing each role does:
    tutor: "Tutor access ends today and their open matches end. Refused while they still have sessions booked.", // tutor,
    admin: "Their admin access ends.", // admin,
    parent: "They stop seeing their children.", // parent,
    student: "Their student record is kept, without the login.", // student.
  }; // End of the list.
  return ( // Shows:
    <li className="rounded-xl bg-zinc-50 px-3 py-2">{/* a soft grey row: */}
      <div className="flex flex-wrap items-center justify-between gap-2">{/* a row: */}
        <span className="text-sm">{label}</span>{/* the role's name, */}
        <span className="flex items-center gap-3">{/* a group: */}
          {showLevel && <SetLevelForm accountId={person.account_id} level={person.admin_level as string} />}{/* the level drop-down, if allowed, */}
          {canRemove && !confirming && ( // if it can be removed and isn't being removed yet:
            <button type="button" onClick={() => setConfirming(true)} className="text-sm font-medium text-red-700 underline underline-offset-4">{/* a red "Remove" button: */}
              Remove{/* (its words) */}
            </button> // (end of the button)
          )}{/* End of that part. */}
        </span>{/* End of the group. */}
      </div>{/* End of the row. */}
      {why && <p className="mt-1 text-xs text-zinc-500">{why}</p>}{/* Why it can't be removed, if so. */}
      {confirming && ( // If removing:
        <form action={formAction} className="mt-2 space-y-2">{/* a form: */}
          <input type="hidden" name="account_id" value={person.account_id} />{/* who (hidden), */}
          <input type="hidden" name="role" value={role} />{/* which role (hidden), */}
          <p className="text-xs text-zinc-600">{effects[role]} Their records are kept under the usual keeping rules.</p>{/* what removing does, */}
          <label className="block space-y-1">{/* a label: */}
            <span className="text-xs font-medium text-zinc-800">Type {person.full_name} to confirm</span>{/* asking them to type the name, */}
            <input name="confirm_name" required autoComplete="off" className={inputClass} />{/* the name box. */}
          </label>{/* End of the label. */}
          <div className="flex gap-2">{/* A row of buttons: */}
            <BusyButton type="submit" disabled={pending} className="rounded-full bg-red-700 px-4 py-1.5 text-sm font-medium text-white hover:bg-red-800 disabled:opacity-50">{/* a red button: */}
              {pending ? "Removing…" : "Remove role"}{/* its words change while removing. */}
            </BusyButton>{/* End of the button. */}
            <button type="button" onClick={() => setConfirming(false)} className={plainButton}>{/* A button that cancels: */}
              Cancel{/* "Cancel". */}
            </button>{/* End of the button. */}
          </div>{/* End of the row. */}
        </form> // End of the form.
      )}{/* End of that part. */}
      <Result state={state} />{/* The reply. */}
    </li> // End of the row.
  ); // End of what's shown.
} // End of HeldRole.

// The form for adding a role a person doesn't have yet.
function AddRoleForm({ person: p, isOwner }: { person: StaffMember; isOwner: boolean }) {
  const [state, formAction, pending] = useActionState(addRole, initialFormState); // The reply, the action to send, and whether it's sending.
  const [role, setRole] = useState(""); // The chosen role (blank to start).
  const options: { value: string; label: string }[] = []; // The roles that can be added.
  if (!p.is_tutor) options.push({ value: "tutor", label: "Tutor" }); // Tutor, if they aren't one.
  if (!p.is_admin && isOwner) options.push({ value: "admin", label: "Admin" }); // Admin, if they aren't one and this is the owner.
  if (!p.is_parent) options.push({ value: "parent", label: "Parent" }); // Parent, if they aren't one.
  const choices = options; // The choices.
  if (choices.length === 0) return null; // Nothing to add: shows nothing.
  return ( // Shows:
    <form action={formAction} className="space-y-2">{/* a form: */}
      <input type="hidden" name="account_id" value={p.account_id} />{/* who (hidden), */}
      <div className="flex flex-wrap items-end gap-2">{/* a row: */}
        <label className="block min-w-40 flex-1 space-y-1">{/* a label: */}
          <span className="text-xs font-medium text-zinc-800">Add a role</span>{/* "Add a role", */}
          <select name="role" value={role} onChange={(e) => setRole(e.target.value)} required className={inputClass}>{/* a drop-down, remembering the choice: */}
            <option value="" disabled>{/* a blank first option that can't be picked: */}
              Choose…{/* "Choose…", */}
            </option>{/* (end of the option) */}
            {choices.map((o) => ( // for each choice:
              <option key={o.value} value={o.value}>{/* an option: */}
                {o.label}{/* its name. */}
              </option> // (end of the option)
            ))}{/* End of the loop. */}
          </select>{/* End of the drop-down. */}
        </label>{/* End of the label. */}
        {role === "admin" && ( // If adding an admin:
          <label className="block min-w-40 flex-1 space-y-1">{/* a label: */}
            <span className="text-xs font-medium text-zinc-800">Admin level</span>{/* "Admin level", */}
            <select name="level" defaultValue="support" className={inputClass}>{/* a drop-down (support to start): */}
              <option value="operations">Operations</option>{/* operations, */}
              <option value="support">Support</option>{/* support, */}
              <option value="finance">Finance</option>{/* finance. */}
            </select>{/* End of the drop-down. */}
          </label> // End of the label.
        )}{/* End of that part. */}
        <BusyButton type="submit" disabled={pending || !role} className={smallButton}>{/* A small button (greyed out until a role is chosen): */}
          {pending ? "Adding…" : "Add"}{/* its words change while adding. */}
        </BusyButton>{/* End of the button. */}
      </div>{/* End of the row. */}
      <p className="text-xs text-zinc-500">{/* A small grey note: */}
        A student role comes from &quot;Become a learner&quot; on their own dashboard, because it needs a student record.{/* why the student role is added elsewhere. */}
      </p>{/* End of the note. */}
      <Result state={state} />{/* The reply. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of AddRoleForm.
