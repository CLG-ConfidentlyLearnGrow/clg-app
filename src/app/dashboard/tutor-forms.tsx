// Summary: the forms on the tutor dashboard: most hours per week, a new
// available time, sending in a check (with photo shrinking), and adding a subject.
//
"use client"; // Marks this file as code that runs in the browser.

import { addAvailability, addTeaching, saveMaxHours, submitMyCheck } from "@/app/actions/tutor"; // The tutor actions these forms send to.
import { startTransition, useActionState, useState, type FormEvent } from "react"; // React tools: run a send in the background, track a form's result, remember a value, and the form-send type.
import { ActionForm } from "@/components/action-form"; // A shared form that shows a save button and messages.
import { Button, Field, FormMessage, Select } from "@/components/ui"; // Shared page parts: a button, a field, a message line and a drop-down.
import { initialFormState } from "@/lib/forms"; // The empty starting result for a form.
import { CHECK_KINDS, CHECK_NAMES, WEEKDAYS } from "@/lib/checks"; // Check types and names, and the weekday names.
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS, YEAR_LEVEL_NAMES } from "@/lib/students"; // Subject suggestions and year levels with their names.

export function MaxHoursForm({ current }: { current: number | null }) { // The "most hours each week" form.
  return ( // Shows:
    <ActionForm action={saveMaxHours} submitLabel="Save hours">{/* the form, saving with saveMaxHours: */}
      <Field // a number box:
        label="Most hours I can work each week" // its label,
        name="max_weekly_hours" // its name for the action,
        type="number" // numbers only,
        min={0} // no less than 0,
        max={60} // no more than 60,
        step={0.5} // in half-hour steps,
        defaultValue={current ?? ""} // filled with the current value (if any),
        required // and must be filled in.
      />{/* End of the box. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MaxHoursForm.

export function AvailabilityForm({ libraries }: { libraries: { id: string; name: string; suburb: string | null }[] }) { // The "add a time I'm available" form (given the list of libraries).
  return ( // Shows:
    <ActionForm action={addAvailability} submitLabel="Add time">{/* the form, saving with addAvailability: */}
      <Select label="Day" name="weekday" defaultValue="1">{/* a day drop-down, Monday first: */}
        {WEEKDAYS.map((d, i) => ( // for each weekday:
          <option key={d} value={i + 1}>{/* an option (1 = Monday): */}
            {d}{/* the day's name, */}
          </option> // end of the option.
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field label="From" name="starts_at" type="time" required />{/* the start time, */}
      <Field label="To" name="ends_at" type="time" required />{/* the end time, */}
      <fieldset className="space-y-2">{/* a group for where they can teach: */}
        <legend className="mb-1 text-sm font-medium text-zinc-800">Where you can teach in this time</legend>{/* its heading, */}
        <label className="flex items-start gap-2 text-sm">{/* a tick box line: */}
          <input type="checkbox" name="online" defaultChecked className="mt-1" /> Online{/* online (ticked to start). */}
        </label>{/* End of the line. */}
        <Select label="Library (one per time)" name="library_id" defaultValue="">{/* a library drop-down: */}
          <option value="">No library</option>{/* the "no library" choice, */}
          {libraries.map((l) => ( // for each library:
            <option key={l.id} value={l.id}>{/* an option: */}
              {l.name}{/* the library's name, */}
              {l.suburb ? ` (${l.suburb})` : ""}{/* with its suburb, if known. */}
            </option> // End of the option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <p className="text-xs text-zinc-600">{/* a help line: */}
          Choose online, one library, or both. For a different library on another day, add another time.{/* explaining the choices. */}
        </p>{/* End of the help line. */}
      </fieldset>{/* End of the group. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AvailabilityForm.

// Phone photos can be large. Shrink big images before sending so the upload
// is quick and stays under the size limit. PDFs are sent as they are.
async function shrinkImage(file: File): Promise<File> { // Shrinks a big photo (returns the file to send).
  if (!file.type.startsWith("image/") || file.size < 1_500_000) return file; // Not a photo, or already small: sends it as it is.
  try { // Tries to shrink it:
    const bitmap = await createImageBitmap(file); // reads the picture,
    const scale = Math.min(1, 2400 / Math.max(bitmap.width, bitmap.height)); // works out how much to shrink it (longest side 2400 pixels at most),
    const canvas = document.createElement("canvas"); // makes a blank drawing area,
    canvas.width = Math.round(bitmap.width * scale); // sets its width,
    canvas.height = Math.round(bitmap.height * scale); // and height,
    canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height); // draws the photo onto it, smaller,
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85)); // saves the drawing as a JPEG picture,
    return blob ? new File([blob], "certificate.jpg", { type: "image/jpeg" }) : file; // and sends that (or the original if saving failed).
  } catch { // If anything went wrong:
    return file; // sends the original.
  } // End of the fallback.
} // End of shrinkImage.

export function MyCheckForm() { // The "send in a check" form.
  const [state, formAction, pending] = useActionState(submitMyCheck, initialFormState); // The form's result, the send step, and whether it's sending.
  const [preparing, setPreparing] = useState(false); // Whether a photo is being shrunk.

  async function onSubmit(event: FormEvent<HTMLFormElement>) { // Runs when the form is sent:
    event.preventDefault(); // stops the browser's normal send,
    const form = event.currentTarget; // the form,
    const data = new FormData(form); // its filled-in values,
    const file = data.get("document"); // the file chosen,
    if (file instanceof File && file.size > 0) { // if there is a file:
      setPreparing(true); // shows it's busy,
      data.set("document", await shrinkImage(file)); // swaps in the shrunk photo,
      setPreparing(false); // and stops showing busy.
    } // End of the file part.
    startTransition(() => formAction(data)); // Sends the values to the action.
  } // End of onSubmit.

  const busy = pending || preparing; // Busy while shrinking or sending.
  return ( // Shows:
    <form onSubmit={onSubmit} className="space-y-4">{/* the form: */}
      <FormMessage state={state} />{/* the result message, */}
      <Select label="Check" name="kind" defaultValue="" required>{/* the check drop-down (must choose): */}
        <option value="" disabled>{/* a "Choose…" prompt that can't be picked: */}
          Choose…{/* its words, */}
        </option>{/* end of the prompt. */}
        {CHECK_KINDS.map((k) => ( // for each check type:
          <option key={k} value={k}>{/* an option: */}
            {CHECK_NAMES[k]}{/* the check's name, */}
          </option> // end of the option.
        ))}{/* End of the loop. */}
      </Select>{/* End of the drop-down. */}
      <Field // the number box:
        label="Card, registration or certificate number" // its label,
        name="reference" // its name for the action,
        maxLength={100} // up to 100 letters,
        hint="Not needed for RRHAN-EC training or first aid." // a help hint.
      />{/* End of the box. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Field // the date done box:
          label="Date done or issued" // its label,
          name="completed_on" // its name for the action,
          type="date" // a date,
          hint="Enough on its own for RRHAN-EC and first aid (3 years) or a police check (5 years)." // a help hint.
        />{/* End of the box. */}
        <Field // the expiry date box:
          label="Expires or due again on" // its label,
          name="expires_on" // its name for the action,
          type="date" // a date,
          hint="Needed for a working with children card. Otherwise the app can work it out." // a help hint.
        />{/* End of the box. */}
      </div>{/* End of the columns. */}
      <Field // the file box:
        label="Copy of the certificate or card" // its label,
        name="document" // its name for the action,
        type="file" // a file,
        required // must be chosen,
        accept="application/pdf,image/jpeg,image/png,image/webp" // PDF or picture types only,
        hint="A PDF, or a clear photo of the whole card or certificate. Only you and CLG admins can open it." // a help hint.
      />{/* End of the box. */}
      <Button type="submit" disabled={busy}>{/* the send button (greyed while busy): */}
        {busy ? "Sending…" : "Send to CLG"}{/* says "Sending…" while busy. */}
      </Button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of MyCheckForm.

export function TeachingForm() { // The "add a subject I teach" form.
  return ( // Shows:
    <ActionForm action={addTeaching} submitLabel="Add subject">{/* the form, saving with addTeaching: */}
      <Field // the subject box:
        label="Subject" // its label,
        name="subject" // its name for the action,
        list="subject-suggestions" // offers the suggestion list,
        required // must be filled in,
        maxLength={100} // up to 100 letters,
        hint="Pick from the list or type your own." // a help hint.
      />{/* End of the box. */}
      <datalist id="subject-suggestions">{/* the suggestion list: */}
        {SUBJECT_SUGGESTIONS.map((s) => ( // for each suggested subject:
          <option key={s} value={s} /> // an option.
        ))}{/* End of the loop. */}
      </datalist>{/* End of the list. */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="From" name="from_level" defaultValue="" required>{/* the lowest year level drop-down: */}
          <option value="" disabled>{/* a "Choose…" prompt that can't be picked: */}
            Choose…{/* its words, */}
          </option>{/* end of the prompt. */}
          {YEAR_LEVELS.map((y) => ( // for each year level:
            <option key={y} value={y}>{/* an option: */}
              {y === "Foundation" ? "Foundation (Reception)" : YEAR_LEVEL_NAMES[y]}{/* its name (Foundation shows as Reception too). */}
            </option> // End of the option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Select label="To" name="to_level" defaultValue="" required>{/* the highest year level drop-down: */}
          <option value="" disabled>{/* a "Choose…" prompt that can't be picked: */}
            Choose…{/* its words, */}
          </option>{/* end of the prompt. */}
          {YEAR_LEVELS.map((y) => ( // for each year level:
            <option key={y} value={y}>{/* an option: */}
              {y === "Foundation" ? "Foundation (Reception)" : YEAR_LEVEL_NAMES[y]}{/* its name (Foundation shows as Reception too). */}
            </option> // End of the option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TeachingForm.
