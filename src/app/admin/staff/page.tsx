// Summary: the staff directory page for admins.
//
import { RoleTabs } from "@/components/role-tabs"; // The tabs for each dashboard.
import { BackButton, PageTitle } from "@/components/ui"; // The back button and page heading.
import { ANY_ADMIN, FULL_ADMIN, requireAdminLevel } from "@/lib/auth"; // The admin level groups, and the admin level check.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { StaffDirectory, type Invitation, type StaffMember } from "./staff-directory"; // The directory itself, and the types of its rows.

// Staff directory: every tutor and admin with their job title, searchable
// and filterable. Any admin level can look; the owner and operations admins
// can change job titles, add roles and send links; only the owner removes
// roles or removes someone who has left CLG. See docs/features/staff-directory.md
// and docs/features/staff-leaving.md.
export default async function StaffDirectoryPage() {
  const viewer = await requireAdminLevel(ANY_ADMIN); // Makes sure the person is an admin at any level, and gets who they are.
  const canEdit = FULL_ADMIN.includes(viewer.level); // True for the owner and operations admins.
  const supabase = await createClient(); // Connects to the database.
  const { data, error } = await supabase.rpc("staff_directory"); // Reads the staff list.
  const listed = (data ?? []) as StaffMember[]; // The staff, as the directory gives them.
  // Each person's first and last name (admins can read names). If this
  // can't be read (before the staff names update is run), names stay as they are.
  const parts = listed.length // Only asks if there's anyone listed:
    ? await supabase.from("accounts").select("id, first_name, last_name").in("id", listed.map((p) => p.account_id)) // their first and last names,
    : { data: [], error: null }; // (otherwise nothing to read)
  const partsById = new Map( // A quick lookup from account id to names:
    ((parts.error ? [] : parts.data) ?? []).map((r) => [r.id as string, r as { first_name: string | null; last_name: string | null }]), // one entry per person,
  ); // End of the lookup.
  const staff = listed.map((p) => ({ // Each person, with their names added:
    ...p, // everything the directory gave,
    first_name: partsById.get(p.account_id)?.first_name ?? null, // their first name (blank if not given),
    last_name: partsById.get(p.account_id)?.last_name ?? null, // their last name (blank if not given),
    names_known: !parts.error, // and whether the names could be read at all.
  })); // End of the staff list.
  // Staff invited who haven't joined yet (owner and operations only).
  const invitations = canEdit // The waiting invitations, only for those who can edit:
    ? ((( // (the result of:)
        await supabase // (a database read:)
          .from("invitations") // from the invitations table,
          .select("id, email, role, admin_level, expires_at") // the id, email, role, admin level and expiry,
          .is("accepted_at", null) // not yet used,
          .in("role", ["tutor", "admin"]) // for tutors and admins,
          .order("created_at", { ascending: false }) // newest first.
      ).data ?? []) as Invitation[]) // (or none)
    : []; // Nobody else sees them.
  const back = // The "back" link:
    viewer.level === "finance" // for finance admins,
      ? { href: "/admin/billing", label: "Back to billing" } // back to billing,
      : canEdit // for those who can edit,
        ? { href: "/admin?section=staff", label: "Back to staff and accounts" } // back to staff and accounts,
        : { href: "/admin", label: "Back to admin" }; // otherwise back to admin.

  return ( // Shows:
    <>{/* (a group:) */}
      <RoleTabs roles={viewer.roles} active="admin" />{/* the dashboard tabs, */}
      <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:py-12">{/* the main area: */}
        <p className="mb-4"><BackButton href={back.href}>{back.label}</BackButton></p>{/* the back button, */}
        <PageTitle // The page heading:
          role="admin" // in the admin colour,
          title="Staff directory" // titled "Staff directory",
          intro={ // with an introduction:
            canEdit // for those who can edit,
              ? "Everyone who works for CLG, with their job title and what they do in the app. Search or filter to find someone. Press Manage on a person to change their name or job title, send them a link, add or remove a role, or remove them from the team when they leave. Choose \"Left CLG\" under Status to see former staff." // mentioning the Manage button and former staff,
              : "Everyone who works for CLG, with their job title and what they do in the app. Search or filter to find someone." // otherwise without it.
          } // (end of the introduction)
        />{/* (end of the heading) */}
        {error ? ( // If the list couldn't load:
          <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{/* a red alert box: */}
            Could not load the staff directory. Please refresh the page.{/* asking them to refresh. */}
          </p> // End of the alert.
        ) : ( // Otherwise:
          <StaffDirectory // the directory:
            staff={staff} // the staff,
            invitations={invitations} // the invitations,
            canEdit={canEdit} // whether they can edit,
            isOwner={viewer.level === "owner"} // whether they're the owner,
            viewerId={viewer.id} // and who they are.
          /> // (end of the directory)
        )}{/* End of the choice. */}
      </main>{/* End of the main area. */}
    </> // (end of the group)
  ); // End of what's shown.
} // End of StaffDirectoryPage.
