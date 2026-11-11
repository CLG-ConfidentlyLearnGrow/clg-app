// Summary: makes sure parents and students have agreed to the current privacy
// policy and terms, and that parents have given yearly consent for each child.
// Sends them to the agreement page if not.

// Stops this file ever being sent to the browser.
import "server-only";
// Lets the code send someone to another page.
import { redirect } from "next/navigation";
// The signed-in person's details, for type checking only.
import type { Viewer } from "@/lib/auth";
// The current version of the policy and terms.
import { POLICY_VERSION } from "@/lib/forms";
// Connects to the database as the signed-in person.
import { createClient } from "@/lib/supabase/server";

// Parents and students must have agreed to the current privacy policy and
// terms. People who signed up themselves agreed on the sign-up form; families
// set up by CLG agree here the first time they sign in.
export async function requireFamilyAgreement(viewer: Viewer) {
  if (!viewer.roles.includes("parent") && !viewer.roles.includes("student")) return; // Staff-only accounts skip this.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("my_policy_consent", { p_version: POLICY_VERSION }); // Asks: has this person agreed to this version?
  if (data !== true) redirect("/agree"); // Not yet, so sends them to agree first.
  // Parents also agree for each child, once a year.
  if (viewer.roles.includes("parent") && (await childrenNeedingConsent()).length > 0) redirect("/agree"); // Any child due means back to the agreement page.
} // End of requireFamilyAgreement.

// Records a parent's consent for each child listed (renewed every 12
// months; see docs/features/privacy-laws-baseline.md). The database checks
// the parent looks after each child.
export async function giveParentalConsent(studentIds: string[]): Promise<boolean> {
  const supabase = await createClient(); // Connects to the database.
  for (const id of studentIds) { // Goes through each child in turn.
    const { error } = await supabase.rpc("give_parental_consent", { p_student: id, p_version: POLICY_VERSION }); // Saves consent for this child.
    if (error) return false; // Stops and reports failure if one doesn't save.
  } // End of the loop over children.
  return true; // All saved.
} // End of giveParentalConsent.

// Children this parent looks after who need consent given (or renewed).
export async function childrenNeedingConsent(): Promise<{ student_id: string; full_name: string; last_given: string | null }[]> {
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("children_needing_consent"); // Asks the database which children are due.
  return (data ?? []) as { student_id: string; full_name: string; last_given: string | null }[]; // Hands back the list (empty if none).
} // End of childrenNeedingConsent.
