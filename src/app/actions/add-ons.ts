// Summary: add-ons (extras on top of tutoring, such as study plans): the
// owner sets each one free, paid or off; admins give paid add-ons to students.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The full-admin group, and the admin-level check.
import { parseDollars } from "@/lib/billing/money"; // Turns a typed price into cents.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Add-ons: extras on top of tutoring, such as study plans. The owner
// decides whether each one is free, paid or off; admins give a paid add-on
// to the students who pay for it. Every action re-checks who is asking
// here, and the database checks again.

const ADMIN_PAGE = "/admin"; // The admin page, refreshed after changes.
const day = z.union([z.literal(""), z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Choose a date.")]); // A date field that may be blank, or must be YYYY-MM-DD.

// The rules for the add-on settings form:
const setSchema = z.object({
  code: z.string().regex(/^[a-z0-9_]{2,40}$/), // the add-on's code (lower-case letters, numbers and _),
  mode: z.enum(["free", "paid", "off"]), // free, paid or off,
  price: z.string().trim().max(20).optional().default(""), // the price as typed (optional),
  price_period: z.enum(["week", "month", "term"]), // and whether the price is per week, month or term.
}); // End of the rules.

// Saves one add-on's settings (owner only).
export async function setAddOn(_prev: FormState, formData: FormData): Promise<FormState> {
  const viewer = await requireAdminLevel(FULL_ADMIN); // Must be a full admin.
  if (viewer.level !== "owner") return { error: "Only the owner can change an add-on." }; // Only the owner can change add-ons.
  const parsed = setSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: "Please check the form and try again." }; // Problem: general message.
  const v = parsed.data; // The checked values.

  let cents: number | null = null; // The price in cents (none yet).
  if (v.price !== "") { // If a price was typed:
    cents = parseDollars(v.price); // turns it into cents,
    if (cents === null) return { error: "Enter the price in dollars, for example 25 or 29.50." }; // not a price: shows an example.
  } // End of the price.
  if (v.mode === "paid" && !cents) return { error: "Set a price before making it paid." }; // Paid needs a price.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase // Saves to the database:
    .from("add_ons") // in the add-ons table,
    .update({ mode: v.mode, price_cents: cents, price_period: v.price_period, gst_applies: formData.get("gst_applies") === "on" }) // the mode, price, period and whether GST applies (tick box),
    .eq("code", v.code) // for this add-on,
    .select("code"); // and reports which row changed.
  if (error || !data?.length) return { error: "Couldn't save it. Please try again." }; // Nothing saved: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page.
  return { // Tells the admin:
    message: // (the message)
      v.mode === "paid" // if paid,
        ? "Saved. Only students you give it to below can use it now. No one is charged automatically yet." // who can use it now, and that no one is charged automatically yet,
        : "Saved.", // otherwise just "Saved."
  }; // End of the message.
} // End of setAddOn.

// The rules for giving an add-on to a student:
const giveSchema = z.object({
  add_on: z.string().regex(/^[a-z0-9_]{2,40}$/), // the add-on's code,
  student_id: z.uuid("Choose a student."), // which student,
  starts_on: day, // start date (optional),
  ends_on: day, // end date (optional),
  note: z.string().trim().max(300, "Keep the note under 300 characters.").optional().default(""), // a note (optional, up to 300 letters).
}); // End of the rules.

// Gives an add-on to a student (or updates their dates and note).
export async function giveAddOn(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdminLevel(FULL_ADMIN); // Must be a full admin.
  const parsed = giveSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  if (v.starts_on && v.ends_on && v.ends_on < v.starts_on) return { error: "The end date is before the start date." }; // End date can't be before start date.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const row: Record<string, string | null> = { // The row to save:
    add_on: v.add_on, // which add-on,
    student_id: v.student_id, // which student,
    ends_on: v.ends_on || null, // end date (or none),
    note: v.note || null, // note (or none).
  }; // End of the row.
  if (v.starts_on) row.starts_on = v.starts_on; // Adds the start date only if given (otherwise the database uses today).
  const { error } = await supabase.from("add_on_members").upsert(row, { onConflict: "add_on,student_id" }); // Saves it, replacing any existing row for this add-on and student.
  if (error) return { error: "Couldn't save it. Please try again." }; // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page.
  return { message: "Saved." }; // Tells the person it worked.
} // End of giveAddOn.

// Takes an add-on away from a student.
export async function endAddOn(formData: FormData) {
  await requireAdminLevel(FULL_ADMIN); // Must be a full admin.
  const parsed = z // Checks the form has:
    .object({ add_on: z.string().regex(/^[a-z0-9_]{2,40}$/), student_id: z.uuid() }) // an add-on code and a student id,
    .safeParse(Object.fromEntries(formData)); // (from the form's fields).
  if (!parsed.success) return; // Problem: does nothing.
  const supabase = await createClient(); // Connects to the database.
  await supabase.from("add_on_members").delete().eq("add_on", parsed.data.add_on).eq("student_id", parsed.data.student_id); // Deletes that student's add-on row.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page.
} // End of endAddOn.
