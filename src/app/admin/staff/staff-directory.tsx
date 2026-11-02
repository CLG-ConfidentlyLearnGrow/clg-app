"use client";

import { useActionState, useEffect, useMemo, useState } from "react";
import { setJobTitle } from "@/app/actions/staff-directory";
import { Empty } from "@/components/ui";
import { initialFormState } from "@/lib/forms";

export type StaffMember = {
  account_id: string;
  full_name: string;
  email: string | null;
  job_title: string | null;
  is_tutor: boolean;
  is_admin: boolean;
  admin_level: "owner" | "operations" | "support" | "finance" | null;
  tutor_active: boolean | null;
  work_state: string | null;
  subjects: string[];
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
  return out;
}

const selectClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none";

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
      <select className={selectClass} value={value} onChange={(e) => onChange(e.target.value)}>
        {children}
      </select>
    </label>
  );
}

export function StaffDirectory({ staff, canEdit }: { staff: StaffMember[]; canEdit: boolean }) {
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

  const shown = staff.filter((p) => {
    if (status === "current" && isFinished(p)) return false;
    if (status === "finished" && !isFinished(p)) return false;
    if (role === "tutor" && !p.is_tutor) return false;
    if (role === "admin" && !p.is_admin) return false;
    if (["owner", "operations", "support", "finance"].includes(role) && p.admin_level !== role) return false;
    if (title === NO_TITLE && p.job_title) return false;
    if (title !== "all" && title !== NO_TITLE && p.job_title !== title) return false;
    if (state !== "all" && p.work_state !== state) return false;
    if (subject !== "all" && !p.subjects.includes(subject)) return false;
    const words = search.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (words.length) {
      const text = [p.full_name, p.email ?? "", p.job_title ?? "", ...appRoles(p), ...p.subjects, p.work_state ?? ""]
        .join(" ")
        .toLowerCase();
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
            className={selectClass}
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
          </p>
          {filtered && (
            <button type="button" onClick={clear} className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700">
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

      {staff.length === 0 ? (
        <Empty>No staff yet. Add tutors and admins in Staff and accounts.</Empty>
      ) : shown.length === 0 ? (
        <Empty>Nobody matches. Try fewer words or clear the filters.</Empty>
      ) : (
        <ul className="grid gap-4 md:grid-cols-2">
          {shown.map((p) => (
            <StaffCard key={p.account_id} person={p} canEdit={canEdit} />
          ))}
        </ul>
      )}
    </div>
  );
}

function StaffCard({ person: p, canEdit }: { person: StaffMember; canEdit: boolean }) {
  const [editing, setEditing] = useState(false);
  return (
    <li className="rounded-2xl border border-zinc-200/80 bg-white p-5 shadow-[0_1px_3px_rgba(65,64,66,0.06)]">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-base font-semibold tracking-tight">{p.full_name}</p>
          <p className={`text-sm ${p.job_title ? "text-zinc-800" : "text-zinc-500 italic"}`}>{p.job_title ?? "No job title yet"}</p>
        </div>
        {canEdit && !editing && (
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="text-sm font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700"
            aria-label={`Edit job title for ${p.full_name}`}
          >
            Edit
          </button>
        )}
      </div>
      {editing && <JobTitleForm person={p} onDone={() => setEditing(false)} />}
      <div className="mt-3 flex flex-wrap gap-1.5">
        {appRoles(p).map((r) => (
          <span key={r} className="inline-block rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-800">
            {r}
          </span>
        ))}
        {p.work_state && (
          <span className="inline-block rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-800">{p.work_state}</span>
        )}
      </div>
      {p.subjects.length > 0 && <p className="mt-2 text-sm text-zinc-600">Teaches: {p.subjects.join(", ")}</p>}
      {p.email && (
        <p className="mt-2 text-sm [overflow-wrap:anywhere]">
          <a href={`mailto:${p.email}`} className="text-teal-700 underline decoration-teal-300 underline-offset-4 hover:decoration-teal-700">
            {p.email}
          </a>
        </p>
      )}
    </li>
  );
}

function JobTitleForm({ person, onDone }: { person: StaffMember; onDone: () => void }) {
  const [state, formAction, pending] = useActionState(setJobTitle, initialFormState);
  // Close the form once the title is saved.
  useEffect(() => {
    if (state.message) onDone();
  }, [state, onDone]);
  return (
    <form action={formAction} className="mt-3 space-y-2">
      <input type="hidden" name="account_id" value={person.account_id} />
      <label className="block space-y-1">
        <span className="text-sm font-medium text-zinc-800">Job title</span>
        <input
          name="job_title"
          defaultValue={person.job_title ?? ""}
          maxLength={80}
          list="job-title-suggestions"
          autoFocus
          className={selectClass}
        />
        <span className="block text-xs text-zinc-500">For example: Tutor, Operations coordinator. Leave blank to remove.</span>
      </label>
      {state.error && (
        <p role="alert" className="text-sm text-red-700">
          {state.error}
        </p>
      )}
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={pending}
          className="rounded-full bg-teal-700 px-4 py-1.5 text-sm font-medium text-white shadow-sm hover:bg-teal-900 disabled:opacity-50"
        >
          {pending ? "Saving…" : "Save"}
        </button>
        <button type="button" onClick={onDone} className="rounded-full border border-zinc-300 px-4 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50">
          Cancel
        </button>
      </div>
    </form>
  );
}
