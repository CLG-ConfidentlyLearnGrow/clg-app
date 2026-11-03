// Reasons a family or tutor leaves CLG. Must match the list in the
// leaving_records table.
export const LEAVING_REASONS: Record<string, string> = {
  goals_met: "Goals met, no longer needed",
  finished_study: "Finished school or study",
  cost: "Cost",
  timing: "Times didn't suit",
  tutor_fit: "Tutor or student wasn't the right fit",
  other_provider: "Went to another tutor or provider",
  moved: "Moved away",
  own_study_or_work: "Tutor: own study or other work",
  pay: "Tutor: pay",
  hours: "Tutor: not enough hours",
  workload: "Tutor: workload",
  personal: "Personal or family reasons",
  other: "Other",
};
