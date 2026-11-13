// Summary: the "Report a problem" form. The person says what went wrong and
// what they were trying to do, and adds up to 6 screenshots (chosen from
// their device, or pasted). Screenshots are shrunk in the browser before
// sending, which keeps uploads quick on a phone and strips hidden photo
// details such as location.
//
"use client"; // Runs in the browser, so pictures can be shrunk and previewed before sending.

import { useEffect, useRef, useState, useTransition, type ClipboardEvent, type FormEvent } from "react"; // React's helpers for remembering things, busy states, and event types.
import { submitProblemReport } from "@/app/actions/problem-reports"; // The server action that sends the report.
import { Button, FormMessage, TextArea } from "@/components/ui"; // The main button, the message box and the multi-line text box.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message).
import { MAX_SCREENSHOT_BYTES, MAX_SCREENSHOTS, SCREENSHOT_MAX_SIDE } from "@/lib/problem-reports"; // The screenshot limits.

type Shot = { file: File; preview: string }; // One screenshot ready to send: the shrunk file and a preview address.

// Shrinks one picture so its longest side is at most SCREENSHOT_MAX_SIDE and
// it's under the size limit, by redrawing it as a JPEG. Redrawing also drops
// hidden details (like where a photo was taken). Gives back the new file, or
// null if the browser can't read the picture.
async function shrink(file: File): Promise<File | null> { // Takes the chosen picture.
  let bitmap: ImageBitmap; // The picture, read by the browser.
  try { // Tries to read it:
    bitmap = await createImageBitmap(file); // reads the picture.
  } catch { // Couldn't read it (not a picture, or an unusual type):
    return null; // gives up on this one.
  } // End of the attempt.
  let scale = Math.min(1, SCREENSHOT_MAX_SIDE / Math.max(bitmap.width, bitmap.height)); // How much to shrink it (never enlarge).
  for (let attempt = 0; attempt < 5; attempt++) { // Tries up to five times, smaller each time:
    const canvas = document.createElement("canvas"); // a drawing area,
    canvas.width = Math.max(1, Math.round(bitmap.width * scale)); // as wide as the shrunk picture,
    canvas.height = Math.max(1, Math.round(bitmap.height * scale)); // and as tall.
    const ctx = canvas.getContext("2d"); // The drawing tools.
    if (!ctx) return null; // No drawing tools (very old browser): gives up.
    ctx.fillStyle = "#ffffff"; // A white background (for see-through parts of a PNG),
    ctx.fillRect(0, 0, canvas.width, canvas.height); // filled in first,
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height); // then the picture drawn on top at the new size.
    const quality = attempt === 0 ? 0.85 : 0.75; // Good quality first, a little lower after.
    const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/jpeg", quality)); // Saves the drawing as a JPEG.
    if (blob && blob.size <= MAX_SCREENSHOT_BYTES) { // Small enough:
      bitmap.close(); // frees the browser's copy of the picture,
      return new File([blob], "screenshot.jpg", { type: "image/jpeg" }); // and hands back the shrunk file.
    } // End of the size check.
    scale *= 0.75; // Still too big: shrinks it a bit more and tries again.
  } // End of the attempts.
  bitmap.close(); // Frees the browser's copy of the picture.
  return null; // Couldn't get it small enough: gives up on this one.
} // End of shrink.

