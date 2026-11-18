// Summary: the server action for the Tutor lateness page (Carla, 18 Nov
// 2026). The owner or an operations admin marks a late start reviewed, with
// a private note. The database checks who is asking again.
// See docs/features/tutor-work-rules.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The owner-and-operations group, and the admin check.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Marks one late start reviewed, with a private note.
export async function reviewLateness(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireAdminLevel(FULL_ADMIN); // Only the owner and operations admins.
  const parsed = z.object({ // The rules:
    id: z.uuid(), // which line,
    note: z.string().trim().min(3, "Please write a short note, for example what was discussed with the tutor.").max(1000, "Please keep the note under 1000 characters."), // and the note.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("review_session_lateness", { p_id: parsed.data.id, p_note: parsed.data.note }); // Saves it.
  if (error) return { error: ["42501", "22023"].includes(error.code ?? "") ? error.message : "We could not save that. Please try again." }; // Failed: the database's own words, or a general message.
  revalidatePath("/admin/lateness"); // Refreshes the page.
  return { message: "Saved." }; // Confirms.
} // End of reviewLateness.
