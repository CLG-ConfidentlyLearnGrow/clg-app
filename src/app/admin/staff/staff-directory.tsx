"use client";

import { useActionState, useMemo, useState } from "react";
import { cancelInvitation } from "@/app/actions/admin";
import { addRole, removeRole, resendStaffInvite, sendStaffLoginLink, setJobTitle } from "@/app/actions/staff-directory";
import { Empty } from "@/components/ui";
import { initialFormState, type FormState } from "@/lib/forms";
import { SetLevelForm } from "../level-forms";

export type StaffMember = {
  account_id: string;
  full_name: string;
  email: string | null;
  job_title: string | null;
  is_tutor: boolean;
  is_admin: boolean;
  is_parent: boolean;
  is_student: boolean;
  admin_level: "owner" | "operations" | "support" | "finance" | null;
  tutor_active: boolean | null;
  work_state: string | null;
  subjects: string[];
  last_sign_in_at: string | null;
};

export type Invitation = {
  id: string;
  email: string;
  role: "tutor" | "admin";
  admin_level: string | null;
  expires_at: string;
};

const LEVEL_NAMES: Record<string, string> = {
  owner: "Owner",
  operations: "Operations admin",
  support: "Support admin",
  finance: "Finance admin",
};

// Job titles offered as suggestions when typing, alongside any already used.
const SUGGESTED_TITLES = ["Director", "Child Safety Officer", "Operations coordinator", "Office support", "Bookkeeper", "Tutor", "Senior tutor"];

const NO_TITLE = "__none__";

// A tutor who has finished with CLG and has no admin role.
function isFinished(p: StaffMember) {
  return !p.is_admin && p.is_tutor && p.tutor_active === false;
}

// What the person does in the app, in plain words.
function appRoles(p: StaffMember): string[] {
  const out: string[] = [];
  if (p.is_admin) out.push(p.admin_level ? LEVEL_NAMES[p.admin_level] : "Admin");
  if (p.is_tutor) out.push(p.tutor_active === false ? "Tutor (finished)" : "Tutor");
  if (p.is_parent) out.push("Parent");
  if (p.is_student) out.push("Student");
  return out;
}

function invitationRole(i: Invitation) {
  return i.role === "admin" ? `${LEVEL_NAMES[i.admin_level ?? "operations"] ?? "Admin"}` : "Tutor";
}

function plainDate(iso: string) {
  return new Date(iso).toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide" });
}

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none";
const smallButton =
  "rounded-full bg-teal-700 px-4 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-teal-900 disabled:opacity-50";
const plainButton = "rounded-full border border-zinc-300 px-4 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50 disabled:opacity-50";
const linkButton = "text-sm font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700";
const pill = "inline-block rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-800";

function FilterSelect({
  label,
  value,
  onChange,
  children,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      <select className={inputClass} value={value} onChange={(e) => onChange(e.target.value)}>
        {children}
      </select>
    </label>
  );
}

// The result of an action, shown under its form. Long messages (such as a
// link to copy) wrap.
function Result({ state }: { state: FormState }) {
  if (state.error)
    return (
      <p role="alert" className="text-sm text-red-700">
        {state.error}
      </p>
    );
  if (state.message)
    return (
      <p role="status" className="text-sm text-teal-800 [overflow-wrap:anywhere]">
        {state.message}
      </p>
    );
  return null;
}

