// Summary: lets an admin write a short overview of a university or TAFE
// unit, so the tutor can read about it before the first session.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is an admin at the right level.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// An admin writes a short overview of a university or TAFE unit, so the
// tutor can read about it before the first session. Blank clears it.
// See docs/features/tertiary-study-details.md.
// The rules for the overview form:
const schema = z.object({
  subject_id: z.uuid(), // which unit (must be a proper id),
  overview: z.string().trim().max(4000, "Please keep the overview under 4,000 characters."), // and the overview text (up to 4,000 letters; blank clears it).
}); // End of the rules.

// Saves (or clears) one unit's overview.
export async function setCourseOverview(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(["owner", "operations", "support"]); // Only owner, operations and support admins.
  const parsed = schema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("admin_set_course_overview", { // Asks the database to save the overview:
    p_subject: parsed.data.subject_id, // for this unit,
    p_overview: parsed.data.overview, // with this text.
  }); // End of the save.
  if (error) { // The save failed:
    console.error("Set course overview failed:", error.code, error.message); // notes why in the server log,
    return { error: error.code === "22023" ? `${error.message}.` : "We couldn't save the overview. Please try again." }; // shows the database's own plain message if it gave one, otherwise a general one.
  } // End of the failure case.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: parsed.data.overview ? "Overview saved. The tutor will see it." : "Overview cleared." }; // Confirms it saved (or cleared).
} // End of setCourseOverview.
