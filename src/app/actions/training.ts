// Summary: server actions for the training module: finishing a module
// (marking its quiz), and admin tools for modules, lessons, quiz questions,
// lesson files, the handbook and training settings.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { z } from "zod"; // The form-checking library.
import { requireAdmin, requireViewer } from "@/lib/auth"; // Checks for a full admin, and for anyone signed in.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { AUDIENCES, STAGES } from "@/lib/training"; // The audience and stage choices.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Every action checks who's asking here, and the database checks again
// (row level security and its own functions).

const uuid = z.uuid(); // The rule for a proper id.
const ADMIN_PAGE = "/admin/training"; // The training admin page, refreshed after changes.

// Turns a database error into a reply: its own plain message, or a general one.
function plain(error: { code?: string; message: string } | null, fallback: string): FormState { // Takes the error and a general message.
  if (!error) return {}; // No error: nothing to report.
  const ours = ["42501", "22023", "23505", "23514"].includes(error.code ?? ""); // True for the database's own plain refusals.
  return { error: ours ? `${error.message}.` : fallback }; // Shows that message, or the general one.
} // End of plain.

// Reads a whole number from a form field, or null when it's blank or not a number.
function whole(value: FormDataEntryValue | null): number | null { // Takes the field's value.
  const t = String(value ?? "").trim(); // The typed text without spaces at the ends.
  if (!/^\d+$/.test(t)) return null; // Blank or not a whole number: nothing.
  return Number(t); // The number.
} // End of whole.

// Turns a list of question numbers into words, e.g. [2, 4] -> "2 and 4".
function numberList(n: number[]): string { // Takes the numbers.
  if (n.length <= 1) return n.join(""); // One (or none): just that.
  return `${n.slice(0, -1).join(", ")} and ${n[n.length - 1]}`; // Otherwise "a, b and c".
} // End of numberList.

// ---------------------------------------------------------------------------
// Doing training
// ---------------------------------------------------------------------------

// Finishes a module: sends the quiz answers (one per question, named q1,
// q2, ...) to the database, which marks them. 100% is needed; people can
// try as often as they like.
export async function finishModule(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireViewer(); // Must be signed in.
  const id = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const count = whole(formData.get("question_count")) ?? 0; // How many questions the quiz has.
  const answers: number[] = []; // The answers, in question order.
  for (let i = 1; i <= count; i++) { // For each question:
    const a = whole(formData.get(`q${i}`)); // reads the chosen answer,
    if (a === null) return { error: `Please answer question ${i}.` }; // none chosen: asks for it,
    answers.push(a); // otherwise keeps it.
  } // End of the questions.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("training_finish", { p_module: id.data, p_answers: answers }); // Asks the database to mark it and record it.
  if (error) return plain(error, "Could not save your answers. Please try again."); // Failed: plain message.
  const result = data as { passed: boolean; score: number; total: number; wrong: number[]; already?: boolean }; // What the database said.
  revalidatePath("/training"); // Refreshes the training pages.
  if (!result.passed) { // Not all right:
    return { error: `You got ${result.score} of ${result.total}. Have another look at question${result.wrong.length > 1 ? "s" : ""} ${numberList(result.wrong)}, then try again. You can try as many times as you like.` }; // says which to look at again.
  } // End of the not-passed case.
  await supabase.rpc("training_save_progress", { p_module: id.data, p_answers: [] }); // Passed: clears any answers saved for later (they are no longer needed).
  if (result.already) return { message: "All right. You had already finished this module, so nothing new was recorded." }; // Already done: says so.
  return { message: "Well done, all right! This module is finished. Your certificate is ready on the Training page." }; // Passed: well done.
} // End of finishModule.

