// The Matching tab (scheduling module): one place for owner, operations and
// support admins to match students with tutors. The database decides who
// can see what; this page only shows it.

import type { ReactNode } from "react";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Card, Empty, Field, Select, TextLink } from "@/components/ui";
import { FRONT_DESK, FULL_ADMIN, getAdminLevel, needsTwoStep, requireViewer } from "@/lib/auth";
import { CHECK_NAMES, STATES, type CheckKind } from "@/lib/checks";
import { WEEKDAY_NAMES, addDays, clockTime, localToday, placeLabel, shortDate } from "@/lib/scheduling";
import { YEAR_LEVELS } from "@/lib/students";
import { createClient } from "@/lib/supabase/server";
import { BookForm } from "../schedule/forms";
import { CourseDetails, type CourseUnit } from "@/components/course-details";
import { CourseOverviewForm } from "../admin/course-overview-form";
import { ADMIN_SECTIONS } from "../admin/sections";
import { RoleTabs } from "@/components/role-tabs";
import { SectionShell } from "@/components/section-shell";

type StageCount = { stage: string; subjects: number; oldest_days: number | null };
type QueueRow = {
  student_id: string;
  student_name: string;
  year_level: string | null;
  working_level: string | null;
  subject: string;
  state: string;
  stage: string;
  days: number;
  tutor_name: string | null;
  has_places: boolean;
  total: number;
};
type Shortlist = {
  tutor_id: string;
  tutor_name: string;
  teaches_sibling: boolean;
  sibling_names: string | null;
  times: number;
  preferred_times: number;
  in_person_times: number;
  best_weekday: number | null;
  best_start: string | null;
  best_end: string | null;
  best_delivery: "online" | "library" | "home" | null;
  best_library: string | null;
  best_library_name: string | null;
  booked_minutes: number;
  max_weekly_hours: number | null;
  at_max: boolean;
  learning_support: boolean;
  check_kind: string | null;
  check_expires: string | null;
  rank: number;
};
type Gap = { subject: string; level: string; state: string; waiting: number; longest_days: number };

const STAGES: { id: string; label: string; hint: string }[] = [
  { id: "needs_tutor", label: "Needs a tutor", hint: "Asked for, nothing booked or waiting" },
  { id: "waitlist", label: "Waitlist", hint: "No suitable tutor available yet" },
  { id: "tutor_to_confirm", label: "Waiting for confirmation", hint: "Offer waiting for the tutor (and family) to approve" },
  { id: "assigned", label: "Assigned, no time", hint: "Tutor assigned but no weekly time booked" },
  { id: "active", label: "Active", hint: "Weekly sessions running" },
];
const PAGE_SIZE = 30;
const PARTS: Record<string, string> = {
  morning: "mornings",
  midday: "middle of the day",
  afternoon: "afternoons",
  evening: "evenings",
};
const CHANGE_REASON_NAMES: Record<string, string> = {
  family_request: "Family asked for something else",
  tutor_request: "Tutor asked for something else",
  tutor_fit: "Another tutor suited the student better",
  time: "Better time for the tutor's day",
  place: "Better place",
  other: "Other",
};

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";
const hours = (minutes: number) => `${Math.round((minutes / 60) * 10) / 10} hr`;