// The form itself. "page" is the page the person came from, if known.
export function ReportProblemForm({ page }: { page: string }) {
  const [shots, setShots] = useState<Shot[]>([]); // The screenshots added so far.
  const [state, setState] = useState<FormState>({}); // The latest reply (error or thanks).
  const [note, setNote] = useState(""); // A note about screenshots that couldn't be added.
  const [pending, startTransition] = useTransition(); // Whether the report is being sent.
  const fileInput = useRef<HTMLInputElement>(null); // The hidden file picker, so the button can open it.
  const shotsRef = useRef<Shot[]>([]); // The latest screenshots, for tidying up when the page closes.
  useEffect(() => { shotsRef.current = shots; }, [shots]); // Keeps that copy up to date after each change.

  // Frees the preview pictures when the person leaves the page.
  useEffect(() => () => shotsRef.current.forEach((s) => URL.revokeObjectURL(s.preview)), []); // Runs once, tidying up on the way out.

  // Adds pictures (from the picker or pasted), shrinking each one first.
  async function addFiles(files: File[]) { // Takes the pictures.
    const room = MAX_SCREENSHOTS - shots.length; // How many more can be added.
    const pictures = files.filter((f) => f.type.startsWith("image/")); // Only pictures.
    if (pictures.length === 0) return; // None: nothing to do.
    const added: Shot[] = []; // The pictures that worked.
    let skipped = 0; // How many couldn't be used.
    for (const f of pictures.slice(0, room)) { // For each picture that fits:
      const small = await shrink(f); // shrinks it,
      if (small) added.push({ file: small, preview: URL.createObjectURL(small) }); // adds it with a preview,
      else skipped++; // or counts it as skipped.
    } // End of the pictures loop.
    const over = Math.max(0, pictures.length - room); // How many didn't fit in the limit.
    setNote( // Explains anything left out:
      [ // (each reason, if it applies)
        over ? `Only ${MAX_SCREENSHOTS} screenshots can be added, so ${over} ${over === 1 ? "was" : "were"} left out.` : "", // too many,
        skipped ? `${skipped} ${skipped === 1 ? "picture" : "pictures"} couldn't be read. Please try a JPG or PNG screenshot.` : "", // couldn't be read.
      ].filter(Boolean).join(" "), // (joined, skipping blanks)
    ); // End of the note.
    setShots((now) => [...now, ...added].slice(0, MAX_SCREENSHOTS)); // Adds them (never more than the limit).
  } // End of addFiles.

  // Takes one screenshot off the list.
  function removeShot(index: number) { // Takes its place in the list.
    setShots((now) => { // Updates the list:
      URL.revokeObjectURL(now[index].preview); // frees its preview,
      return now.filter((_, i) => i !== index); // and leaves it out.
    }); // End of the update.
  } // End of removeShot.

  // Lets someone paste a screenshot straight into the form (Ctrl+V or ⌘V).
  function onPaste(e: ClipboardEvent<HTMLFormElement>) { // Runs when something is pasted.
    const files = Array.from(e.clipboardData.files); // Any files that were pasted.
    if (files.some((f) => f.type.startsWith("image/"))) { // A picture was pasted:
      e.preventDefault(); // stops it being pasted as text,
      void addFiles(files); // and adds it as a screenshot.
    } // End of the picture check.
  } // End of onPaste.

  // Sends the report with the shrunk screenshots.
  function onSubmit(e: FormEvent<HTMLFormElement>) { // Runs when the form is sent.
    e.preventDefault(); // Stops the browser sending it the usual way.
    const form = e.currentTarget; // The form, so it can be cleared afterwards.
    const data = new FormData(form); // The typed fields.
    data.set("page", page); // The page they came from,
    data.set("device", navigator.userAgent.slice(0, 400)); // and their browser and device (helps find the cause).
    shots.forEach((s) => data.append("screenshots", s.file)); // Adds each shrunk screenshot.
    startTransition(async () => { // While sending (the button shows it's busy):
      const reply = await submitProblemReport({}, data); // sends the report,
      setState(reply); // shows the reply,
      if (reply.message) { // and if it worked:
        form.reset(); // clears the typed fields,
        shots.forEach((s) => URL.revokeObjectURL(s.preview)); // frees the previews,
        setShots([]); // clears the screenshots,
        setNote(""); // and clears any note.
      } // End of the success case.
    }); // End of sending.
  } // End of onSubmit.

  return ( // Shows:
    <form onSubmit={onSubmit} onPaste={onPaste} className="space-y-4">{/* the form (pasting a picture adds it), */}
      <FormMessage state={state} />{/* the error or thanks, */}
      <TextArea // the main box:
        label="What went wrong?" // its words,
        name="what_happened" // its name,
        rows={5} // five lines tall,
        minLength={10} // at least a short sentence,
        maxLength={4000} // up to 4,000 characters,
        required // must be filled in,
        hint="For example: what you pressed, what you expected, and what happened instead. Please don't include medical details." // help under the box.
      />{/* End of the main box. */}
      <TextArea // the second box:
        label="What were you trying to do? (optional)" // its words,
        name="trying_to" // its name,
        rows={2} // two lines tall,
        maxLength={1000} // up to 1,000 characters.
      />{/* End of the second box. */}

      <div className="space-y-2">{/* The screenshots part: */}
        <p className="text-sm font-medium text-zinc-800">Screenshots (optional, up to {MAX_SCREENSHOTS})</p>{/* its heading, */}
        <p className="text-xs text-zinc-500">{/* help text: */}
          Add pictures of the problem, or paste one with Ctrl+V. Please crop out anything not needed, such as other people&apos;s details.{/* (its words) */}
        </p>{/* End of the help text. */}
        <input // the hidden file picker:
          ref={fileInput} // (so the button below can open it)
          type="file" // picks files,
          accept="image/*" // pictures only,
          multiple // several at once,
          className="sr-only" // hidden (the button below is easier to tap),
          aria-label="Choose screenshots" // named for screen readers,
          onChange={(e) => { // when pictures are chosen:
            void addFiles(Array.from(e.target.files ?? [])); // adds them,
            e.target.value = ""; // and clears the picker so the same picture can be chosen again.
          }} // (end of the change handler)
        />{/* End of the picker. */}
        {shots.length < MAX_SCREENSHOTS && ( // While there's room for more:
          <button // a button that opens the picker:
            type="button" // (doesn't send the form)
            onClick={() => fileInput.current?.click()} // opens the picker,
            className="rounded-lg border border-dashed border-zinc-400 px-4 py-2 text-sm text-zinc-700 hover:border-brand hover:text-brand" // dashed border, like a drop area,
          >{/* (end of the button's settings) */}
            {shots.length ? "Add another screenshot" : "Add screenshots"}{/* its words. */}
          </button> // End of the button.
        )}{/* End of the add button. */}
        {note && <p className="text-xs text-amber-800">{note}</p>}{/* Any note about pictures left out. */}
        {shots.length > 0 && ( // If there are screenshots:
          <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3">{/* a grid of previews (two across on phones): */}
            {shots.map((s, i) => ( // for each screenshot:
              <li key={s.preview} className="relative overflow-hidden rounded-lg border border-zinc-200 bg-zinc-50">{/* a small framed box: */}
                {/* eslint-disable-next-line @next/next/no-img-element -- a preview of a picture on this device; the Next.js image tool can't show these */}
                <img src={s.preview} alt={`Screenshot ${i + 1}`} className="h-28 w-full object-contain" />{/* the preview, */}
                <button // a remove button:
                  type="button" // (doesn't send the form)
                  onClick={() => removeShot(i)} // takes this one off,
                  className="absolute top-1 right-1 rounded-full bg-white/90 px-2 py-0.5 text-xs text-zinc-700 shadow hover:text-red-700" // a small white pill in the corner,
                  aria-label={`Remove screenshot ${i + 1}`} // named for screen readers,
                >{/* (end of the button's settings) */}
                  Remove{/* its words. */}
                </button>{/* End of the remove button. */}
              </li> // End of the box.
            ))}{/* End of the previews loop. */}
          </ul> // End of the grid.
        )}{/* End of the previews. */}
      </div>{/* End of the screenshots part. */}

      <Button type="submit" disabled={pending}>{/* the send button, switched off while sending, */}
        {pending ? "Sending…" : "Send report"}{/* showing "Sending…" while busy, otherwise its words. */}
      </Button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of ReportProblemForm.
