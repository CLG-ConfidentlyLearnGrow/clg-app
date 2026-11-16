// Summary: the Training page for tutors and admin staff: their CLG
// certification, every module for them (starting course, refreshers and
// ongoing learning) with where they're up to, certificates, and a link to
// the handbook.
//
import Link from "next/link"; // Links between pages.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, TextLink } from "@/components/ui"; // The card, "nothing yet" note and link style.
import { needsTwoStep, requireViewer, type Role } from "@/lib/auth"; // Checks two-step login, makes sure someone is signed in, and the role type.
import { staffRole } from "@/lib/training"; // Works out which dashboard the page belongs to.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { CERT_NAMES, STAGES, STAGE_NAMES, STATE_NAMES, STATE_STYLES, hrs, timeText, type Certification, type MyModule } from "@/lib/training"; // Training words, colours and shapes.

// Shows the Training page.
export default async function TrainingPage({ searchParams }: PageProps<"/training">) { // Reads the address's settings.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login needed for training records.
  const { as } = await searchParams; // Which dashboard it was opened from.
  const role = staffRole(as, viewer.roles); // The dashboard to show it in.
  const supabase = await createClient(); // Connects to the database.
  const [mods, cert, urgent] = await Promise.all([ // Reads three things at once:
    supabase.rpc("training_my_modules"), // their modules and where they're up to,
    supabase.rpc("training_certification").maybeSingle<Certification>(), // their certification,
    supabase.from("handbook_pages").select("id, title").eq("status", "published").eq("urgent", true).order("position").limit(1).maybeSingle(), // and the pinned handbook page.
  ]); // End of the reads.
  const modules = (mods.data ?? []) as MyModule[]; // Their modules.
  const c = cert.data; // Their certification (if read).
  const toDo = modules.filter((m) => m.state === "to_do" || m.state === "overdue" || m.state === "renew_soon"); // Modules needing attention.
  const quarterPct = c && c.target_minutes > 0 ? Math.min(100, Math.round((c.quarter_minutes / c.target_minutes) * 100)) : 0; // How far through this quarter's hours (as a percentage).

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="training">{/* the dashboard tabs and menu, with Training open: */}
      <p className="text-sm text-zinc-600">{/* a short explanation: */}
        CLG training is paid work time. Compulsory modules are paid automatically for their set time once you finish them.{" "}{/* training is paid, */}
        If something has happened and you need to know what to do, go to the{" "}<TextLink href={`/handbook?as=${role}`}>tutor handbook</TextLink>.{/* and where the handbook is. */}
      </p>{/* End of the explanation. */}
      {urgent.data && ( // If there's a pinned handbook page:
        <Link href={`/handbook/${urgent.data.id}?as=${role}`} className="block rounded-2xl border-2 border-red-300 bg-red-50 px-5 py-4 text-red-900 hover:bg-red-100">{/* a red box linking to it: */}
          <span className="block font-semibold">{urgent.data.title}</span>{/* its title, */}
          <span className="text-sm">Open the handbook page for what to do, step by step.</span>{/* and what it's for. */}
        </Link> // End of the box.
      )}{/* End of the pinned page. */}

      <Card title="Your CLG certification">{/* the certification card: */}
        {c ? ( // if it was read:
          <div className="space-y-3 text-sm">{/* a block: */}
            <p>{/* the status: */}
              <span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${c.state === "certified" ? "bg-emerald-50 text-emerald-800" : c.state === "lapsed" ? "bg-red-50 text-red-800" : "bg-sky-50 text-sky-800"}`}>{CERT_NAMES[c.state]}</span>{/* as a coloured badge, */}
              {c.certified_since && <span className="ml-2 text-zinc-600">since {plainDate(c.certified_since)}</span>}{/* and since when (if certified). */}
            </p>{/* End of the status. */}
            {c.state === "in_training" ? ( // still in training:
              <p className="text-zinc-700">Finish your compulsory modules below to become CLG certified.</p> // what to do,
            ) : ( // otherwise:
              <>{/* (a group:) */}
                <p className="text-zinc-700">{/* this quarter's hours: */}
                  This quarter: {hrs(c.quarter_minutes)} of {hrs(c.target_minutes)} done, by {plainDate(c.quarter_ends)}. Safety modules do not count towards these hours.{/* done, needed and by when, */}
                </p>{/* End of the hours line. */}
                <div className="h-2 w-full overflow-hidden rounded-full bg-zinc-100" aria-hidden>{/* a progress bar: */}
                  <div className="h-2 rounded-full bg-brand" style={{ width: `${quarterPct}%` }} />{/* filled to the percentage done. */}
                </div>{/* End of the bar. */}
                {c.state === "lapsed" && <p className="text-red-800">Last quarter ended short of the hours. Finish {hrs(Math.max(0, c.target_minutes - c.quarter_minutes))} more this quarter to be certified again.</p>}{/* what to do if lapsed, */}
                {c.state === "certified" && <p><TextLink href="/training/certificate/certified">Download your CLG certified certificate</TextLink></p>}{/* the certificate, if certified. */}
              </> // End of the group.
            )}{/* End of the choice. */}
          </div> // End of the block.
        ) : ( // not read:
          <Empty>Your certification could not be read just now.</Empty> // says so.
        )}{/* End of the choice. */}
      </Card>{/* End of the certification card. */}

      {toDo.length > 0 && ( // If any modules need attention:
        <Card title="To do now">{/* a card listing them: */}
          <ModuleList modules={toDo} role={role} />{/* the list. */}
        </Card> // End of the card.
      )}{/* End of the to-do card. */}

      {STAGES.map((stage) => { // For each stage (starting course, refreshers, ongoing):
        const list = modules.filter((m) => m.stage === stage); // its modules,
        if (list.length === 0) return null; // none: nothing shown.
        return ( // shows:
          <Card key={stage} title={STAGE_NAMES[stage]} collapsible defaultOpen={stage === "starting"}>{/* a fold-up card (the starting course open): */}
            <ModuleList modules={list} role={role} />{/* the list. */}
          </Card> // End of the card.
        ); // End of what's shown.
      })}{/* End of the stages. */}
      {modules.length === 0 && <Empty>There is no training for you yet. CLG will let you know when modules are ready.</Empty>}{/* Nothing at all: says so. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of TrainingPage.

// A list of modules with where the person is up to.
function ModuleList({ modules, role }: { modules: MyModule[]; role: Role }) { // Takes the modules and the dashboard.
  return ( // Shows:
    <ul className="divide-y divide-zinc-100">{/* a list with lines between: */}
      {modules.map((m) => ( // for each module:
        <li key={m.module_id} className="flex flex-wrap items-start justify-between gap-3 py-3">{/* a row: */}
          <div className="min-w-0 flex-1">{/* the left side: */}
            <Link href={`/training/${m.module_id}?as=${role}`} className="font-medium text-zinc-900 underline decoration-zinc-300 underline-offset-4 hover:decoration-zinc-700">{m.title}</Link>{/* the name, linking to the module, */}
            <p className="mt-0.5 text-xs text-zinc-600">{/* the details: */}
              {timeText(m.minutes)}{/* its time, */}
              {m.required ? " · Compulsory" : ""}{/* compulsory or not, */}
              {m.holds_matching ? " · Needed before new students" : ""}{/* whether new matches wait for it, */}
              {m.renew_months ? ` · Redo every ${m.renew_months} months` : ""}{/* how often it's redone, */}
            </p>{/* End of the details. */}
            {m.summary && <p className="mt-1 text-sm text-zinc-700">{m.summary}</p>}{/* the summary, if any. */}
          </div>{/* End of the left side. */}
          <div className="text-right text-xs">{/* the right side: */}
            <span className={`inline-block rounded-full px-2.5 py-1 font-semibold ${STATE_STYLES[m.state]}`}>{STATE_NAMES[m.state]}</span>{/* where they're up to, */}
            {(m.state === "to_do" || m.state === "overdue") && m.due_on && <p className="mt-1 text-zinc-600">Due {plainDate(m.due_on)}</p>}{/* the due date, */}
            {m.state === "renew_soon" && m.expires_on && <p className="mt-1 text-zinc-600">Redo by {plainDate(m.expires_on)}</p>}{/* the redo date, */}
            {m.completion_id && m.completed_on && (m.state === "done" || m.state === "renew_soon") && ( // when finished:
              <p className="mt-1"><TextLink href={`/training/certificate/${m.completion_id}`}>Certificate</TextLink></p> // the certificate link.
            )}{/* End of the certificate. */}
          </div>{/* End of the right side. */}
        </li> // End of the row.
      ))}{/* End of the modules. */}
    </ul> // End of the list.
  ); // End of what's shown.
} // End of ModuleList.
