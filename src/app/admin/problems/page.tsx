// Summary: the Problem reports page for reviewers: the queue of reports
// (filtered by status), one report in full with its screenshots and the
// reviewer's form, and (owner only) the reviewer list setting.
//
import { addProblemReviewer, deleteProblemReport, removeProblemReviewer } from "@/app/actions/problem-reports"; // The actions for the reviewer list and deleting a report.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, SubHeading, Table, TextLink } from "@/components/ui"; // Shared page parts: card, empty note, small heading, table and text link.
import { ADMIN_LEVEL_NAMES, ANY_ADMIN, requireAdminLevel, type AdminLevel } from "@/lib/auth"; // Admin level names, the "any admin" group, and the admin check.
import { PROBLEM_PRIORITY_LABELS, PROBLEM_STATUSES, PROBLEM_STATUS_LABELS, type ProblemReport, type ProblemStatus } from "@/lib/problem-reports"; // Status and priority words, and the report type.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { SendToGitHubForm, UpdateProblemForm } from "./forms"; // The reviewer's forms.

// The filters along the top of the queue: open reports (the default), each
// status on its own, or everything.
const FILTERS = [ // Each filter's id, words, and the statuses it shows:
  { id: "open", label: "Open", statuses: ["new", "checking", "approved"] }, // still needing work,
  ...PROBLEM_STATUSES.map((s) => ({ id: s, label: PROBLEM_STATUS_LABELS[s], statuses: [s] })), // one per status,
  { id: "all", label: "All", statuses: [...PROBLEM_STATUSES] }, // and everything.
] as { id: string; label: string; statuses: ProblemStatus[] }[]; // (the shape of each filter)

// A small coloured label for a priority (urgent stands out).
function PriorityTag({ priority }: { priority: ProblemReport["priority"] }) {
  if (priority === "normal") return null; // Normal needs no label.
  const look = priority === "urgent" ? "bg-red-100 text-red-800" : "bg-zinc-100 text-zinc-600"; // Red for urgent, grey for low.
  return <span className={`ml-2 rounded-full px-2 py-0.5 text-xs ${look}`}>{priority === "urgent" ? "Urgent" : "Low"}</span>; // The label.
} // End of PriorityTag.

