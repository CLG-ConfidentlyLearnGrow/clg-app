// Summary: sends pop-up notifications to people's phones and computers
// (Carla, 18 Nov 2026). The database decides what is due (push_claim); this
// file locks each pop-up so only the person's device can read it, and hands
// it to the browser maker's push service (Apple, Google, Microsoft or
// Mozilla), which delivers it to the device.
//
// Settings (in Vercel's Environment Variables, see docs/features/push-notifications.md):
//   NEXT_PUBLIC_VAPID_PUBLIC_KEY  CLG's public pop-up key (safe to show; the browser needs it)
//   VAPID_PRIVATE_KEY             CLG's private pop-up key (secret; proves pop-ups come from CLG)
//   VAPID_SUBJECT                 a contact for the push services, e.g. mailto:admin@clgtutoring.com (optional)

import "server-only"; // Stops this file ever being sent to the browser, because it uses the private key.
import webpush from "web-push"; // The library that locks and sends pop-ups using the web push standard.
import { createAdminClient } from "@/lib/supabase/admin"; // Connects to the database with full access (server only).

// One pop-up waiting to be sent, as push_claim hands it over.
export type DuePopUp = { // The shape, listed below.
  source: string; // which kind of notice (session, progress, help_chat, lateness, safety_concern)
  source_id: string; // the notice's id in its own table
  account_id: string; // who it is for
  title: string; // the heading (never names or details)
  body: string; // the message (never names or details)
  link: string; // the CLG page it opens when tapped
  urgent: boolean; // true for "immediate danger" child safety alerts
}; // End of the pop-up shape.

// One device with pop-ups turned on.
type Device = { // The shape, listed below.
  id: string; // the device row's id
  account_id: string; // whose device it is
  endpoint: string; // its private delivery address
  p256dh: string; // its public key
  auth_secret: string; // its shared secret
  failures: number; // how many sends in a row have failed
}; // End of the device shape.

// After this many failed sends in a row, a device is removed (it has most
// likely been reset, or the browser was removed).
const MAX_FAILURES = 5; // Five failures in a row.

// The public key, which the browser needs to turn pop-ups on. Blank until set.
export function pushPublicKey(): string { // Starts the steps.
  return process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? ""; // The key from Vercel's settings, or blank.
} // End of pushPublicKey.

// True once both pop-up keys are set, so pop-ups can be sent.
export function pushIsSetUp(): boolean { // Starts the steps.
  return Boolean(pushPublicKey() && process.env.VAPID_PRIVATE_KEY); // Both keys are needed.
} // End of pushIsSetUp.

// Gives the web push library CLG's keys. Done each time so a key changed in
// Vercel is picked up on the next run.
function applyKeys(): void { // Starts the steps.
  webpush.setVapidDetails( // Sets the details the push services check:
    process.env.VAPID_SUBJECT || "mailto:noreply@clgtutoring.com", // who to contact about CLG's pop-ups,
    pushPublicKey(), // CLG's public key,
    process.env.VAPID_PRIVATE_KEY ?? "", // and CLG's private key.
  ); // End of the details.
} // End of applyKeys.

// A label for a pop-up, so a newer one of the same kind replaces the older
// one instead of stacking up (for example several help chat messages).
function tagFor(p: DuePopUp): string { // Starts the steps.
  return p.source === "help_chat" ? `help-${p.link}` : `clg-${p.source}`; // One per chat for help chat, one per kind otherwise.
} // End of tagFor.

// Sends one pop-up to one device. Returns "sent", "gone" (the device no
// longer exists, so it should be removed) or "failed" (try again later).
async function sendOne(device: Device, p: DuePopUp): Promise<"sent" | "gone" | "failed"> { // Starts the steps.
  const payload = JSON.stringify({ title: p.title, body: p.body, link: p.link, tag: tagFor(p), urgent: p.urgent }); // What the device will show (no names or details).
  try { // The push service might refuse it.
    await webpush.sendNotification( // Locks the pop-up for this device and sends it:
      { endpoint: device.endpoint, keys: { p256dh: device.p256dh, auth: device.auth_secret } }, // to this device, using its key and secret,
      payload, // with the pop-up's words,
      { TTL: p.urgent ? 60 * 60 * 12 : 60 * 60 * 4, urgency: p.urgent ? "high" : "normal" }, // kept by the push service for up to 4 hours (12 if urgent) while the device is off.
    ); // End of the send.
    return "sent"; // Accepted.
  } catch (err) { // It was refused or could not be reached:
    const status = (err as { statusCode?: number }).statusCode; // the push service's answer code, if any.
    if (status === 404 || status === 410) return "gone"; // 404 or 410 means the device's address no longer exists.
    console.error("Sending a pop-up:", status ?? "", err instanceof Error ? err.message : String(err)); // Notes any other problem in the server log (no personal details).
    return "failed"; // Try again later.
  } // End of the error handling.
} // End of sendOne.

