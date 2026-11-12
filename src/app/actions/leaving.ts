// Summary: records why a family or tutor left CLG.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

// When a family or tutor leaves CLG, an admin records why. The database
// checks who can do this (full admins only).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The rules for the "who left" form:
const schema = z.object({
  who: z.string().regex(/^(family|tutor):[0-9a-f-]{36}$/, "Choose who left."), // who left, as "family:id" or "tutor:id",
  left_on: z.iso.date("Choose the day they left."), // the day they left,
  reason: z.string().min(1, "Choose the main reason."), // the main reason (required),
  details: z.string().trim().max(2000).optional(), // more details (optional, up to 2,000 letters),
  left_happy: z.enum(["", "yes", "no"]).optional(), // and whether they left happy (yes, no, or not said).
}); // End of the rules.

// Saves the leaving record.
export async function recordLeaving(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = schema.safeParse(Object.fromEntries(formData)); // Checks the form's fields against the rules above.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // (the checked values)
  const [kind, personId] = v.who.split(":"); // Splits "family:id" into the kind and the id.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("record_leaving", { // Asks the database to save the record:
    p_who: kind, // whether it's a family or tutor,
    p_family: kind === "family" ? personId : null, // the family's id (if a family),
    p_tutor: kind === "tutor" ? personId : null, // the tutor's id (if a tutor),
    p_left_on: v.left_on, // the day they left,
    p_reason: v.reason, // the main reason,
    p_details: v.details || null, // any details (or none),
    p_left_happy: v.left_happy === "yes" ? true : v.left_happy === "no" ? false : null, // left happy: yes, no, or not said,
    p_review_asked: formData.get("review_asked") === "on", // and whether a review was asked for (tick box).
  }); // End of the save.
  if (error) return { error: "Couldn't save the record. Only full admins can record why someone left." }; // Failed: explains only full admins can do this.
  revalidatePath("/admin"); // Refreshes the admin pages so they show the change.
  return { message: "Saved." }; // Tells the person it worked.
} // End of recordLeaving.
