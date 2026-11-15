// Summary: reads a person's first and last name, and makes sure tutors and
// admins have given both before they use their dashboard (Carla, 15 Nov 2026:
// staff were showing as the start of their email, like "amy.swann2000").
// See docs/features/staff-names.md.

// Stops this file ever being sent to the browser.
import "server-only";
// Lets the code send someone to another page.
import { redirect } from "next/navigation";
// The signed-in person's details, for type checking only.
import type { Viewer } from "@/lib/auth";
// Connects to the database as the signed-in person.
import { createClient } from "@/lib/supabase/server";

// A person's first and last name as saved (either can be blank).
export type NameParts = { first: string; last: string };

// Reads the signed-in person's own first and last name. Gives back null if
// the database couldn't answer (for example, before Carla has run the
// staff names update), so nobody is ever stuck because of that.
export async function readMyNameParts(viewer: Viewer): Promise<NameParts | null> {
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase // Asks the database for:
    .from("accounts") // their account row,
    .select("first_name, last_name") // its first and last name,
    .eq("id", viewer.id) // for this person only,
    .maybeSingle(); // (one row, or none).
  if (error || !data) return null; // Couldn't read it: don't guess.
  return { first: (data.first_name as string | null) ?? "", last: (data.last_name as string | null) ?? "" }; // Hands back both names (blank if not given).
} // End of readMyNameParts.

// Tutors and admins must have a first and last name, so colleagues and
// families see a real name. If either is missing, sends them to the name
// page first, which brings them back here once it's saved.
export async function requireStaffName(viewer: Viewer, backTo: string) {
  const isStaff = viewer.roles.includes("tutor") || viewer.roles.includes("admin"); // True for tutors and admins.
  if (!isStaff) return; // Families aren't asked here (they gave a name when signing up).
  const parts = await readMyNameParts(viewer); // Reads their first and last name.
  if (!parts) return; // Couldn't read it: let them carry on rather than block them.
  if (parts.first && parts.last) return; // Both given: nothing to do.
  redirect(`/my-name?next=${encodeURIComponent(backTo)}`); // Missing: asks for it, then comes back.
} // End of requireStaffName.
