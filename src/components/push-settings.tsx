// Summary: the "Pop-up notifications" controls (Carla, 18 Nov 2026). Two
// pieces share the same browser steps:
//   * PushSettings: the full card in Sessions > Notices, to turn pop-ups on
//     or off for this device, see and remove other devices, and send a test.
//   * PushPrompt: a small, dismissable note on each dashboard inviting the
//     person to turn pop-ups on, shown only until they decide.
// Pop-ups need the browser's permission, which must be asked for after a
// button press (phones refuse it otherwise), so nothing is asked by itself.
//
"use client"; // Marks this file as code that runs in the browser.

import { useCallback, useEffect, useRef, useState } from "react"; // React's tools for remembering values, keeping a value in a box, and running steps after showing.
import Link from "next/link"; // Links between app pages.
import { Button } from "@/components/ui"; // CLG's main button (shows a spinner while busy).
import { removePushDevice, removeThisPushDevice, savePushDevice, sendMeATestPopUp } from "@/app/actions/push"; // The server steps for pop-ups.

// CLG's public pop-up key. It is safe to show, and the browser needs it to
// turn pop-ups on. Blank until Carla adds it in Vercel.
// Any spaces, line breaks or quote marks picked up when the key was pasted
// into Vercel are removed, because the browser refuses a key with them
// (Carla, 20 Nov 2026: "Something went wrong" on the first try).
const PUBLIC_KEY = (process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? "").replace(/[^A-Za-z0-9_-]/g, ""); // The key with only its own letters, numbers, - and _ kept, or blank.

// Where "Not now" on the dashboard note is remembered on this device.
const DISMISS_KEY = "clg-push-prompt-dismissed"; // The saved setting's name.

// What this device can do about pop-ups right now.
type DeviceState = // The shape, listed below.
  | "checking" // still finding out
  | "unsupported" // this browser cannot show pop-ups
  | "needs-install" // an iPhone or iPad that must add CLG to the home screen first
  | "blocked" // the person said no to pop-ups in the browser before
  | "off" // pop-ups could be turned on
  | "on"; // pop-ups are on for this device

// One of the person's devices, as the Notices page reads it.
export type PushDevice = { id: string; device_label: string; endpoint: string; last_seen_at: string; created_at: string }; // Its id, name, address and dates.

// Turns the public key (written in letters) into the bytes the browser wants.
function keyToBytes(base64: string): Uint8Array<ArrayBuffer> { // Starts the steps.
  const padding = "=".repeat((4 - (base64.length % 4)) % 4); // Adds the padding the key format leaves off.
  const text = atob((base64 + padding).replace(/-/g, "+").replace(/_/g, "/")); // Changes the web-safe letters back and decodes them.
  const bytes = new Uint8Array(new ArrayBuffer(text.length)); // Makes room for the bytes.
  for (let i = 0; i < text.length; i += 1) bytes[i] = text.charCodeAt(i); // Copies each one across.
  return bytes; // Hands back the bytes.
} // End of keyToBytes.

// A short name for this device from what the browser says about itself,
// e.g. "iPhone (Safari)" or "Windows (Edge)", so people can tell devices apart.
function deviceLabel(): string { // Starts the steps.
  const ua = navigator.userAgent; // What the browser says about itself.
  const device = /iPhone/.test(ua) ? "iPhone" // an iPhone,
    : /iPad|Macintosh.*Mobile/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) ? "iPad" // an iPad (newer ones say "Macintosh" but have a touch screen),
    : /Android/.test(ua) ? "Android" // an Android phone or tablet,
    : /Windows/.test(ua) ? "Windows" // a Windows computer,
    : /Macintosh/.test(ua) ? "Mac" // a Mac,
    : /CrOS/.test(ua) ? "Chromebook" // a Chromebook,
    : "Computer"; // or anything else.
  const browser = /Edg\//.test(ua) ? "Edge" // Microsoft Edge,
    : /Firefox|FxiOS/.test(ua) ? "Firefox" // Firefox,
    : /Chrome|CriOS/.test(ua) ? "Chrome" // Chrome,
    : /Safari/.test(ua) ? "Safari" // Safari,
    : "browser"; // or another browser.
  return `${device} (${browser})`; // Puts them together.
} // End of deviceLabel.

