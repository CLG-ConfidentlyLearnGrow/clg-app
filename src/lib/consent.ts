import "server-only";
import { redirect } from "next/navigation";
import type { Viewer } from "@/lib/auth";
import { POLICY_VERSION } from "@/lib/forms";
import { createClient } from "@/lib/supabase/server";

// Parents and students must have agreed to the current privacy policy and
// terms. People who signed up themselves agreed on the sign-up form; families
// set up by CLG agree here the first time they sign in.
export async function requireFamilyAgreement(viewer: Viewer) {
  if (!viewer.roles.includes("parent") && !viewer.roles.includes("student")) return;
  const supabase = await createClient();
  const { data } = await supabase.rpc("my_policy_consent", { p_version: POLICY_VERSION });
  if (data !== true) redirect("/agree");
  // Parents also agree for each child, once a year.
  if (viewer.roles.includes("parent") && (await childrenNeedingConsent()).length > 0) redirect("/agree");
}

// Records a parent's consent for each child listed (renewed every 12
// months; see docs/features/privacy-laws-baseline.md). The database checks
// the parent looks after each child.
export async function giveParentalConsent(studentIds: string[]): Promise<boolean> {
  const supabase = await createClient();
  for (const id of studentIds) {
    const { error } = await supabase.rpc("give_parental_consent", { p_student: id, p_version: POLICY_VERSION });
    if (error) return false;
  }
  return true;
}

// Children this parent looks after who need consent given (or renewed).
export async function childrenNeedingConsent(): Promise<{ student_id: string; full_name: string; last_given: string | null }[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("children_needing_consent");
  return (data ?? []) as { student_id: string; full_name: string; last_given: string | null }[];
}
