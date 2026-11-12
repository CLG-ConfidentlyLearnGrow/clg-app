// Summary: the staff-only card listing materials that fit a student.
//
import { Card, Empty, TextLink } from "@/components/ui"; // The card, "nothing yet" note and link style.
import { MATERIAL_KIND_NAMES, type MaterialKind, yearRange } from "@/lib/materials"; // Material kind names, the kind type, and year ranges in words.

// Materials that fit this student, listed by themselves (staff only; the
// materials module works them out from the student's goals and levels).

// One material as the database gives it for this student.
export type StudentMaterial = {
  material_id: string; // its id,
  title: string; // its title,
  kind: MaterialKind; // its kind,
  subject: string; // its subject,
  from_level: string; // lowest year level,
  to_level: string; // highest year level,
  goal_skill_ids: string[]; // the skills in the student's goals it covers,
  fits_level: boolean; // whether it fits their level,
  times_used: number; // how often it's been used with them,
  last_used: string | null; // and when it was last used (if ever).
}; // End of the shape.

// Shows the materials that fit this student.
export function StudentMaterialsCard({
  materials, // the materials,
  skillNames, // and each skill's name by id.
}: { // (their types:)
  materials: StudentMaterial[]; // a list of materials,
  skillNames: Record<string, string>; // a lookup of skill names.
}) { // (end of the settings)
  const forGoals = materials.filter((m) => m.goal_skill_ids.length > 0); // Materials for the student's goals.
  const forLevel = materials.filter((m) => m.goal_skill_ids.length === 0); // Materials only for their level.
  const row = (m: StudentMaterial) => ( // Shows one material as a list item:
    <li key={m.material_id} className="py-2 text-sm">{/* a list item: */}
      <div className="flex flex-wrap items-baseline justify-between gap-2">{/* a row that wraps: */}
        <a // a link:
          href={`/materials/${m.material_id}/file`} // that opens the stamped file,
          target="_blank" // in a new tab,
          rel="noopener" // safely,
          className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4" // styled as a link.
        >{/* (end of its settings) */}
          {m.title}{/* The material's title. */}
        </a>{/* End of the link. */}
        <span className="text-xs text-zinc-500">{/* Small grey details: */}
          {MATERIAL_KIND_NAMES[m.kind] ?? m.kind} · {m.subject} · {yearRange(m.from_level, m.to_level)}{/* its kind, subject and year levels, */}
          {m.times_used > 0 && ` · used ${m.times_used} time${m.times_used === 1 ? "" : "s"}, last ${m.last_used}`}{/* and how often and when it was last used, if ever. */}
        </span>{/* End of the details. */}
      </div>{/* End of the row. */}
      {m.goal_skill_ids.length > 0 && ( // If it covers goal skills:
        <p className="mt-1 text-xs text-zinc-500">{/* a small grey line: */}
          Works on: {m.goal_skill_ids.map((id) => skillNames[id]).filter(Boolean).join("; ")}{/* listing the skills it works on. */}
        </p> // End of the line.
      )}{/* End of the skills. */}
    </li> // End of the list item.
  ); // End of row.

  return ( // Shows:
    <Card // a card that can be opened and closed:
      collapsible // (collapsible)
      defaultOpen={forGoals.length > 0} // open if there are goal materials,
      title="Materials for this student" // titled "Materials for this student",
      description="Added by themselves: materials tagged with skills in the student's goals, then materials for their subjects at the level they work at. Only staff see this." // with a short explanation.
    >{/* (end of the card's settings) */}
      {materials.length === 0 ? ( // If there are no materials:
        <Empty>{/* a "nothing yet" note: */}
          No CLG materials fit yet. See the whole <TextLink href="/materials">materials library</TextLink>.{/* with a link to the whole library. */}
        </Empty> // End of the note.
      ) : ( // Otherwise:
        <>{/* (a group:) */}
          {forGoals.length > 0 && <ul className="divide-y divide-zinc-100">{forGoals.map(row)}</ul>}{/* the goal materials as a list, */}
          {forLevel.length > 0 && ( // if there are level materials:
            <details className="mt-3" open={forGoals.length === 0}>{/* a section that opens when clicked (open if there are no goal materials): */}
              <summary className="cursor-pointer text-sm text-teal-800">{/* its clickable heading: */}
                {forLevel.length} more for their subjects and level{/* how many more there are. */}
              </summary>{/* End of the heading. */}
              <ul className="divide-y divide-zinc-100">{forLevel.map(row)}</ul>{/* The level materials as a list. */}
            </details> // End of the section.
          )}{/* End of the level materials. */}
        </> // (end of the group)
      )}{/* End of the choice. */}
    </Card> // End of the card.
  ); // End of what's shown.
} // End of StudentMaterialsCard.
