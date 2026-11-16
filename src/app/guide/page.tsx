// Summary: the App guide page: a simple, step-by-step "how to use the app"
// handbook for the dashboard it's opened from (Carla, 16 Nov 2026). Parents
// see the parent guide, students the student guide, tutors the tutor guide,
// and admins the guide for their own admin level. A search box finds the
// steps for a task, and admins who help families and tutors can open those
// guides too (see guidesFor in src/lib/app-guides). Nobody can open a guide
// that isn't theirs by changing the address. At the top, a button replays
// the first-time app tour for that guide (Carla, 16 Nov 2026).
//
import Link from "next/link"; // Links between pages.
import { redirect } from "next/navigation"; // Sends the person to another page.
import { AppGuideView } from "@/components/app-guide-view"; // Shows a guide's contents, parts and steps.
import { AppTour } from "@/components/app-tour"; // The app tour pop-up, opened with a button here.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { TextLink } from "@/components/ui"; // The link style.
import { getAdminLevel, needsTwoStep, requireViewer, type Role } from "@/lib/auth"; // The admin level reader, two-step check, signed-in person, and role type.
import { GUIDE_NAMES, getGuide, guidesFor, isGuideId, ownGuide } from "@/lib/app-guides"; // The guides, who may open which, and their names.
import { TOUR_VERSIONS, getTour } from "@/lib/app-tours"; // Each tour's edition, and the tours (one per guide).
import { ROLE_ORDER } from "@/lib/roles"; // The order of the dashboards.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person (for their tour progress).

// Gives the first value of an address setting, as text.
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? ""; // The first value, or blank.

// Shows the App guide.
export default async function GuidePage({ searchParams }: PageProps<"/guide">) { // Reads the address's settings.
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const params = await searchParams; // The address's settings.
  const asked = one(params.as); // The dashboard it was opened from.
  const role: Role | undefined = viewer.roles.includes(asked as Role) ? (asked as Role) : ROLE_ORDER.find((r) => viewer.roles.includes(r)); // That dashboard if they have it, otherwise their first one.
  if (!role) redirect("/dashboard"); // No dashboard at all: to the welcome page.
  if ((role === "admin" || role === "tutor") && needsTwoStep(viewer)) redirect("/mfa"); // Staff dashboards need two-step login first, like every other staff page.
  const level = viewer.roles.includes("admin") ? await getAdminLevel() : null; // Their admin level, if they're an admin.
  const allowed = guidesFor(viewer.roles, level); // Every guide they may open.
  const wanted = one(params.g); // The guide asked for in the address, if any.
  const own = ownGuide(role, level); // The guide that belongs to this dashboard.
  const id = isGuideId(wanted) && allowed.includes(wanted) ? wanted : own && allowed.includes(own) ? own : allowed[0]; // The guide asked for (if allowed), else this dashboard's, else their first.
  if (!id) redirect("/dashboard"); // No guide they may open: back to their dashboard.
  const guide = getGuide(id); // The guide, ready to show.
  const q = one(params.q).trim().slice(0, 100); // The search words (up to 100 characters).
  const others = allowed.filter((g) => g !== id); // The other guides they may open.
  const here = (g: string) => `/guide?as=${role}&g=${g}`; // The address of a guide, in this dashboard.
  const ownTour = id === own; // Whether this guide's tour is their own dashboard's (only then is progress saved).
  const { data: progress } = ownTour // Their saved tour progress, for their own tour only:
    ? await (await createClient()).from("app_tour_progress").select("version, step, finished").eq("tour", id).maybeSingle() // read from the database (only their own row),
    : { data: null }; // or nothing for someone else's tour.
  const carryOn = progress && !progress.finished && Number(progress.version) === TOUR_VERSIONS[id] && Number(progress.step) > 0 ? Number(progress.step) : 0; // The step to carry on from, if they stopped part-way through this edition.

  return ( // Shows:
    <DashboardFrame role={role} roles={viewer.roles} current="guide">{/* the dashboard tabs and menu, with App guide open: */}
      <div>{/* the guide's heading: */}
        <h2 className="text-xl font-semibold text-zinc-900">{guide.title}</h2>{/* its title, */}
        <p className="mt-1 text-sm text-zinc-600">{guide.who} Open a task to see its steps.</p>{/* who it's for, and how to use it. */}
      </div>{/* End of the heading. */}
      <form className="flex gap-2" role="search">{/* a search box (sends the words in the address): */}
        <input type="hidden" name="as" value={role} />{/* keeps the dashboard (hidden), */}
        <input type="hidden" name="g" value={id} />{/* keeps the guide (hidden), */}
        <label className="sr-only" htmlFor="guide-q">Search this guide</label>{/* a label for screen readers, */}
        <input id="guide-q" name="q" defaultValue={q} placeholder="Search, e.g. cancel, invoice, password" className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" />{/* the box, */}
        <button type="submit" className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white">Search</button>{/* and the button. */}
      </form>{/* End of the search. */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-zinc-200 bg-white p-5 text-sm shadow-sm">{/* a card for the app tour: */}
        <div>{/* its words: */}
          <h2 className="font-semibold text-zinc-900">App tour</h2>{/* the heading, */}
          <p className="mt-1 text-zinc-600">{ownTour ? "A few minutes on the main parts of your dashboard, and why each one matters." : `The first-time tour for ${GUIDE_NAMES[id]}, so you can talk people through it.`}</p>{/* what it is (for their own tour, or someone else's). */}
        </div>{/* End of the words. */}
        <AppTour tour={getTour(id)} role={role} save={ownTour} startAt={carryOn} buttonLabel={carryOn ? `Carry on the tour (step ${carryOn + 1})` : ownTour ? (progress ? "Take the tour again" : "Take the tour") : "See their tour"} />{/* the button that opens the tour (where they left off, if they stopped part-way). */}
      </div>{/* End of the tour card. */}
      {q && <p className="text-sm"><TextLink href={here(id)}>Show the whole guide</TextLink></p>}{/* While searching, a way back to the whole guide. */}
      <AppGuideView guide={guide} query={q} />{/* The guide itself (or the matching tasks). */}
      {others.length > 0 && ( // If they may open other guides:
        <div className="rounded-2xl border border-zinc-200 bg-white p-5 text-sm shadow-sm">{/* a small card: */}
          <h2 className="font-semibold text-zinc-900">Other guides you can open</h2>{/* its heading, */}
          <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1">{/* the guides, in a row: */}
            {others.map((g) => ( // each guide:
              <li key={g}><Link href={here(g)} className="text-teal-800 underline underline-offset-4">{GUIDE_NAMES[g]}</Link></li> // a link to it.
            ))}{/* End of the guides. */}
          </ul>{/* End of the list. */}
        </div> // End of the card.
      )}{/* End of the other guides. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of GuidePage.
