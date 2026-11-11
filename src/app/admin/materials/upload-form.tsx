// Summary: the admin form for uploading one or many teaching materials as drafts.
//
"use client"; // Runs in the browser, so files can be sent straight to the file store.

import { useActionState, useState, useTransition, type FormEvent } from "react"; // Lets the form remember files, replies and upload progress, and the type of a form event.
import { addMaterials } from "@/app/actions/materials"; // The server action that checks and saves the drafts.
import { Button, FormMessage, Select, TextArea } from "@/components/ui"; // The button, reply message, drop-down and larger text box.
import { initialFormState, type FormState } from "@/lib/forms"; // The starting (empty) form reply, and the reply type.
import { // From the materials helpers:
  MATERIAL_KINDS, // the kinds of material,
  MATERIAL_KIND_NAMES, // their names,
  MAX_SOURCE_BYTES, // the biggest editable original allowed,
  MAX_VIEW_BYTES, // the biggest file for tutors allowed,
  SOURCE_TYPES, // the allowed editable file types,
  titleFromFileName, // and a title made from a file name.
} from "@/lib/materials"; // (end of the list)
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS } from "@/lib/students"; // Suggested subjects, and the list of year levels.
import { createBrowserSupabase } from "@/lib/supabase/browser"; // Connects to the database from the browser.

const inputClass = // The style for a plain input box:
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"; // (matching the other boxes).

type Row = { file: File; title: string; source: File | null }; // One chosen file: the file, its title, and its editable original (if any).

// Gives a file's kind (PDF, JPG or PNG), or nothing if it's none of these.
function viewExt(file: File): "pdf" | "jpg" | "png" | null {
  const name = file.name.toLowerCase(); // Its name in lower case.
  if (file.type === "application/pdf" || name.endsWith(".pdf")) return "pdf"; // A PDF: "pdf".
  if (file.type === "image/jpeg" || /\.jpe?g$/.test(name)) return "jpg"; // A JPEG: "jpg".
  if (file.type === "image/png" || name.endsWith(".png")) return "png"; // A PNG: "png".
  return null; // Anything else: nothing.
} // End of viewExt.