// Collects every pop-up due now and sends it to each of the person's
// devices. Returns how many were sent and any problem message.
export async function sendDuePopUps(): Promise<{ sent: number; problem?: string }> { // Starts the steps.
  if (!pushIsSetUp()) { // The keys are not set yet:
    return { sent: 0, problem: "Pop-up notifications are not set up yet (the VAPID keys are missing in Vercel)." }; // says so and sends nothing.
  } // End of the check.
  applyKeys(); // Gives the library CLG's keys.
  const supabase = createAdminClient(); // Connects with full access.
  const claimed = await supabase.rpc("push_claim", { p_limit: 200 }); // Collects up to 200 due pop-ups (each is marked as sent).
  if (claimed.error) return { sent: 0, problem: `push_claim: ${claimed.error.message}` }; // Could not collect them: reports why.
  const due = (claimed.data ?? []) as DuePopUp[]; // The pop-ups.
  if (due.length === 0) return { sent: 0 }; // Nothing due: done.

  const people = [...new Set(due.map((p) => p.account_id))]; // Everyone who has a pop-up waiting (each once).
  const devicesRes = await supabase // Reads their devices:
    .from("push_subscriptions") // from the devices table,
    .select("id, account_id, endpoint, p256dh, auth_secret, failures") // these details,
    .in("account_id", people); // for those people.
  if (devicesRes.error) { // Could not read them:
    await release(supabase, due); // puts every pop-up back to try again next time,
    return { sent: 0, problem: `Reading devices: ${devicesRes.error.message}` }; // and reports why.
  } // End of the failure case.
  const devices = (devicesRes.data ?? []) as Device[]; // The devices.

  let sent = 0; // How many pop-ups reached at least one device.
  const retry: DuePopUp[] = []; // Pop-ups that no device took, to try again next time.
  const gone = new Set<string>(); // Devices whose address no longer exists.
  const failed = new Map<string, number>(); // Devices that failed this time, with their new failure count.
  const worked = new Set<string>(); // Devices that took at least one pop-up.
  for (const p of due) { // For each pop-up:
    const mine = devices.filter((d) => d.account_id === p.account_id && !gone.has(d.id)); // that person's devices (skipping ones already found gone),
    const results = await Promise.all(mine.map((d) => sendOne(d, p))); // sends it to all of them at once.
    results.forEach((r, i) => { // For each device's result:
      const d = mine[i]; // the device,
      if (r === "sent") worked.add(d.id); // took it: noted,
      if (r === "gone") gone.add(d.id); // no longer exists: noted for removal,
      if (r === "failed") failed.set(d.id, (failed.get(d.id) ?? d.failures) + 1); // failed: one more failure noted.
    }); // End of the results.
    if (results.includes("sent")) sent += 1; // At least one device took it: counted.
    else if (results.includes("failed")) retry.push(p); // None took it but some may later: tried again next time.
  } // End of the pop-ups.

  if (gone.size > 0) await supabase.from("push_subscriptions").delete().in("id", [...gone]); // Removes devices that no longer exist.
  for (const [id, count] of failed) { // For each device that failed:
    if (worked.has(id)) continue; // it took another pop-up, so it is working: skipped.
    if (count >= MAX_FAILURES) await supabase.from("push_subscriptions").delete().eq("id", id); // Too many failures in a row: removed.
    else await supabase.from("push_subscriptions").update({ failures: count }).eq("id", id); // Otherwise: the failure count is saved.
  } // End of the failed devices.
  if (worked.size > 0) { // Some devices took pop-ups:
    await supabase.from("push_subscriptions").update({ failures: 0, last_sent_at: new Date().toISOString() }).in("id", [...worked]); // marks them as working, sent just now.
  } // End of the working devices.
  if (retry.length > 0) await release(supabase, retry); // Puts back pop-ups to try again next run.
  return { sent }; // Reports how many were sent.
} // End of sendDuePopUps.

// Puts pop-ups back in the queue, so the next run tries them again.
async function release(supabase: ReturnType<typeof createAdminClient>, items: DuePopUp[]): Promise<void> { // Starts the steps.
  await supabase.rpc("push_release", { // Asks the database to forget they were sent:
    p_sources: items.map((p) => p.source), // their kinds,
    p_ids: items.map((p) => p.source_id), // their notice ids,
    p_accounts: items.map((p) => p.account_id), // and who they were for.
  }); // End of the request.
} // End of release.

// Sends a test pop-up to every device of one person, so they can check it
// works. Returns how many devices took it.
export async function sendTestPopUp(accountId: string): Promise<{ sent: number; devices: number; problem?: string }> { // Starts the steps.
  if (!pushIsSetUp()) return { sent: 0, devices: 0, problem: "Pop-up notifications are not set up yet. Please let CLG know." }; // Keys missing: says so.
  applyKeys(); // Gives the library CLG's keys.
  const supabase = createAdminClient(); // Connects with full access (the person was checked by the caller).
  const res = await supabase // Reads their devices:
    .from("push_subscriptions") // from the devices table,
    .select("id, account_id, endpoint, p256dh, auth_secret, failures") // these details,
    .eq("account_id", accountId); // for this person only.
  const devices = (res.data ?? []) as Device[]; // The devices.
  const test: DuePopUp = { // The test pop-up:
    source: "test", // a test,
    source_id: "test", // with no notice behind it,
    account_id: accountId, // for this person,
    title: "Pop-ups are working", // the heading,
    body: "This is a test from the CLG app. You will see notices like this on this device.", // the message,
    link: "/schedule?section=notices", // opens the Notices section,
    urgent: false, // not urgent.
  }; // End of the test pop-up.
  const results = await Promise.all(devices.map((d) => sendOne(d, test))); // Sends it to every device at once.
  const goneIds = devices.filter((_, i) => results[i] === "gone").map((d) => d.id); // Devices that no longer exist.
  if (goneIds.length > 0) await supabase.from("push_subscriptions").delete().in("id", goneIds); // Removes them.
  return { sent: results.filter((r) => r === "sent").length, devices: devices.length }; // Reports how many took it, out of how many.
} // End of sendTestPopUp.
