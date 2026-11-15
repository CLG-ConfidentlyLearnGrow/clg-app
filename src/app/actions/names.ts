// Summary: saving first and last names. Anyone can change their own name;
// the owner and operations admins can change a tutor's or admin's name from
// the staff directory. The database tidies and checks the name again, and
// notes each change in the activity log. See docs/features/staff-names.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new name.
import { redirect } from "next/navigation"; // Lets the code send someone to another page.
import { z } from "zod"; // The form-checking library.
import { requireAdmin, requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, or is a full admin.
import { safeNextPath, type FormState } from "@/lib/forms"; // The safe "go to" check, and the shape of a form's reply.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The rule for one name box: trimmed, 1 to 100 characters.
const namePart = (what: string) => // Makes the rule for a box called "what":
  z.string().trim().min(1, `Please enter a ${what}.`).max(100, `Please keep the ${what} to 100 characters or fewer.`); // (the rule itself)

// The rules for the name form.
const nameSchema = z.object({
  first_name: namePart("first name"), // first name (required),
  last_name: namePart("last name"), // last name (required).
}); // End of the rules.

// Turns a database refusal into a plain message for the person.
function plainError(error: { code?: string; message: string }, fallback: string): string {
  const plain = ["42501", "22023"].includes(error.code ?? ""); // True for the database's own plain refusals (wrong person, or a name that isn't right).
  return plain ? `${error.message}.` : fallback; // Shows that message, or a general one.
} // End of plainError.

// Refreshes every page that shows names, so the new name appears straight away.
function refreshNames() {
  revalidatePath("/", "layout"); // Refreshes the whole app (the top bar shows the signed-in name on every page).
} // End of refreshNames.

// Saves the signed-in person's own first and last name. If the form says
// where to go next (because they were asked for their name before using
// their dashboard), goes there once saved.
export async function setMyName(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in (sends anyone else to sign in).
  const parsed = nameSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { first_name, last_name } = parsed.data; // The checked names.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_my_name", { p_first: first_name, p_last: last_name }); // Asks the database to save it (only ever their own name).
  if (error) return { error: plainError(error, "Couldn't save your name. Please try again.") }; // It failed: says so plainly.

  refreshNames(); // Shows the new name everywhere.
  const next = formData.get("next"); // Where to go next, if the form says.
  if (typeof next === "string" && next) redirect(safeNextPath(next)); // Goes there (only to a page on this site).
  return { message: `Saved. You now show as ${first_name} ${last_name}.` }; // Otherwise confirms what they now show as.
} // End of setMyName.

// The rules for an admin changing a staff member's name: whose, plus the names.
const staffNameSchema = nameSchema.extend({ account_id: z.uuid() });

// The owner or an operations admin saves a tutor's or admin's first and last name.
export async function setStaffName(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin(); // Makes sure the person is the owner or an operations admin (sends anyone else away).
  const parsed = staffNameSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const { account_id, first_name, last_name } = parsed.data; // The checked values.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("set_staff_name", { p_account: account_id, p_first: first_name, p_last: last_name }); // Asks the database to save it (it checks the admin's level again).
  if (error) return { error: plainError(error, "Couldn't save the name. Please try again.") }; // It failed: says so plainly.

  refreshNames(); // Shows the new name everywhere.
  return { message: `Saved as ${first_name} ${last_name}` }; // Confirms the new name.
} // End of setStaffName.
