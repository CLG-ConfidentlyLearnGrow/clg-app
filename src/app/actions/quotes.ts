// Summary: the server actions for the quotes (Carla, 22 Nov 2026): Carla
// adds, changes and removes quotes, and chooses the quote of the month. The
// database checks every rule again (owner only, no short forms, no repeats).
// See docs/features/quotes.md.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is the owner.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Runs one database request and gives back the form reply. Messages the
// database wrote for people (codes 42501, 22023 and P0002) are shown as they are.
async function run(name: string, args: Record<string, unknown>, done: string): Promise<FormState> { // Takes the function, its inputs, and the thank you message.
  await requireAdminLevel(["owner"]); // Owner only.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc(name, args); // Asks the database.
  if (error) return { error: ["42501", "22023", "P0002"].includes(error.code ?? "") ? error.message : "We could not save this. Please try again." }; // Failed: plain message.
  revalidatePath("/", "layout"); // Refreshes every page (the quotes show on the Overview and loading screen).
  return { message: done }; // Confirms.
} // End of run.

// Adds or changes a quote.
export async function saveQuote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ // The form's fields:
    id: z.union([z.literal(""), z.uuid()]).default(""), // which quote (blank for a new one),
    body: z.string().trim().min(3, "Please write the quote.").max(400, "Please keep the quote under 400 characters."), // the quote,
    who: z.string().trim().min(2, "Please write who said it.").max(120, "Please keep this under 120 characters."), // who said it,
    theme: z.string().trim().max(60, "Please keep the theme short.").optional(), // the theme.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  const active = p.data.id ? formData.get("active") === "on" : true; // Whether it is in use (new ones always are).
  return run("quote_save", { p_id: p.data.id || null, p_body: p.data.body, p_who: p.data.who, p_theme: p.data.theme || null, p_active: active }, "Saved."); // Saves it.
} // End of saveQuote.

// Removes a quote.
export async function removeQuote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const id = z.uuid().safeParse(formData.get("id")); // Reads and checks the id.
  if (!id.success) return { error: "Could not read which quote this is." }; // Bad id: plain message.
  return run("quote_remove", { p_id: id.data }, "Removed."); // Removes it.
} // End of removeQuote.

// Chooses (or clears) the quote of the month.
export async function setMonthQuote(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  const p = z.object({ month: z.string().regex(/^\d{4}-\d{2}-01$/, "Please choose a month."), quote: z.union([z.literal(""), z.uuid()]).default("") }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!p.success) return { error: p.error.issues[0].message }; // Shows the first rule that failed.
  return run("quote_set_month", { p_month: p.data.month, p_quote: p.data.quote || null }, p.data.quote ? "Quote of the month chosen." : "Choice cleared. The month uses the next quote in the list."); // Saves it.
} // End of setMonthQuote.
