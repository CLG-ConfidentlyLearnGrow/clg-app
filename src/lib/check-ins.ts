// Summary: the words for the check-ins after a new match (Carla, 16 Nov
// 2026). The tutor, the parents and a learner with their own login are each
// asked how it is going 1 week, 2 weeks and 6 weeks after the first session.
// This file keeps the question wording in one place, so the dashboard card,
// the admin page and the App guides all say the same thing.
// See docs/features/match-check-ins.md.
//

// Which check-in it is, in words (the database stores 1, 2 or 6).
export const CHECK_IN_STAGES: Record<number, string> = { // Each stage and its name:
  1: "1-week check-in", // a week after the first session,
  2: "2-week check-in", // two weeks after,
  6: "6-week check-in", // six weeks after.
}; // End of the list.

// The 1 to 5 scale for "How is it going?", lowest first.
export const CHECK_IN_RATINGS: { value: string; label: string }[] = [ // Each choice and its words:
  { value: "1", label: "1: Not well at all" }, // the lowest,
  { value: "2", label: "2: Not very well" }, // poor,
  { value: "3", label: "3: Okay" }, // in the middle,
  { value: "4", label: "4: Well" }, // good,
  { value: "5", label: "5: Very well" }, // the highest.
]; // End of the list.

// The answers to "Is it a good fit?", in words.
export const CHECK_IN_FIT: Record<string, string> = { // Each answer and its words:
  yes: "Yes", // a good fit,
  unsure: "Not sure yet", // too early to tell,
  no: "No", // not a good fit.
}; // End of the list.

// Who answered, in words (for the admin page).
export const CHECK_IN_WHO: Record<string, string> = { // Each role and its words:
  tutor: "Tutor", // the tutor,
  parent: "Parent or carer", // a parent or carer,
  student: "Learner", // the learner themselves.
}; // End of the list.

// The person answering, and who the check-in is about.
export type CheckInKind = "tutor" | "parent" | "student"; // The three roles that are asked.

// The questions, worded for the person answering. "tutor" and "student" are
// first names (for example "How are Sam's sessions with Alex going?").
export function checkInQuestions(kind: CheckInKind, tutor: string, student: string) { // Takes the role and the two first names.
  if (kind === "tutor") { // For the tutor:
    return { // the questions are:
      heading: `How is it going with ${student}?`, // the card's heading,
      rating: `How are your sessions with ${student} going?`, // the rating question,
      fit: `Do you think you are a good fit for ${student}?`, // the fit question,
    }; // (end)
  } // End of the tutor wording.
  if (kind === "student") { // For a learner with their own login:
    return { // the questions are:
      heading: `How is it going with ${tutor}?`, // the card's heading,
      rating: `How are your sessions with ${tutor} going?`, // the rating question,
      fit: `Would you like to keep working with ${tutor}?`, // the fit question,
    }; // (end)
  } // End of the learner wording.
  return { // For a parent or carer, the questions are:
    heading: `How is ${student} going with ${tutor}?`, // the card's heading,
    rating: `How are ${student}'s sessions with ${tutor} going?`, // the rating question,
    fit: `Would you like ${student} to keep working with ${tutor}?`, // the fit question.
  }; // (end)
} // End of checkInQuestions.

// The start of "recent" on the admin page: about four months ago, long
// enough to cover a whole 6-week cycle of check-ins and more. Gives back the
// date and time in the database's format.
export function checkInSince(): string { // No inputs.
  return new Date(Date.now() - 120 * 24 * 60 * 60 * 1000).toISOString(); // Now, less 120 days.
} // End of checkInSince.
