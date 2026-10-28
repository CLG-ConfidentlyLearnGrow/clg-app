import { Button, Card, Empty, Field, SubHeading, Table, TextLink } from "@/components/ui";
import { NOTE_OVERDUE_HOURS, STALLED_AFTER_SESSIONS, hoursAgo, minutesAndSeconds } from "@/lib/progress";
import { addDays, localToday, sessionWhen, shortDate } from "@/lib/scheduling";
import { createClient } from "@/lib/supabase/server";

type Measure = {
  tutor_id: string;
  tutor_name: string | null;
  sessions_held: number;
  sessions_noted: number;
  noted_within_24_hr: number;
  notes: number;
  notes_with_reflection: number;
  median_writing_seconds: number | null;
  skills_moved_up: number;
};
type DueNote = {
  session_id: string;
  student_id: string;
  student_name: string;
  tutor_name: string | null;
  starts_at: string;
  hours_since_end: number;
};
type ToCheck = {
  student_id: string;
  student_name: string;
  tutor_names: string | null;
  active_goals: number;
  last_note_on: string | null;
  notes_since_movement: number;
  notes_due: number;
};
type RecentNote = {
  id: string;
  student_id: string;
  session_date: string;
  went_well: string | null;
  next_step: string | null;
  home_tip: string | null;
  student: { full_name: string } | null;
  tutor: { account: { full_name: string } | null } | null;
};

const isDate = (v: unknown): v is string => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
const share = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "-");

