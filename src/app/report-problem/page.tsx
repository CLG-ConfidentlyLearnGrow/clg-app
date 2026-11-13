// Summary: the "Report a problem" page, open to anyone signed in. It has the
// report form (with screenshots) and a list of the person's own reports,
// showing where each is up to and any reply from CLG.
//
import { Card, Empty, Page, Table, TextLink } from "@/components/ui"; // Shared page parts: card, empty note, page frame, table and text link.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { safeNextPath } from "@/lib/forms"; // Keeps a page address inside the app (ignores outside links).
import { PROBLEM_STATUS_LABELS, type ProblemStatus } from "@/lib/problem-reports"; // The words for each status.
import { shortDate } from "@/lib/scheduling"; // Shows a date in a short, friendly way.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { ReportProblemForm } from "./form"; // The report form.

// One of the person's own reports, as the database gives it.
type MyReport = { // The report's details:
  id: string; // its id,
  created_at: string; // when it was sent,
  what_happened: string; // what they wrote,
  status: ProblemStatus; // where it's up to,
  reply: string | null; // CLG's reply (if any),
  screenshots: number; // how many screenshots it has.
}; // End of the shape.

// Shows the page. "from" in the address is the page the person came from.
export default async function ReportProblemPage({ searchParams }: PageProps<"/report-problem">) {
  await requireViewer(); // Makes sure someone is signed in.
  const params = await searchParams; // Reads the address settings.
  const from = typeof params.from === "string" ? safeNextPath(params.from, "") : ""; // The page they came from (only if it's inside the app).
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.rpc("my_problem_reports"); // Reads their own reports (never reviewers' notes).
  const mine = (data ?? []) as MyReport[]; // Their reports (or none).

  return ( // Shows:
    <Page // the page frame:
      title="Report a problem" // the heading,
      intro="Something not working, or confusing? Tell us here. A CLG reviewer reads every report and replies on this page." // the sentence under it.
    >{/* (end of the frame's settings) */}
      <Card // the form card:
        title="What's the problem?" // its title,
        description={<>For a worry about a child&apos;s safety, don&apos;t use this form: use <TextLink href="/safety">Child safety</TextLink> in the top bar instead.</>} // a note sending safety concerns to the Child safety page.
      >{/* (end of the card's settings) */}
        <ReportProblemForm page={from} />{/* the form, knowing which page they came from. */}
      </Card>{/* End of the form card. */}

      <Card title="Your reports" description="Where each report is up to. Reports are kept for 2 years after they're closed; screenshots for 90 days.">{/* The list card: */}
        {mine.length === 0 ? ( // No reports yet:
          <Empty>You haven&apos;t reported any problems.</Empty> // says so.
        ) : ( // Otherwise:
          <Table headings={["Sent", "Problem", "Status", "Reply from CLG"]}>{/* a table: */}
            {mine.map((r) => ( // for each report:
              <tr key={r.id}>{/* one row: */}
                <td className="whitespace-nowrap">{shortDate(r.created_at)}</td>{/* when it was sent, */}
                <td>{/* what they wrote: */}
                  <p className="line-clamp-3 whitespace-pre-line">{r.what_happened}</p>{/* (up to three lines) */}
                  {r.screenshots > 0 && <p className="mt-1 text-xs text-zinc-500">{r.screenshots} screenshot{r.screenshots === 1 ? "" : "s"}</p>}{/* and how many screenshots, */}
                </td>{/* (end of the cell) */}
                <td className="whitespace-nowrap">{PROBLEM_STATUS_LABELS[r.status]}</td>{/* where it's up to, */}
                <td className="whitespace-pre-line">{r.reply ?? "No reply yet"}</td>{/* and the reply. */}
              </tr> // End of the row.
            ))}{/* End of the reports loop. */}
          </Table> // End of the table.
        )}{/* End of the choice. */}
      </Card>{/* End of the list card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of ReportProblemPage.
