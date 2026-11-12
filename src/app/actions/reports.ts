// Summary: the owner's report actions: make a report for chosen dates,
// delete one of those, and change the report settings (super and other costs).
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

// The database checks that only the owner can do any of these.

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { parseDollars } from "@/lib/billing/money"; // Reads a typed price like "$1,200" as cents.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// The rules for the "make a report" form:
const makeSchema = z.object({
  from: z.iso.date("Choose the first day."), // the first day,
  to: z.iso.date("Choose the last day."), // the last day.
}).refine((v) => v.from <= v.to, { message: "Choose a first day on or before the last day." }); // The first day can't be after the last.

// Makes a report for the dates chosen, then opens it.
export async function makeReport(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = makeSchema.safeParse(Object.fromEntries(formData)); // Checks the form's fields against the rules above.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("report_make", { p_from: parsed.data.from, p_to: parsed.data.to }); // Asks the database to make and save the report.
  if (error || !data) return { error: error?.message.startsWith("Choose") ? error.message : "Couldn't make the report. Only the owner can make reports." }; // Failed: shows the database's plain message, or explains only the owner can.
  revalidatePath("/admin/reports"); // Refreshes the reports page so the new report is listed.
  redirect(`/admin/reports?id=${data as string}`); // Opens the new report.
} // End of makeReport.

// Deletes a report the owner made for their own dates.
export async function deleteReport(formData: FormData): Promise<void> {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Checks the report id looks right.
  if (!id.success) return; // Not a real id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("report_delete", { p_id: id.data }); // Asks the database to delete it (it refuses automatic reports).
  revalidatePath("/admin/reports"); // Refreshes the reports page.
  redirect("/admin/reports"); // Goes back to the list.
} // End of deleteReport.

// The rules for the settings form:
const settingsSchema = z.object({
  super_percent: z.coerce.number("Enter super as a number, e.g. 12.").min(0, "Super can't be below 0%.").max(50, "Super can't be above 50%."), // super, 0 to 50%,
  other_costs: z.string().trim(), // other costs a month, as typed.
}); // End of the rules.

// Saves the super percentage and other monthly costs used for profit.
export async function saveReportSettings(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = settingsSchema.safeParse(Object.fromEntries(formData)); // Checks the form's fields against the rules above.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const cents = parsed.data.other_costs === "" ? 0 : parseDollars(parsed.data.other_costs); // Reads the other costs (blank means none).
  if (cents === null) return { error: "Enter other costs as dollars, e.g. 1200 or $1,200.50." }; // Not a price: explains how to type it.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("report_save_settings", { p_super_percent: parsed.data.super_percent, p_monthly_other_costs_cents: cents }); // Asks the database to save them.
  if (error) return { error: "Couldn't save. Only the owner can change report settings." }; // Failed: explains only the owner can.
  revalidatePath("/admin/reports"); // Refreshes the reports page.
  return { message: "Saved. New reports will use these settings." }; // Tells the person it worked.
} // End of saveReportSettings.
