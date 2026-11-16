// Summary: actions for the private calendar link: make a new link (any old
// one stops working) or turn the link off. Tutors (Carla, 12 Nov 2026) and
// parents and students (15 Nov 2026) each have their own kind of link.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Whether two-step sign-in is still needed, and the signed-in person.
import { siteUrl } from "@/lib/env"; // The app's own web address.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

const PAGE = "/dashboard/tutor/calendar"; // The tutor weekly calendar page, refreshed after changes.
const FAMILY_PAGE = "/dashboard/calendar"; // The parents' and students' weekly calendar page.

// What the calendar link form gets back: a problem, a message, and (just
// after making one) the new link to copy.
export type CalendarLinkState = { error?: string; message?: string; link?: string }; // The reply's shape.

// Checks the person is a tutor signed in with two steps. Gives back a plain
// problem message, or nothing if all is well.
async function tutorProblem(): Promise<string | null> { // No inputs.
  const viewer = await requireViewer(); // The signed-in person (sends signed-out people to log in).
  if (!viewer.roles.includes("tutor")) return "Only tutors have a calendar link."; // Not a tutor: says so.
  if (needsTwoStep(viewer)) return "Please finish setting up two-step sign-in first."; // Two-step sign-in not done: says so.
  return null; // All is well.
} // End of tutorProblem.

// Makes a new calendar link and hands it back once, to copy.
export async function makeCalendarLink(): Promise<CalendarLinkState> { // No inputs: always for the signed-in tutor.
  const problem = await tutorProblem(); // Checks the person.
  if (problem) return { error: problem }; // Not allowed: shows why.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("reset_calendar_link"); // Asks the database for a new link (it checks again).
  if (error || typeof data !== "string") { // It didn't work:
    return { error: error?.code === "42501" ? error.message : "Could not make a calendar link. Please try again." }; // shows the database's plain refusal, or a general message.
  } // End of the problem check.
  revalidatePath(PAGE); // Refreshes the calendar page (so it shows the new "made on" date).
  return { // Hands back:
    link: `${siteUrl()}/api/calendar/${data}.ics`, // the full link (ending in ".ics" so every calendar app accepts it),
    message: "Your new calendar link is ready. Any older link has stopped working.", // and a plain message.
  }; // End of the reply.
} // End of makeCalendarLink.

// Turns the calendar link off. The calendar app stops getting updates.
export async function turnOffCalendarLink(): Promise<CalendarLinkState> { // No inputs: always for the signed-in tutor.
  const problem = await tutorProblem(); // Checks the person.
  if (problem) return { error: problem }; // Not allowed: shows why.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("remove_calendar_link"); // Asks the database to remove the link (it checks again).
  if (error) return { error: "Could not turn off the calendar link. Please try again." }; // It didn't work: plain message.
  revalidatePath(PAGE); // Refreshes the calendar page.
  return { message: "Calendar link turned off. You can remove the CLG calendar from your calendar app too." }; // Tells the tutor it worked.
} // End of turnOffCalendarLink.

// ---------------------------------------------------------------------------
// Parents and students (Carla, 15 Nov 2026)
// ---------------------------------------------------------------------------

// Checks the person is a parent, or a student with their own login. Gives
// back a plain problem message, or nothing if all is well.
async function familyProblem(): Promise<string | null> { // No inputs.
  const viewer = await requireViewer(); // The signed-in person (sends signed-out people to log in).
  if (!viewer.roles.includes("parent") && !viewer.roles.includes("student")) return "Only parents and students have a family calendar link."; // Neither: says so.
  return null; // All is well.
} // End of familyProblem.

// Makes a new family calendar link and hands it back once, to copy.
export async function makeFamilyCalendarLink(): Promise<CalendarLinkState> { // No inputs: always for the signed-in person.
  const problem = await familyProblem(); // Checks the person.
  if (problem) return { error: problem }; // Not allowed: shows why.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("reset_family_calendar_link"); // Asks the database for a new link (it checks again).
  if (error || typeof data !== "string") { // It didn't work:
    return { error: error?.code === "42501" ? error.message : "Could not make a calendar link. Please try again." }; // shows the database's plain refusal, or a general message.
  } // End of the problem check.
  revalidatePath(FAMILY_PAGE); // Refreshes the family calendar page (so it shows the new "made on" date).
  return { // Hands back:
    link: `${siteUrl()}/api/calendar/family/${data}.ics`, // the full link (ending in ".ics" so every calendar app accepts it),
    message: "Your new calendar link is ready. Any older link has stopped working.", // and a plain message.
  }; // End of the reply.
} // End of makeFamilyCalendarLink.

// Turns the family calendar link off.
export async function turnOffFamilyCalendarLink(): Promise<CalendarLinkState> { // No inputs: always for the signed-in person.
  const problem = await familyProblem(); // Checks the person.
  if (problem) return { error: problem }; // Not allowed: shows why.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("remove_family_calendar_link"); // Asks the database to remove the link.
  if (error) return { error: "Could not turn off the calendar link. Please try again." }; // It didn't work: plain message.
  revalidatePath(FAMILY_PAGE); // Refreshes the family calendar page.
  return { message: "Calendar link turned off. You can remove the CLG calendar from your calendar app too." }; // Says it worked.
} // End of turnOffFamilyCalendarLink.
