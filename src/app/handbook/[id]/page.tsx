// Summary: one page of the tutor handbook.
//
import { notFound, redirect } from "next/navigation"; // Shows "not found", or sends the person elsewhere.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { TrainingText } from "@/components/training-text"; // Shows the page's text with simple formatting.
import { Card, TextLink } from "@/components/ui"; // The card and link style.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { plainDate } from "@/lib/billing/money"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { staffRole } from "@/lib/training"; // Works out which dashboard the page belongs to.

// Shows one handbook page.
export default async function HandbookEntryPage({ params, searchParams }: PageProps<"/handbook/[id]">) { // Reads the address's id and settings.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login needed.
  const { id } = await params; // The page's id.
  const { as } = await searchParams; // Which dashboard it was opened from.
  const role = staffRole(as, viewer.roles); // The dashboard to show it in.
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound(); // Odd id: not found.
  const supabase = await createClient(); // Connects to the database.
  const { data: page } = await supabase.from("handbook_pages").select("title, body, urgent, status, updated_at").eq("id", id).maybeSingle(); // Reads the page (only if they can see it).
  if (!page) notFound(); // Can't see it: not found.

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="handbook">{/* the dashboard tabs and menu, with Handbook open: */}
      <p><TextLink href={`/handbook?as=${role}`}>← All handbook pages</TextLink></p>{/* a link back to the list, */}
      {page.status !== "published" && <p className="text-sm text-amber-800">Admin preview: this page is a draft.</p>}{/* a note when an admin previews a draft, */}
      <div className={page.urgent ? "rounded-2xl border-2 border-red-300 bg-red-50 p-1" : ""}>{/* a red frame when pinned: */}
        <Card title={page.title} description={`Last updated ${plainDate(page.updated_at.slice(0, 10))}`}>{/* a card with the heading and when it was updated: */}
          <TrainingText text={page.body} />{/* the page's text. */}
        </Card>{/* End of the card. */}
      </div>{/* End of the frame. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of HandbookEntryPage.
