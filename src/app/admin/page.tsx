// Summary: the main admin page: families, tutors and checks, curriculum,
// progress, staff and levels, people leaving, and records (privacy, deletion, holds).
//
import { // The admin actions used here:
  cancelInvitation, // cancel a staff invitation,
  confirmCheck, // confirm a tutor's check,
  releaseHold, // release a records hold,
  verifyParentLink, // confirm a parent's link to a child.
} from "@/app/actions/admin"; // End of the list.
import { confirmAllCurricula, confirmCurriculum, discardCurriculum } from "@/app/actions/curriculum"; // Curriculum actions: confirm all, confirm one, throw one away.
import { AcaraImportForm } from "./acara-import"; // The Australian Curriculum loader form.
import { CurriculumFileForm } from "./curriculum-file-import"; // The curriculum file upload form.
import { Button, Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: button, card, empty line, small heading, table and text link.
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { SectionShell } from "@/components/section-shell"; // The page frame with a side menu.
import { ADMIN_SECTIONS, sectionFrom } from "./sections"; // The admin sections, and a reader for the section in the address.
import { FamilySetupForm } from "./family-setup-form"; // The "set up a family" form.
import { RemoveRoleForm } from "./remove-role-form"; // The "remove a role" form.
import { StudentLoginForm } from "./student-login-form"; // The "give a student their own login" form.
import { NewLinkForm } from "./new-link-form"; // The "send a new login link" form.
import { DuplicateList, LinkParentForm, ParentLinkList, type DuplicateRow, type ParentLinkRow } from "./parent-link-forms"; // Parent link parts: double-ups, link a parent, the parents list, and their types.
import { ProgressSection } from "./progress-section"; // The progress section.
import { AddOnsSection } from "./add-ons-section"; // The add-ons section.
import { LeavingSection } from "./leaving-section"; // The people-leaving section.
import { ADMIN_LEVEL_NAMES, FRONT_DESK, FULL_ADMIN, requireAdminLevel, type AdminLevel } from "@/lib/auth"; // Admin level names, level groups, the level check, and the level type.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { getToDoCounts } from "@/lib/to-do-counts"; // Reads the to-do numbers.
import { CountBadge } from "@/components/count-badge"; // The small to-do number badge.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { checkName, type AuState } from "@/lib/checks"; // Check names, and the state type.
import { // The admin forms used here:
  CheckForm, // record a check,
  DeclineCheckForm, // send a check back,
  EraseStudentForm, // delete a student,
  HoldForm, // place a records hold,
  InviteForm, // invite staff,
  RetentionPeriodForm, // change how long records are kept,
  TutorLeftForm, // record that a tutor has left,
  UnlockForm, // unlock an account,
  WorkStateForm, // set a tutor's work state.
} from "./forms"; // End of the forms.
import { EmergencyApproveForm, EmergencyCancelForm, EmergencyRequestForm, LevelBadge, SetLevelForm } from "./level-forms"; // Admin level forms: emergency access approve, cancel and request, the level badge, and set a level.
import { // The curriculum forms:
  FrameworkForm, // add a curriculum,
  ImportSkillsForm, // paste in skills,
  StudentFrameworkForm, // set a student's curriculum.
} from "./curriculum-forms"; // End of the forms.
import { BusyButton } from "@/components/busy-button"; // A button that shows it's busy while sending.

type PendingLink = { // A parent's link to a child waiting for CLG:
  parent_id: string; // the parent,
  student_id: string; // the student,
  relationship: string; // how they're related,
  parent: { full_name: string } | null; // the parent's name,
  student: { full_name: string; date_of_birth: string } | null; // and the student's name and birth date.
}; // End of PendingLink.
type CheckRow = { // A tutor's check standing:
  tutor_id: string; // the tutor,
  full_name: string; // their name,
  kind: string; // the check type,
  expires_on: string | null; // its expiry (if any),
  status: string; // and its status.
}; // End of CheckRow.

type Due = { // A record due for deletion:
  kind: "student" | "account" | "tutor"; // what kind (student, unused account or former tutor),
  record_id: string; // its id,
  full_name: string; // the person's name,
  due_on: string; // and when it's due.
}; // End of Due.
type Hold = { // A records hold:
  id: string; // its id,
  reason: string; // why it was placed,
  placed_at: string; // when,
  student: { full_name: string } | null; // the student (if it's on a student),
  account: { full_name: string } | null; // or the account (if it's on an account).
}; // End of Hold.
type Rule = { kind: string; keep_for: string; description: string }; // How long one kind of record is kept, and what it covers.

const RULE_LABELS: Record<string, string> = { // The names for each kind of record kept:
  student_records: "Student records", // student records,
  unused_accounts: "Unused accounts", // unused accounts,
  former_tutors: "Former tutors", // former tutors,
  activity_log: "Activity log", // the activity log.
}; // End of the names.
const DUE_LABELS: Record<Due["kind"], string> = { // The names for each kind of record due:
  student: "Student", // student,
  account: "Unused account", // unused account,
  tutor: "Former tutor", // former tutor.
}; // End of the names.

// Postgres writes "1 year 6 mons"; show it in plain words.
function plainPeriod(p: string) { // Takes the period text.
  return p.replace(/\bmons?\b/g, (m) => (m === "mon" ? "month" : "months")); // Changes "mon" or "mons" to "month" or "months".
} // End of plainPeriod.

export default async function AdminPage({ searchParams }: PageProps<"/admin">) { // The page itself (reads the address's settings).
  // Finance admins work in Billing; everyone else at their level sees the
  // sections that fit it (the database decides what they can actually read).
  const viewer = await requireAdminLevel(FRONT_DESK); // Must be a front-desk admin.
  const isFull = FULL_ADMIN.includes(viewer.level); // Whether they're a full admin.
  const supabase = await createClient(); // Connects to the database.
  const params = await searchParams; // The address's settings.
  const visibleSections = isFull // The sections this admin sees:
    ? ADMIN_SECTIONS // all of them for full admins,
    : ADMIN_SECTIONS.filter((s) => s.id === "families" || s.id === "matching"); // otherwise just families and matching.
  const wanted = sectionFrom(params.section); // The section asked for.
  // Matching has its own page (owner, operations and support).
  if (wanted === "matching") redirect("/matching"); // Matching asked for: goes to its page.
  const section = visibleSections.some((s) => s.id === wanted) ? wanted : visibleSections[0].id; // The open section (the first they can see if the one asked for isn't allowed).

  const [me, pending, checks, students, tutorList, cleared, due, holds, rules] = // Reads everything at once:
    await Promise.all([ // (waits for all of them)
      supabase // this admin's own saved level:
        .from("admin_profiles") // from admin_profiles,
        .select("level") // the level,
        .eq("account_id", viewer.id) // for this admin,
        .maybeSingle(), // if any.
      supabase // parent links waiting:
        .from("parent_student_links") // from parent_student_links,
        .select( // with these details:
          "parent_id, student_id, relationship, parent:parent_profiles(account:accounts(full_name)), student:students(full_name, date_of_birth)", // the parent's and student's names,
        ) // (end of the details)
        .is("verified_at", null), // not yet confirmed.
      supabase // each tutor's check standing:
        .from("tutor_check_status") // from tutor_check_status,
        .select("tutor_id, full_name, kind, expires_on, status") // these details,
        .order("full_name"), // by name.
      supabase // the students:
        .from("students") // from students,
        .select("id, account_id, full_name, date_of_birth, state, year_level, school, goals, extra_info, learning_needs, student_subjects(subject, working_level)") // their details and subjects,
        .order("full_name"), // by name.
      supabase // the tutors:
        .from("tutor_profiles") // from tutor_profiles,
        .select("account_id, account:accounts(full_name)"), // with their names.
      supabase.from("tutor_cleared_states").select("tutor_id, state"), // the states each tutor is cleared for,
      supabase.rpc("upcoming_deletions", { p_days: 30 }), // records due for deletion in 30 days,
      supabase // records holds:
        .from("retention_holds") // from retention_holds,
        .select( // with these details:
          "id, reason, placed_at, student:students(full_name), account:accounts!retention_holds_account_id_fkey(full_name)", // and the student's or account's name,
        ) // (end of the details)
        .is("released_at", null) // still in place,
        .order("placed_at"), // oldest first.
      supabase // how long records are kept:
        .from("retention_rules") // from retention_rules,
        .select("kind, keep_for, description") // these details,
        .order("kind"), // by kind.
    ]); // End of the reads.
  const teachingList = await supabase // Reads what each tutor teaches:
    .from("tutor_teaching") // from tutor_teaching,
    .select("tutor_id, subject, from_level, to_level") // these details,
    .order("subject"); // by subject.
  const teachingByTutor = new Map<string, string[]>(); // What each tutor teaches, by tutor.
  for (const t of teachingList.data ?? []) { // For each subject a tutor teaches:
    const range = t.from_level === t.to_level ? t.from_level : `${t.from_level} to ${t.to_level}`; // the year level, or the range,
    teachingByTutor.set(t.tutor_id, [...(teachingByTutor.get(t.tutor_id) ?? []), `${t.subject} (${range})`]); // added to that tutor's list.
  } // End of the loop.
  const pendingChecks = await supabase // Reads checks waiting for CLG:
    .from("tutor_checks") // from tutor_checks,
    .select( // with these details:
      "id, kind, reference, completed_on, expires_on, submitted_at, document_path, tutor:tutor_profiles(account:accounts(full_name))", // and the tutor's name,
    ) // (end of the details)
    .is("verified_at", null) // not confirmed,
    .is("declined_at", null) // not sent back,
    .order("submitted_at"); // oldest first.
  const pendingCheckRows = (pendingChecks.data ?? []) as unknown as { // The checks waiting:
    id: string; // each has an id,
    kind: string; // a type,
    reference: string | null; // a number (if any),
    completed_on: string | null; // the date done (if known),
    expires_on: string; // an expiry date,
    submitted_at: string | null; // when it was sent,
    document_path: string | null; // where the copy is stored,
    tutor: { account: { full_name: string } | null } | null; // and the tutor's name.
  }[]; // (end of the type)
  const frameworkList = await supabase // Reads the curricula in use:
    .from("curriculum_frameworks") // from curriculum_frameworks,
    .select("id, code, name, version, confirmed_at, source") // these details,
    .eq("active", true) // in use,
    .order("code"); // by code.
  const frameworks = (frameworkList.data ?? []).map((f) => ({ // Each curriculum as:
    id: f.id as string, // its id,
    code: f.code as string, // its code,
    name: `${f.code}: ${f.name} (v${f.version})`, // its full name with version,
    confirmed: Boolean(f.confirmed_at), // whether it's confirmed,
    source: (f.source as string | null) ?? null, // and where it came from (if known).
  })); // End of the curricula.
  const frameworkOptions = frameworks.map(({ id, name }) => ({ id, name })); // The curricula as choices.
  const confirmedOptions = frameworks // Only the confirmed ones as choices:
    .filter((f) => f.confirmed) // confirmed,
    .map(({ id, name }) => ({ id, name })); // as choices.
  const drafts = await Promise.all( // The drafts, each with a summary:
    frameworks // from the curricula,
      .filter((f) => !f.confirmed) // the unconfirmed ones,
      .map(async (f) => { // each:
        const summary = await supabase.rpc("curriculum_summary", { // reads its summary:
          p_framework: f.id, // for this curriculum.
        }); // (end of the read)
        return { // gives back:
          ...f, // the curriculum,
          summary: (summary.data ?? []) as { // with its summary of:
            subject: string; // subject,
            level_band: string; // year or level,
            skills: number; // and number of skills.
          }[], // (end of the summary)
        }; // (end of what's given back)
      }), // End of each.
  ); // End of the drafts.
  // Saved level, ignoring emergency access (which only operations can ask for).
  const savedLevel = (me.data?.level ?? null) as AdminLevel | null; // Their saved level.
  // Acting as owner, including during emergency owner access.
  const isOwner = viewer.level === "owner"; // Whether they're acting as owner.
  // Every staff member with their roles and level, and any emergency owner
  // access request (owner and operations only).
  const [staffRes, emergencyRes, pausedRes] = await Promise.all([ // Reads three more things at once:
    isFull && section === "staff" ? supabase.rpc("staff_list") : Promise.resolve({ data: [] }), // the staff list (full admins, on the Staff section),
    isFull // for full admins:
      ? supabase // emergency owner access:
          .from("emergency_owner_access") // from emergency_owner_access,
          .select("id, requested_by, reason, requested_at, starts_at, ends_at, requester:accounts!emergency_owner_access_requested_by_fkey(full_name)") // these details and who asked,
          .is("cancelled_at", null) // not cancelled,
          .gt("ends_at", new Date().toISOString()) // not yet ended,
          .order("requested_at", { ascending: false }) // newest first,
          .limit(1) // just one.
      : Promise.resolve({ data: [] }), // otherwise none.
    section === "families" ? supabase.rpc("family_pause_status") : Promise.resolve({ data: [] }), // and family pause status (on the Families section).
  ]); // End of the reads.
  const staffRows = (staffRes.data ?? []) as { // The staff:
    account_id: string; // each has an account,
    full_name: string; // a name,
    email: string | null; // an email (if known),
    is_tutor: boolean; // whether they're a tutor,
    tutor_active: boolean | null; // whether still tutoring (if a tutor),
    admin_level: AdminLevel | null; // and their admin level (if an admin).
  }[]; // (end of the type)
  const emergency = ((emergencyRes.data ?? []) as unknown as { // The emergency owner access request (if any):
    id: string; // its id,
    requested_by: string; // who asked,
    reason: string; // why,
    requested_at: string; // when,
    starts_at: string; // when it starts,
    ends_at: string; // when it ends,
    requester: { full_name: string } | null; // and the asker's name.
  }[])[0]; // (the first one)
  const emergencyRunning = emergency ? new Date(emergency.starts_at) <= new Date() : false; // Whether it has started.
  const pausedFamilies = ((pausedRes.data ?? []) as { family_id: string; family_name: string; paused: boolean; paused_since: string | null }[]).filter( // The paused families:
    (f) => f.paused, // only those paused.
  ); // (end of the filter)
  // Staff invitations nobody has used yet (only needed on the Staff section).
  const openInvites = // Staff invitations not yet used:
    section === "staff" // on the Staff section:
      ? ((( // (reads)
          await supabase // the invitations:
            .from("invitations") // from invitations,
            .select("id, email, role, expires_at") // these details,
            .is("accepted_at", null) // not yet accepted,
            .order("created_at", { ascending: false }) // newest first.
        ).data ?? []) as { id: string; email: string; role: string; expires_at: string }[]) // (the rows)
      : []; // otherwise none.
  // Parents of each student, and possible double-ups (Families section only).
  const [parentLinksRes, duplicatesRes] = // Reads two more things:
    section === "families" // on the Families section,
      ? await Promise.all([supabase.rpc("admin_student_parents"), supabase.rpc("admin_possible_duplicate_children")]) // each student's parents and possible double-ups,
      : [{ data: [] }, { data: [] }]; // otherwise none.
  const parentLinks = (parentLinksRes.data ?? []) as ParentLinkRow[]; // Each student's parents.
  const duplicates = (duplicatesRes.data ?? []) as DuplicateRow[]; // Possible double-ups.
  const dueRows = (due.data ?? []) as Due[]; // Records due for deletion.
  const holdRows = (holds.data ?? []) as unknown as Hold[]; // Records holds.
  const ruleRows = (rules.data ?? []) as Rule[]; // How long records are kept.

  const statesByTutor = new Map<string, string[]>(); // Each tutor's cleared states, by tutor.
  for (const row of cleared.data ?? []) { // For each cleared state:
    statesByTutor.set(row.tutor_id, [ // adds it to that tutor's list:
      ...(statesByTutor.get(row.tutor_id) ?? []), // the list so far,
      row.state, // plus this state.
    ]); // (end of the list)
  } // End of the loop.

  const checkRows = (checks.data ?? []) as CheckRow[]; // Each tutor's check standing.
  const tutors = ( // The tutors:
    (tutorList.data ?? []) as unknown as { // from the tutor rows:
      account_id: string; // each has an account,
      account: { full_name: string } | null; // and a name.
    }[] // (end of the type)
  ) // (end of the rows)
    .map((t) => ({ id: t.account_id, name: t.account?.full_name ?? "Tutor" })) // each as an id and name,
    .sort((a, b) => a.name.localeCompare(b.name)); // by name.
  const studentRows = (students.data ?? []) as { // The students:
    id: string; // each has an id,
    account_id: string | null; // their own login (if any),
    full_name: string; // their name,
    date_of_birth: string | null; // birth date (if known),
    state: AuState | null; // state (if known),
    year_level: string | null; // year level (if known),
    school: string | null; // school (if known),
    goals: string | null; // goals (if any),
    extra_info: string | null; // extra information (if any),
    learning_needs: string | null; // learning needs (if any),
    student_subjects: { subject: string; working_level: string | null }[]; // and their subjects with levels.
  }[]; // (end of the type)
  // Students 16 or over still on a parent's account can get their own login.
  const sixteenAgo = new Date(); // Today's date,
  sixteenAgo.setFullYear(sixteenAgo.getFullYear() - 16); // moved back 16 years.
  const loginReady = studentRows // Students who can get their own login:
    .filter((s) => !s.account_id && s.date_of_birth && s.date_of_birth <= sixteenAgo.toISOString().slice(0, 10)) // no login yet and born at least 16 years ago,
    .map((s) => ({ id: s.id, name: s.full_name })); // each as an id and name.
  const pendingLinks = ( // The parent links waiting:
    (pending.data ?? []) as unknown as (Omit<PendingLink, "parent"> & { // from the rows:
      parent: { account: { full_name: string } | null } | null; // the type, with the parent's name inside an account,
    })[] // (end of the type)
  ).map((l) => ({ ...l, parent: l.parent?.account ?? null })); // each with the parent's name brought up a level.

  // Numbers on the menu where something needs doing (one list for the whole app).
  const todo = await getToDoCounts(viewer.roles); // The to-do numbers.
  const billingToDo = [todo.get("billing", "families"), todo.get("billing", "invoices"), todo.get("billing", "pay")] // Billing's total: families, invoices and pay,
    .reduce<number>((t, n) => t + (n ?? 0), 0); // added up.

  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={viewer.roles} active="admin" />{/* the dashboard tabs, with Admin open, */}
      <SectionShell // the page frame:
        basePath="/admin" // at this address,
        label="Admin" // labelled "Admin",
        role="admin" // in the admin colours,
        section={section} // on the open section,
        sections={visibleSections.map((s) => ({ ...s, count: todo.get("admin", s.id) }))} // with each section's to-do number on the menu.
      >{/* (end of the frame's settings) */}
        <p className="text-sm text-zinc-600">{/* a grey line: */}
          Your admin level: <strong>{ADMIN_LEVEL_NAMES[viewer.level]}</strong>{/* their admin level, */}
          {savedLevel === "operations" && viewer.level === "owner" ? " (emergency owner access)" : ""}{/* noting emergency owner access (if on), */}
          {" · "}{/* a dot, */}
          <TextLink href="/admin/staff">Staff directory</TextLink>{/* a link to the staff directory. */}
        </p>{/* End of the line. */}
        {emergency && savedLevel === "owner" && ( // For the owner, if emergency access is asked for:
          <Card title={emergencyRunning ? "Emergency owner access is running" : "Emergency owner access requested"}>{/* a card (running or requested): */}
            <EmergencyStatus emergency={emergency} running={emergencyRunning} />{/* what it says and when, */}
            {!emergencyRunning && <EmergencyApproveForm id={emergency.id} />}{/* the approve form (if not started), */}
            <EmergencyCancelForm id={emergency.id} label={emergencyRunning ? "End it now" : "Cancel the request"} />{/* the cancel form. */}
          </Card> // End of the card.
        )}{/* End of this part. */}
        {isFull ? ( // For full admins:
          <p className="text-sm">{/* a line: */}
            <TextLink href="/admin/billing">Billing: invoices, payments, credits and pauses</TextLink>{" "}{/* the billing link, then a space, */}
            <CountBadge n={billingToDo} className="bg-admin-strong text-white" />{/* billing's to-do number, */}
            {" · "}{/* a dot, */}
            <TextLink href="/admin/teams">Teams links for online sessions</TextLink>{/* the Teams links link, */}
            {" · "}{/* a dot, */}
            <TextLink href="/admin/materials">Materials library</TextLink>{/* the materials library link. */}
          </p> // End of the line.
        ) : ( // otherwise:
          <p className="text-sm">{/* a line: */}
            <TextLink href="/schedule">Bookings and sessions for every family</TextLink>{/* a link to bookings and sessions. */}
          </p> // End of the line.
        )}{/* End of this part. */}
        {section === "families" && ( // The families section:
          <>{/* (a group) */}
            <Card // the "set up a family" card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Set up a family" // its title,
              description="Fill in a family's details for them, for example during a call, and they get a link to choose a password. Add one child at a time; use the same parent email for each child." // its help text.
            >{/* (end of the card's settings) */}
              <FamilySetupForm />{/* the form. */}
            </Card>{/* End of the card. */}
            <Card // the double-ups card:
              collapsible // can fold,
              defaultOpen={duplicates.length > 0} // open if there are any,
              title={`Possible double-ups (${duplicates.length})`} // its title with the count,
              description="Students with the same name and date of birth, usually because a second parent added a child CLG already has. Their parent's link waits here until you decide." // its help text.
            >{/* (end of the card's settings) */}
              <DuplicateList rows={duplicates} />{/* the double-ups list. */}
            </Card>{/* End of the card. */}
            <Card // the "link another parent" card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Link another parent or guardian" // its title,
              description="For a student with more than one parent or guardian. Each parent sees the same profile, instead of adding the child again." // its help text.
            >{/* (end of the card's settings) */}
              <LinkParentForm // the form:
                students={studentRows.map((s) => ({ id: s.id, name: s.full_name, born: s.date_of_birth }))} // with each student's id, name and birth date.
              />{/* End of the form. */}
            </Card>{/* End of the card. */}
            <Card // the "parents of each student" card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Parents of each student" // its title,
              description="Who can see each student. Remove a link made by mistake here." // its help text.
            >{/* (end of the card's settings) */}
              <ParentLinkList rows={parentLinks} />{/* the list. */}
            </Card>{/* End of the card. */}
            <Card // the "own login" card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Give a student their own login" // its title,
              description="For a student aged 16 or over who is on a parent's account. They keep their details, history and tutor, and their parent can still see everything." // its help text.
            >{/* (end of the card's settings) */}
              <StudentLoginForm students={loginReady} />{/* the form, with students who can get one. */}
            </Card>{/* End of the card. */}
            <Card // the "new login link" card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Send a new login link" // its title,
              description="If a family's or student's link ran out before they used it, send them a new one." // its help text.
            >{/* (end of the card's settings) */}
              <NewLinkForm />{/* the form. */}
            </Card>{/* End of the card. */}
            <Card // the paused families card:
              collapsible // can fold,
              defaultOpen={pausedFamilies.length > 0} // open if there are any,
              title={`Families paused for an overdue bill (${pausedFamilies.length})`} // its title with the count,
              description="Their sessions are on hold until they pay or the owner agrees a new date." // its help text.
            >{/* (end of the card's settings) */}
              {pausedFamilies.length === 0 ? ( // if none:
                <Empty>No family is paused.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="space-y-1 text-sm">{/* a list: */}
                  {pausedFamilies.map((f) => ( // for each:
                    <li key={f.family_id}>{/* a row: */}
                      {f.family_name}{/* the family's name, */}
                      {f.paused_since && // if known,
                        ` (since ${new Date(f.paused_since).toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide" })})`}{/* since when (Adelaide date). */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
            {isFull && (<>{/* For full admins: */}
            <Card // the parent links card:
              title="Parent links to confirm" // its title,
              description={ // its help text:
                <>{/* (a group) */}
                  A parent&apos;s own child is confirmed straight away. Links only wait here when CLG added a
                  parent by hand without confirming, or a double-up is being checked above.{/* (end of the text) */}
                </> // End of the group.
              } // (end of the help text)
            >{/* (end of the card's settings) */}
              {pendingLinks.length === 0 ? ( // if none:
                <Empty>Nothing waiting.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="space-y-2 text-sm">{/* a list: */}
                  {pendingLinks.map((l) => ( // for each link:
                    <li // a row:
                      key={`${l.parent_id}-${l.student_id}`} // one per link,
                      className="flex items-center justify-between gap-4" // styled as a row.
                    >{/* (end of the row's settings) */}
                      <span>{/* (a group) */}
                        {l.parent?.full_name ?? "Parent"} ({l.relationship}) of{" "}{/* the parent and how they're related, then, */}
                        {l.student?.full_name}, born {l.student?.date_of_birth}{/* the child and their birth date. */}
                      </span>{/* End of the group. */}
                      <form action={verifyParentLink}>{/* the confirm form: */}
                        <input // a hidden value:
                          type="hidden" // hidden,
                          name="parent_id" // named parent_id,
                          value={l.parent_id} // the parent.
                        />{/* (end of the value) */}
                        <input // a hidden value:
                          type="hidden" // hidden,
                          name="student_id" // named student_id,
                          value={l.student_id} // the student.
                        />{/* (end of the value) */}
                        <Button type="submit">Confirm</Button>{/* the confirm button. */}
                      </form>{/* End of the form. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card title="Assign a tutor">{/* the "assign a tutor" card: */}
              <p className="text-sm">{/* a line: */}
                Matching now has its own tab. Choose a student there to see the tutors who suit them best and offer a
                time. The tutor sees the student&apos;s details once they and the family accept.{/* (end of the text) */}
              </p>{/* End of the line. */}
              <p className="mt-3">{/* a line: */}
                <TextLink href="/matching">Go to Matching</TextLink>{/* a link to Matching. */}
              </p>{/* End of the line. */}
            </Card>{/* End of the card. */}
            </>)}{/* End of the full admin part. */}
          </> // End of the group.
        )}{/* End of the families section. */}

        {section === "tutors" && ( // The tutors section:
          <>{/* (a group) */}
            <Card // the checks to confirm card:
              collapsible // can fold,
              title={`Checks to confirm (${pendingCheckRows.length})`} // its title with the count,
              description="Checks tutors have added, each with a copy of the certificate. Open the copy, check it against the official record (for a WWCC, the state's online check), then confirm it." // its help text.
            >{/* (end of the card's settings) */}
              {pendingCheckRows.length === 0 ? ( // if none:
                <Empty>Nothing waiting.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="divide-y divide-zinc-100">{/* a list: */}
                  {pendingCheckRows.map((c) => ( // for each check:
                    <li // a row:
                      key={c.id} // one per check,
                      className="space-y-3 py-4 text-sm first:pt-0 last:pb-0" // styled as a row.
                    >{/* (end of the row's settings) */}
                      <div className="flex flex-wrap items-start justify-between gap-3">{/* the top part: */}
                        <div>{/* (a group) */}
                          <p className="font-medium">{/* a bold line: */}
                            {c.tutor?.account?.full_name ?? "Tutor"}:{" "}{/* the tutor's name, then, */}
                            {checkName(c.kind)}{/* the check's name. */}
                          </p>{/* End of the line. */}
                          <p className="text-zinc-600">{/* a grey line: */}
                            {c.reference && `Number ${c.reference} · `}{/* its number (if any), */}
                            {c.completed_on && `Done ${c.completed_on} · `}{/* the date done (if known), */}
                            Due again {c.expires_on}{/* and when it's due again. */}
                          </p>{/* End of the line. */}
                          {c.document_path ? ( // if there's a copy:
                            <a // a link:
                              href={`/checks/${c.id}/document`} // to open it,
                              target="_blank" // in a new tab,
                              rel="noreferrer" // without passing on this page's address,
                              className="mt-1 inline-block font-medium text-teal-800 underline" // styled as a link.
                            >{/* (end of the link's settings) */}
                              Open their copy{/* its words, */}
                            </a> // end of the link.
                          ) : ( // otherwise:
                            <p className="mt-1 text-xs text-zinc-500">No copy attached.</p> // says no copy.
                          )}{/* End of this part. */}
                        </div>{/* End of the group. */}
                        <form action={confirmCheck}>{/* the confirm form: */}
                          <input type="hidden" name="check_id" value={c.id} />{/* the check (hidden), */}
                          <Button type="submit">Confirm</Button>{/* the confirm button. */}
                        </form>{/* End of the form. */}
                      </div>{/* End of the top part. */}
                      <details className="rounded-xl bg-zinc-50 px-4 py-2">{/* a fold-out: */}
                        <summary className="cursor-pointer text-zinc-700">{/* its heading: */}
                          Doesn&apos;t match? Send it back{/* its words, */}
                        </summary>{/* end of the heading. */}
                        <div className="pt-3">{/* a box: */}
                          <DeclineCheckForm checkId={c.id} />{/* the send-back form. */}
                        </div>{/* End of the box. */}
                      </details>{/* End of the fold-out. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="Tutor child safety checks">{/* the check standing card: */}
              {checkRows.length === 0 ? ( // if none:
                <Empty>{/* a line: */}
                  No tutors yet. Checks appear here once tutors are added.{/* says no tutors yet. */}
                </Empty> // End of the line.
              ) : ( // otherwise:
                <Table headings={["Tutor", "Check", "Expires", "Status"]}>{/* a table: */}
                  {checkRows.map((c) => ( // for each check:
                    <tr // a row:
                      key={`${c.tutor_id}-${c.kind}`} // one per tutor and check,
                      className={c.status === "current" ? "" : "text-red-700"} // red if not current.
                    >{/* (end of the row's settings) */}
                      <td className="font-medium">{c.full_name}</td>{/* the tutor's name, */}
                      <td>{checkName(c.kind)}</td>{/* the check's name, */}
                      <td>{c.expires_on ?? "-"}</td>{/* its expiry (or a dash), */}
                      <td>{c.status.replace("_", " ")}</td>{/* its status in words. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="Record a check">{/* the "record a check" card: */}
              <CheckForm tutors={tutors} />{/* the form. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="States each tutor is cleared for">{/* the cleared states card: */}
              <ul className="space-y-1 text-sm">{/* a list: */}
                {tutors.map((t) => ( // for each tutor:
                  <li key={t.id}>{/* a row: */}
                    {t.name}:{" "}{/* their name, then, */}
                    {(statesByTutor.get(t.id) ?? []).join(", ") || "none yet"}{/* their states (or none yet). */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="What each tutor teaches" description="Tutors add these themselves in their dashboard.">{/* the "what each tutor teaches" card: */}
              <ul className="space-y-1 text-sm">{/* a list: */}
                {tutors.map((t) => ( // for each tutor:
                  <li key={t.id}>{/* a row: */}
                    {t.name}: {(teachingByTutor.get(t.id) ?? []).join(", ") || "not added yet"}{/* their name and subjects (or not added yet). */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="Tutor work state">{/* the work state card: */}
              <WorkStateForm tutors={tutors} />{/* the form. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="Tutor finished with CLG">{/* the "tutor finished" card: */}
              <TutorLeftForm tutors={tutors} />{/* the form. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the tutors section. */}

        {section === "curriculum" && ( // The curriculum section:
          <>{/* (a group) */}
            {drafts.length > 0 && ( // If there are drafts:
              <Card // a card:
                title={`Curricula to check and confirm (${drafts.length})`} // its title with the count,
                description="Each one is a draft until you confirm it. Open one to see how many skills it has for each year, then confirm it so tutors can use it in goals." // its help text.
              >{/* (end of the card's settings) */}
                <ul className="divide-y divide-zinc-100">{/* a list: */}
                  {drafts.map((d) => { // for each draft:
                    const total = d.summary.reduce((n, r) => n + Number(r.skills), 0); // its total number of skills,
                    return ( // shows:
                      <li key={d.id} className="py-3 first:pt-0">{/* a row: */}
                        <details>{/* a fold-out: */}
                          <summary className="cursor-pointer text-sm">{/* its heading: */}
                            <span className="font-medium">{d.name}</span>{" "}{/* the name, then a space, */}
                            <span className="text-zinc-600">({total.toLocaleString("en-AU")} skills)</span>{/* the skill count. */}
                          </summary>{/* End of the heading. */}
                          <div className="mt-3 space-y-3">{/* a box: */}
                            {total === 0 ? ( // if no skills:
                              <Empty>No skills loaded yet.</Empty> // says so.
                            ) : ( // otherwise:
                              <div className="max-h-64 overflow-y-auto">{/* a scrolling box: */}
                                <Table headings={["Subject", "Year or level", "Skills"]}>{/* a table: */}
                                  {d.summary.map((r) => ( // for each subject and level:
                                    <tr key={`${r.subject}-${r.level_band}`}>{/* a row: */}
                                      <td className="font-medium">{r.subject}</td>{/* the subject, */}
                                      <td>{r.level_band}</td>{/* the year or level, */}
                                      <td>{r.skills}</td>{/* the skill count. */}
                                    </tr> // End of the row.
                                  ))}{/* End of the loop. */}
                                </Table>{/* End of the table. */}
                              </div> // End of the scrolling box.
                            )}{/* End of this part. */}
                            {d.source && <p className="text-xs text-zinc-500">Source: {d.source}</p>}{/* where it came from (if known). */}
                          </div>{/* End of the box. */}
                        </details>{/* End of the fold-out. */}
                        <div className="mt-2 flex flex-wrap gap-3">{/* a row of buttons: */}
                          {total > 0 && ( // if it has skills:
                            <form action={confirmCurriculum}>{/* the confirm form: */}
                              <input type="hidden" name="framework_id" value={d.id} />{/* the curriculum (hidden), */}
                              <BusyButton type="submit" className="text-sm font-medium text-teal-800 underline hover:font-bold hover:text-teal-950">{/* the confirm button: */}
                                Confirm{/* its words, */}
                              </BusyButton>{/* end of the button. */}
                            </form> // End of the form.
                          )}{/* End of this part. */}
                          <form action={discardCurriculum}>{/* the throw-away form: */}
                            <input type="hidden" name="framework_id" value={d.id} />{/* the curriculum (hidden), */}
                            <BusyButton type="submit" className="text-sm text-red-700 underline hover:font-bold hover:text-red-900">{/* the button: */}
                              Throw away{/* its words, */}
                            </BusyButton>{/* end of the button. */}
                          </form>{/* End of the form. */}
                        </div>{/* End of the row of buttons. */}
                      </li> // End of the row.
                    ); // End of what's shown for this draft.
                  })}{/* End of the loop. */}
                </ul>{/* End of the list. */}
                {drafts.length > 1 && ( // If more than one draft:
                  <form action={confirmAllCurricula} className="mt-4">{/* the confirm-all form: */}
                    <Button type="submit">Confirm all {drafts.length}</Button>{/* the button, with the count. */}
                  </form> // End of the form.
                )}{/* End of this part. */}
              </Card> // End of the card.
            )}{/* End of this part. */}

            <Card // the upload card:
              title="Upload a curriculum" // its title,
              description="Load a whole curriculum at once. Each one arrives as a draft for you to check and confirm." // its help text.
            >{/* (end of the card's settings) */}
              <SubHeading>Australian Curriculum (Reception to Year 10)</SubHeading>{/* a small heading, */}
              <AcaraImportForm loadedCodes={frameworks.map((f) => f.code)} />{/* the Australian Curriculum loader (knowing which are loaded), */}
              <SubHeading>Any other curriculum, such as SACE for Years 11 and 12</SubHeading>{/* a small heading, */}
              <CurriculumFileForm />{/* the file upload form. */}
            </Card>{/* End of the card. */}

            <Card // the curriculum list card:
              collapsible defaultOpen={false} title="Curriculum and skills" // folded to start, with its title,
              description="Goals are built from these skills. Load each curriculum once, confirm it, then set which one applies to each student." // its help text.
            >{/* (end of the card's settings) */}
              {frameworks.length === 0 ? ( // if none:
                <Empty>No curriculum loaded yet.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="mb-2 space-y-1 text-sm">{/* a list: */}
                  {frameworks.map((f) => ( // for each curriculum:
                    <li // a row:
                      key={f.id} // one per curriculum,
                      className="flex flex-wrap items-center gap-2" // styled as a row.
                    >{/* (end of the row's settings) */}
                      <span className="font-medium">{f.name}</span>{/* its name, */}
                      {f.confirmed ? ( // if confirmed:
                        <span className="rounded-full bg-teal-50 px-2 text-xs text-teal-800">{/* a tag: */}
                          In use{/* "In use", */}
                        </span> // end of the tag.
                      ) : ( // otherwise:
                        <span className="rounded-full bg-zinc-100 px-2 text-xs text-zinc-600">{/* a tag: */}
                          Draft{/* "Draft", */}
                        </span> // end of the tag.
                      )}{/* End of this part. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
              <SubHeading>Load skills by pasting rows</SubHeading>{/* a small heading, */}
              <ImportSkillsForm frameworks={frameworkOptions} />{/* the paste-skills form, */}
              <SubHeading>Add a curriculum</SubHeading>{/* a small heading, */}
              <FrameworkForm />{/* the add-a-curriculum form. */}
            </Card>{/* End of the card. */}

            <Card // the student curriculum card:
              title="Set a student's curriculum" // its title,
              description="Choose which confirmed curriculum each student follows. A student can have more than one." // its help text.
            >{/* (end of the card's settings) */}
              <StudentFrameworkForm // the form:
                students={studentRows.map((s) => ({ // the students:
                  id: s.id, // each id,
                  name: `${s.full_name} (${s.state ?? "details not finished"})`, // and name with state.
                }))} // (end of the students)
                frameworks={confirmedOptions} // the confirmed curricula.
              />{/* End of the form. */}
            </Card>{/* End of the card. */}

            <Card // the "link skills" card:
              collapsible // can fold,
              defaultOpen={false} // folded to start,
              title="Link skills to a student" // its title,
              description="Open a student's progress page and use Add a goal to choose the skills they're working on. Set their curriculum first." // its help text.
            >{/* (end of the card's settings) */}
              {studentRows.length === 0 ? ( // if no students:
                <Empty>No students yet.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="space-y-1 text-sm">{/* a list: */}
                  {studentRows.map((s) => ( // for each student:
                    <li key={s.id}>{/* a row: */}
                      <TextLink href={`/students/${s.id}/progress`}>{s.full_name}</TextLink>{" "}{/* a link to their progress page, then a space, */}
                      <span className="text-zinc-500">({s.state ?? "details not finished"})</span>{/* their state. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the curriculum section. */}

        {section === "progress" && ( // The progress section:
          <>{/* (a group) */}
            <ProgressSection from={params.from} to={params.to} />{/* the progress reports (with the dates from the address), */}
            <AddOnsSection isOwner={isOwner} />{/* and the add-ons. */}
          </> // End of the group.
        )}{/* End of the progress section. */}

        {section === "staff" && ( // The staff section:
          <>{/* (a group) */}
            <Card // the staff card:
              title="Staff and levels" // its title,
              description="Owner: everything. Operations: day-to-day. Support: families and bookings. Finance: invoices and pay." // what each level does.
            >{/* (end of the card's settings) */}
              <p className="mb-4 text-sm">{/* a line: */}
                <TextLink href="/admin/staff">Open the staff directory</TextLink> to search staff and set job titles.{/* a link to the staff directory and what it's for. */}
              </p>{/* End of the line. */}
              {staffRows.length === 0 ? ( // if no staff:
                <Empty>No staff yet.</Empty> // says so.
              ) : ( // otherwise:
                <Table headings={["Name", "Email", "Tutor", "Admin"]}>{/* a table: */}
                  {staffRows.map((p) => ( // for each person:
                    <tr key={p.account_id}>{/* a row: */}
                      <td>{p.full_name}</td>{/* their name, */}
                      <td>{p.email ?? ""}</td>{/* their email, */}
                      <td>{p.is_tutor ? (p.tutor_active === false ? "Finished" : "Yes") : "No"}</td>{/* tutor: finished, yes or no, */}
                      <td>{/* the admin cell: */}
                        {isOwner && p.admin_level && p.admin_level !== "owner" && p.account_id !== viewer.id ? ( // the owner can change other admins' levels (not the owner's or their own):
                          <SetLevelForm accountId={p.account_id} level={p.admin_level} /> // the level form.
                        ) : p.admin_level ? ( // otherwise, if an admin:
                          <LevelBadge level={p.admin_level} /> // their level badge.
                        ) : ( // otherwise:
                          "No" // "No".
                        )}{/* End of this part. */}
                      </td>{/* End of the cell. */}
                    </tr> // End of the row.
                  ))}{/* End of the loop. */}
                </Table> // End of the table.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card title="Add staff">{/* the "add staff" card: */}
              <InviteForm canInviteAdmins={isOwner} />{/* the invite form (only the owner can invite admins). */}
            </Card>{/* End of the card. */}

            {savedLevel === "operations" && ( // For operations admins:
              <Card // a card:
                title="Emergency owner access" // its title,
                description="If the owner can't be reached and something only the owner can do is urgent, ask for owner access here." // its help text.
              >{/* (end of the card's settings) */}
                {emergency ? ( // if a request exists:
                  <>{/* (a group) */}
                    <EmergencyStatus emergency={emergency} running={emergencyRunning} />{/* what it says and when, */}
                    {emergency.requested_by === viewer.id && ( // if they asked:
                      <EmergencyCancelForm id={emergency.id} label="Withdraw my request" /> // the withdraw form.
                    )}{/* End of this part. */}
                  </> // End of the group.
                ) : ( // otherwise:
                  <EmergencyRequestForm /> // the request form.
                )}{/* End of this part. */}
              </Card> // End of the card.
            )}{/* End of this part. */}

            <Card // the invitations card:
              title="Invitations not used yet" // its title,
              description="Each link works once, for 7 days, only for that email. To send a new link, add the person again above." // its help text.
            >{/* (end of the card's settings) */}
              {openInvites.length === 0 ? ( // if none:
                <Empty>No invitations waiting.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="divide-y divide-zinc-100 text-sm">{/* a list: */}
                  {openInvites.map((i) => { // for each invitation:
                    const expired = new Date(i.expires_at) <= new Date(); // whether it has expired,
                    return ( // shows:
                      <li key={i.id} className="flex flex-wrap items-center justify-between gap-3 py-2">{/* a row: */}
                        <span>{/* (a group) */}
                          <span className="font-medium">{i.email}</span> as {i.role}{/* the email and role, */}
                          <span className="text-zinc-500">{/* in grey: */}
                            {" "}{/* a space, */}
                            · {expired ? "expired" : `works until ${new Date(i.expires_at).toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide" })}`}{/* expired, or works until when (Adelaide date). */}
                          </span>{/* End of the grey part. */}
                        </span>{/* End of the group. */}
                        <form action={cancelInvitation}>{/* the cancel form: */}
                          <input type="hidden" name="id" value={i.id} />{/* the invitation (hidden), */}
                          <Button type="submit">Cancel</Button>{/* the cancel button. */}
                        </form>{/* End of the form. */}
                      </li> // End of the row.
                    ); // End of what's shown for this invitation.
                  })}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card title="Unlock an account">{/* the unlock card: */}
              <UnlockForm />{/* the form. */}
            </Card>{/* End of the card. */}
          </> // End of the group.
        )}{/* End of the staff section. */}

        {section === "leaving" && <LeavingSection />}{/* The people-leaving section. */}

        {section === "records" && ( // The records section:
          <>{/* (a group) */}
            <Card // the privacy card:
              title="Privacy requests and breaches" // its title,
              description="Requests from families and staff to see, fix or delete information, and the register of suspected data breaches with their deadlines." // its help text.
            >{/* (end of the card's settings) */}
              <TextLink href="/admin/privacy">Open privacy requests and the breach register</TextLink>{" "}{/* a link to privacy requests, then a space, */}
              <CountBadge // the to-do badge:
                n={(todo.get("privacy", "requests") ?? 0) + (todo.get("privacy", "incidents") ?? 0)} // requests plus breaches,
                className="bg-admin-strong text-white" // styled for admins.
              />{/* (end of the badge) */}
            </Card>{/* End of the card. */}

            <Card // the deletion card:
              title="Records due for deletion" // its title,
              description={ // its help text:
                <>{/* (a group) */}
                  The app deletes records automatically each night once CLG no
                  longer needs them. These are due in the next 30 days. Place a
                  hold to keep any of them, for example while a complaint or
                  concern is open.{/* (end of the text) */}
                </> // End of the group.
              } // (end of the help text)
            >{/* (end of the card's settings) */}
              {dueRows.length === 0 ? ( // if none due:
                <Empty>Nothing due in the next 30 days.</Empty> // says so.
              ) : ( // otherwise:
                <>{/* (a group) */}
                  <div className="mb-6">{/* a box: */}
                    <Table headings={["Name", "Type", "Deleted on"]}>{/* a table: */}
                      {dueRows.map((d) => ( // for each record:
                        <tr key={`${d.kind}-${d.record_id}`}>{/* a row: */}
                          <td className="font-medium">{d.full_name}</td>{/* the name, */}
                          <td>{DUE_LABELS[d.kind]}</td>{/* the kind, */}
                          <td>{d.due_on}</td>{/* when it's deleted. */}
                        </tr> // End of the row.
                      ))}{/* End of the loop. */}
                    </Table>{/* End of the table. */}
                  </div>{/* End of the box. */}
                  <HoldForm // the hold form:
                    due={dueRows.map((d) => ({ // the records due:
                      value: `${d.kind === "student" ? "student" : "account"}:${d.record_id}`, // each as kind and id,
                      label: `${d.full_name} (${DUE_LABELS[d.kind].toLowerCase()})`, // with a name and kind label.
                    }))} // (end of the records)
                  />{/* End of the form. */}
                </> // End of the group.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card title="Holds">{/* the holds card: */}
              {holdRows.length === 0 ? ( // if none:
                <Empty>No holds in place.</Empty> // says so.
              ) : ( // otherwise:
                <ul className="space-y-2 text-sm">{/* a list: */}
                  {holdRows.map((h) => ( // for each hold:
                    <li // a row:
                      key={h.id} // one per hold,
                      className="flex items-center justify-between gap-4" // styled as a row.
                    >{/* (end of the row's settings) */}
                      <span>{/* (a group) */}
                        {h.student?.full_name ?? // the student's name,
                          h.account?.full_name ?? // or the account's,
                          "Deleted record"}{/* or "Deleted record", */}
                        : {h.reason} (since {h.placed_at.slice(0, 10)}){/* then why and since when. */}
                      </span>{/* End of the group. */}
                      <form action={releaseHold}>{/* the release form: */}
                        <input type="hidden" name="hold_id" value={h.id} />{/* the hold (hidden), */}
                        <Button type="submit">Release</Button>{/* the release button. */}
                      </form>{/* End of the form. */}
                    </li> // End of the row.
                  ))}{/* End of the loop. */}
                </ul> // End of the list.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            <Card collapsible defaultOpen={false} title="How long records are kept">{/* the "how long records are kept" card: */}
              <ul className="mb-4 space-y-1 text-sm">{/* a list: */}
                {ruleRows.map((r) => ( // for each kind:
                  <li key={r.kind}>{/* a row: */}
                    <strong>{/* in bold: */}
                      {RULE_LABELS[r.kind] ?? r.kind}: {plainPeriod(r.keep_for)}{/* its name and how long, */}
                      .{/* then a full stop. */}
                    </strong>{" "}{/* End of the bold part, then a space. */}
                    {r.description}{/* what it covers. */}
                  </li> // End of the row.
                ))}{/* End of the loop. */}
              </ul>{/* End of the list. */}
              {isOwner && ( // For the owner:
                <RetentionPeriodForm // the change form:
                  rules={ruleRows.map((r) => ({ // the kinds:
                    kind: r.kind, // each kind,
                    label: RULE_LABELS[r.kind] ?? r.kind, // with its name.
                  }))} // (end of the kinds)
                /> // End of the form.
              )}{/* End of this part. */}
            </Card>{/* End of the card. */}

            {isOwner && ( // For the owner:
              <Card // a card:
                collapsible // can fold,
                defaultOpen={false} // folded to start,
                title="Remove a role or delete an account" // its title,
                description="For when someone's role changes (for example a tutor who becomes an admin only), or to clear test accounts." // its help text.
              >{/* (end of the card's settings) */}
                <RemoveRoleForm />{/* the remove-role form. */}
              </Card> // End of the card.
            )}{/* End of this part. */}

            {isOwner && ( // For the owner:
              <Card // a card:
                title="Delete a student on request" // its title,
                description={ // its help text:
                  <>{/* (a group) */}
                    When a family asks for their child&apos;s information to be
                    deleted. Billing and child safety records kept elsewhere are
                    not affected.{/* (end of the text) */}
                  </> // End of the group.
                } // (end of the help text)
              >{/* (end of the card's settings) */}
                <EraseStudentForm // the delete form:
                  students={studentRows.map((s) => ({ // the students:
                    id: s.id, // each id,
                    name: s.full_name, // and name.
                  }))} // (end of the students)
                />{/* End of the form. */}
              </Card> // End of the card.
            )}{/* End of this part. */}
          </> // End of the group.
        )}{/* End of the records section. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of AdminPage.

// What an emergency owner access request says, and when it starts or ends.
function EmergencyStatus({ // Takes:
  emergency, // the request,
  running, // and whether it's running.
}: { // The types of those:
  emergency: { requested_at: string; starts_at: string; ends_at: string; reason: string; requester: { full_name: string } | null }; // when asked, starts, ends, why and who,
  running: boolean; // yes or no.
}) { // End of the types.
  const when = (iso: string) => // Shows a time in Adelaide:
    new Date(iso).toLocaleString("en-AU", { // in Australian style:
      timeZone: "Australia/Adelaide", // Adelaide time,
      weekday: "short", // short weekday,
      day: "numeric", // day number,
      month: "short", // short month,
      hour: "numeric", // hour,
      minute: "2-digit", // minutes.
    }); // (end of the format)
  const hoursLeft = Math.max(0, Math.ceil((new Date(running ? emergency.ends_at : emergency.starts_at).getTime() - new Date().getTime()) / 3600000)); // Hours left until it ends (if running) or starts (if not).
  return ( // Shows:
    <div className="mb-4 space-y-1 text-sm">{/* a box: */}
      <p>{/* a line: */}
        <strong>{emergency.requester?.full_name ?? "An admin"}</strong> asked on {when(emergency.requested_at)}.{/* who asked and when. */}
      </p>{/* End of the line. */}
      <p>{/* a line: */}
        <strong>Reason:</strong> {emergency.reason}{/* the reason. */}
      </p>{/* End of the line. */}
      <p>{/* a line: */}
        {running // if running,
          ? `Owner access is on until ${when(emergency.ends_at)} (about ${hoursLeft} hr left). Then it ends by itself.` // when it ends and hours left,
          : `Owner access starts ${when(emergency.starts_at)} (in about ${hoursLeft} hr) unless the owner cancels it or approves it sooner. It then lasts 7 days.`}{/* otherwise when it starts and how long it lasts. */}
      </p>{/* End of the line. */}
      <p className="text-xs text-zinc-500">Adelaide time. Everything done with owner access is recorded in the activity log.</p>{/* a note about Adelaide time and the activity log. */}
    </div> // End of the box.
  ); // End of what's shown.
} // End of EmergencyStatus.