// Marks one lesson as done, so the person can stop and come back to the
// module another time and see where they were up to (Carla, 18 Nov 2026).
export async function markLessonDone(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireViewer(); // Must be signed in.
  const moduleId = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  const lessonId = uuid.safeParse(formData.get("lesson_id")); // Reads and checks the lesson's id.
  if (!moduleId.success || !lessonId.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("training_save_progress", { p_module: moduleId.data, p_done_lesson: lessonId.data }); // Asks the database to save it.
  if (error) return plain(error, "Could not save your place. Please try again."); // Failed: plain message.
  revalidatePath("/training", "layout"); // Refreshes the training pages, so the lesson shows as done.
  return { message: "Saved. You can stop here and carry on another time." }; // Says it is saved.
} // End of markLessonDone.

// Saves the quiz answers chosen so far without checking them, so the person
// can finish the quiz another time (Carla, 18 Nov 2026).
export async function saveQuizAnswers(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireViewer(); // Must be signed in.
  const id = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const count = whole(formData.get("question_count")) ?? 0; // How many questions the quiz has.
  const answers: number[] = []; // The answers so far, in question order.
  for (let i = 1; i <= count; i++) answers.push(whole(formData.get(`q${i}`)) ?? 0); // Each chosen answer, or 0 when not answered yet.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("training_save_progress", { p_module: id.data, p_answers: answers }); // Asks the database to keep them.
  if (error) return plain(error, "Could not save your answers. Please try again."); // Failed: plain message.
  revalidatePath("/training", "layout"); // Refreshes the training pages.
  return { message: "Your answers are saved. Come back any time to finish the quiz." }; // Says they are saved.
} // End of saveQuizAnswers.

// ---------------------------------------------------------------------------
// Admin: modules
// ---------------------------------------------------------------------------

// The fields of a module form, checked.
const moduleSchema = z.object({ // The rules:
  title: z.string().trim().min(2, "Please give the module a name.").max(150, "Keep the name under 150 characters."), // a name, 2 to 150 characters,
  summary: z.string().trim().max(600, "Keep the summary under 600 characters."), // a summary up to 600 characters,
  audience: z.enum(AUDIENCES), // who it's for,
  stage: z.enum(STAGES), // starting, refresher or ongoing,
  minutes: z.coerce.number().int().min(5, "The time must be at least 5 minutes.").max(480, "The time must be 8 hr or less."), // its set time, 5 to 480 minutes,
  renew_months: z.union([z.literal(""), z.coerce.number().int().min(1).max(60)]), // redo every 1 to 60 months, or blank,
  position: z.coerce.number().int().min(0).max(9999), // its order,
}); // End of the rules.

// Reads a module form's fields into what the database stores.
function moduleFields(formData: FormData) { // Takes the form.
  const parsed = moduleSchema.safeParse(Object.fromEntries(formData)); // Checks the fields.
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Please check the details." } as const; // Problem: the first message.
  const required = formData.get("required") === "on"; // Whether it's compulsory (ticked).
  return { // The values to save:
    values: { // (the module's columns)
      title: parsed.data.title, // its name,
      summary: parsed.data.summary, // summary,
      audience: parsed.data.audience, // who it's for,
      stage: parsed.data.stage, // stage,
      minutes: parsed.data.minutes, // set time,
      renew_months: parsed.data.renew_months === "" ? null : parsed.data.renew_months, // redo period (or none),
      position: parsed.data.position, // order,
      required, // compulsory or not,
      holds_matching: required && formData.get("holds_matching") === "on", // holds matches (only if compulsory),
      in_order: formData.get("in_order") === "on", // must be done in order with the other modules ticked the same way,
      needed_for: (["drafting", "term_review"] as const).find((j) => j === formData.get("needed_for")) ?? null, // a job it is needed before (or none),
      // (whether it counts towards the quarter's hours is set by the database: every module except safety ones)
    }, // (end of the columns)
  } as const; // End of the values.
} // End of moduleFields.

// Adds a new module (as a draft) and opens it for editing.
export async function createModule(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  const viewer = await requireAdmin(); // Only owner and operations admins.
  const f = moduleFields(formData); // Reads the fields.
  if ("error" in f) return { error: f.error }; // Problem: says what.
  const id = crypto.randomUUID(); // A new id for the module.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("training_modules").insert({ id, ...f.values, status: "draft", created_by: viewer.id }); // Saves it as a draft.
  if (error) return plain(error, "Could not add the module. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page.
  redirect(`${ADMIN_PAGE}/${id}`); // Opens the new module to add lessons and questions.
} // End of createModule.

// Saves a module's details, including publishing or retiring it.
export async function saveModule(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the module's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const f = moduleFields(formData); // Reads the fields.
  if ("error" in f) return { error: f.error }; // Problem: says what.
  const status = z.enum(["draft", "published", "retired"]).safeParse(formData.get("status")); // Reads and checks the status.
  if (!status.success) return { error: "Choose draft, published or retired." }; // Problem: asks for one.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("training_modules").update({ ...f.values, status: status.data }).eq("id", id.data); // Saves the changes.
  if (error) return plain(error, "Could not save the module. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  revalidatePath("/training", "layout"); // And the training pages.
  return { message: status.data === "published" ? "Saved. It is published, so the people it is for can see it." : "Saved." }; // Says it's saved.
} // End of saveModule.

// Assigns a module to a tutor or admin staff member, with a due date
// (Carla, 18 Nov 2026). An assigned module is paid for its set time.
export async function assignModule(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const moduleId = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  const person = uuid.safeParse(formData.get("account_id")); // Reads and checks the person's id.
  if (!moduleId.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  if (!person.success) return { error: "Please choose who to assign it to." }; // No person chosen: asks for one.
  const due = z.iso.date().safeParse(formData.get("due_on")); // Reads and checks the due date.
  if (!due.success) return { error: "Please choose a due date." }; // No date: asks for one.
  const reason = String(formData.get("reason") ?? "").trim().slice(0, 300); // Why it is assigned (optional, up to 300 characters).
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("training_assign", { p_account: person.data, p_module: moduleId.data, p_due: due.data, p_reason: reason || null }); // Asks the database to assign it.
  if (error) return plain(error, "Could not assign the module. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  return { message: "Assigned. They have been told, and it is on their To do list." }; // Says it is done.
} // End of assignModule.

// Removes a module assignment.
export async function unassignModule(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const moduleId = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  const person = uuid.safeParse(formData.get("account_id")); // Reads and checks the person's id.
  if (!moduleId.success || !person.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("training_unassign", { p_account: person.data, p_module: moduleId.data }); // Asks the database to remove it.
  if (error) return plain(error, "Could not remove it. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  return { message: "Removed." }; // Says it is done.
} // End of unassignModule.

// Deletes a draft module (published ones are retired instead, to keep records).
export async function deleteDraftModule(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the module's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { data: files } = await supabase.from("training_lessons").select("file_path").eq("module_id", id.data).not("file_path", "is", null); // The lesson files to remove too.
  const { error, count } = await supabase.from("training_modules").delete({ count: "exact" }).eq("id", id.data).eq("status", "draft"); // Deletes it, only if it's a draft.
  if (error) return plain(error, "Could not delete it. Please try again."); // Failed: plain message.
  if (!count) return { error: "Only drafts can be deleted. Retire a published module instead, so its records stay." }; // Not a draft: explains.
  const paths = (files ?? []).map((f) => f.file_path as string); // The file names.
  if (paths.length) await supabase.storage.from("training").remove(paths); // Removes the files from the store.
  revalidatePath(ADMIN_PAGE); // Refreshes the admin page.
  redirect(ADMIN_PAGE); // Goes back to the list.
} // End of deleteDraftModule.

// Asks everyone to redo a module after a big change.
export async function askRedo(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the module's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.rpc("training_ask_redo", { p_module: id.data }); // Asks the database to start a new version.
  if (error) return plain(error, "Could not do that. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  return { message: "Done. Everyone it is for needs to finish it again, with the usual time allowed from today." }; // Says what happens now.
} // End of askRedo.

// ---------------------------------------------------------------------------
// Admin: lessons
// ---------------------------------------------------------------------------

// The fields of a lesson form, checked.
const lessonSchema = z.object({ // The rules:
  module_id: uuid, // the module it belongs to,
  title: z.string().trim().min(2, "Please give the lesson a heading.").max(150, "Keep the heading under 150 characters."), // a heading,
  body: z.string().max(20000, "This lesson is too long. Split it into two lessons."), // its text,
  position: z.coerce.number().int().min(0).max(9999), // its order,
  link_url: z.union([z.literal(""), z.string().trim().regex(/^https:\/\//, "Links must start with https://").max(500)]), // an optional secure link,
  link_label: z.string().trim().max(150), // the link's words,
}); // End of the rules.

// Adds a lesson, or saves changes to one (when an id is sent).
export async function saveLesson(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const parsed = lessonSchema.safeParse(Object.fromEntries(formData)); // Checks the fields.
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Please check the lesson." }; // Problem: the first message.
  const values = { // The values to save:
    module_id: parsed.data.module_id, // the module,
    title: parsed.data.title, // heading,
    body: parsed.data.body.trim(), // text,
    position: parsed.data.position, // order,
    link_url: parsed.data.link_url || null, // link (or none),
    link_label: parsed.data.link_url ? parsed.data.link_label || null : null, // link words (only with a link),
    updated_at: new Date().toISOString(), // when it was changed.
  }; // End of the values.
  const supabase = await createClient(); // Connects to the database.
  const id = uuid.safeParse(formData.get("id")); // An existing lesson's id, if sent.
  const { error } = id.success // Saves:
    ? await supabase.from("training_lessons").update(values).eq("id", id.data) // changes to that lesson,
    : await supabase.from("training_lessons").insert(values); // or a new lesson.
  if (error) return plain(error, "Could not save the lesson. Please try again."); // Failed: plain message.
  revalidatePath(`${ADMIN_PAGE}/${parsed.data.module_id}`); // Refreshes the module's admin page.
  return { message: id.success ? "Lesson saved." : "Lesson added." }; // Says it's saved.
} // End of saveLesson.

// Deletes a lesson (and its file).
export async function deleteLesson(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the lesson's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { data: lesson } = await supabase.from("training_lessons").select("module_id, file_path").eq("id", id.data).maybeSingle(); // Reads the lesson first.
  if (!lesson) return { error: "That lesson is already gone." }; // Not found: already gone.
  const { error } = await supabase.from("training_lessons").delete().eq("id", id.data); // Deletes it.
  if (error) return plain(error, "Could not delete the lesson. Please try again."); // Failed: plain message.
  if (lesson.file_path) await supabase.storage.from("training").remove([lesson.file_path]); // Removes its file from the store.
  revalidatePath(`${ADMIN_PAGE}/${lesson.module_id}`); // Refreshes the module's admin page.
  return { message: "Lesson deleted." }; // Says it's done.
} // End of deleteLesson.

// Attaches a video or PDF (already uploaded from the browser) to a lesson.
export async function attachLessonFile(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("lesson_id")); // Reads and checks the lesson's id.
  const path = z.string().regex(/^lessons\/[0-9a-f-]{36}\.(mp4|webm|mov|pdf)$/).safeParse(formData.get("path")); // Checks the stored file name is one this app made.
  const name = z.string().trim().min(1).max(200).safeParse(formData.get("file_name")); // Checks the original file name.
  if (!id.success || !path.success || !name.success) return { error: "That file could not be attached. Please try again." }; // Problem: plain message.
  const supabase = await createClient(); // Connects to the database.
  const { data: lesson } = await supabase.from("training_lessons").select("module_id, file_path").eq("id", id.data).maybeSingle(); // Reads the lesson first.
  if (!lesson) return { error: "That lesson is gone. Please reload the page." }; // Not found: asks to reload.
  const { error } = await supabase.from("training_lessons").update({ file_path: path.data, file_name: name.data, updated_at: new Date().toISOString() }).eq("id", id.data); // Saves the file on the lesson.
  if (error) { // Failed:
    await supabase.storage.from("training").remove([path.data]); // removes the uploaded file so nothing is left behind,
    return plain(error, "Could not attach the file. Please try again."); // and says so.
  } // End of the failure case.
  if (lesson.file_path && lesson.file_path !== path.data) await supabase.storage.from("training").remove([lesson.file_path]); // Removes the file it replaced.
  revalidatePath(`${ADMIN_PAGE}/${lesson.module_id}`); // Refreshes the module's admin page.
  return { message: "File attached." }; // Says it's done.
} // End of attachLessonFile.

// Removes a lesson's video or PDF.
export async function removeLessonFile(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the lesson's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { data: lesson } = await supabase.from("training_lessons").select("module_id, file_path").eq("id", id.data).maybeSingle(); // Reads the lesson first.
  if (!lesson?.file_path) return { message: "There is no file on this lesson." }; // No file: nothing to do.
  const { error } = await supabase.from("training_lessons").update({ file_path: null, file_name: null }).eq("id", id.data); // Takes the file off the lesson.
  if (error) return plain(error, "Could not remove the file. Please try again."); // Failed: plain message.
  await supabase.storage.from("training").remove([lesson.file_path]); // Deletes the file from the store.
  revalidatePath(`${ADMIN_PAGE}/${lesson.module_id}`); // Refreshes the module's admin page.
  return { message: "File removed." }; // Says it's done.
} // End of removeLessonFile.

// ---------------------------------------------------------------------------
// Admin: quiz questions
// ---------------------------------------------------------------------------

// Adds a question, or saves changes to one (when an id is sent). Choices
// are typed one per line; the right one is given by its number.
export async function saveQuestion(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const moduleId = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  if (!moduleId.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const prompt = String(formData.get("prompt") ?? "").trim(); // The question.
  if (prompt.length < 3 || prompt.length > 600) return { error: "Write the question (up to 600 characters)." }; // Too short or long: asks again.
  const options = String(formData.get("options") ?? "").split(/\r?\n/).map((o) => o.trim()).filter(Boolean); // The choices, one per line, blanks left out.
  if (options.length < 2 || options.length > 6) return { error: "Give 2 to 6 choices, one per line." }; // Wrong number: asks again.
  if (options.some((o) => o.length > 300)) return { error: "Keep each choice under 300 characters." }; // A choice too long: asks again.
  const correct = whole(formData.get("correct_option")); // The right choice's number.
  if (correct === null || correct < 1 || correct > options.length) return { error: `Choose which choice is right (1 to ${options.length}).` }; // Missing or out of range: asks again.
  const explanation = String(formData.get("explanation") ?? "").trim().slice(0, 600) || null; // Why it's right (for admins), if given.
  const position = whole(formData.get("position")) ?? 100; // Its order.
  const values = { module_id: moduleId.data, prompt, options, correct_option: correct, explanation, position }; // The values to save.
  const supabase = await createClient(); // Connects to the database.
  const id = uuid.safeParse(formData.get("id")); // An existing question's id, if sent.
  const { error } = id.success // Saves:
    ? await supabase.from("training_questions").update(values).eq("id", id.data) // changes to that question,
    : await supabase.from("training_questions").insert(values); // or a new question.
  if (error) return plain(error, "Could not save the question. Please try again."); // Failed: plain message.
  revalidatePath(`${ADMIN_PAGE}/${moduleId.data}`); // Refreshes the module's admin page.
  return { message: id.success ? "Question saved." : "Question added." }; // Says it's saved.
} // End of saveQuestion.

// Deletes a quiz question.
export async function deleteQuestion(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the question's id.
  const moduleId = uuid.safeParse(formData.get("module_id")); // Reads and checks the module's id.
  if (!id.success || !moduleId.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("training_questions").delete().eq("id", id.data); // Deletes it.
  if (error) return plain(error, "Could not delete the question. Please try again."); // Failed: plain message.
  revalidatePath(`${ADMIN_PAGE}/${moduleId.data}`); // Refreshes the module's admin page.
  return { message: "Question deleted." }; // Says it's done.
} // End of deleteQuestion.

// ---------------------------------------------------------------------------
// Admin: settings and the handbook
// ---------------------------------------------------------------------------

// Saves the training settings: days allowed, hours each quarter, largest upload.
export async function saveTrainingSettings(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  const viewer = await requireAdmin(); // Only owner and operations admins.
  const parsed = z.object({ // The rules:
    grace_days: z.coerce.number().int().min(0, "Days allowed cannot be negative.").max(180, "Days allowed can be up to 180."), // days allowed, 0 to 180,
    quarter_hours: z.coerce.number().min(0).max(40, "Up to 40 hr a quarter."), // hours each quarter, 0 to 40,
    video_max_mb: z.coerce.number().int().min(1).max(5000, "The largest upload can be up to 5000 MB."), // largest upload, 1 to 5000 MB,
  }).safeParse(Object.fromEntries(formData)); // (checked against the form)
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Please check the settings." }; // Problem: the first message.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("training_settings").update({ // Saves:
    grace_days: parsed.data.grace_days, // days allowed,
    quarter_minutes: Math.round(parsed.data.quarter_hours * 60), // hours each quarter, as minutes,
    video_max_mb: parsed.data.video_max_mb, // largest upload,
    updated_by: viewer.id, // who changed them,
    updated_at: new Date().toISOString(), // and when.
  }).eq("id", true); // (the one settings row)
  if (error) return plain(error, "Could not save the settings. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  return { message: "Settings saved." }; // Says it's saved.
} // End of saveTrainingSettings.

// Adds a handbook page, or saves changes to one (when an id is sent).
export async function saveHandbookPage(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  const viewer = await requireAdmin(); // Only owner and operations admins.
  const parsed = z.object({ // The rules:
    title: z.string().trim().min(2, "Please give the page a heading.").max(150, "Keep the heading under 150 characters."), // a heading,
    body: z.string().max(30000, "This page is too long. Split it into two pages."), // its text,
    audience: z.enum(AUDIENCES), // who it's for,
    status: z.enum(["draft", "published"]), // draft or published,
    position: z.coerce.number().int().min(0).max(9999), // its order,
  }).safeParse(Object.fromEntries(formData)); // (checked against the form)
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Please check the page." }; // Problem: the first message.
  const values = { // The values to save:
    ...parsed.data, // the checked fields,
    body: parsed.data.body.trim(), // the text without spaces at the ends,
    urgent: formData.get("urgent") === "on", // whether it's pinned at the top in red,
    updated_by: viewer.id, // who changed it,
    updated_at: new Date().toISOString(), // and when.
  }; // End of the values.
  const supabase = await createClient(); // Connects to the database.
  const id = uuid.safeParse(formData.get("id")); // An existing page's id, if sent.
  if (id.success) { // Changing a page:
    const { error } = await supabase.from("handbook_pages").update(values).eq("id", id.data); // saves the changes,
    if (error) return plain(error, "Could not save the page. Please try again."); // failed: plain message.
    revalidatePath(ADMIN_PAGE, "layout"); // refreshes the admin pages,
    revalidatePath("/handbook", "layout"); // and the handbook,
    return { message: "Page saved." }; // and says it's saved.
  } // End of changing.
  const newId = crypto.randomUUID(); // A new page's id.
  const { error } = await supabase.from("handbook_pages").insert({ id: newId, ...values }); // Adds the page.
  if (error) return plain(error, "Could not add the page. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  redirect(`${ADMIN_PAGE}/handbook/${newId}`); // Opens the new page for editing.
} // End of saveHandbookPage.

// Deletes a handbook page.
export async function deleteHandbookPage(_prev: FormState, formData: FormData): Promise<FormState> { // Gets the last reply and the form.
  await requireAdmin(); // Only owner and operations admins.
  const id = uuid.safeParse(formData.get("id")); // Reads and checks the page's id.
  if (!id.success) return { error: "Something went wrong. Please reload the page." }; // Problem: asks to reload.
  const supabase = await createClient(); // Connects to the database.
  const { error } = await supabase.from("handbook_pages").delete().eq("id", id.data); // Deletes it.
  if (error) return plain(error, "Could not delete the page. Please try again."); // Failed: plain message.
  revalidatePath(ADMIN_PAGE, "layout"); // Refreshes the admin pages.
  revalidatePath("/handbook", "layout"); // And the handbook.
  redirect(`${ADMIN_PAGE}?section=handbook`); // Goes back to the handbook list.
} // End of deleteHandbookPage.
