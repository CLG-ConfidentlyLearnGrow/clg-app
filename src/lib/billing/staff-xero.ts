// Summary: the billing module's part in someone leaving CLG. When the owner
// removes a staff member from the team and ticks "End their employment in
// Xero too", the staff directory calls this. It sets their last day and
// reason in Xero Payroll, then ticks off the Xero to-do the database added
// when they left. It writes only billing's own to-do list.

// Stops this file ever being sent to the browser.
import "server-only";
// The all-powerful database helper, used to read the Xero link and tick the to-do off.
import { createAdminClient } from "@/lib/supabase/admin";
// Xero's settings, and the stored Xero connection.
import { xeroConfig } from "./config";
// Checks Xero is connected.
import { xeroConnection } from "./xero";
// The call that ends employment in Xero, and the reason codes.
import { endXeroEmployment, type XeroLeavingCode } from "./payroll";

// Ends someone's employment in Xero. Never throws: it hands back a plain
// sentence saying what happened, for the owner to read.
export async function endEmploymentInXero(accountId: string, lastDay: string, code: XeroLeavingCode): Promise<{ ok: boolean; note: string }> {
  const todo = "It's on the Xero to-do list on Admin > Billing > Staff pay."; // Where the reminder is, for every "not done" case.
  if (!xeroConfig() || !(await xeroConnection().catch(() => null))) { // Xero isn't set up or connected:
    return { ok: false, note: `Xero isn't connected, so end their employment in Xero yourself. ${todo}` }; // says to do it by hand.
  } // End of that check.
  const db = createAdminClient(); // Connects with full access (this runs after the owner's checks).
  const { data: pay } = await db.from("billing_staff_pay").select("xero_employee_id").eq("account_id", accountId).maybeSingle(); // Reads their Xero link.
  if (!pay?.xero_employee_id) { // Not linked to a Xero employee:
    return { ok: false, note: `They weren't linked to a Xero employee, so end their employment in Xero yourself. ${todo}` }; // says to do it by hand.
  } // End of that check.
  try { // Tries:
    await endXeroEmployment(pay.xero_employee_id, lastDay, code); // to end their employment in Xero.
  } catch (e) { // If Xero refused:
    return { ok: false, note: `Xero couldn't be updated (${(e as Error).message}), so end their employment in Xero yourself. ${todo}` }; // says why, and to do it by hand.
  } // End of the try.
  const { data: task } = await db // Finds the to-do for this leaving:
    .from("billing_xero_tasks") // in the Xero to-do list,
    .select("id") // just its id,
    .eq("account_id", accountId) // for this person,
    .eq("kind", "left") // about leaving,
    .is("done_at", null) // still to do,
    .order("created_at", { ascending: false }) // newest first,
    .limit(1) // just one,
    .maybeSingle(); // (or none).
  if (task) await db.rpc("billing_xero_task_done", { p_task: task.id, p_how: "app" }); // Ticks it off as done by the app.
  return { ok: true, note: "Their employment has also been ended in Xero. Pay their final wages and any leave owed in a Xero pay run." }; // Confirms, with the step left in Xero.
} // End of endEmploymentInXero.