// True on an iPhone or iPad that has not been added to the home screen.
// Apple only allows pop-ups once CLG is on the home screen (iOS 16.4 or later).
function iosNeedsInstall(): boolean { // Starts the steps.
  const ua = navigator.userAgent; // What the browser says about itself.
  const isApple = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1); // An iPhone or iPad.
  const installed = window.matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone === true; // Opened from the home screen.
  return isApple && !installed; // Needs adding to the home screen first.
} // End of iosNeedsInstall.

// Finds out what this device can do, and its current pop-up address if any.
async function readDevice(): Promise<{ state: DeviceState; endpoint: string | null }> { // Starts the steps.
  if (iosNeedsInstall()) return { state: "needs-install", endpoint: null }; // iPhone or iPad not on the home screen yet.
  if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) return { state: "unsupported", endpoint: null }; // The browser cannot do pop-ups.
  if (Notification.permission === "denied") return { state: "blocked", endpoint: null }; // The person said no before.
  const reg = await navigator.serviceWorker.getRegistration("/"); // CLG's service worker, if it is set up.
  const sub = reg ? await reg.pushManager.getSubscription() : null; // This device's pop-up address, if any.
  if (sub && Notification.permission === "granted") return { state: "on", endpoint: sub.endpoint }; // Pop-ups are on.
  return { state: "off", endpoint: null }; // Pop-ups could be turned on.
} // End of readDevice.

// Asks the browser for permission, sets up CLG's service worker, makes a
// pop-up address for this device and saves it. Returns a plain problem
// message, or null when it worked.
async function turnOn(): Promise<string | null> { // Starts the steps.
  if (!PUBLIC_KEY) return "Pop-up notifications are not set up yet. Please let CLG know."; // The key is missing: plain message.
  const permission = await Notification.requestPermission(); // Asks the person (the browser shows its own question).
  if (permission !== "granted") return "Pop-ups were not allowed. You can allow them later in your browser or phone settings."; // They said no: plain message.
  const reg = await navigator.serviceWorker.register("/sw.js", { scope: "/" }); // Sets up CLG's service worker (or finds it).
  await navigator.serviceWorker.ready; // Waits until it is running.
  const sub = (await reg.pushManager.getSubscription()) // Uses this device's existing pop-up address,
    ?? (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyToBytes(PUBLIC_KEY) })); // or makes a new one (every pop-up will be shown, as browsers require).
  const json = sub.toJSON(); // The address and keys as plain values.
  const result = await savePushDevice({ endpoint: sub.endpoint, p256dh: json.keys?.p256dh ?? "", auth: json.keys?.auth ?? "", label: deviceLabel() }); // Saves it for the signed-in person.
  return result.ok ? null : result.message; // Worked, or the plain problem.
} // End of turnOn.

// Turns a browser problem into a plain message that also names the problem,
// so CLG can tell what went wrong from a screenshot.
function browserProblem(err: unknown, where: string): string {
  const name = err instanceof Error ? err.name : "Error"; // The browser's short name for the problem, e.g. "AbortError".
  const detail = err instanceof Error ? err.message : String(err); // The browser's own words about it.
  return `Something went wrong with this browser${where ? ` ${where}` : ""}. Please try again, or try another browser. (Details for CLG: ${name}: ${detail.slice(0, 160)})`; // The plain message, then the details (cut to 160 letters).
} // End of browserProblem.