export default async function MatchingPage({ searchParams }: PageProps<"/matching">) {
  const viewer = await requireViewer();
  if (needsTwoStep(viewer)) redirect("/mfa");
  const level = viewer.roles.includes("admin") ? await getAdminLevel() : null;
  if (!level || !FRONT_DESK.includes(level)) redirect("/dashboard");
  const isFull = FULL_ADMIN.includes(level);

  const params = await searchParams;
  const view = one(params.view) === "gaps" ? "gaps" : "queue";
  const stage = STAGES.find((s) => s.id === one(params.stage))?.id ?? "needs_tutor";
  const search = one(params.q).slice(0, 100);
  const year = (YEAR_LEVELS as readonly string[]).includes(one(params.year)) ? one(params.year) : "";
  const state = (STATES as readonly string[]).includes(one(params.state)) ? one(params.state) : "";
  const page = Math.max(Number(one(params.page)) || 1, 1);
  const studentId = one(params.student);
  const subject = one(params.subject).slice(0, 100);

  const supabase = await createClient();
  const [countsRes, queueRes] = await Promise.all([
    supabase.rpc("matching_stage_counts"),
    supabase.rpc("matching_queue", {
      p_stage: stage,
      p_search: search || null,
      p_year: year || null,
      p_state: state || null,
      p_limit: PAGE_SIZE,
      p_offset: (page - 1) * PAGE_SIZE,
    }),
  ]);
  const counts = (countsRes.data ?? []) as StageCount[];
  const rows = (queueRes.data ?? []) as QueueRow[];
  const total = rows[0]?.total ?? 0;
  const pages = Math.max(Math.ceil(total / PAGE_SIZE), 1);

  const filters = {
    stage,
    ...(search ? { q: search } : {}),
    ...(year ? { year } : {}),
    ...(state ? { state } : {}),
  };
  const link = (over: Record<string, string>) => `/matching?${new URLSearchParams({ ...filters, ...over }).toString()}`;
  const currentIndex = rows.findIndex((r) => r.student_id === studentId && r.subject === subject);
  const next = currentIndex >= 0 ? rows[currentIndex + 1] : undefined;
  const current = STAGES.find((s) => s.id === stage)!;

  // Same admin side menu as the rest of the admin area, so admins can move
  // between sections without leaving Matching. It can be hidden.
  const adminSections = isFull
    ? ADMIN_SECTIONS
    : ADMIN_SECTIONS.filter((s) => s.id === "families" || s.id === "matching");

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <SectionShell
        basePath="/admin"
        label="Admin"
        section="matching"
        sections={adminSections.map((s) => ({ id: s.id, label: s.label }))}
      >
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p className="text-sm text-zinc-600">
              Students waiting for a tutor, and the tutors who suit them best. Matching is on fit only.
            </p>
          </div>
          <nav className="flex gap-2 text-sm" aria-label="Matching views">
            <Link
              href="/matching"
              className={`rounded-full border px-3 py-1 ${view === "queue" ? "border-teal-700 bg-teal-50" : "border-zinc-300 bg-white"}`}
            >
              Students waiting
            </Link>
            <Link
              href="/matching?view=gaps"
              className={`rounded-full border px-3 py-1 ${view === "gaps" ? "border-teal-700 bg-teal-50" : "border-zinc-300 bg-white"}`}
            >
              Gaps
            </Link>
          </nav>
        </div>

        {view === "gaps" ? (
          <GapsView />
        ) : (
          <>
            <ul className="grid grid-cols-2 gap-2 sm:grid-cols-5">
              {STAGES.map((s) => {
                const c = counts.find((x) => x.stage === s.id);
                const active = s.id === stage;
                return (
                  <li key={s.id}>
                    <Link
                      href={link({ stage: s.id, page: "1" })}
                      className={`block rounded-lg border px-3 py-2 text-sm ${active ? "border-teal-700 bg-teal-50" : "border-zinc-200 bg-white hover:border-teal-700"}`}
                    >
                      <span className="block text-2xl font-semibold">{c?.subjects ?? 0}</span>
                      <span className="block">{s.label}</span>
                      {c?.oldest_days != null && <span className="block text-xs text-zinc-600">longest {c.oldest_days} days</span>}
                    </Link>
                  </li>
                );
              })}
            </ul>

            <div className="grid gap-6 lg:grid-cols-[22rem_1fr]">
              <div className={`space-y-4 ${studentId ? "order-2 lg:order-1" : ""}`}>
                <Card title={`${current.label} (${total})`} description={current.hint}>
                  <form method="get" action="/matching" className="mb-4 space-y-2">
                    <input type="hidden" name="stage" value={stage} />
                    <Field label="Search by student or subject" name="q" defaultValue={search} maxLength={100} />
                    <div className="grid grid-cols-2 gap-2">
                      <Select label="Year level" name="year" defaultValue={year}>
                        <option value="">Any</option>
                        {YEAR_LEVELS.map((y) => (
                          <option key={y} value={y}>
                            {y}
                          </option>
                        ))}
                      </Select>
                      <Select label="State" name="state" defaultValue={state}>
                        <option value="">Any</option>
                        {STATES.map((s) => (
                          <option key={s} value={s}>
                            {s}
                          </option>
                        ))}
                      </Select>
                    </div>
                    <button type="submit" className="rounded-full border border-zinc-300 bg-white px-4 py-1.5 text-sm">
                      Filter
                    </button>
                  </form>
                  {rows.length === 0 ? (
                    <Empty>Nobody at this stage.</Empty>
                  ) : (
                    <ul className="divide-y divide-zinc-100 text-sm">
                      {rows.map((r) => {
                        const active = r.student_id === studentId && r.subject === subject;
                        return (
                          <li key={`${r.student_id}-${r.subject}`}>
                            <Link
                              href={link({ page: String(page), student: r.student_id, subject: r.subject })}
                              aria-current={active ? "true" : undefined}
                              className={`block rounded-md px-2 py-2 ${active ? "bg-teal-50" : "hover:bg-zinc-50"}`}
                            >
                              <span className="flex items-baseline justify-between gap-2">
                                <span className="font-medium">{r.student_name}</span>
                                <span className={`text-xs ${r.days >= 7 && stage !== "active" ? "text-amber-900" : "text-zinc-600"}`}>
                                  {r.days === 0 ? "today" : `${r.days} day${r.days === 1 ? "" : "s"}`}
                                </span>
                              </span>
                              <span className="block text-zinc-600">
                                {r.subject} · {r.year_level ?? "year not set"}
                                {r.working_level ? ` · working at ${r.working_level}` : ""} · {r.state}
                                {r.tutor_name ? ` · ${r.tutor_name}` : ""}
                              </span>
                            </Link>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                  {pages > 1 && (
                    <p className="mt-4 flex items-center gap-4 text-sm">
                      {page > 1 && (
                        <Link className="underline" href={link({ page: String(page - 1) })}>
                          Previous
                        </Link>
                      )}
                      <span className="text-zinc-600">
                        Page {page} of {pages}
                      </span>
                      {page < pages && (
                        <Link className="underline" href={link({ page: String(page + 1) })}>
                          Next
                        </Link>
                      )}
                    </p>
                  )}
                </Card>
                {isFull && <ReasonsCard />}
              </div>

              <div className={studentId ? "order-1 lg:order-2" : ""}>
                {studentId && subject ? (
                  <StudentPanel
                    studentId={studentId}
                    subject={subject}
                    nextHref={next ? link({ page: String(page), student: next.student_id, subject: next.subject }) : null}
                  />
                ) : (
                  <Card title="Choose a student">
                    <Empty>Pick a student from the list to see the tutors who suit them.</Empty>
                  </Card>
                )}
              </div>
            </div>
          </>
        )}
      </SectionShell>
    </>
  );
}

// ---------------------------------------------------------------------------
// One student: everything about them, and the tutor shortlist
// ---------------------------------------------------------------------------
async function StudentPanel({ studentId, subject, nextHref }: { studentId: string; subject: string; nextHref: string | null }) {
  const supabase = await createClient();
  const [studentRes, subjectsRes, placesRes, librariesRes, shortlistRes, notOfferedRes] = await Promise.all([
    supabase
      .from("students")
      .select("id, full_name, family_id, year_level, school, state, goals, learning_needs, program")
      .eq("id", studentId)
      .maybeSingle(),
    supabase
      .from("student_subjects")
      .select("id, subject, working_level, course_code, course_url, course_overview")
      .eq("student_id", studentId)
      .order("added_at"),
    supabase
      .from("student_places")
      .select("online, library_ids, preferred_days, preferred_parts, preferred_school_hours, tutor_preferences")
      .eq("student_id", studentId)
      .maybeSingle(),
    supabase.from("libraries").select("id, name"),
    supabase.rpc("matching_shortlist", { p_student: studentId, p_subject: subject }),
    supabase.rpc("matching_not_offered", { p_student: studentId, p_subject: subject }),
  ]);
  const student = studentRes.data as {
    id: string;
    full_name: string;
    family_id: string | null;
    year_level: string | null;
    school: string | null;
    state: string;
    goals: string | null;
    learning_needs: string | null;
    program: string | null;
  } | null;
  if (!student) {
    return (
      <Card title="Student not found">
        <Empty>This student may have been removed.</Empty>
      </Card>
    );
  }
  const subjects = (subjectsRes.data ?? []) as (CourseUnit & { working_level: string | null })[];
  const places = placesRes.data as {
    online: boolean;
    library_ids: string[];
    preferred_days: number[] | null;
    preferred_parts: string[] | null;
    preferred_school_hours: boolean;
    tutor_preferences: string | null;
  } | null;
  const libraryName = new Map((librariesRes.data ?? []).map((l) => [l.id as string, l.name as string]));
  const shortlist = (shortlistRes.data ?? []) as Shortlist[];
  const notOffered = (notOfferedRes.data ?? []) as { tutor_id: string; tutor_name: string; reason: string }[];
  const thisSubject = subjects.find((s) => s.subject.toLowerCase() === subject.toLowerCase());

  // Siblings and past tutors.
  const [siblingsRes, pastRes] = await Promise.all([
    student.family_id
      ? supabase.from("students").select("id, full_name").eq("family_id", student.family_id).neq("id", student.id)
      : Promise.resolve({ data: [] as { id: string; full_name: string }[] }),
    supabase
      .from("tutor_assignments")
      .select("subject, ends_on, accounts:tutor_id (full_name)")
      .eq("student_id", student.id)
      .lt("ends_on", localToday()),
  ]);
  const siblings = (siblingsRes.data ?? []) as { id: string; full_name: string }[];
  const past = (pastRes.data ?? []) as unknown as { subject: string; ends_on: string; accounts: { full_name: string } | null }[];

  const today = localToday();
  const first = addDays(today, 7);
  const top = shortlist.find((t) => t.times > 0);
  const optionFor = (t: Shortlist) => ({
    student_id: student.id,
    subject,
    tutor_id: t.tutor_id,
    weekday: t.best_weekday ?? 1,
    start_time: t.best_start ?? "",
    minutes: 60,
    delivery: t.best_delivery ?? "online",
    library_id: t.best_library,
  });
  const preferred = [
    places?.preferred_days?.length ? places.preferred_days.map((d) => WEEKDAY_NAMES[d - 1].slice(0, 3)).join(", ") : "",
    places?.preferred_parts?.length ? places.preferred_parts.map((p) => PARTS[p] ?? p).join(", ") : "",
    places?.preferred_school_hours ? "school hours" : "",
  ].filter(Boolean);

  return (
    <div className="space-y-4">
      <Card
        title={`${student.full_name} · ${subject}`}
        description={
          <span className="flex flex-wrap gap-3">
            <TextLink href={`/schedule?section=child-places&student=${student.id}`}>Session places</TextLink>
            <TextLink href={`/schedule?${new URLSearchParams({ section: "book", student: student.id, subject, auto: "1" }).toString()}`}>
              All available times
            </TextLink>
            {nextHref && <TextLink href={nextHref}>Next student →</TextLink>}
          </span>
        }
      >
        <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
          <Detail label="School year">
            {student.year_level ?? "Not set"}
            {student.school ? ` at ${student.school}` : ""} · {student.state}
          </Detail>
          <Detail label="Working level">{thisSubject?.working_level ?? "Not sure"}</Detail>
          <Detail label="Other subjects">
            {subjects
              .filter((s) => s !== thisSubject)
              .map((s) => `${s.subject}${s.working_level ? ` (${s.working_level})` : ""}`)
              .join(", ") || "None"}
          </Detail>
          <Detail label="Goal">{student.goals || "None given"}</Detail>
          <Detail label="Learning needs">{student.learning_needs || "None given"}</Detail>
          <Detail label="Tutor preferences">{places?.tutor_preferences || "None given"}</Detail>
          <Detail label="Places">
            {places
              ? [places.online ? "Online" : null, ...places.library_ids.map((id) => libraryName.get(id) ?? "a library")]
                  .filter(Boolean)
                  .join(", ")
              : "Not set yet (online assumed)"}
          </Detail>
          <Detail label="Preferred times">{preferred.length ? preferred.join(" · ") : "None given"}</Detail>
          <Detail label="Siblings">{siblings.map((s) => s.full_name).join(", ") || "None"}</Detail>
          <Detail label="Past tutors">
            {past.map((p) => `${p.accounts?.full_name ?? "A tutor"} (${p.subject}, to ${shortDate(p.ends_on)})`).join(", ") || "None"}
          </Detail>
        </dl>
        {/* University and TAFE students: degree, unit codes, course pages and CLG's overview. */}
        <div className="mt-3 text-sm">
          <CourseDetails
            program={student.program}
            units={subjects}
            overviewForm={(u) => <CourseOverviewForm subjectId={u.id} overview={u.course_overview} />}
          />
        </div>
      </Card>

      <Card
        title="Tutors who suit"
        description="Best fit tutor: teaches the subject at the level the student is working at, then a tutor who already teaches a sibling, then spare hours, then a place that suits, then a time that suits. Pay rates are not shown."
      >
        {shortlistRes.error ? (
          <Empty>{shortlistRes.error.message}</Empty>
        ) : shortlist.length === 0 ? (
          <Empty>No tutor teaches {subject} at this level for {student.state} yet. See the Gaps view.</Empty>
        ) : (
          <ol className="space-y-3">
            {shortlist.map((t) => (
              <li key={t.tutor_id} className={`rounded-lg border p-3 text-sm ${t === top ? "border-teal-700 bg-teal-50" : "border-zinc-200"}`}>
                <p className="flex flex-wrap items-baseline justify-between gap-2">
                  <span className="font-medium">
                    {t.rank}. {t.tutor_name}
                    {t === top && (
                      <span className="ml-2 text-xs font-semibold uppercase tracking-wide text-teal-800">Suggested</span>
                    )}
                  </span>
                  <span className="text-xs text-zinc-600">
                    {hours(t.booked_minutes)} booked
                    {t.max_weekly_hours != null ? ` of ${t.max_weekly_hours} hr` : ""}
                  </span>
                </p>
                <ul className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-zinc-700">
                  {t.teaches_sibling && <li>✓ Teaches {t.sibling_names} (sibling)</li>}
                  <li>
                    ✓ Teaches {subject} at {thisSubject?.working_level ?? student.year_level}
                  </li>
                  <li>✓ Checks current for {student.state}</li>
                  {t.times > 0 && (
                    <li>
                      ✓ {t.times} time{t.times === 1 ? "" : "s"} that suit
                      {t.preferred_times > 0 ? ` (${t.preferred_times} preferred)` : ""}
                    </li>
                  )}
                  {t.in_person_times > 0 && <li>✓ In person available</li>}
                  {t.learning_support && <li>✓ Learning support experience</li>}
                </ul>
                {t.at_max && (
                  <p className="mt-1 text-amber-900">
                    At their weekly maximum{t.max_weekly_hours != null ? ` (${t.max_weekly_hours} hr)` : ""}. They can&apos;t be
                    booked past it; if they&apos;re the only option, ask them first.
                  </p>
                )}
                {!t.at_max && t.times === 0 && (
                  <p className="mt-1 text-amber-900">No available times match this student&apos;s places right now.</p>
                )}
                {t.check_kind && t.check_expires && (
                  <p className="mt-1 text-amber-900">
                    {CHECK_NAMES[t.check_kind as CheckKind] ?? t.check_kind} expires {shortDate(t.check_expires)}.
                  </p>
                )}
                {t.times > 0 && t.best_weekday && t.best_start && t.best_end && (
                  <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
                    <span>
                      Best time: {WEEKDAY_NAMES[t.best_weekday - 1]} {clockTime(t.best_start)} to {clockTime(t.best_end)} ·{" "}
                      {placeLabel(t.best_delivery ?? "online", t.best_library_name)}
                    </span>
                    <BookForm
                      option={optionFor(t)}
                      defaultFirst={first}
                      defaultLast={addDays(first, 70)}
                      isAdmin
                      startOpen={t === top}
                      suggested={top ? optionFor(top) : null}
                    />
                  </div>
                )}
              </li>
            ))}
          </ol>
        )}
      </Card>

      {notOffered.length > 0 && (
        <Card collapsible defaultOpen={false} title={`Tutors who don't fit (${notOffered.length})`}>
          <ul className="divide-y divide-zinc-100 text-sm">
            {notOffered.map((t) => (
              <li key={t.tutor_id} className="py-2">
                <span className="font-medium">{t.tutor_name}</span>
                <span className="text-zinc-600"> · {t.reason}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}

function Detail({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-xs font-medium text-zinc-500">{label}</dt>
      <dd className="whitespace-pre-line">{children}</dd>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Gaps: what waiting students need that no tutor offers yet
// ---------------------------------------------------------------------------
async function GapsView() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("matching_gaps");
  const gaps = (data ?? []) as Gap[];
  return (
    <Card
      title="Gaps"
      description="Subjects and levels that students are waiting for, where no tutor with current checks teaches them. This shows who to recruit next."
    >
      {gaps.length === 0 ? (
        <Empty>No gaps: every waiting student has at least one tutor who teaches their subject and level.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {gaps.map((g) => (
            <li key={`${g.subject}-${g.level}-${g.state}`} className="flex flex-wrap items-baseline justify-between gap-2 py-2">
              <span>
                <span className="font-medium">{g.subject}</span>
                <span className="text-zinc-600">
                  {" "}
                  · {g.level} · {g.state}
                </span>
              </span>
              <span className="text-zinc-600">
                {g.waiting} waiting · longest {g.longest_days} day{g.longest_days === 1 ? "" : "s"}
              </span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Why suggestions were changed (full admins)
// ---------------------------------------------------------------------------
async function ReasonsCard() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("offer_change_reasons", { p_days: 90 });
  const reasons = (data ?? []) as { reason: string; changes: number; recent_notes: string[] | null }[];
  return (
    <Card
      collapsible
      defaultOpen={false}
      title="Why suggestions were changed"
      description="Last 90 days. If the same reason keeps coming up, the suggestions can be improved to allow for it."
    >
      {reasons.length === 0 ? (
        <Empty>No changes recorded yet.</Empty>
      ) : (
        <ul className="divide-y divide-zinc-100 text-sm">
          {reasons.map((r) => (
            <li key={r.reason} className="py-2">
              <span className="font-medium">{CHANGE_REASON_NAMES[r.reason] ?? r.reason}</span>
              <span className="text-zinc-600"> · {r.changes}</span>
              {r.recent_notes?.length ? <span className="block text-zinc-600">{r.recent_notes.join(" · ")}</span> : null}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

export const metadata = { title: "Matching · CLG Tutoring" };
