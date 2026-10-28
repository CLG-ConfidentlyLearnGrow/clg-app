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
}
