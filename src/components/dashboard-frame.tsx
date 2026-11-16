// Summary: the frame for any page that belongs to a dashboard: the dashboard
// tabs across the top, and that dashboard's side menu (with Sessions,
// Billing and the rest as tabs), around the page's own contents. It also
// shows the "What's new" pop-up when that dashboard has updates the person
// hasn't seen yet (Carla, 15 Nov 2026), and the first-time app tour the
// first time someone opens that dashboard (Carla, 16 Nov 2026). The tour
// comes first: while it's showing, "What's new" waits for the next visit, so
// two pop-ups never open at once. Check-ins after a new match show as cards
// above the page's contents while one is waiting (Carla, 16 Nov 2026).
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import type { Role } from "@/lib/auth"; // The type for a role (for type checking).
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard the person can use.
import { SectionShell, type Section } from "@/components/section-shell"; // The page frame with a side menu, and one menu item's shape.
import { getDashboardMenu } from "@/lib/dashboard-menu"; // Builds a dashboard's side menu.
import { ROLE_TABS } from "@/lib/roles"; // Each dashboard's name and address.
import { WhatsNew } from "@/components/whats-new"; // The "What's new" pop-up for this dashboard.
import { firstTimeTour } from "@/components/first-time-tour"; // The first-time app tour for this dashboard, if it should open.
import { CheckInPrompts } from "@/components/check-in-prompts"; // The check-in cards after a new match (Carla, 16 Nov 2026).

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
  const sections = menu.map((s) => (s.id === current && items ? { ...s, items } : s)); // The open item gets its smaller sections.
  const tour = await firstTimeTour(role); // The first-time tour, if this dashboard's tour hasn't been seen yet (otherwise nothing).
  return ( // Shows:
    <>{/* (a group) */}
      <RoleTabs roles={roles} active={role} />{/* the dashboard tabs, with this one open, */}
      {tour ?? <WhatsNew role={role} />}{/* the first-time tour if it's due, otherwise the "What's new" pop-up (if this dashboard has unseen updates), */}
      <SectionShell // the page frame:
        basePath={ROLE_TABS[role].href} // at the dashboard's address (each menu item has its own address anyway),
        label={ROLE_TABS[role].label} // labelled with the dashboard's name,
        role={role} // in the dashboard's colours,
        section={current} // on the open item,
        subSection={sub} // and the open smaller section,
        sections={sections} // with the dashboard's menu.
      >{/* (end of the frame's settings) */}
        <CheckInPrompts role={role} />{/* Any check-ins waiting for them after a new match (tutor, parent and student dashboards only), */}
        {children}{/* then the page's own contents. */}
      </SectionShell>{/* End of the page frame. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of DashboardFrame.