// Turns pop-ups off on this device: removes it from CLG and from the browser.
async function turnOff(): Promise<string | null> { // Starts the steps.
  const reg = await navigator.serviceWorker.getRegistration("/"); // CLG's service worker.
  const sub = reg ? await reg.pushManager.getSubscription() : null; // This device's pop-up address.
  if (!sub) return null; // None: already off.
  const result = await removeThisPushDevice(sub.endpoint); // Removes it from CLG.
  await sub.unsubscribe(); // Removes it from the browser too.
  return result.ok ? null : result.message; // Worked, or the plain problem.
} // End of turnOff.

// The full pop-up settings card for the Notices section.
export function PushSettings({ devices }: { devices: PushDevice[] }) { // Starts the steps.
  const [state, setState] = useState<DeviceState>("checking"); // What this device can do (checking to start).
  const [endpoint, setEndpoint] = useState<string | null>(null); // This device's pop-up address, if on.
  const [busy, setBusy] = useState<string | null>(null); // Which button is working, if any.
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null); // A message to show after a press.

  const resaved = useRef(false); // Whether this device's saved address has been refreshed yet on this visit.
  const savedEndpoints = useRef(devices.map((d) => d.endpoint)); // The person's saved device addresses (kept in a box so checking them does not re-run the steps below).
  useEffect(() => { savedEndpoints.current = devices.map((d) => d.endpoint); }, [devices]); // Keeps the box up to date when the list changes.

  // Reads this device's state and shows it.
  const refresh = useCallback(() => readDevice().then((found) => { // Checks what this device can do now, then:
    setState(found.state); // shows it,
    setEndpoint(found.endpoint); // remembers the address,
    return found; // and hands it back for the first check below.
  }), []); // (the same steps every time)

  useEffect(() => { // After the card first shows:
    void refresh().then(async (found) => { // checks this device, then
      if (resaved.current) return; // (only once per visit)
      resaved.current = true; // notes it is done,
      if (found.state === "on" && found.endpoint && savedEndpoints.current.includes(found.endpoint)) { // and if it is on and saved for this person,
        await turnOn().catch(() => null); // re-saves it quietly so "last used" stays right (permission is already given, so nothing is asked).
      } // End of the quiet refresh.
    }); // End of the first check.
    const onMessage = (e: MessageEvent) => { if (e.data?.type === "clg-push-refresh") void turnOn().then(refresh); }; // When the service worker says the address changed, saves the new one.
    navigator.serviceWorker?.addEventListener("message", onMessage); // Listens for that message.
    return () => navigator.serviceWorker?.removeEventListener("message", onMessage); // Stops listening when the card goes.
  }, [refresh]); // (runs once)

  // Runs one button's work, showing a spinner and then a message.
  const run = async (which: string, work: () => Promise<string | null>, success: string) => { // Starts the steps.
    setBusy(which); // Shows that button as busy.
    setMessage(null); // Clears any old message.
    try { // The browser steps could fail.
      const problem = await work(); // Does the work.
      setMessage(problem ? { ok: false, text: problem } : { ok: true, text: success }); // Shows how it went.
    } catch (err) { // Something unexpected went wrong:
      setMessage({ ok: false, text: browserProblem(err, "") }); // plain message, with the details.
    } // End of the error handling.
    setBusy(null); // The button is free again.
    await refresh(); // Shows the device's new state.
  }; // End of run.

  const thisSaved = endpoint !== null && devices.some((d) => d.endpoint === endpoint); // True when this device is on and saved for this person.
  const others = devices.filter((d) => d.endpoint !== endpoint); // The person's other devices.

  return ( // Shows:
    <div className="space-y-4 text-sm">{/* the card's contents: */}
      <p>{/* an explanation: */}
        Pop-ups appear on your phone or computer when there is a new notice, even when the app is closed or you have
        been signed out. They only say what kind of notice it is (for example &quot;Session reminder&quot;), never
        names or details, because they can show on a locked screen. Tap one to open the app. Nothing pops up
        between 9pm and 5am your local time.{/* what pop-ups are and how private they are. */}
      </p>{/* End of the explanation. */}

      {state === "checking" && <p className="text-zinc-500">Checking this device...</p>}{/* While checking: says so. */}
      {state === "unsupported" && ( // A browser that cannot do pop-ups:
        <p>This browser cannot show pop-ups. Try Chrome, Edge, Firefox or Safari, or add CLG to your home screen first (<Link className="underline" href="/install">how to add CLG</Link>).</p> // suggests another browser.
      )}{/* End of this part. */}
      {state === "needs-install" && ( // An iPhone or iPad not on the home screen:
        <p>On an iPhone or iPad, pop-ups only work once CLG is on your home screen (iOS 16.4 or later). <Link className="underline" href="/install">Add CLG to your home screen</Link>, open it from there, then come back here.</p> // explains the steps.
      )}{/* End of this part. */}
      {state === "blocked" && ( // Pop-ups were refused before:
        <p>Pop-ups are blocked for CLG in this browser. To allow them, open your browser or phone settings, find app.clgtutoring.com (or CLG) under Notifications, and choose Allow. Then come back here.</p> // explains how to allow them.
      )}{/* End of this part. */}
      {state === "off" && ( // Pop-ups could be turned on:
        <Button type="button" busy={busy === "on"} disabled={busy !== null} onClick={() => run("on", turnOn, "Pop-ups are on for this device.")}>{/* the turn-on button: */}
          Turn on pop-ups on this device{/* its words. */}
        </Button> // End of the button.
      )}{/* End of this part. */}
      {state === "on" && ( // Pop-ups are on here:
        <div className="flex flex-wrap items-center gap-3">{/* a row: */}
          <span className="rounded-full bg-teal-50 px-3 py-1 text-teal-900">{thisSaved ? "On for this device" : "On in this browser"}</span>{/* a label saying they are on, */}
          {!thisSaved && ( // On in the browser but saved for someone else (a shared device):
            <Button type="button" busy={busy === "on"} disabled={busy !== null} onClick={() => run("on", turnOn, "Pop-ups on this device now come to you.")}>{/* a button to take it over: */}
              Send my pop-ups to this device{/* its words. */}
            </Button> // End of the button.
          )}{/* End of this part. */}
          <Button type="button" busy={busy === "test"} disabled={busy !== null} onClick={() => run("test", async () => { const r = await sendMeATestPopUp(); return r.ok ? null : r.message; }, "A test pop-up is on its way. It can take a minute to arrive.")}>{/* the test button: */}
            Send me a test{/* its words. */}
          </Button>{/* End of the button. */}
          <button type="button" className="text-teal-800 underline disabled:opacity-50" disabled={busy !== null} onClick={() => run("off", turnOff, "Pop-ups are off for this device.")}>{/* the turn-off link: */}
            Turn off on this device{/* its words. */}
          </button>{/* End of the button. */}
        </div> // End of the row.
      )}{/* End of this part. */}

      {message && ( // After a press:
        <p role={message.ok ? "status" : "alert"} className={message.ok ? "rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-teal-900" : "rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-red-800"}>{message.text}</p> // shows how it went (green if it worked, red if not).
      )}{/* End of the message. */}

      {others.length > 0 && ( // The person has other devices:
        <div>{/* a list: */}
          <p className="font-medium">Your other devices with pop-ups on</p>{/* its heading, */}
          <ul className="mt-2 divide-y divide-zinc-100">{/* the devices: */}
            {others.map((d) => ( // for each device:
              <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 py-2">{/* a row: */}
                <span>{d.device_label} <span className="text-xs text-zinc-500">(last used {new Date(d.last_seen_at).toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" })})</span></span>{/* its name and when it was last used, */}
                <button type="button" className="text-teal-800 underline disabled:opacity-50" disabled={busy !== null} onClick={() => run(`remove-${d.id}`, async () => { const r = await removePushDevice(d.id); return r.ok ? null : r.message; }, "That device will not get pop-ups any more.")}>{/* a remove link: */}
                  Remove{/* its words. */}
                </button>{/* End of the link. */}
              </li> // End of the row.
            ))}{/* End of the loop. */}
          </ul>{/* End of the devices. */}
        </div> // End of the list.
      )}{/* End of this part. */}
    </div> // End of the card's contents.
  ); // End of what's shown.
} // End of PushSettings.

// The small dashboard note inviting the person to turn on pop-ups. It shows
// only when this device could have pop-ups but does not yet, and the person
// has not chosen "Not now" on this device.
export function PushPrompt() { // Starts the steps.
  const [state, setState] = useState<DeviceState>("checking"); // What this device can do (checking to start).
  const [hidden, setHidden] = useState(true); // Hidden until checked.
  const [busy, setBusy] = useState(false); // Whether the button is working.
  const [problem, setProblem] = useState<string | null>(null); // A problem to show, if any.

  useEffect(() => { // After the dashboard first shows:
    let dismissed = false; // Whether "Not now" was chosen before.
    try { dismissed = window.localStorage.getItem(DISMISS_KEY) === "yes"; } catch { dismissed = false; } // Reads it (some private windows block this, which counts as not chosen).
    if (dismissed || !PUBLIC_KEY) return; // Chosen before, or pop-ups are not set up yet: stays hidden.
    void readDevice().then((found) => { // Checks this device:
      setState(found.state); // remembers what it can do,
      setHidden(!(found.state === "off" || found.state === "needs-install")); // and shows the note only if pop-ups could be turned on (or the iPhone needs adding to the home screen).
    }).catch(() => setHidden(true)); // Any problem: stays hidden.
  }, []); // (runs once)

  // Hides the note on this device for good.
  const notNow = () => { // Starts the steps.
    try { window.localStorage.setItem(DISMISS_KEY, "yes"); } catch { /* cannot remember: the note may show again next time, which is fine */ } // Remembers the choice where possible.
    setHidden(true); // Hides it now.
  }; // End of notNow.

  // Turns pop-ups on from the note.
  const onPress = async () => { // Starts the steps.
    setBusy(true); // Shows the spinner.
    setProblem(null); // Clears any old problem.
    const result = await turnOn().catch((err: unknown) => browserProblem(err, "while turning on pop-ups")); // Turns them on (any problem becomes a plain message with the details).
    setBusy(false); // The button is free again.
    if (result) setProblem(result); // A problem: shows it.
    else setHidden(true); // Worked: the note goes away.
  }; // End of onPress.

  if (hidden) return null; // Nothing to show.
  return ( // Shows:
    <div className="mb-4 rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">{/* a soft green note: */}
      <p className="font-medium">Get pop-up notifications on this device</p>{/* its heading, */}
      {state === "needs-install" ? ( // An iPhone or iPad not on the home screen:
        <p className="mt-1">On an iPhone or iPad, add CLG to your home screen first, then open it from there to turn on pop-ups. <Link className="underline" href="/install">How to add CLG</Link></p> // explains the first step.
      ) : ( // Otherwise:
        <p className="mt-1">See reminders and new messages straight away, even when the app is closed or you have been signed out. Pop-ups never show names or details.</p> // explains what pop-ups give.
      )}{/* End of the explanation. */}
      {problem && <p role="alert" className="mt-2 text-red-800">{problem}</p>}{/* Any problem, in red. */}
      <div className="mt-3 flex flex-wrap items-center gap-3">{/* the buttons: */}
        {state === "off" && ( // Pop-ups could be turned on:
          <Button type="button" busy={busy} disabled={busy} onClick={onPress}>Turn on pop-ups</Button> // the turn-on button.
        )}{/* End of this part. */}
        <button type="button" className="underline" onClick={notNow}>Not now</button>{/* the "Not now" link. */}
      </div>{/* End of the buttons. */}
    </div> // End of the note.
  ); // End of what's shown.
} // End of PushPrompt.