// Admin oversight for progress tracking: the measures the research brief
// names, overdue notes, students who may need a change of plan, and recent
// notes to spot-check. Reviewed weekly.
export async function ProgressSection({ from: fromParam, to: toParam }: { from: unknown; to: unknown }) {
  const today = localToday();
  const to = isDate(toParam) ? toParam : today;
  const from = isDate(fromParam) ? fromParam : addDays(to, -27);

  const supabase = await createClient();
  const [measuresRes, dueRes, checkRes, recentRes] = await Promise.all([
    supabase.rpc("progress_measures", { p_from: from, p_to: to }),
    supabase.rpc("list_notes_due"),
    supabase.rpc("progress_students_to_check"),
    supabase
      .from("session_notes")
      .select(
        "id, student_id, session_date, went_well, next_step, home_tip, student:students(full_name), tutor:tutor_profiles(account:accounts(full_name))",
      )
      .neq("attendance", "absent")
      .order("created_at", { ascending: false })
      .limit(10),
  ]);
  const measures = (measuresRes.data ?? []) as Measure[];
  const overdue = ((dueRes.data ?? []) as DueNote[]).filter((d) => d.hours_since_end >= NOTE_OVERDUE_HOURS);
  const toCheck = ((checkRes.data ?? []) as ToCheck[]).filter(
    (s) => s.active_goals === 0 || s.notes_since_movement >= STALLED_AFTER_SESSIONS,
  );
  const recent = (recentRes.data ?? []) as unknown as RecentNote[];

  const total = measures.reduce(
    (t, m) => ({
      held: t.held + m.sessions_held,
      noted: t.noted + m.sessions_noted,
      onTime: t.onTime + m.noted_within_24_hr,
      notes: t.notes + m.notes,
      reflected: t.reflected + m.notes_with_reflection,
      movedUp: t.movedUp + m.skills_moved_up,
    }),
    { held: 0, noted: 0, onTime: 0, notes: 0, reflected: 0, movedUp: 0 },
  );

  return (
    <>
      <Card
        title="How progress tracking is going"
        description="The measures from the research brief. The pilot aims for every session to have a note within 24 hr, written in under 3 minutes."
      >
        <form method="get" className="mb-5 flex flex-wrap items-end gap-3">
          <input type="hidden" name="section" value="progress" />
          <div className="w-40">
            <Field label="From" name="from" type="date" defaultValue={from} max={today} />
          </div>
          <div className="w-40">
            <Field label="To" name="to" type="date" defaultValue={to} max={today} />
          </div>
          <Button type="submit">Show</Button>
        </form>
        {measures.length === 0 ? (
          <Empty>No sessions or notes between {shortDate(from)} and {shortDate(to)}.</Empty>
        ) : (
          <>
            <ul className="mb-5 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
              <Stat label="Sessions with a note" value={share(total.noted, total.held)} />
              <Stat label="Noted within 24 hr" value={share(total.onTime, total.held)} />
              <Stat label="Notes with a reflection" value={share(total.reflected, total.notes)} />
              <Stat label="Skills moved up" value={String(total.movedUp)} />
            </ul>
            <Table headings={["Tutor", "Sessions", "With note", "Within 24 hr", "Reflections", "Time to write", "Skills up"]}>
              {measures.map((m) => (
                <tr key={m.tutor_id}>
                  <td className="font-medium">{m.tutor_name ?? "Former tutor"}</td>
                  <td>{m.sessions_held}</td>
                  <td>{share(m.sessions_noted, m.sessions_held)}</td>
                  <td>{share(m.noted_within_24_hr, m.sessions_held)}</td>
                  <td>{share(m.notes_with_reflection, m.notes)}</td>
                  <td>{minutesAndSeconds(m.median_writing_seconds)}</td>
                  <td>{m.skills_moved_up}</td>
                </tr>
              ))}
            </Table>
            <p className="mt-3 text-xs text-zinc-500">
              Sessions counts sessions marked done in the app. Time to write is the middle value of notes written with
              the timer. Families and tutors never see these figures.
            </p>
          </>
        )}
      </Card>

      <Card title={`Notes overdue (${NOTE_OVERDUE_HOURS} hr or more)`}>
        {overdue.length === 0 ? (
          <Empty>None. Every recent session has its note.</Empty>
        ) : (
          <Table headings={["Student", "Tutor", "Session", "Ended"]}>
            {overdue.map((d) => (
              <tr key={d.session_id}>
                <td className="font-medium">
                  <TextLink href={`/students/${d.student_id}/progress?session=${d.session_id}`}>{d.student_name}</TextLink>
                </td>
                <td>{d.tutor_name ?? "-"}</td>
                <td>{sessionWhen(d.starts_at)}</td>
                <td>{hoursAgo(d.hours_since_end)}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      <Card
        title="Students to check"
        description={`Students with no goals yet, or whose skills haven't moved in ${STALLED_AFTER_SESSIONS} or more sessions. They may need a change of goals, approach or tutor.`}
      >
        {toCheck.length === 0 ? (
          <Empty>Nobody right now.</Empty>
        ) : (
          <Table headings={["Student", "Tutor", "Why", "Last note"]}>
            {toCheck.map((s) => (
              <tr key={s.student_id}>
                <td className="font-medium">
                  <TextLink href={`/students/${s.student_id}/progress`}>{s.student_name}</TextLink>
                </td>
                <td>{s.tutor_names ?? "-"}</td>
                <td>
                  {s.active_goals === 0
                    ? "No goals set"
                    : `No skill moved in ${s.notes_since_movement} sessions`}
                </td>
                <td>{s.last_note_on ? shortDate(s.last_note_on) : "None yet"}</td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      <Card
        collapsible
        defaultOpen={false}
        title="Recent notes to spot-check"
        description="Is the next step specific, and written to the student? Is the tip for home a small habit?"
      >
        {recent.length === 0 ? (
          <Empty>No notes yet.</Empty>
        ) : (
          <ul className="divide-y divide-zinc-100 text-sm">
            {recent.map((n) => (
              <li key={n.id} className="py-3 first:pt-0">
                <p className="font-medium">
                  <TextLink href={`/students/${n.student_id}/progress`}>{n.student?.full_name ?? "Student"}</TextLink>
                  <span className="font-normal text-zinc-600">
                    {" "}
                    · {shortDate(n.session_date)}
                    {n.tutor?.account?.full_name && ` · ${n.tutor.account.full_name}`}
                  </span>
                </p>
                {n.went_well && <p>Went well: {n.went_well}</p>}
                {n.next_step && <p>Next step: {n.next_step}</p>}
                {n.home_tip && <p>Try at home: {n.home_tip}</p>}
              </li>
            ))}
          </ul>
        )}
        <SubHeading>What good looks like</SubHeading>
        <p className="text-sm text-zinc-600">
          Feedback works when it says where the student is going, how they are going, and what to do next (EEF,
          Feedback). Parents help most with habits like planning and practice, not re-teaching (EEF, Parental
          engagement).
        </p>
      </Card>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <li className="rounded-xl bg-zinc-50 px-4 py-3">
      <span className="block text-xl font-semibold">{value}</span>
      <span className="text-xs text-zinc-600">{label}</span>
    </li>
  );
}
