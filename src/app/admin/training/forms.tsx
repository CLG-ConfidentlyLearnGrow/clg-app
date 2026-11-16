// Summary: admin forms for training: a module's details, lessons (with a
// video or PDF uploaded straight to the file store), quiz questions, the
// handbook, training settings, and small one-button actions.
//
"use client"; // Runs in the browser, so the forms can react straight away.

import { useActionState, useState, useTransition, type FormEvent } from "react"; // Form helpers, remembered values, and a way to show work in progress.
import { attachLessonFile, saveHandbookPage, saveLesson, saveModule, createModule, saveQuestion, saveTrainingSettings } from "@/app/actions/training"; // The server actions these forms send to.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { BusyButton, Field, FormMessage, Select, TextArea } from "@/components/ui"; // The unstyled busy button, input box, reply message, drop-down and larger text box.
import { initialFormState, type FormState } from "@/lib/forms"; // The starting (empty) form reply, and its shape.
import { createBrowserSupabase } from "@/lib/supabase/browser"; // Connects from the browser (to upload large files straight to the store).
import { AUDIENCES, AUDIENCE_NAMES, LESSON_FILE_TYPES, STAGES, STAGE_NAMES } from "@/lib/training"; // Training choices and their words.

// A module as the details form needs it.
export type ModuleRow = { // its details:
  id: string; // its id,
  title: string; // name,
  summary: string; // summary,
  audience: string; // who it's for,
  stage: string; // stage,
  required: boolean; // compulsory or not,
  holds_matching: boolean; // whether new matches wait for it,
  counts_toward_certified: boolean; // whether it counts towards the quarter's hours,
  minutes: number; // set time,
  renew_months: number | null; // redo period (if any),
  status: string; // draft, published or retired,
  position: number; // order.
}; // End of the shape.

// A tick box with words beside it.
function Tick({ name, label, hint, defaultChecked }: { name: string; label: string; hint?: string; defaultChecked?: boolean }) { // Takes the field name, words, help and starting value.
  return ( // Shows:
    <label className="flex items-start gap-2 text-sm">{/* a row: */}
      <input type="checkbox" name={name} defaultChecked={defaultChecked} className="mt-1" />{/* the tick box, */}
      <span>{/* the words: */}
        <span className="font-medium text-zinc-800">{label}</span>{/* the label, */}
        {hint && <span className="block text-zinc-600">{hint}</span>}{/* and help, if any. */}
      </span>{/* End of the words. */}
    </label> // End of the row.
  ); // End of what's shown.
} // End of Tick.

// The fields shared by the new-module and edit-module forms.
function ModuleFields({ m }: { m?: ModuleRow }) { // Takes the module (none for a new one).
  return ( // Shows:
    <>{/* (a group:) */}
      <Field label="Name" name="title" required minLength={2} maxLength={150} defaultValue={m?.title} />{/* the name, */}
      <TextArea label="Summary" name="summary" rows={2} maxLength={600} defaultValue={m?.summary} hint="One or two lines on what it covers." />{/* the summary, */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Who it's for" name="audience" defaultValue={m?.audience ?? "tutor"}>{/* who it's for: */}
          {AUDIENCES.map((a) => <option key={a} value={a}>{AUDIENCE_NAMES[a]}</option>)}{/* each choice. */}
        </Select>{/* End of the choice. */}
        <Select label="Where it sits" name="stage" defaultValue={m?.stage ?? "ongoing"}>{/* the stage: */}
          {STAGES.map((s) => <option key={s} value={s}>{STAGE_NAMES[s]}</option>)}{/* each choice. */}
        </Select>{/* End of the choice. */}
        <Field label="Set time (minutes)" name="minutes" type="number" min={5} max={480} required defaultValue={m?.minutes ?? 30} hint="What it takes, and what's paid for compulsory modules." />{/* the set time, */}
        <Field label="Redo every (months)" name="renew_months" type="number" min={1} max={60} defaultValue={m?.renew_months ?? ""} hint="Leave blank if it never needs redoing. Child safety and privacy: 12." />{/* the redo period, */}
        <Field label="Order" name="position" type="number" min={0} max={9999} defaultValue={m?.position ?? 100} hint="Smaller numbers show first." />{/* the order. */}
      </div>{/* End of the columns. */}
      <Tick name="required" label="Compulsory" hint="Everyone it's for must finish it. It's paid automatically for the set time." defaultChecked={m?.required} />{/* compulsory, */}
      <Tick name="holds_matching" label="Needed before new students (safety)" hint="Tutors can't be matched with new students once it's overdue. Only works if it's compulsory." defaultChecked={m?.holds_matching} />{/* holds matches, */}
      <p className="text-sm text-zinc-600">Safety modules (needed before new students) never count towards the training hours each quarter. Every other module does. The app sets this itself.</p>{/* how the quarterly hours are counted (automatic, Carla 16 Nov 2026). */}
    </> // End of the group.
  ); // End of what's shown.
} // End of ModuleFields.