// Shows the page (the owner, and admins on the reviewer list).
export default async function ProblemReportsPage({ searchParams }: PageProps<"/admin/problems">) {
  const viewer = await requireAdminLevel(ANY_ADMIN); // Must be an admin with two-step login (any level).
  const params = await searchParams; // Reads the address settings.
  const supabase = await createClient(); // Connects to the database.
  const isOwner = viewer.level === "owner"; // Whether this is the owner (always a reviewer, and chooses the list).
  const { count: onList } = await supabase.from("problem_reviewers").select("account_id", { count: "exact", head: true }).eq("account_id", viewer.id); // Whether they're on the list (only reviewers can read it).
  const isReviewer = isOwner || (onList ?? 0) > 0; // Allowed to see reports.

  const section = params.section === "reviewers" && isOwner ? "reviewers" : "queue"; // Which section is open (the reviewer list is owner only).
  const filter = FILTERS.find((f) => f.id === params.status) ?? FILTERS[0]; // The filter chosen (open reports by default).
  const id = typeof params.id === "string" && /^[0-9a-f-]{36}$/.test(params.id) ? params.id : null; // The report to open, if any.

  const items = [ // This page's sections under its tab:
    { id: "queue", label: "Reports", href: "/admin/problems" }, // the queue,
    ...(isOwner ? [{ id: "reviewers", label: "Who checks reports", href: "/admin/problems?section=reviewers" }] : []), // and the reviewer list (owner only).
  ]; // End of the sections.

  // Not on the list: explains, instead of showing an empty queue.
  if (!isReviewer) { // Not a reviewer:
    return ( // shows:
      <DashboardFrame role="admin" roles={viewer.roles} current="problems">{/* the dashboard frame, */}
        <Card title="Problem reports">{/* a card: */}
          <p className="text-sm text-zinc-700">Only the owner and the admins they choose can check problem reports. Ask the owner if you should be on the list.</p>{/* explaining who can. */}
        </Card>{/* End of the card. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the not-a-reviewer case.

  // The owner's reviewer list.
  if (section === "reviewers") { // The reviewer list section:
    const { data } = await supabase.rpc("problem_reviewer_choices"); // every admin, and whether they're on the list,
    const admins = (data ?? []) as { account_id: string; full_name: string; level: AdminLevel | null; on_list: boolean }[]; // (or none).
    return ( // shows:
      <DashboardFrame role="admin" roles={viewer.roles} current="problems" sub="reviewers" items={items}>{/* the dashboard frame, */}
        <Card // a card:
          title="Who checks problem reports" // its title,
          description="You always see every report. Add the admins who should also check them. Only admins can be added, because screenshots may show children's details, and they need two-step login to see reports." // explaining the rules.
        >{/* (end of the card's settings) */}
          {admins.filter((a) => a.level !== "owner").length === 0 ? ( // No other admins:
            <Empty>There are no other admins yet. Reports come to you.</Empty> // says reports come to the owner.
          ) : ( // Otherwise:
            <Table headings={["Admin", "Level", "Checks reports", ""]}>{/* a table: */}
              {admins.filter((a) => a.level !== "owner").map((a) => ( // for each admin other than the owner:
                <tr key={a.account_id}>{/* a row: */}
                  <td>{a.full_name}</td>{/* their name, */}
                  <td>{a.level ? ADMIN_LEVEL_NAMES[a.level] : "Not set"}</td>{/* their level, */}
                  <td>{a.on_list ? "Yes" : "No"}</td>{/* whether they check reports, */}
                  <td className="text-right">{/* and a button to change it: */}
                    <form action={a.on_list ? removeProblemReviewer : addProblemReviewer}>{/* a form that adds or removes them: */}
                      <input type="hidden" name="account_id" value={a.account_id} />{/* their id, hidden, */}
                      <button type="submit" className={`text-sm hover:underline ${a.on_list ? "text-red-700" : "text-teal-800"}`}>{/* the button: */}
                        {a.on_list ? "Remove" : "Add"}{/* "Remove" or "Add". */}
                      </button>{/* End of the button. */}
                    </form>{/* End of the form. */}
                  </td>{/* (end of the cell) */}
                </tr> // End of the row.
              ))}{/* End of the admins loop. */}
            </Table> // End of the table.
          )}{/* End of the choice. */}
        </Card>{/* End of the card. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the reviewer list section.

  // One report in full.
  if (id) { // A report is open:
    const [{ data: reportData }, { data: shotData }] = await Promise.all([ // reads two things at once:
      supabase.from("problem_reports").select("*").eq("id", id).maybeSingle(), // the report,
      supabase.from("problem_report_screenshots").select("id").eq("report_id", id).order("added_at"), // and its screenshots, in the order added.
    ]); // End of the reads.
    const report = reportData as ProblemReport | null; // The report (or nothing if not found).
    const shots = (shotData ?? []) as { id: string }[]; // Its screenshots.
    const githubReady = Boolean(process.env.GITHUB_ISSUES_TOKEN && process.env.GITHUB_ISSUES_REPO); // Whether the GitHub settings are in place.
    return ( // shows:
      <DashboardFrame role="admin" roles={viewer.roles} current="problems" sub="queue" items={items}>{/* the dashboard frame, */}
        {!report ? ( // Not found:
          <Card title="Report not found">{/* a card saying so: */}
            <p className="text-sm">It may have been deleted. <TextLink href="/admin/problems">Back to all reports</TextLink></p>{/* with a link back. */}
          </Card> // End of the card.
        ) : ( // Found:
          <>{/* (a group:) */}
            <Card title={`Reported by ${report.reporter_name}`} description={`Sent ${shortDate(report.created_at)} · ${PROBLEM_STATUS_LABELS[report.status]}`}>{/* the report card: */}
              <SubHeading>What went wrong</SubHeading>{/* a heading, */}
              <p className="text-sm whitespace-pre-line">{report.what_happened}</p>{/* what they wrote, */}
              {report.trying_to && ( // what they were trying to do, if given:
                <>{/* (a group:) */}
                  <SubHeading>What they were trying to do</SubHeading>{/* a heading, */}
                  <p className="text-sm whitespace-pre-line">{report.trying_to}</p>{/* and their words. */}
                </> // End of the group.
              )}{/* End of that part. */}
              <SubHeading>Where</SubHeading>{/* a heading, */}
              <p className="text-sm break-all">{report.page ?? "Page not known"}</p>{/* the page, */}
              {report.device && <p className="mt-1 text-xs break-all text-zinc-500">{report.device}</p>}{/* and their browser, small. */}
              <SubHeading>Screenshots</SubHeading>{/* a heading, */}
              {shots.length === 0 ? ( // No screenshots:
                <Empty>No screenshots{report.status === "fixed" || report.status === "closed" ? " (they're removed 90 days after a report is closed)" : ""}.</Empty> // says so (and why, if closed).
              ) : ( // Otherwise:
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">{/* a grid of screenshots: */}
                  {shots.map((s, i) => ( // for each one:
                    <a key={s.id} href={`/problem-screenshots/${s.id}`} target="_blank" rel="noreferrer" className="block overflow-hidden rounded-lg border border-zinc-200">{/* a link that opens it full size: */}
                      {/* eslint-disable-next-line @next/next/no-img-element -- a private screenshot behind a one-minute link; the Next.js image tool would keep a copy */}
                      <img src={`/problem-screenshots/${s.id}`} alt={`Screenshot ${i + 1}`} className="max-h-80 w-full bg-zinc-50 object-contain" />{/* the picture. */}
                    </a> // End of the link.
                  ))}{/* End of the screenshots loop. */}
                </div> // End of the grid.
              )}{/* End of the screenshots. */}
            </Card>{/* End of the report card. */}

            <Card title="Check and reply" description="A person checks every report. Nothing is changed in the app automatically.">{/* the reviewer's card: */}
              <UpdateProblemForm report={report} />{/* the form. */}
            </Card>{/* End of the reviewer's card. */}

            {isOwner && ( // Owner only: GitHub and delete.
              <Card title="Send to the developer" description="Turns an approved report into a GitHub issue, so it can be fixed (for example by Claude) and checked before it goes live.">{/* the GitHub card: */}
                {report.github_issue_url ? ( // Already sent:
                  <p className="text-sm">On GitHub: <a href={report.github_issue_url} target="_blank" rel="noreferrer" className="font-medium text-teal-700 underline">{report.github_issue_url}</a></p> // the issue's link.
                ) : githubReady ? ( // Ready to send:
                  <SendToGitHubForm id={report.id} /> // the send button.
                ) : ( // Not set up:
                  <p className="text-sm text-zinc-600">GitHub isn&apos;t set up yet. Add GITHUB_ISSUES_TOKEN and GITHUB_ISSUES_REPO in Vercel to turn this on (see the admin guide).</p> // says what's needed.
                )}{/* End of the choice. */}
                <form action={deleteProblemReport} className="mt-6 border-t border-zinc-100 pt-4">{/* the delete form: */}
                  <input type="hidden" name="id" value={report.id} />{/* the report's id, hidden, */}
                  <button type="submit" className="text-sm text-red-700 hover:underline">Delete this report and its screenshots</button>{/* the delete button, */}
                  <p className="mt-1 text-xs text-zinc-500">For example, if it holds details that shouldn&apos;t have been shared. This can&apos;t be undone.</p>{/* and when to use it. */}
                </form>{/* End of the delete form. */}
              </Card> // End of the GitHub card.
            )}{/* End of the owner-only part. */}
            <p><TextLink href="/admin/problems">Back to all reports</TextLink></p>{/* A link back to the queue. */}
          </> // End of the group.
        )}{/* End of the choice. */}
      </DashboardFrame> // End of the frame.
    ); // End of what's shown.
  } // End of the open report.

  // The queue.
  const { data } = await supabase // Reads the reports:
    .from("problem_reports") // from the reports table,
    .select("id, reporter_name, what_happened, status, priority, created_at, github_issue_url") // with what the list needs,
    .in("status", filter.statuses) // in the chosen statuses,
    .order("created_at", { ascending: false }) // newest first,
    .limit(200); // at most 200.
  const reports = (data ?? []) as Pick<ProblemReport, "id" | "reporter_name" | "what_happened" | "status" | "priority" | "created_at" | "github_issue_url">[]; // The reports listed.
  const ordered = [...reports].sort((a, b) => Number(b.priority === "urgent") - Number(a.priority === "urgent")); // Urgent ones first (otherwise newest first).

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="problems" sub="queue" items={items}>{/* the dashboard frame, */}
      <Card title="Problem reports" description="Reports anyone using the app has sent. Check each one, reply, and mark where it's up to.">{/* the queue card: */}
        <div className="mb-4 flex flex-wrap gap-2">{/* the filter buttons (wrap on small screens): */}
          {FILTERS.map((f) => ( // for each filter:
            <TextLink // a link:
              key={f.id} // (its id)
              href={f.id === "open" ? "/admin/problems" : `/admin/problems?status=${f.id}`} // to the queue with that filter,
              aria-current={f.id === filter.id ? "page" : undefined} // marked as current when chosen,
              className={`rounded-full border px-3 py-1 text-sm ${f.id === filter.id ? "border-brand bg-brand text-white" : "border-zinc-300 text-zinc-700 hover:border-brand"}`} // filled in when chosen.
            >{/* (end of the link's settings) */}
              {f.label}{/* its words. */}
            </TextLink> // End of the link.
          ))}{/* End of the filters loop. */}
        </div>{/* End of the filters. */}
        {ordered.length === 0 ? ( // None:
          <Empty>No reports here.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Sent", "From", "Problem", "Status", ""]}>{/* a table: */}
            {ordered.map((r) => ( // for each report:
              <tr key={r.id}>{/* a row: */}
                <td className="whitespace-nowrap">{shortDate(r.created_at)}</td>{/* when it was sent, */}
                <td>{r.reporter_name}</td>{/* who sent it, */}
                <td><p className="line-clamp-2">{r.what_happened}</p></td>{/* the start of what they wrote, */}
                <td className="whitespace-nowrap">{PROBLEM_STATUS_LABELS[r.status]}<PriorityTag priority={r.priority} />{r.github_issue_url ? <span className="ml-2 text-xs text-zinc-500">GitHub</span> : null}</td>{/* where it's up to, its priority, and whether it's on GitHub, */}
                <td className="text-right"><TextLink href={`/admin/problems?id=${r.id}`}>Open</TextLink></td>{/* and a link to open it. */}
              </tr> // End of the row.
            ))}{/* End of the reports loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
        <p className="mt-4 text-xs text-zinc-500">Priority: {PROBLEM_PRIORITY_LABELS.urgent}. Urgent reports are listed first.</p>{/* A note on urgent reports. */}
      </Card>{/* End of the queue card. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of ProblemReportsPage.
