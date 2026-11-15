// Summary: shared words and shapes for the training module (tutor and staff
// training, quizzes, certificates and the handbook), used by the pages and
// server actions.
//

import type { Role } from "@/lib/auth"; // The role type (for type checking only).

// Which dashboard a training or handbook page belongs to: the one it was
// opened from ("as" in the address), or tutor first.
export function staffRole(asParam: string | string[] | undefined, roles: Role[]): Role { // Takes the "as" setting and the person's roles.
  if (asParam === "admin" && roles.includes("admin")) return "admin"; // Opened from the admin dashboard: admin.
  return roles.includes("tutor") ? "tutor" : "admin"; // Otherwise tutor if they tutor, else admin.
} // End of staffRole.

// Who a module or handbook page is for.
export const AUDIENCES = ["tutor", "admin", "everyone"] as const; // The three choices (fixed).
export type Audience = (typeof AUDIENCES)[number]; // One of those choices (for type checking).
export const AUDIENCE_NAMES: Record<Audience, string> = { // Each choice in words:
  tutor: "Tutors", // tutors,
  admin: "Admin staff", // admin staff,
  everyone: "Tutors and admin staff", // or both.
}; // End of the list.

// Where a module sits: the starting course, a refresher, or ongoing learning.
export const STAGES = ["starting", "refresher", "ongoing"] as const; // The three stages (fixed).
export type Stage = (typeof STAGES)[number]; // One stage (for type checking).
export const STAGE_NAMES: Record<Stage, string> = { // Each stage in words:
  starting: "Starting course", // the starting course,
  refresher: "Refreshers", // refreshers,
  ongoing: "Ongoing learning", // ongoing learning.
}; // End of the list.

// Where a person is up to with a module (worked out by the database).
export type TrainingState = "done" | "renew_soon" | "to_do" | "overdue" | "optional"; // The five states.
export const STATE_NAMES: Record<TrainingState, string> = { // Each state in words:
  done: "Done", // finished,
  renew_soon: "Redo soon", // finished, but due to redo soon,
  to_do: "To do", // compulsory and not done yet,
  overdue: "Overdue", // compulsory and past its due date,
  optional: "Optional", // not compulsory.
}; // End of the list.
export const STATE_STYLES: Record<TrainingState, string> = { // Each state's colours:
  done: "bg-emerald-50 text-emerald-800", // green for done,
  renew_soon: "bg-amber-50 text-amber-800", // amber for redo soon,
  to_do: "bg-sky-50 text-sky-800", // blue for to do,
  overdue: "bg-red-50 text-red-800", // red for overdue,
  optional: "bg-zinc-100 text-zinc-700", // grey for optional.
}; // End of the list.

// CLG certification (worked out by the database).
export type CertState = "in_training" | "certified" | "lapsed"; // The three states.
export const CERT_NAMES: Record<CertState, string> = { // Each in words:
  in_training: "Finishing the starting course", // still doing the compulsory modules,
  certified: "CLG certified", // certified,
  lapsed: "Certification lapsed", // a quarter ended short of hours.
}; // End of the list.

// One module in a person's own training list.
export type MyModule = { // its details:
  module_id: string; // the module's id,
  title: string; // its name,
  summary: string; // what it covers,
  stage: Stage; // starting, refresher or ongoing,
  required: boolean; // whether it's compulsory,
  holds_matching: boolean; // whether new matches wait for it,
  counts_toward_certified: boolean; // whether it counts towards the quarter's hours,
  minutes: number; // its set time,
  renew_months: number | null; // how often it's redone (if it is),
  module_position: number; // its order,
  state: TrainingState; // where they're up to,
  due_on: string | null; // when it's due (if it is),
  completed_on: string | null; // when they last finished it (if they have),
  expires_on: string | null; // when it runs out (if it does),
  completion_id: string | null; // their latest completion's id (for the certificate).
}; // End of the shape.

// A person's CLG certification.
export type Certification = { // its details:
  state: CertState; // where they're up to,
  certified_since: string | null; // when they first qualified (if they have),
  quarter_minutes: number; // minutes that count, this quarter,
  last_quarter_minutes: number; // minutes that count, last quarter,
  target_minutes: number; // minutes needed each quarter,
  quarter_ends: string; // the last day of this quarter.
}; // End of the shape.

// Minutes written as hours, e.g. 90 -> "1.5 hr" (CLG writes "hr", not "h").
export function hrs(minutes: number): string { // Takes the minutes.
  return `${Math.round((minutes / 60) * 100) / 100} hr`; // Hands back hours with up to two decimals.
} // End of hrs.

// A module's set time in words: minutes under an hour, otherwise hours.
export function timeText(minutes: number): string { // Takes the minutes.
  return minutes < 60 ? `${minutes} min` : hrs(minutes); // "45 min" or "1.5 hr".
} // End of timeText.

// File types admins can attach to a lesson, by file extension.
export const LESSON_FILE_TYPES: Record<string, string> = { // Each extension and its file type:
  mp4: "video/mp4", // MP4 video,
  webm: "video/webm", // WebM video,
  mov: "video/quicktime", // QuickTime video (from iPhones and Macs),
  pdf: "application/pdf", // PDF document.
}; // End of the list.

// Whether a stored lesson file is a video (not a PDF).
export function isVideo(path: string | null): boolean { // Takes the stored file name.
  return !!path && !path.endsWith(".pdf"); // A file that isn't a PDF is a video.
} // End of isVideo.
