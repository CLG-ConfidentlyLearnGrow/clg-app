// Summary: edit one training module (owner and operations): its details and
// status, its lessons (text, a video or PDF, a link), and its quiz questions.
//
import { notFound } from "next/navigation"; // Shows "not found".
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, Empty, TextLink } from "@/components/ui"; // The back button, card, "nothing yet" note and link style.
import { askRedo, deleteDraftModule, deleteLesson, deleteQuestion, removeLessonFile } from "@/app/actions/training"; // The server actions for the small buttons.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { LessonFileForm, LessonForm, ModuleForm, QuestionForm, SmallAction, type LessonRow, type ModuleRow, type QuestionRow } from "../forms"; // The admin forms and their shapes.

// Shows the module editing page.
export default async function AdminTrainingModulePage({ params }: PageProps<"/admin/training/[id]">) { // Reads the address's id.
  const viewer = await requireAdmin(); // Only owner and operations admins.
  const { id } = await params; // The module's id.
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound(); // Odd id: not found.
  const supabase = await createClient(); // Connects to the database.
  const [mod, lessons, questions, settings, done] = await Promise.all([ // Reads five things at once:
    supabase.from("training_modules").select("id, title, summary, audience, stage, required, holds_matching, counts_toward_certified, minutes, renew_months, status, position, version").eq("id", id).maybeSingle(), // the module,
    supabase.from("training_lessons").select("id, title, body, position, file_path, file_name, link_url, link_label").eq("module_id", id).order("position").order("id"), // its lessons,
    supabase.rpc("training_questions_for_admin", { p_module: id }), // its questions with answers,
    supabase.from("training_settings").select("video_max_mb").eq("id", true).maybeSingle(), // the largest upload allowed,
    supabase.from("training_completions").select("id", { count: "exact", head: true }).eq("module_id", id), // and how many people have finished it.
  ]); // End of the reads.
  if (!mod.data) notFound(); // No such module: not found.
  const m = mod.data as ModuleRow & { version: number }; // The module.
  const lessonRows = (lessons.data ?? []) as LessonRow[]; // The lessons.
  const questionRows = (questions.data ?? []) as QuestionRow[]; // The questions.
  const maxMb = settings.data?.video_max_mb ?? 500; // The largest upload, in MB.
  const nextLesson = (lessonRows.at(-1)?.position ?? 0) + 1; // The next lesson's order number.
  const nextQuestion = (questionRows.at(-1)?.question_position ?? 0) + 1; // The next question's order number.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="training-admin">{/* the dashboard tabs and menu, with Training setup open: */}
      <p className="flex flex-wrap items-center gap-4"><BackButton href="/admin/training">Back to all modules</BackButton><TextLink href={`/training/${m.id}?as=admin`}>Preview as staff</TextLink></p>{/* a button back to the module list, and a link to a preview, */}
      <Card title="Module details" description={`Version ${m.version}. ${done.count ?? 0} completion(s) so far.`}>{/* the details card: */}
        <ModuleForm m={m} />{/* the details form. */}
      </Card>{/* End of the details card. */}

      <Card title="Lessons" description="Short lessons work best: one idea each, with an example. Add a video or PDF to any lesson.">{/* the lessons card: */}
        {lessonRows.length === 0 && <Empty>No lessons yet. Add the first one below.</Empty>}{/* none: says so. */}
        <div className="space-y-6">{/* the lessons, with space between: */}
          {lessonRows.map((l) => ( // each lesson:
            <details key={l.id} className="rounded-xl border border-zinc-200 p-4">{/* a fold-up box: */}
              <summary className="cursor-pointer font-medium">{l.position}. {l.title}{l.file_name ? ` · ${l.file_name}` : ""}</summary>{/* its order, heading and file, */}
              <div className="mt-4 space-y-5">{/* the contents: */}
                <LessonForm moduleId={m.id} lesson={l} nextPosition={nextLesson} />{/* the lesson form, */}
                <div className="space-y-2 border-t border-zinc-100 pt-4">{/* the file part: */}
                  {l.file_path ? ( // a file is attached:
                    <div className="flex flex-wrap items-center gap-3 text-sm">{/* a row: */}
                      <span>Attached: {l.file_name}</span>{/* its name, */}
                      <SmallAction action={removeLessonFile} fields={{ id: l.id }} label="Remove file" confirm="Remove this file from the lesson?" />{/* and a remove button. */}
                    </div> // End of the row.
                  ) : null}{/* End of the attached file. */}
                  <LessonFileForm lessonId={l.id} maxMb={maxMb} />{/* the upload form (replaces any file). */}
                </div>{/* End of the file part. */}
                <SmallAction action={deleteLesson} fields={{ id: l.id }} label="Delete lesson" confirm="Delete this lesson and its file?" />{/* the delete button. */}
              </div>{/* End of the contents. */}
            </details> // End of the box.
          ))}{/* End of the lessons. */}
        </div>{/* End of the lessons. */}
        <div className="mt-6 border-t border-zinc-100 pt-5">{/* the add part: */}
          <h3 className="mb-3 text-sm font-semibold">Add a lesson</h3>{/* its heading, */}
          <LessonForm moduleId={m.id} nextPosition={nextLesson} />{/* and the form. */}
        </div>{/* End of the add part. */}
      </Card>{/* End of the lessons card. */}

      <Card title="Quiz" description="Everyone needs 100%, with unlimited tries. They're told which questions to look at again, never the answers. For refreshers, ask where to find things in the handbook.">{/* the quiz card: */}
        {questionRows.length === 0 && <Empty>No questions. Without a quiz, people just mark the module as finished.</Empty>}{/* none: says so. */}
        <div className="space-y-6">{/* the questions: */}
          {questionRows.map((q) => ( // each question:
            <details key={q.id} className="rounded-xl border border-zinc-200 p-4">{/* a fold-up box: */}
              <summary className="cursor-pointer font-medium">{q.question_position}. {q.prompt}</summary>{/* its order and question, */}
              <div className="mt-4 space-y-4">{/* the contents: */}
                <QuestionForm moduleId={m.id} q={q} nextPosition={nextQuestion} />{/* the question form, */}
                <SmallAction action={deleteQuestion} fields={{ id: q.id, module_id: m.id }} label="Delete question" confirm="Delete this question?" />{/* and the delete button. */}
              </div>{/* End of the contents. */}
            </details> // End of the box.
          ))}{/* End of the questions. */}
        </div>{/* End of the questions. */}
        <div className="mt-6 border-t border-zinc-100 pt-5">{/* the add part: */}
          <h3 className="mb-3 text-sm font-semibold">Add a question</h3>{/* its heading, */}
          <QuestionForm moduleId={m.id} nextPosition={nextQuestion} />{/* and the form. */}
        </div>{/* End of the add part. */}
      </Card>{/* End of the quiz card. */}

      <Card title="Big changes and deleting">{/* the last card: */}
        <div className="space-y-4 text-sm">{/* a block: */}
          {m.status === "published" && ( // a published module:
            <div className="space-y-2">{/* the redo part: */}
              <p>Changed something important? Ask everyone it&apos;s for to finish it again. They get the usual time allowed from today, and it&apos;s paid again if it&apos;s compulsory. Small fixes don&apos;t need this.</p>{/* what it does, */}
              <SmallAction action={askRedo} fields={{ id: m.id }} label="Ask everyone to redo this" confirm="Everyone will need to finish this module again. Go ahead?" />{/* and the button. */}
            </div> // End of the redo part.
          )}{/* End of the published case. */}
          {m.status === "draft" ? ( // a draft:
            <SmallAction action={deleteDraftModule} fields={{ id: m.id }} label="Delete this draft" confirm="Delete this draft module, its lessons, files and questions?" /> // a delete button,
          ) : ( // otherwise:
            <p className="text-zinc-600">Published modules can&apos;t be deleted, so training records stay. Set the status to Retired to hide it.</p> // explains to retire instead.
          )}{/* End of the choice. */}
        </div>{/* End of the block. */}
      </Card>{/* End of the last card. */}
      <p><BackButton href="/admin/training">Back to all modules</BackButton></p>{/* the same back button at the bottom, so it's there after scrolling down. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of AdminTrainingModulePage.
