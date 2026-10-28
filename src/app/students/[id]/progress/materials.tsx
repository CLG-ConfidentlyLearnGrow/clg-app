import { Card, Empty, TextLink } from "@/components/ui";
import { MATERIAL_KIND_NAMES, type MaterialKind, yearRange } from "@/lib/materials";

// Materials that fit this student, listed by themselves (staff only; the
// materials module works them out from the student's goals and levels).

export type StudentMaterial = {
  material_id: string;
  title: string;
  kind: MaterialKind;
  subject: string;
  from_level: string;
  to_level: string;
  goal_skill_ids: string[];
  fits_level: boolean;
  times_used: number;
  last_used: string | null;
};

export function StudentMaterialsCard({
  materials,
  skillNames,
}: {
  materials: StudentMaterial[];
  skillNames: Record<string, string>;
}) {
  const forGoals = materials.filter((m) => m.goal_skill_ids.length > 0);
  const forLevel = materials.filter((m) => m.goal_skill_ids.length === 0);
  const row = (m: StudentMaterial) => (
    <li key={m.material_id} className="py-2 text-sm">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <a
          href={`/materials/${m.material_id}/file`}
          target="_blank"
          rel="noopener"
          className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4"
        >
          {m.title}
        </a>
        <span className="text-xs text-zinc-500">
          {MATERIAL_KIND_NAMES[m.kind] ?? m.kind} · {m.subject} · {yearRange(m.from_level, m.to_level)}
          {m.times_used > 0 && ` · used ${m.times_used} time${m.times_used === 1 ? "" : "s"}, last ${m.last_used}`}
        </span>
      </div>
      {m.goal_skill_ids.length > 0 && (
        <p className="mt-1 text-xs text-zinc-500">
          Works on: {m.goal_skill_ids.map((id) => skillNames[id]).filter(Boolean).join("; ")}
        </p>
      )}
    </li>
  );

  return (
    <Card
      collapsible
      defaultOpen={forGoals.length > 0}
      title="Materials for this student"
      description="Added by themselves: materials tagged with skills in the student's goals, then materials for their subjects at the level they work at. Only staff see this."
    >
      {materials.length === 0 ? (
        <Empty>
          No CLG materials fit yet. See the whole <TextLink href="/materials">materials library</TextLink>.
        </Empty>
      ) : (
        <>
          {forGoals.length > 0 && <ul className="divide-y divide-zinc-100">{forGoals.map(row)}</ul>}
          {forLevel.length > 0 && (
            <details className="mt-3" open={forGoals.length === 0}>
              <summary className="cursor-pointer text-sm text-teal-800">
                {forLevel.length} more for their subjects and level
              </summary>
              <ul className="divide-y divide-zinc-100">{forLevel.map(row)}</ul>
            </details>
          )}
        </>
      )}
    </Card>
  );
}
