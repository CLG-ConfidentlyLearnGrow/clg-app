// Summary: one training module for tutors and admin staff: its lessons
// (text, videos, PDFs and links) in order, then the quiz.
//
import { notFound, redirect } from "next/navigation"; // Shows "not found", or sends the person elsewhere.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { TrainingText } from "@/components/training-text"; // Shows lesson text with simple formatting.
import { BackButton, Card, Empty, TextLink } from "@/components/ui"; // The back button, card, "nothing yet" note and link style.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { STATE_NAMES, STATE_STYLES, isVideo, staffRole, timeText, type MyModule } from "@/lib/training"; // Training words, colours and helpers.
import { QuizForm, type QuizQuestion } from "./quiz-form"; // The quiz.

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
  const [mod, lessons, questions, mine] = await Promise.all([ // Reads four things at once:
    supabase.from("training_modules").select("id, title, summary, minutes, required, status").eq("id", id).maybeSingle(), // the module (only if they can see it),
    supabase.from("training_lessons").select("id, title, body, file_path, file_name, link_url, link_label").eq("module_id", id).order("position").order("id"), // its lessons, in order,
    supabase.from("training_questions").select("id, prompt, options").eq("module_id", id).order("position").order("id"), // its questions, in order (no answers),
    supabase.rpc("training_my_modules"), // and where they're up to.
  ]); // End of the reads.
  if (!mod.data) notFound(); // Can't see it: not found.
  const m = mod.data; // The module.
  const me = ((mine.data ?? []) as MyModule[]).find((x) => x.module_id === id); // Where they're up to with it (if it's for them).
  const lessonRows = (lessons.data ?? []) as { id: string; title: string; body: string; file_path: string | null; file_name: string | null; link_url: string | null; link_label: string | null }[]; // The lessons.
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
        {m.status !== "published" && <p className="text-sm text-amber-800">Admin preview: this module isn&apos;t published yet.</p>}{/* a note when an admin previews a draft. */}
      </div>{/* End of the heading block. */}

      {lessonRows.length === 0 && <Empty>This module has no lessons yet.</Empty>}{/* No lessons: says so. */}
      {lessonRows.map((l, i) => ( // each lesson:
        <Card key={l.id} title={`${i + 1}. ${l.title}`}>{/* a card with its number and heading: */}
          <div className="space-y-4">{/* a block: */}
            {files[i] && isVideo(l.file_path) && ( // a video:
              <video controls preload="metadata" className="w-full rounded-xl bg-black" src={files[i]!}>{/* a video player, */}
                Your browser can&apos;t play this video. <a href={files[i]!}>Download it instead</a>.{/* (with a download link for old browsers) */}
              </video> // End of the player.
            )}{/* End of the video. */}
            {files[i] && !isVideo(l.file_path) && ( // a PDF:
              <p><TextLink href={files[i]!} target="_blank" rel="noopener noreferrer">Open {l.file_name ?? "the PDF"}</TextLink></p> // a link that opens it.
            )}{/* End of the PDF. */}
            {l.body && <TrainingText text={l.body} />}{/* the lesson's text, */}
            {l.link_url && ( // an outside link:
              <p><TextLink href={l.link_url} target="_blank" rel="noopener noreferrer">{l.link_label || l.link_url}</TextLink></p> // opens in a new tab.
            )}{/* End of the link. */}
          </div>{/* End of the block. */}
        </Card> // End of the card.
      ))}{/* End of the lessons. */}

      {me ? ( // If the module is for them:
        <Card title={(questions.data ?? []).length ? "Quiz" : "Finish this module"} description={(questions.data ?? []).length ? "Answer every question. You need them all right, and you can try as many times as you like. Use the handbook and the lessons above." : "Mark it as finished once you've worked through the lessons."}>{/* the quiz card: */}
          <QuizForm moduleId={m.id} questions={(questions.data ?? []) as QuizQuestion[]} done={me.state === "done"} />{/* the quiz. */}
        </Card> // End of the card.
      ) : ( // Otherwise (an admin previewing):
        <Empty>This module isn&apos;t one of yours, so there&apos;s no quiz to do here.</Empty> // says so.
      )}{/* End of the quiz. */}
      <p><BackButton href={`/training?as=${role}`}>Back to all modules</BackButton></p>{/* The same back button at the bottom, so it's there after the quiz. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of TrainingModulePage.