// Add one or many materials at once. The files go straight from this
// browser to CLG's private file store; then the server checks each one and
// saves it as a draft. Everything chosen here (kind, subject, years) applies
// to every file; each can be changed afterwards.
export function UploadMaterialsForm() {
  const [state, formAction, saving] = useActionState(addMaterials, initialFormState); // The server's reply, the action to send, and whether it's saving.
  const [rows, setRows] = useState<Row[]>([]); // The chosen files.
  const [local, setLocal] = useState<FormState>({}); // Messages from this page (before sending).
  const [uploading, startUpload] = useTransition(); // Whether files are uploading, and the way to start uploading.
  const busy = saving || uploading; // True while uploading or saving.

  // Keeps the chosen files that are allowed, and explains any that aren't.
  function choose(list: FileList | null) {
    const files = [...(list ?? [])]; // The chosen files as a list.
    const bad = files.filter((f) => !viewExt(f)); // Files of the wrong type.
    const big = files.filter((f) => viewExt(f) && f.size > MAX_VIEW_BYTES); // Files that are too big.
    setLocal( // Sets the message:
      bad.length || big.length // if any were left out,
        ? { // an error:
            error: [ // (made of:)
              bad.length ? `Not added (not a PDF, JPG or PNG): ${bad.map((f) => f.name).join(", ")}. Save Word or PowerPoint files as PDF first; you can attach the original as the editable copy.` : "", // which were the wrong type and what to do,
              big.length ? `Not added (over 4 MB): ${big.map((f) => f.name).join(", ")}. Save a smaller PDF and try again.` : "", // which were too big and what to do,
            ] // (end of the parts)
              .filter(Boolean) // leaving out blank parts,
              .join(" "), // joined with a space.
          } // (end of the error)
        : {}, // otherwise no message.
    ); // (end of the message)
    setRows( // Keeps:
      files // the files,
        .filter((f) => viewExt(f) && f.size <= MAX_VIEW_BYTES) // of the right type and size,
        .slice(0, 20) // at most 20,
        .map((file) => ({ file, title: titleFromFileName(file.name), source: null })), // each with a title from its file name.
    ); // (end of the list)
  } // End of choose.

  // Uploads each file, then sends the list to the server.
  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault(); // Stops the browser sending the form itself.
    const form = new FormData(e.currentTarget); // The form's other fields.
    if (rows.length === 0) { // No files:
      setLocal({ error: "Choose at least one file." }); // asks for at least one,
      return; // and stops.
    } // End of the check.
    setLocal({}); // Clears any message.
    startUpload(async () => { // Starts uploading:
      const supabase = createBrowserSupabase(); // connects from the browser,
      const store = supabase.storage.from("materials"); // the materials file store,
      const sent: { viewPath: string; fileName: string; title: string; sourcePath?: string; sourceName?: string }[] = []; // the files uploaded so far.
      for (const r of rows) { // For each file:
        const ext = viewExt(r.file)!; // its kind,
        const viewPath = `view/${crypto.randomUUID()}.${ext}`; // a random storage name,
        const up = await store.upload(viewPath, r.file, { contentType: r.file.type || undefined, upsert: false }); // uploads it (never replacing another file).
        if (up.error) { // Failed:
          setLocal({ error: `Couldn't upload ${r.file.name}. Check your connection and try again.` }); // says which file,
          await store.remove(sent.flatMap((s) => [s.viewPath, ...(s.sourcePath ? [s.sourcePath] : [])])); // removes the files already uploaded,
          return; // and stops.
        } // End of the failure case.
        const item: (typeof sent)[number] = { viewPath, fileName: r.file.name, title: r.title }; // The file's details to send.
        if (r.source) { // If there's an editable original:
          const sExt = r.source.name.toLowerCase().split(".").pop() ?? ""; // its extension,
          const sourcePath = `source/${crypto.randomUUID()}.${sExt}`; // a random storage name,
          const sUp = await store.upload(sourcePath, r.source, { contentType: SOURCE_TYPES[sExt], upsert: false }); // uploads it.
          if (!sUp.error) { // Worked:
            item.sourcePath = sourcePath; // adds its storage name,
            item.sourceName = r.source.name; // and its file name.
          } // End of that case.
        } // End of the original.
        sent.push(item); // Adds the file to the list.
      } // End of the files loop.
      form.set("files_json", JSON.stringify(sent)); // Adds the list to the form.
      formAction(form); // Sends the form to the server.
      setRows([]); // Clears the chosen files,
      (e.target as HTMLFormElement).reset(); // and empties the form.
    }); // End of the upload.
  } // End of onSubmit.

  return ( // Shows:
    <form onSubmit={onSubmit} className="space-y-4">{/* a form that uploads when sent: */}
      <FormMessage state={local.error ? local : state} />{/* the page's message, or the server's reply, */}

      <label className="block space-y-1">{/* a label: */}
        <span className="text-sm font-medium text-zinc-800">Files tutors will open</span>{/* "Files tutors will open", */}
        <input // a file picker:
          type="file" // (a file)
          multiple // that allows several,
          accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png" // that accepts PDF, JPG and PNG,
          onChange={(e) => choose(e.target.files)} // keeps the files as soon as they're chosen,
          className={inputClass} // styled like the other boxes.
        />{/* (end of the picker) */}
        <span className="block text-xs text-zinc-500">{/* A small grey note: */}
          PDF, JPG or PNG, under 4 MB each, up to 20 at a time. Tutors get a copy with their name on every page.{/* the allowed types and sizes. */}
        </span>{/* End of the note. */}
      </label>{/* End of the label. */}

      {rows.length > 0 && ( // When files are chosen:
        <ul className="space-y-3 rounded-xl bg-zinc-50 p-3">{/* a list: */}
          {rows.map((r, i) => ( // for each file:
            <li key={`${r.file.name}-${i}`} className="space-y-2 rounded-lg bg-white p-3 shadow-sm">{/* a white box: */}
              <label className="block space-y-1">{/* a label: */}
                <span className="text-xs text-zinc-500">Title for {r.file.name}</span>{/* "Title for" the file, */}
                <input // a text box:
                  value={r.title} // showing its title,
                  maxLength={200} // up to 200 characters,
                  onChange={(e) => setRows((prev) => prev.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))} // updates that file's title as it's typed,
                  className={inputClass} // styled like the other boxes.
                />{/* (end of the box) */}
              </label>{/* End of the label. */}
              <label className="block space-y-1">{/* A label: */}
                <span className="text-xs text-zinc-500">Editable original (optional, admins only): Word, PowerPoint, Excel</span>{/* "Editable original", */}
                <input // a file picker:
                  type="file" // (a file)
                  accept=".docx,.pptx,.xlsx,.doc,.ppt,.xls,.pdf" // that accepts Office files and PDFs,
                  onChange={(e) => { // when a file is chosen:
                    const f = e.target.files?.[0] ?? null; // the file,
                    if (f && f.size > MAX_SOURCE_BYTES) { // if it's over 50 MB:
                      setLocal({ error: `${f.name} is over 50 MB, so it wasn't added.` }); // says so,
                      return; // and stops.
                    } // End of the check.
                    setRows((prev) => prev.map((x, j) => (j === i ? { ...x, source: f } : x))); // Adds it to that file's row.
                  }} // (end of the handler)
                  className="text-xs" // small text.
                />{/* (end of the picker) */}
              </label>{/* End of the label. */}
            </li> // End of the box.
          ))}{/* End of the files loop. */}
        </ul> // End of the list.
      )}{/* End of the files part. */}

      <div className="grid gap-4 sm:grid-cols-2">{/* Two columns on wider screens: */}
        <Select label="Kind" name="kind" defaultValue="worksheet">{/* a drop-down of kinds (worksheet to start): */}
          {MATERIAL_KINDS.map((k) => ( // for each kind:
            <option key={k} value={k}>{/* an option: */}
              {MATERIAL_KIND_NAMES[k]}{/* its name. */}
            </option> // (end of the option)
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <label className="block space-y-1">{/* A label: */}
          <span className="text-sm font-medium text-zinc-800">Subject</span>{/* "Subject", */}
          <input name="subject" list="material-subjects" required className={inputClass} placeholder="For example General Maths" />{/* a text box with suggestions (must be filled in), */}
          <datalist id="material-subjects">{/* the suggestions list: */}
            {SUBJECT_SUGGESTIONS.map((s) => ( // for each suggested subject:
              <option key={s} value={s} /> // an option.
            ))}{/* End of the loop. */}
          </datalist>{/* End of the suggestions. */}
          <span className="block text-xs text-zinc-500">Use the same name tutors use in &ldquo;What you teach&rdquo;.</span>{/* A note to use the tutors' subject names. */}
        </label>{/* End of the label. */}
        <Select label="Suits from" name="from_level" defaultValue="Year 5">{/* A drop-down of the lowest year: */}
          {YEAR_LEVELS.map((y) => ( // for each year:
            <option key={y}>{y}</option> // an option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
        <Select label="Suits up to" name="to_level" defaultValue="Year 5">{/* A drop-down of the highest year: */}
          {YEAR_LEVELS.map((y) => ( // for each year:
            <option key={y}>{y}</option> // an option.
          ))}{/* End of the loop. */}
        </Select>{/* End of the drop-down. */}
      </div>{/* End of the columns. */}
      <TextArea // The note for tutors:
        label="Note for tutors (optional)" // its label,
        name="description" // its field name,
        maxLength={1000} // up to 1,000 characters,
        hint="What it is and how to use it, for example: 20 minutes, use after introducing equivalent fractions." // and a hint.
      />{/* (end of the box) */}
      <Button type="submit" disabled={busy}>{/* The button (greyed out while busy): */}
        {uploading ? "Uploading…" : saving ? "Checking files…" : "Upload and save as drafts"}{/* its words show what's happening. */}
      </Button>{/* End of the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of UploadMaterialsForm.
