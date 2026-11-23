// Summary: shared words for the decision steps record (Carla, 22 Nov 2026),
// from How We Do Things v1.0, section 4. Used by the Decision steps page.
//

// The name and meaning of each step, 1 to 5.
export const STEP_NAMES: Record<number, { name: string; meaning: string }> = { // step number -> words:
  1: { name: "Suggest, then ask", meaning: "Find at least three possible solutions, pick the best and say why, and ask Carla to approve it." }, // Step 1,
  2: { name: "Fix, then tell straight away", meaning: "Choose and fix it yourself, then message Carla straight away with what happened and what you did." }, // Step 2,
  3: { name: "Fix, then put it in your daily update", meaning: "Fix it, then include the problem, at least three options, your choice and why, and that it is done in your end-of-day update." }, // Step 3,
  4: { name: "Fix and record", meaning: "The same details go in your decisions log instead of a message. Carla can read it at any time." }, // Step 4,
  5: { name: "Overview only", meaning: "Similar decisions made well again and again become a regular overview. Only flag noteworthy ones in your daily update." }, // Step 5.
}; // End of the step words.

// "Step 3: Fix, then put it in your daily update".
export function stepLabel(step: number): string { // Takes the step number.
  return `Step ${step}: ${STEP_NAMES[step]?.name ?? ""}`; // The number and its name.
} // End of stepLabel.

// One line of a person's record, as the database hands it back.
export type RecordLine = { kind_id: string; audience: "admin" | "tutor"; title: string; step: number; on_probation: boolean; moved_on: string | null; note: string | null; start_step: number; goal_step: number; goal_note: string | null }; // Its fields.
