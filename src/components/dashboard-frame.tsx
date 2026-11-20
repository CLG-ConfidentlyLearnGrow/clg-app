// Summary: the frame for any page that belongs to a dashboard: the dashboard
// tabs across the top, and that dashboard's side menu (with Sessions,
// Billing and the rest as tabs), around the page's own contents. It also
// shows the "What's new" pop-up when that dashboard has updates the person
// hasn't seen yet (Carla, 15 Nov 2026), and the first-time app tour the
// first time someone opens that dashboard (Carla, 16 Nov 2026). The tour
// comes first: while it's showing, "What's new" waits for the next visit, so
// two pop-ups never open at once. Check-ins after a new match show as cards
// above the page's contents while one is waiting (Carla, 16 Nov 2026), and
// so does a staff member's employment contract while it waits to be signed
// (Carla, 17 Nov 2026). Every page except the App guide itself has a "Show
// me how" button by its heading, which opens the App guide steps for that
// page as a refresher (Carla, 18 Nov 2026). A small note invites people to
// turn on pop-up notifications on the device they are using, until they
// turn them on or choose "Not now" (Carla, 18 Nov 2026).
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { SectionShell, type Section } from "@/components/section-shell"; // The page frame with a side menu, and one menu item's shape.
import { getDashboardMenu } from "@/lib/dashboard-menu"; // Builds a dashboard's side menu.
import { ROLE_PAGES, ROLE_TABS } from "@/lib/roles"; // Each dashboard's main working page, and its name and address.
import { WhatsNew } from "@/components/whats-new"; // The "What's new" pop-up for this dashboard.
import { firstTimeTour } from "@/components/first-time-tour"; // The first-time app tour for this dashboard, if it should open.
import { CheckInPrompts } from "@/components/check-in-prompts"; // The check-in cards after a new match (Carla, 16 Nov 2026).
import { ContractPrompt } from "@/components/contract-prompt"; // The "contract ready to sign" card for staff (Carla, 17 Nov 2026).
import { PushPrompt } from "@/components/push-settings"; // The "turn on pop-up notifications" note (Carla, 18 Nov 2026).
import { PageHelp } from "@/components/page-help"; // The "Show me how" button and pop-up (Carla, 18 Nov 2026).
import { GuideParts } from "@/components/app-guide-view"; // Shows a few App guide parts, for that pop-up.
import { getAdminLevel, type Role } from "@/lib/auth"; // Reads the signed-in admin's level (to pick their guide), and the type for a role.
import { ownGuide } from "@/lib/app-guides"; // Picks the App guide for a dashboard.
import { pageHelp } from "@/lib/app-guides/page-help"; // Picks the App guide steps for a page.
import { getTour } from "@/lib/app-tours"; // The app tours (one per guide), to take again from the pop-up.

// Shows the dashboard tabs and side menu around a page. "current" is the
// menu item that's open; "items" are smaller sections to show under it
// (e.g. Sessions: Overview, Bookings), with "sub" the one that's open.
export async function DashboardFrame({
  role, // Which dashboard this page belongs to.
  roles, // All of the person's roles (for the tabs and numbers).
  current, // The open menu item's id.
  sub, // The open smaller section's id, if any.
  items, // The smaller sections under the open item, if any.
  children, // The page's own contents.
}: { // The settings' types:
  role: Role; // dashboard is a role,
  roles: Role[]; // roles is a list,
  current: string; // open item is text,
  sub?: string; // open smaller section is optional text,
  items?: Section[]; // smaller sections are an optional list,
  children: ReactNode; // contents can be anything shown.
}) { // End of the settings.
  const menu = await getDashboardMenu(role, roles); // The dashboard's side menu.
  const sections = menu.map((s) => (s.id === current && items ? { ...s, items, countsInside: true } : s)); // The open item gets the page's own smaller sections, with their up-to-date numbers (which then carry all of its numbers).
  const tour = await firstTimeTour(role); // The first-time tour, if this dashboard's tour hasn't been seen yet (otherwise nothing).
  const guideId = ownGuide(role, role === "admin" ? await getAdminLevel() : null); // This dashboard's App guide (none for an admin without a level).
  const open = sections.find((s) => s.id === current); // The open menu item (for its name and the guide's address).
  const help = guideId && current !== "guide" ? pageHelp(guideId, current) : null; // The guide steps for this page (not on the App guide page itself, which already shows them all).
  const guideHref = sections.find((s) => s.id === "guide")?.href ?? `/guide?as=${role}`; // The address of the whole App guide for this dashboard.
  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={roles} active={role} />{/* the dashboard tabs, with this one open, */}
      {tour ?? <WhatsNew role={role} />}{/* the first-time tour if it's due, otherwise the "What's new" pop-up (if this dashboard has unseen updates), */}
      <SectionShell // the page frame:
        basePath={ROLE_PAGES[role]} // at the dashboard's main working page (each menu item has its own address anyway),
        label={ROLE_TABS[role].label} // labelled with the dashboard's name,
        role={role} // in the dashboard's colours,
        section={current} // on the open item,
        subSection={sub} // and the open smaller section,
        sections={sections} // with the dashboard's menu,
        help={help && guideId ? ( // and, where there is help for this page, the "Show me how" button:
          <PageHelp role={role} page={open?.label ?? ROLE_TABS[role].label} guideHref={guideHref} tour={getTour(guideId)}>{/* named for the page, linking to the whole guide, with the tour to take again, */}
            <GuideParts parts={help.parts} />{/* showing the guide steps for this page. */}
          </PageHelp> // End of the button.
        ) : undefined} // (no button where there is no guide)
      >{/* (end of the frame's settings) */}
        {current !== "contract" && <ContractPrompt role={role} />}{/* A card while a staff member has a contract to sign (tutor and admin dashboards, not on the contract page itself), */}
        <CheckInPrompts role={role} />{/* Any check-ins waiting for them after a new match (tutor, parent and student dashboards only), */}
        <PushPrompt />{/* the "turn on pop-up notifications" note (only on devices that could have them but do not yet), */}
        {children}{/* then the page's own contents. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of DashboardFrame.
