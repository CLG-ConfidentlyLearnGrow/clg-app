// Reasons a family or tutor leaves CLG. Must match the list in the
// leaving_records table.
export const LEAVING_REASONS: Record<string, string> = { // Each reason's code and its words:
  goals_met: "Goals met, no longer needed", // goals met,
  finished_study: "Finished school or study", // finished school or study,
  cost: "Cost", // cost,
  timing: "Times didn't suit", // times didn't suit,
  tutor_fit: "Tutor or student wasn't the right fit", // not the right fit,
  other_provider: "Went to another tutor or provider", // went elsewhere,
  moved: "Moved away", // moved away,
  own_study_or_work: "Tutor: own study or other work", // tutor's own study or work,
  pay: "Tutor: pay", // tutor's pay,
  hours: "Tutor: not enough hours", // tutor's hours,
  workload: "Tutor: workload", // tutor's workload,
  personal: "Personal or family reasons", // personal or family reasons,
  other: "Other", // other.
}; // End of the list.
