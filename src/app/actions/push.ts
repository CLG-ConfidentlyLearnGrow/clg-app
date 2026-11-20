// Summary: server actions for pop-up notifications (Carla, 18 Nov 2026):
// turning them on or off for the device someone is using, removing one of
// their other devices, and sending themselves a test pop-up. The database
// checks again that each device is the person's own.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { z } from "zod"; // The form-checking library.
import { revalidatePath } from "next/cache"; // Refreshes a page so it shows the latest details.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { sendTestPopUp } from "@/lib/push"; // Sends a test pop-up to a person's devices.

// What the browser hands over when pop-ups are turned on.
const subscriptionSchema = z.object({ // The device's details:
  endpoint: z.string().url().startsWith("https://").max(1000), // its private delivery address (secure web addresses only),
  p256dh: z.string().min(20).max(200), // its public key,
  auth: z.string().min(8).max(100), // its shared secret,
  label: z.string().max(80), // and a name for it, e.g. "iPhone (Safari)".
}); // End of the rules.

// The answer each action gives back to the screen.
export type PushResult = { ok: boolean; message: string }; // Whether it worked, and a plain message.

// Saves the device the person is using, so pop-ups go to it.
export async function savePushDevice(input: { endpoint: string; p256dh: string; auth: string; label: string }): Promise<PushResult> { // Starts the steps.
  const parsed = subscriptionSchema.safeParse(input); // Checks what the browser sent.
  if (!parsed.success) return { ok: false, message: "This device did not give the details the app needs. Please try again, or try another browser." }; // Not valid: plain message.
  const supabase = await createClient(); // Connects as the signed-in person.
  const { error } = await supabase.rpc("push_subscribe", { // Saves the device (the database links it to whoever is signed in):
    p_endpoint: parsed.data.endpoint, // its address,
    p_p256dh: parsed.data.p256dh, // its key,
    p_auth: parsed.data.auth, // its secret,
    p_label: parsed.data.label, // and its name.
  }); // End of the save.
  if (error) return { ok: false, message: error.message }; // Refused: passes on the database's plain message.
  revalidatePath("/schedule"); // Refreshes the Notices page so the device list is up to date.
  return { ok: true, message: "Pop-ups are on for this device." }; // Worked.
} // End of savePushDevice.

// Turns pop-ups off for the device the person is using.
export async function removeThisPushDevice(endpoint: string): Promise<PushResult> { // Starts the steps.
  if (typeof endpoint !== "string" || endpoint.length > 1000) return { ok: false, message: "Something went wrong. Please try again." }; // Not valid: plain message.
  const supabase = await createClient(); // Connects as the signed-in person.
  const { error } = await supabase.rpc("push_unsubscribe", { p_endpoint: endpoint }); // Removes the device (only if it is theirs).
  if (error) return { ok: false, message: error.message }; // Refused: plain message.
  revalidatePath("/schedule"); // Refreshes the Notices page.
  return { ok: true, message: "Pop-ups are off for this device." }; // Worked.
} // End of removeThisPushDevice.

// Removes one of the person's other devices from the list.
export async function removePushDevice(id: string): Promise<PushResult> { // Starts the steps.
  const parsed = z.string().uuid().safeParse(id); // Checks it is a proper id.
  if (!parsed.success) return { ok: false, message: "Something went wrong. Please try again." }; // Not valid: plain message.
  const supabase = await createClient(); // Connects as the signed-in person.
  const { error } = await supabase.rpc("push_remove_device", { p_id: parsed.data }); // Removes it (only if it is theirs).
  if (error) return { ok: false, message: error.message }; // Refused: plain message.
  revalidatePath("/schedule"); // Refreshes the Notices page.
  return { ok: true, message: "That device will not get pop-ups any more." }; // Worked.
} // End of removePushDevice.

// Sends a test pop-up to all of the signed-in person's devices.
export async function sendMeATestPopUp(): Promise<PushResult> { // Starts the steps.
  const supabase = await createClient(); // Connects as the signed-in person.
  const { data } = await supabase.auth.getUser(); // Finds out who is signed in.
  if (!data.user) return { ok: false, message: "Please sign in again." }; // Nobody signed in: plain message.
  const result = await sendTestPopUp(data.user.id); // Sends the test to their devices only.
  if (result.problem) return { ok: false, message: result.problem }; // Not set up: plain message.
  if (result.devices === 0) return { ok: false, message: "Pop-ups are not turned on for any of your devices yet." }; // No devices: says so.
  return { ok: result.sent > 0, message: result.sent > 0 ? `A test pop-up was sent to ${result.sent} of your devices. It can take a minute to arrive.` : "The test pop-up could not be delivered. Please turn pop-ups off and on again on this device." }; // How it went.
} // End of sendMeATestPopUp.
