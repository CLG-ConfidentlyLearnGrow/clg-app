// Summary: one training module for tutors and admin staff: its lessons
// (text, videos, PDFs and links) in order, then the quiz. People can mark
// lessons done and save quiz answers, then carry on another time.
//
import { notFound, redirect } from "next/navigation"; // Shows "not found", or sends the person elsewhere.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { TrainingText } from "@/components/training-text"; // Shows lesson text with simple formatting.
import { BackButton, Card, Empty, TextLink } from "@/components/ui"; // The back button, card, "nothing yet" note and link style.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { STATE_NAMES, STATE_STYLES, isVideo, staffRole, timeText, type MyModule } from "@/lib/training"; // Training words, colours and helpers.
import { LessonDone } from "./lesson-done"; // The "Done, save my place" button under each lesson.
import { QuizForm, type QuizQuestion } from "./quiz-form"; // The quiz.
import { TaskForm } from "./task-form"; // The practice task form.

// Shows one module.
export default async function TrainingModulePage({ params, searchParams }: PageProps<"/training/[id]">) { // Reads the address's id and settings.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login needed.
  const { id } = await params; // The module's id.
  const { as } = await searchParams; // Which dashboard it was opened from.
  const role = staffRole(as, viewer.roles); // The dashboard to show it in.
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound(); // Odd id: not found.
  const supabase = await createClient(); // Connects to the database.
  const [mod, lessons, questions, mine, place, ordered, assignment, task] = await Promise.all([ // Reads eight things at once:
    supabase.from("training_modules").select("id, title, summary, minutes, required, status, practice_task, version").eq("id", id).maybeSingle(), // the module (only if they can see it),
    supabase.from("training_lessons").select("id, title, body, file_path, file_name, link_url, link_label").eq("module_id", id).order("position").order("id"), // its lessons, in order,
    supabase.from("training_questions").select("id, prompt, options, image_path, image_alt").eq("module_id", id).order("position").order("id"), // its questions, in order (no answers),
    supabase.rpc("training_my_modules"), // where they're up to,
    supabase.from("training_progress").select("done_lessons, saved_answers").eq("module_id", id).eq("account_id", viewer.id).maybeSingle(), // the place they saved (lessons done, answers kept),
    supabase.from("training_modules").select("id, title, position, in_order").eq("in_order", true).eq("status", "published").order("position"), // the modules done in order,
    supabase.from("training_assignments").select("due_on, reason").eq("module_id", id).eq("account_id", viewer.id).maybeSingle(), // whether CLG assigned this module to them,
    supabase.from("training_task_submissions").select("answer, status, feedback, module_version").eq("module_id", id).eq("account_id", viewer.id).order("created_at", { ascending: false }).limit(1).maybeSingle(), // and their latest practice task for it.
  ]); // End of the reads.
  if (!mod.data) notFound(); // Can't see it: not found.
  const m = mod.data; // The module.
  const me = ((mine.data ?? []) as MyModule[]).find((x) => x.module_id === id); // Where they're up to with it (if it's for them).
  const lessonRows = (lessons.data ?? []) as { id: string; title: string; body: string; file_path: string | null; file_name: string | null; link_url: string | null; link_label: string | null }[]; // The lessons.
  const myStates = new Map(((mine.data ?? []) as MyModule[]).map((x) => [x.module_id, x.state])); // Where they are up to with each of their modules.
  const thisInOrder = ((ordered.data ?? []) as { id: string; title: string; position: number; in_order: boolean }[]).find((x) => x.id === id); // This module, if it is done in order.
  const waitingFor = thisInOrder ? ((ordered.data ?? []) as { id: string; title: string; position: number }[]).find((x) => x.position < thisInOrder.position && myStates.has(x.id) && !["done", "renew_soon"].includes(myStates.get(x.id) ?? "")) : undefined; // The first earlier in-order module they have not finished (if any).
  const assigned = assignment.data as { due_on: string; reason: string | null } | null; // CLG's assignment of this module to them (if any).
  const doneLessons = new Set((place.data?.done_lessons ?? []) as string[]); // The lessons they have marked as done.
  const savedAnswers = (place.data?.saved_answers ?? []) as number[]; // The quiz answers they saved for later.
  const doneCount = lessonRows.filter((l) => doneLessons.has(l.id)).length; // How many of this module's lessons are done.
  const nextIndex = lessonRows.findIndex((l) => !doneLessons.has(l.id)); // The first lesson not done yet (-1 when all are done).
  const questionRows = (questions.data ?? []) as { id: string; prompt: string; options: string[]; image_path: string | null; image_alt: string | null }[]; // The quiz questions (with any picture).
  const quiz: QuizQuestion[] = await Promise.all(questionRows.map(async (q) => ({ id: q.id, prompt: q.prompt, options: q.options, image_alt: q.image_alt, image_url: q.image_path ? (await supabase.storage.from("training").createSignedUrl(q.image_path, 3600)).data?.signedUrl ?? null : null }))); // Each question, with a link to its picture that works for one hour.
  const myTask = task.data as { answer: string; status: string; feedback: string | null; module_version: number } | null; // Their latest practice task (if any).
  const taskNow = myTask && myTask.module_version === m.version ? myTask : null; // Only if it is for this version of the module.
  const files = await Promise.all( // Makes a link for each lesson file, that works for one hour:
    lessonRows.map(async (l) => (l.file_path ? (await supabase.storage.from("training").createSignedUrl(l.file_path, 3600)).data?.signedUrl ?? null : null)), // (none if no file)
  ); // End of the links.

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="training">{/* the dashboard tabs and menu, with Training open: */}
      <p><BackButton href={`/training?as=${role}`}>Back to all modules</BackButton></p>{/* a button back to the module list, */}
      <div className="space-y-2">{/* the module's heading block: */}
        <h2 className="text-xl font-semibold tracking-tight">{m.title}</h2>{/* its name, */}
        <p className="text-sm text-zinc-600">{/* its details: */}
          {timeText(m.minutes)}{m.required ? " · Compulsory" : " · Optional"}{/* time, and compulsory or not, */}
          {me && <span className={`ml-2 rounded-full px-2 py-0.5 text-xs font-semibold ${STATE_STYLES[me.state]}`}>{STATE_NAMES[me.state]}</span>}{/* where they're up to, */}
          {me?.due_on && (me.state === "to_do" || me.state === "overdue") && <span className="ml-2">Due {plainDate(me.due_on)}</span>}{/* and the due date. */}
        </p>{/* End of the details. */}
        {m.summary && <p className="text-sm text-zinc-700">{m.summary}</p>}{/* the summary, if any. */}
        {assigned && <p className="text-sm text-teal-900">CLG has assigned you this module, due by {plainDate(assigned.due_on)}.{assigned.reason ? ` ${assigned.reason}.` : ""}</p>}{/* an assignment from CLG, */}
        {me && (m.required || assigned) ? ( // compulsory or assigned:
          <p className="text-sm text-zinc-600">You are paid for this module&apos;s set time ({timeText(m.minutes)}) once, when you finish it. Any time beyond that, or doing it again, is in your own time.</p> // the pay rule,
        ) : me ? ( // optional and not assigned:
          <p className="text-sm text-zinc-600">This module is optional. You can do it in your own time. It is only paid if CLG approved it first.</p> // the pay rule for optional training,
        ) : null}{/* End of the pay rule. */}
        {me && waitingFor && <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">These modules are done in order. Please finish <TextLink href={`/training/${waitingFor.id}?as=${role}`}>{waitingFor.title}</TextLink> first. You can read this module now, but you can only finish it after that one.</p>}{/* a note when an earlier in-order module is not done, */}
        {me && doneCount > 0 && ( // Started before:
          <p className="text-sm text-teal-900">{/* where they were up to: */}
            You have done {doneCount} of {lessonRows.length} lessons.{" "}{/* how many are done, */}
            {nextIndex >= 0 ? <TextLink href={`#lesson-${nextIndex + 1}`}>Carry on from lesson {nextIndex + 1}</TextLink> : <TextLink href="#quiz">Go to the quiz</TextLink>}{/* and a link to carry on. */}
          </p> // End of the note.
        )}{/* End of the saved place. */}
        {m.status !== "published" && <p className="text-sm text-amber-800">Admin preview: this module is not published yet.</p>}{/* a note when an admin previews a draft. */}
      </div>{/* End of the heading block. */}

      {lessonRows.length === 0 && <Empty>This module has no lessons yet.</Empty>}{/* No lessons: says so. */}
      {lessonRows.map((l, i) => ( // each lesson:
        <div key={l.id} id={`lesson-${i + 1}`} className="scroll-mt-4">{/* a place the "carry on" link can jump to: */}
        <Card title={`${i + 1}. ${l.title}${doneLessons.has(l.id) ? " ✓" : ""}`}>{/* a card with its number and heading (ticked when done): */}
          <div className="space-y-4">{/* a block: */}
            {files[i] && isVideo(l.file_path) && ( // a video:
              <video controls preload="metadata" className="w-full rounded-xl bg-black" src={files[i]!}>{/* a video player, */}
                Your browser cannot play this video. <a href={files[i]!}>Download it instead</a>.{/* (with a download link for old browsers) */}
              </video> // End of the player.
            )}{/* End of the video. */}
            {files[i] && !isVideo(l.file_path) && ( // a PDF:
              <p><TextLink href={files[i]!} target="_blank" rel="noopener noreferrer">Open {l.file_name ?? "the PDF"}</TextLink></p> // a link that opens it.
            )}{/* End of the PDF. */}
            {l.body && <TrainingText text={l.body} />}{/* the lesson's text, */}
            {l.link_url && ( // an outside link:
              <p><TextLink href={l.link_url} target="_blank" rel="noopener noreferrer">{l.link_label || l.link_url}</TextLink></p> // opens in a new tab.
            )}{/* End of the link. */}
            {me && <LessonDone moduleId={m.id} lessonId={l.id} done={doneLessons.has(l.id)} />}{/* the "Done, save my place" button (only for people the module is for). */}
          </div>{/* End of the block. */}
        </Card>{/* End of the card. */}
        </div> // End of the jump place.
      ))}{/* End of the lessons. */}

      {me && m.practice_task && ( // A module with a practice task, for them:
        <Card title="Practice task (checked by CLG)" description="Write it here. Lauren or Carla checks it and approves it, or sends it back with what to change. The module is finished once the quiz is passed and this is approved. Use only the made-up details given: never write about a real student.">{/* the task card: */}
          <div className="space-y-4">{/* a block: */}
            <TrainingText text={m.practice_task} />{/* the task's instructions, */}
            {taskNow?.status === "approved" ? ( // approved:
              <p className="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-900">Approved.{taskNow.feedback ? ` CLG said: ${taskNow.feedback}` : ""}</p> // says so, with any comment,
            ) : ( // not approved yet:
              <>{/* (a group:) */}
                {taskNow?.status === "submitted" && <p className="rounded-lg bg-sky-50 px-3 py-2 text-sm text-sky-900">Sent. CLG will check it and you will get a notice. You can change it and send it again until then.</p>}{/* waiting, */}
                {taskNow?.status === "returned" && <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">Sent back. CLG said: {taskNow.feedback}</p>}{/* sent back, with what to change, */}
                <TaskForm moduleId={m.id} answer={taskNow?.answer ?? ""} />{/* and the form. */}
              </> // End of the group.
            )}{/* End of the choice. */}
          </div>{/* End of the block. */}
        </Card> // End of the card.
      )}{/* End of the practice task. */}

      {me ? ( // If the module is for them:
        <div id="quiz" className="scroll-mt-4">{/* a place the "go to the quiz" link can jump to: */}
        <Card title={quiz.length ? "Quiz" : "Finish this module"} description={quiz.length ? "Answer every question. You need them all right, and you can try as many times as you like. Use the handbook and the lessons above." : "Mark it as finished once you have worked through the lessons."}>{/* the quiz card: */}
          <QuizForm moduleId={m.id} questions={quiz} done={me.state === "done"} saved={savedAnswers} />{/* the quiz (with any answers saved earlier). */}
        </Card>{/* End of the card. */}
        </div> // End of the jump place.
      ) : ( // Otherwise (an admin previewing):
        <Empty>This module is not one of yours, so there is no quiz to do here.</Empty> // says so.
      )}{/* End of the quiz. */}
      <p><BackButton href={`/training?as=${role}`}>Back to all modules</BackButton></p>{/* The same back button at the bottom, so it's there after the quiz. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of TrainingModulePage.
