// Summary: the tutor handbook: CLG's go-to guide for tutors and staff, with
// "Something's happened" pinned at the top and a search box.
//
import Link from "next/link"; // Links between pages.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty, TextLink } from "@/components/ui"; // The card, "nothing yet" note and link style.
import { needsTwoStep, requireViewer } from "@/lib/auth"; // Checks two-step login, and makes sure someone is signed in.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { staffRole } from "@/lib/training"; // Works out which dashboard the page belongs to.

// Shows the handbook's list of pages.
export default async function HandbookPage({ searchParams }: PageProps<"/handbook">) { // Reads the address's settings.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  if (!viewer.roles.includes("tutor") && !viewer.roles.includes("admin")) redirect("/dashboard"); // Not a tutor or admin: to their dashboard.
  if (needsTwoStep(viewer)) redirect("/mfa"); // Two-step login needed.
  const params = await searchParams; // The address's settings.
  const role = staffRole(params.as, viewer.roles); // The dashboard to show it in.
  const q = typeof params.q === "string" ? params.q.trim().slice(0, 100) : ""; // The search words (up to 100 characters).
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase // Reads the pages:
    .from("handbook_pages") // from the handbook,
    .select("id, title, body, urgent") // with their heading, text and pin,
    .eq("status", "published") // published ones only (admins see drafts in the admin page),
    .order("urgent", { ascending: false }) // pinned first,
    .order("position") // then in order,
    .order("title"); // then by heading.
  const pages = (data ?? []) as { id: string; title: string; body: string; urgent: boolean }[]; // The pages.
  const words = q.toLowerCase().split(/\s+/).filter(Boolean); // The search words, one by one.
  const shown = words.length ? pages.filter((p) => words.every((w) => `${p.title} ${p.body}`.toLowerCase().includes(w))) : pages; // Pages containing every word (or all pages).

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="handbook">{/* the dashboard tabs and menu, with Handbook open: */}
      <p className="text-sm text-zinc-600">{/* a short explanation: */}
        Where to go and what to do. If a child is in danger right now, call 000 first, then use the red{" "}{/* 000 first, */}
        <TextLink href="/safety">Child safety</TextLink> button at the top of every page.{/* and the Child safety page. */}
      </p>{/* End of the explanation. */}
      <form className="flex gap-2" role="search">{/* a search box (sends the words in the address): */}
        <input type="hidden" name="as" value={role} />{/* keeps the dashboard (hidden), */}
        <label className="sr-only" htmlFor="handbook-q">Search the handbook</label>{/* a label for screen readers, */}
        <input id="handbook-q" name="q" defaultValue={q} placeholder="Search, e.g. late, concern, sick, privacy" className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" />{/* the box, */}
        <button type="submit" className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white">Search</button>{/* and the button. */}
      </form>{/* End of the search. */}
      {q && <p className="text-sm text-zinc-600">{shown.length} page{shown.length === 1 ? "" : "s"} found for &ldquo;{q}&rdquo;. <TextLink href={`/handbook?as=${role}`}>Show all</TextLink></p>}{/* How many were found, with a way back. */}
      {shown.length === 0 ? ( // Nothing to show:
        <Empty>{pages.length ? "No pages match. Try a different word, or ask CLG." : "The handbook is being written. CLG will let you know when it is ready."}</Empty> // says why.
      ) : ( // Otherwise:
        <Card>{/* a card with the list: */}
          <ul className="divide-y divide-zinc-100">{/* a list with lines between: */}
            {shown.map((p) => ( // each page:
              <li key={p.id} className="py-3">{/* a row: */}
                <Link href={`/handbook/${p.id}?as=${role}`} className={`font-medium underline underline-offset-4 ${p.urgent ? "text-red-800 decoration-red-300" : "text-zinc-900 decoration-zinc-300"}`}>{p.title}</Link>{/* the heading (red if pinned), linking to the page, */}
                <p className="mt-0.5 line-clamp-2 text-sm text-zinc-600">{p.body.replace(/^##\s*/gm, "").replace(/^-\s*/gm, "").slice(0, 220)}</p>{/* and the start of its text. */}
              </li> // End of the row.
            ))}{/* End of the pages. */}
          </ul>{/* End of the list. */}
        </Card> // End of the card.
      )}{/* End of the choice. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of HandbookPage.