// The form that adds a new module (it starts as a draft).
export function NewModuleForm() { // No inputs.
  return ( // Shows:
    <ActionForm action={createModule} submitLabel="Add module">{/* a form that adds it: */}
      <ModuleFields />{/* the module's fields. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of NewModuleForm.

// The form that changes a module, including publishing or retiring it.
export function ModuleForm({ m }: { m: ModuleRow }) { // Takes the module.
  return ( // Shows:
    <ActionForm action={saveModule} submitLabel="Save module">{/* a form that saves it: */}
      <input type="hidden" name="id" value={m.id} />{/* the module's id (hidden), */}
      <ModuleFields m={m} />{/* the module's fields, */}
      <Select label="Status" name="status" defaultValue={m.status}>{/* draft, published or retired: */}
        <option value="draft">Draft (only admins see it)</option>{/* draft, */}
        <option value="published">Published (the people it&apos;s for can see it)</option>{/* published, */}
        <option value="retired">Retired (hidden, records kept)</option>{/* retired. */}
      </Select>{/* End of the choice. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of ModuleForm.

// A lesson as the lesson form needs it.
export type LessonRow = { id: string; title: string; body: string; position: number; file_path: string | null; file_name: string | null; link_url: string | null; link_label: string | null }; // its details.

// The form that adds a lesson, or changes one.
export function LessonForm({ moduleId, lesson, nextPosition }: { moduleId: string; lesson?: LessonRow; nextPosition: number }) { // Takes the module, the lesson (none for new) and the next free order number.
  return ( // Shows:
    <ActionForm action={saveLesson} submitLabel={lesson ? "Save lesson" : "Add lesson"}>{/* a form that saves it: */}
      <input type="hidden" name="module_id" value={moduleId} />{/* the module's id (hidden), */}
      {lesson && <input type="hidden" name="id" value={lesson.id} />}{/* the lesson's id (hidden, when changing one), */}
      <div className="grid gap-4 sm:grid-cols-[1fr_8rem]">{/* the heading and order side by side: */}
        <Field label="Heading" name="title" required minLength={2} maxLength={150} defaultValue={lesson?.title} />{/* the heading, */}
        <Field label="Order" name="position" type="number" min={0} max={9999} defaultValue={lesson?.position ?? nextPosition} />{/* the order. */}
      </div>{/* End of the row. */}
      <TextArea label="Text" name="body" rows={lesson ? 10 : 6} maxLength={20000} defaultValue={lesson?.body} hint='Start a line with "## " for a heading, or "- " for a bullet point. Leave a blank line between paragraphs. Web addresses become links.' />{/* the text, */}
      <div className="grid gap-4 sm:grid-cols-2">{/* the link fields side by side: */}
        <Field label="Link (optional)" name="link_url" type="url" placeholder="https://" defaultValue={lesson?.link_url ?? ""} />{/* an outside link, */}
        <Field label="Words for the link" name="link_label" maxLength={150} defaultValue={lesson?.link_label ?? ""} />{/* and its words. */}
      </div>{/* End of the row. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of LessonForm.

// Uploads a video or PDF for a lesson straight from the browser to the
// training file store (large videos don't pass through the app's server),
// then attaches it to the lesson.
export function LessonFileForm({ lessonId, maxMb }: { lessonId: string; maxMb: number }) { // Takes the lesson and the largest upload allowed.
  const [state, formAction] = useActionState(attachLessonFile, initialFormState); // The server's reply, and the form's sender.
  const [local, setLocal] = useState<FormState>({}); // A message from the browser (e.g. file too big).
  const [busy, startUpload] = useTransition(); // Whether it's uploading.
  function onSubmit(e: FormEvent<HTMLFormElement>) { // When the form is sent:
    e.preventDefault(); // stops the browser sending it itself,
    const input = e.currentTarget.elements.namedItem("file") as HTMLInputElement; // finds the file picker,
    const file = input.files?.[0]; // and the chosen file.
    if (!file) { setLocal({ error: "Choose a video or PDF first." }); return; } // None chosen: asks for one.
    const ext = file.name.toLowerCase().split(".").pop() ?? ""; // The file's extension.
    if (!LESSON_FILE_TYPES[ext]) { setLocal({ error: "Choose an MP4, WebM or MOV video, or a PDF." }); return; } // Wrong type: says which work.
    if (file.size > maxMb * 1024 * 1024) { setLocal({ error: `That file is over ${maxMb} MB. Make it smaller (for example save the video at 720p), or raise the limit in Settings.` }); return; } // Too big: explains.
    setLocal({ message: "Uploading… large videos can take a few minutes. Keep this page open." }); // Says it's uploading.
    startUpload(async () => { // Starts uploading:
      const path = `lessons/${crypto.randomUUID()}.${ext}`; // a random storage name,
      const up = await createBrowserSupabase().storage.from("training").upload(path, file, { contentType: LESSON_FILE_TYPES[ext], upsert: false }); // uploads it (never replacing another file),
      if (up.error) { setLocal({ error: "The upload didn't work. Check your connection, and that Supabase's upload limit (Storage settings) is at least this size." }); return; } // failed: explains,
      setLocal({}); // clears the browser message,
      const form = new FormData(); // and sends the details to the server:
      form.set("lesson_id", lessonId); // which lesson,
      form.set("path", path); // where the file is,
      form.set("file_name", file.name.slice(0, 200)); // and its original name.
      formAction(form); // (sent)
    }); // End of the upload.
  } // End of onSubmit.
  return ( // Shows:
    <form onSubmit={onSubmit} className="space-y-3">{/* a form that uploads when sent: */}
      <FormMessage state={local.error || local.message ? local : state} />{/* the browser's message, or the server's reply, */}
      <label className="block space-y-1 text-sm">{/* the file picker: */}
        <span className="font-medium text-zinc-800">Video or PDF (up to {maxMb} MB)</span>{/* its label, */}
        <input type="file" name="file" accept="video/mp4,video/webm,video/quicktime,application/pdf,.mp4,.webm,.mov,.pdf" className="block text-sm" />{/* the picker. */}
      </label>{/* End of the picker. */}
      <BusyButton type="submit" busy={busy} className="rounded-full border border-zinc-300 px-4 py-2 text-sm font-medium hover:bg-zinc-50">{busy ? "Uploading…" : "Upload and attach"}</BusyButton>{/* the send button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of LessonFileForm.

// A quiz question as the question form needs it (with its answer).
export type QuestionRow = { id: string; question_position: number; prompt: string; options: string[]; correct_option: number; explanation: string | null }; // its details.

// The form that adds a quiz question, or changes one.
export function QuestionForm({ moduleId, q, nextPosition }: { moduleId: string; q?: QuestionRow; nextPosition: number }) { // Takes the module, the question (none for new) and the next free order number.
  return ( // Shows:
    <ActionForm action={saveQuestion} submitLabel={q ? "Save question" : "Add question"}>{/* a form that saves it: */}
      <input type="hidden" name="module_id" value={moduleId} />{/* the module's id (hidden), */}
      {q && <input type="hidden" name="id" value={q.id} />}{/* the question's id (hidden, when changing one), */}
      <TextArea label="Question" name="prompt" rows={2} required maxLength={600} defaultValue={q?.prompt} />{/* the question, */}
      <TextArea label="Choices, one per line" name="options" rows={4} required defaultValue={q?.options.join("\n")} hint="2 to 6 choices." />{/* the choices, */}
      <div className="grid gap-4 sm:grid-cols-2">{/* two columns: */}
        <Field label="Number of the right choice" name="correct_option" type="number" min={1} max={6} required defaultValue={q?.correct_option ?? 1} hint="1 is the first line." />{/* which is right, */}
        <Field label="Order" name="position" type="number" min={0} max={9999} defaultValue={q?.question_position ?? nextPosition} />{/* the order. */}
      </div>{/* End of the columns. */}
      <TextArea label="Why it's right (admins only)" name="explanation" rows={2} maxLength={600} defaultValue={q?.explanation ?? ""} />{/* an explanation for admins. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of QuestionForm.

// A one-button form for a small action (delete, remove a file, ask for a
// redo), with an "are you sure?" question first when given.
export function SmallAction({ action, fields, label, confirm }: { // Takes:
  action: (prev: FormState, formData: FormData) => Promise<FormState>; // the server action,
  fields: Record<string, string>; // the hidden fields to send,
  label: string; // the button's words,
  confirm?: string; // and an optional question to confirm.
}) { // End of the settings.
  const [state, formAction] = useActionState(action, initialFormState); // The reply and the form's sender.
  return ( // Shows:
    <form action={formAction} onSubmit={(e) => { if (confirm && !window.confirm(confirm)) e.preventDefault(); }} className="space-y-2">{/* a form that asks first (if set): */}
      {Object.entries(fields).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}{/* the hidden fields, */}
      <FormMessage state={state} />{/* the reply, */}
      <BusyButton type="submit" className="rounded-full border border-zinc-300 px-4 py-1.5 text-sm font-medium text-zinc-800 hover:bg-zinc-50">{label}</BusyButton>{/* and the button. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of SmallAction.

// The training settings form.
export function SettingsForm({ graceDays, quarterMinutes, videoMaxMb }: { graceDays: number; quarterMinutes: number; videoMaxMb: number }) { // Takes the current settings.
  return ( // Shows:
    <ActionForm action={saveTrainingSettings} submitLabel="Save settings">{/* a form that saves them: */}
      <Field label="Days allowed to finish a compulsory module" name="grace_days" type="number" min={0} max={180} defaultValue={graceDays} hint="Counted from when someone joins, or when the module becomes compulsory or is changed in a big way. 28 days is 4 weeks." />{/* days allowed, */}
      <Field label="Training hours needed each quarter to stay CLG certified" name="quarter_hours" type="number" min={0} max={40} step={0.25} defaultValue={quarterMinutes / 60} hint="Safety modules don't count towards these hours." />{/* hours each quarter, */}
      <Field label="Largest video or PDF upload (MB)" name="video_max_mb" type="number" min={1} max={5000} defaultValue={videoMaxMb} hint="Supabase's own upload limit (Storage settings) must be at least this big." />{/* largest upload. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SettingsForm.

// A handbook page as the handbook form needs it.
export type HandbookRow = { id: string; title: string; body: string; urgent: boolean; audience: string; status: string; position: number }; // its details.

// The form that adds a handbook page, or changes one.
export function HandbookForm({ page }: { page?: HandbookRow }) { // Takes the page (none for a new one).
  return ( // Shows:
    <ActionForm action={saveHandbookPage} submitLabel={page ? "Save page" : "Add page"}>{/* a form that saves it: */}
      {page && <input type="hidden" name="id" value={page.id} />}{/* the page's id (hidden, when changing one), */}
      <Field label="Heading" name="title" required minLength={2} maxLength={150} defaultValue={page?.title} />{/* the heading, */}
      <TextArea label="Text" name="body" rows={page ? 16 : 6} maxLength={30000} defaultValue={page?.body} hint='Start a line with "## " for a heading, or "- " for a bullet point. Leave a blank line between paragraphs.' />{/* the text, */}
      <div className="grid gap-4 sm:grid-cols-3">{/* three columns: */}
        <Select label="Who it's for" name="audience" defaultValue={page?.audience ?? "everyone"}>{/* who it's for: */}
          {AUDIENCES.map((a) => <option key={a} value={a}>{AUDIENCE_NAMES[a]}</option>)}{/* each choice. */}
        </Select>{/* End of the choice. */}
        <Select label="Status" name="status" defaultValue={page?.status ?? "draft"}>{/* draft or published: */}
          <option value="draft">Draft</option>{/* draft, */}
          <option value="published">Published</option>{/* published. */}
        </Select>{/* End of the choice. */}
        <Field label="Order" name="position" type="number" min={0} max={9999} defaultValue={page?.position ?? 100} />{/* the order. */}
      </div>{/* End of the columns. */}
      <Tick name="urgent" label={'Pin at the top in red (for "Something\'s happened")'} defaultChecked={page?.urgent} />{/* the pin. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of HandbookForm.
