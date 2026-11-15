// Summary: the server action for moving a student's booked sessions to a
// new tutor (scheduling module, Carla 15 Nov 2026). Only matching admins
// (owner, operations, support) with two-step sign-in can do it; the database
// checks that again, along with every matching rule, and gives plain
// messages when something stands in the way.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The rules for the form:
const changeSchema = z.object({ // Each field and its rule:
  student: z.uuid({ message: "Please choose the student again." }), // the student,
  from_tutor: z.uuid({ message: "Please choose the current tutor again." }), // the tutor the sessions are with now,
  subject: z.string().trim().min(1, "Please choose the subject again.").max(100, "Please choose the subject again."), // the subject,
  to_tutor: z.uuid({ message: "Please choose the new tutor." }), // the new tutor,
  from: z.iso.date({ message: "Please choose the change date." }), // the first date to move,
  reason: z.string().trim().min(2, "Please give a short reason.").max(500, "Please keep the reason under 500 characters."), // a short reason,
  tell_old_tutor: z.literal("on").optional(), // the "tell the old tutor" tick.
}); // End of the rules.

// Moves the sessions, and says how many moved.
export async function changeTutor(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message or an error.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = changeSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("change_session_tutor", { // Asks the database to make the change:
    p_student: d.student, // the student,
    p_from_tutor: d.from_tutor, // the current tutor,
    p_subject: d.subject, // the subject,
    p_to_tutor: d.to_tutor, // the new tutor,
    p_from: d.from, // from this date,
    p_reason: d.reason, // why,
    p_tell_old_tutor: d.tell_old_tutor === "on", // and whether to tell the old tutor.
  }); // End of the request.
  if (error) { // The database said no:
    const plain = ["42501", "22023", "23514"].includes(error.code ?? ""); // whether it's one of its plain messages for people,
    return { error: plain ? error.message : "Sorry, the sessions couldn't be moved. Please try again, or contact Carla." }; // its words, or a general message.
  } // End of the error case.
  revalidatePath("/schedule"); // Refreshes the Sessions pages.
  revalidatePath("/matching"); // Refreshes the Matching page (its urgent box).
  const moved = Number(data ?? 0); // How many sessions moved.
  return { // Says it worked:
    message: `Done: ${moved} session${moved === 1 ? "" : "s"} moved to the new tutor, and everyone has been told. If this was an urgent re-match, please mark it sorted on the Matching page.`, // with the count and the next step.
  }; // End of the reply.
} // End of changeTutor.