export function StaffDirectory({
  staff,
  invitations,
  canEdit,
  isOwner,
  viewerId,
}: {
  staff: StaffMember[];
  invitations: Invitation[];
  canEdit: boolean;
  isOwner: boolean;
  viewerId: string;
}) {
  const [search, setSearch] = useState("");
  const [role, setRole] = useState("all");
  const [title, setTitle] = useState("all");
  const [status, setStatus] = useState("current");
  const [state, setState] = useState("all");
  const [subject, setSubject] = useState("all");

  const titles = useMemo(
    () => [...new Set(staff.map((p) => p.job_title).filter((t): t is string => Boolean(t)))].sort((a, b) => a.localeCompare(b)),
    [staff],
  );
  const states = useMemo(
    () => [...new Set(staff.map((p) => p.work_state).filter((s): s is string => Boolean(s)))].sort(),
    [staff],
  );
  const subjects = useMemo(
    () => [...new Set(staff.flatMap((p) => p.subjects))].sort((a, b) => a.localeCompare(b)),
    [staff],
  );
  const suggestions = useMemo(() => [...new Set([...titles, ...SUGGESTED_TITLES])], [titles]);
  const words = search.trim().toLowerCase().split(/\s+/).filter(Boolean);

  const shown = staff.filter((p) => {
    if (status === "invited") return false;
    if (status === "current" && isFinished(p)) return false;
    if (status === "finished" && !isFinished(p)) return false;
    if (status === "never" && p.last_sign_in_at) return false;
    if (role === "tutor" && !p.is_tutor) return false;
    if (role === "admin" && !p.is_admin) return false;
    if (role === "parent" && !p.is_parent) return false;
    if (["owner", "operations", "support", "finance"].includes(role) && p.admin_level !== role) return false;
    if (title === NO_TITLE && p.job_title) return false;
    if (title !== "all" && title !== NO_TITLE && p.job_title !== title) return false;
    if (state !== "all" && p.work_state !== state) return false;
    if (subject !== "all" && !p.subjects.includes(subject)) return false;
    if (words.length) {
      const text = [p.full_name, p.email ?? "", p.job_title ?? "", ...appRoles(p), ...p.subjects, p.work_state ?? ""]
        .join(" ")
        .toLowerCase();
      if (!words.every((w) => text.includes(w))) return false;
    }
    return true;
  });

  // Invitations have no job title, state or subject yet, so those filters hide them.
  const shownInvites = invitations.filter((i) => {
    if (!["current", "invited", "all"].includes(status)) return false;
    if (title !== "all" || state !== "all" || subject !== "all") return false;
    if (role === "tutor" && i.role !== "tutor") return false;
    if (role === "admin" && i.role !== "admin") return false;
    if (role === "parent" || role === "owner") return false;
    if (["operations", "support", "finance"].includes(role) && (i.role !== "admin" || i.admin_level !== role)) return false;
    if (words.length) {
      const text = `${i.email} ${invitationRole(i)} invited`.toLowerCase();
      if (!words.every((w) => text.includes(w))) return false;
    }
    return true;
  });

  const filtered = search.trim() !== "" || role !== "all" || title !== "all" || status !== "current" || state !== "all" || subject !== "all";
  function clear() {
    setSearch("");
    setRole("all");
    setTitle("all");
    setStatus("current");
    setState("all");
    setSubject("all");
  }

  return (
    <div className="space-y-6">
      <section className="rounded-2xl border border-zinc-200/80 bg-white p-6 shadow-[0_1px_3px_rgba(65,64,66,0.06),0_8px_24px_-12px_rgba(65,64,66,0.12)]">
        <label className="block space-y-1">
          <span className="text-sm font-medium text-zinc-800">Search</span>
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Name, email, job title or subject"
            className={inputClass}
          />
        </label>
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <FilterSelect label="Role in the app" value={role} onChange={setRole}>
            <option value="all">Everyone</option>
            <option value="tutor">Tutors</option>
            <option value="admin">All admins</option>
            <option value="owner">Owner</option>
            <option value="operations">Operations admins</option>
            <option value="support">Support admins</option>
            <option value="finance">Finance admins</option>
            <option value="parent">Also a parent</option>
          </FilterSelect>
          <FilterSelect label="Job title" value={title} onChange={setTitle}>
            <option value="all">Any job title</option>
            {titles.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
            <option value={NO_TITLE}>No job title yet</option>
          </FilterSelect>
          <FilterSelect label="Status" value={status} onChange={setStatus}>
            <option value="current">Working now</option>
            {canEdit && <option value="invited">Invited, not joined yet</option>}
            <option value="never">Never signed in</option>
            <option value="finished">Finished</option>
            <option value="all">Everyone</option>
          </FilterSelect>
          <FilterSelect label="Works in (tutors)" value={state} onChange={setState}>
            <option value="all">Any state</option>
            {states.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </FilterSelect>
          <FilterSelect label="Teaches (tutors)" value={subject} onChange={setSubject}>
            <option value="all">Any subject</option>
            {subjects.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </FilterSelect>
        </div>
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm text-zinc-600">
          <p role="status">
            Showing {shown.length} of {staff.length} staff
            {canEdit && invitations.length > 0 ? `, and ${shownInvites.length} of ${invitations.length} invited` : ""}
          </p>
          {filtered && (
            <button type="button" onClick={clear} className={linkButton}>
              Clear search and filters
            </button>
          )}
        </div>
      </section>

      {canEdit && (
        <datalist id="job-title-suggestions">
          {suggestions.map((t) => (
            <option key={t} value={t} />
          ))}
        </datalist>
      )}

      {shownInvites.length > 0 && (
        <section>
          <h2 className="mb-3 text-sm font-semibold text-zinc-800">Invited, not joined yet</h2>
          <ul className="grid items-start gap-4 md:grid-cols-2">
            {shownInvites.map((i) => (
              <InvitationCard key={i.id} invitation={i} />
            ))}
          </ul>
        </section>
      )}

      {staff.length === 0 ? (
        <Empty>No staff yet. Add tutors and admins in Staff and accounts.</Empty>
      ) : shown.length === 0 ? (
        status === "invited" ? null : <Empty>Nobody matches. Try fewer words or clear the filters.</Empty>
      ) : (
        <section>
          {shownInvites.length > 0 && <h2 className="mb-3 text-sm font-semibold text-zinc-800">Staff</h2>}
          <ul className="grid items-start gap-4 md:grid-cols-2">
            {shown.map((p) => (
              <StaffCard key={p.account_id} person={p} canEdit={canEdit} isOwner={isOwner} isMe={p.account_id === viewerId} />
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function InvitationCard({ invitation: i }: { invitation: Invitation }) {
  const [state, formAction, pending] = useActionState(resendStaffInvite, initialFormState);
  const expired = new Date(i.expires_at) <= new Date();
  return (
    <li className="rounded-2xl border border-dashed border-zinc-300 bg-white p-5">
      <p className="text-base font-semibold tracking-tight [overflow-wrap:anywhere]">{i.email}</p>
      <div className="mt-2 flex flex-wrap gap-1.5">
        <span className={pill}>{invitationRole(i)}</span>
        <span className={pill}>{expired ? "Link ran out" : `Link works until ${plainDate(i.expires_at)}`}</span>
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        <form action={formAction}>
          <input type="hidden" name="id" value={i.id} />
          <button type="submit" disabled={pending} className={smallButton}>
            {pending ? "Sending…" : "Send a new invite"}
          </button>
        </form>
        <form action={cancelInvitation}>
          <input type="hidden" name="id" value={i.id} />
          <button type="submit" className={plainButton}>
            Cancel invite
          </button>
        </form>
      </div>
      <p className="mt-2 text-xs text-zinc-500">A new invite works once, for 7 days. The old link stops working.</p>
      <div className="mt-2">
        <Result state={state} />
      </div>
    </li>
  );
}

function StaffCard({
  person: p,
  canEdit,
  isOwner,
  isMe,
}: {
  person: StaffMember;
  canEdit: boolean;
  isOwner: boolean;
  isMe: boolean;
}) {
  const [open, setOpen] = useState(false);
  return (
    <li className="rounded-2xl border border-zinc-200/80 bg-white p-5 shadow-[0_1px_3px_rgba(65,64,66,0.06)]">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-base font-semibold tracking-tight">{p.full_name}</p>
          <p className={`text-sm ${p.job_title ? "text-zinc-800" : "text-zinc-500 italic"}`}>{p.job_title ?? "No job title yet"}</p>
        </div>
        {canEdit && (
          <button
            type="button"
            onClick={() => setOpen((o) => !o)}
            className={linkButton}
            aria-expanded={open}
            aria-label={`${open ? "Close" : "Manage"} ${p.full_name}`}
          >
            {open ? "Close" : "Manage"}
          </button>
        )}
      </div>
      <div className="mt-3 flex flex-wrap gap-1.5">
        {appRoles(p).map((r) => (
          <span key={r} className={pill}>
            {r}
          </span>
        ))}
        {p.work_state && <span className={pill}>{p.work_state}</span>}
        {!p.last_sign_in_at && <span className="inline-block rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-900">Never signed in</span>}
      </div>
      {p.subjects.length > 0 && <p className="mt-2 text-sm text-zinc-600">Teaches: {p.subjects.join(", ")}</p>}
      {p.email && (
        <p className="mt-2 text-sm [overflow-wrap:anywhere]">
          <a href={`mailto:${p.email}`} className="text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700">
            {p.email}
          </a>
        </p>
      )}
      {open && (
        <div className="mt-4 space-y-5 border-t border-zinc-100 pt-4">
          <JobTitleForm person={p} />
          <LoginLinkForm person={p} />
          <RolesPanel person={p} isOwner={isOwner} isMe={isMe} />
        </div>
      )}
    </li>
  );
}

function JobTitleForm({ person }: { person: StaffMember }) {
  const [state, formAction, pending] = useActionState(setJobTitle, initialFormState);
  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="account_id" value={person.account_id} />
      <label className="block space-y-1">
        <span className="text-sm font-medium text-zinc-800">Job title</span>
        <span className="flex gap-2">
          <input name="job_title" defaultValue={person.job_title ?? ""} maxLength={80} list="job-title-suggestions" className={inputClass} />
          <button type="submit" disabled={pending} className={smallButton}>
            {pending ? "Saving…" : "Save"}
          </button>
        </span>
        <span className="block text-xs text-zinc-500">For example: Tutor, Operations coordinator. Leave blank to remove.</span>
      </label>
      <Result state={state} />
    </form>
  );
}

function LoginLinkForm({ person }: { person: StaffMember }) {
  const [state, formAction, pending] = useActionState(sendStaffLoginLink, initialFormState);
  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="account_id" value={person.account_id} />
      <p className="text-sm font-medium text-zinc-800">Login link</p>
      <p className="text-xs text-zinc-500">
        {person.last_sign_in_at
          ? "Emails them a link to set a new password, for example if they're locked out."
          : "They haven't signed in yet. Emails them a new link to choose a password."}
      </p>
      <button type="submit" disabled={pending} className={plainButton}>
        {pending ? "Sending…" : person.last_sign_in_at ? "Send a password link" : "Send a new login link"}
      </button>
      <Result state={state} />
    </form>
  );
}

// Each role the person has, with Remove (owner only), and roles that can be
// added. Removing asks for the person's name to be typed, as elsewhere.
function RolesPanel({ person: p, isOwner, isMe }: { person: StaffMember; isOwner: boolean; isMe: boolean }) {
  const held: { role: "admin" | "tutor" | "parent" | "student"; label: string; canRemove: boolean; why?: string }[] = [];
  if (p.is_admin)
    held.push({
      role: "admin",
      label: p.admin_level ? LEVEL_NAMES[p.admin_level] : "Admin",
      canRemove: isOwner && !isMe && p.admin_level !== "owner",
      why: p.admin_level === "owner" ? "The owner's admin role can't be removed." : isMe ? "You can't remove your own admin role." : undefined,
    });
  if (p.is_tutor) held.push({ role: "tutor", label: p.tutor_active === false ? "Tutor (finished)" : "Tutor", canRemove: isOwner && p.tutor_active !== false });
  if (p.is_parent) held.push({ role: "parent", label: "Parent", canRemove: isOwner });
  if (p.is_student) held.push({ role: "student", label: "Student", canRemove: isOwner });

  return (
    <div className="space-y-3">
      <p className="text-sm font-medium text-zinc-800">Roles</p>
      <ul className="space-y-2">
        {held.map((h) => (
          <HeldRole key={h.role} person={p} role={h.role} label={h.label} canRemove={h.canRemove} why={h.why} isOwner={isOwner} />
        ))}
      </ul>
      {!isOwner && <p className="text-xs text-zinc-500">Only the owner can remove roles or add admins.</p>}
      <AddRoleForm person={p} isOwner={isOwner} />
    </div>
  );
}

function HeldRole({
  person,
  role,
  label,
  canRemove,
  why,
  isOwner,
}: {
  person: StaffMember;
  role: "admin" | "tutor" | "parent" | "student";
  label: string;
  canRemove: boolean;
  why?: string;
  isOwner: boolean;
}) {
  const [confirming, setConfirming] = useState(false);
  const [state, formAction, pending] = useActionState(removeRole, initialFormState);
  const showLevel = role === "admin" && isOwner && person.admin_level && person.admin_level !== "owner" && canRemove;
  const effects: Record<string, string> = {
    tutor: "Tutor access ends today and their open matches end. Refused while they still have sessions booked.",
    admin: "Their admin access ends.",
    parent: "They stop seeing their children.",
    student: "Their student record is kept, without the login.",
  };
  return (
    <li className="rounded-xl bg-zinc-50 px-3 py-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-sm">{label}</span>
        <span className="flex items-center gap-3">
          {showLevel && <SetLevelForm accountId={person.account_id} level={person.admin_level as string} />}
          {canRemove && !confirming && (
            <button type="button" onClick={() => setConfirming(true)} className="text-sm font-medium text-red-700 underline underline-offset-4">
              Remove
            </button>
          )}
        </span>
      </div>
      {why && <p className="mt-1 text-xs text-zinc-500">{why}</p>}
      {confirming && (
        <form action={formAction} className="mt-2 space-y-2">
          <input type="hidden" name="account_id" value={person.account_id} />
          <input type="hidden" name="role" value={role} />
          <p className="text-xs text-zinc-600">{effects[role]} Their records are kept under the usual keeping rules.</p>
          <label className="block space-y-1">
            <span className="text-xs font-medium text-zinc-800">Type {person.full_name} to confirm</span>
            <input name="confirm_name" required autoComplete="off" className={inputClass} />
          </label>
          <div className="flex gap-2">
            <button type="submit" disabled={pending} className="rounded-full bg-red-700 px-4 py-1.5 text-sm font-medium text-white hover:bg-red-800 disabled:opacity-50">
              {pending ? "Removing…" : "Remove role"}
            </button>
            <button type="button" onClick={() => setConfirming(false)} className={plainButton}>
              Cancel
            </button>
          </div>
        </form>
      )}
      <Result state={state} />
    </li>
  );
}

function AddRoleForm({ person: p, isOwner }: { person: StaffMember; isOwner: boolean }) {
  const [state, formAction, pending] = useActionState(addRole, initialFormState);
  const [role, setRole] = useState("");
  const options: { value: string; label: string }[] = [];
  if (!p.is_tutor) options.push({ value: "tutor", label: "Tutor" });
  if (!p.is_admin && isOwner) options.push({ value: "admin", label: "Admin" });
  if (!p.is_parent) options.push({ value: "parent", label: "Parent" });
  const choices = options;
  if (choices.length === 0) return null;
  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="account_id" value={p.account_id} />
      <div className="flex flex-wrap items-end gap-2">
        <label className="block min-w-40 flex-1 space-y-1">
          <span className="text-xs font-medium text-zinc-800">Add a role</span>
          <select name="role" value={role} onChange={(e) => setRole(e.target.value)} required className={inputClass}>
            <option value="" disabled>
              Choose…
            </option>
            {choices.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>
        {role === "admin" && (
          <label className="block min-w-40 flex-1 space-y-1">
            <span className="text-xs font-medium text-zinc-800">Admin level</span>
            <select name="level" defaultValue="support" className={inputClass}>
              <option value="operations">Operations</option>
              <option value="support">Support</option>
              <option value="finance">Finance</option>
            </select>
          </label>
        )}
        <button type="submit" disabled={pending || !role} className={smallButton}>
          {pending ? "Adding…" : "Add"}
        </button>
      </div>
      <p className="text-xs text-zinc-500">
        A student role comes from &quot;Become a learner&quot; on their own dashboard, because it needs a student record.
      </p>
      <Result state={state} />
    </form>
  );
}
