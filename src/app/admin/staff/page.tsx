import { RoleTabs } from "@/components/role-tabs";
import { PageTitle, TextLink } from "@/components/ui";
import { ANY_ADMIN, FULL_ADMIN, requireAdminLevel } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { StaffDirectory, type Invitation, type StaffMember } from "./staff-directory";

// Staff directory: every tutor and admin with their job title, searchable
// and filterable. Any admin level can look; the owner and operations admins
// can change job titles, add roles and send links; only the owner removes
// roles. See docs/features/staff-directory.md.
export default async function StaffDirectoryPage() {
  const viewer = await requireAdminLevel(ANY_ADMIN);
  const canEdit = FULL_ADMIN.includes(viewer.level);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("staff_directory");
  const staff = (data ?? []) as StaffMember[];
  // Staff invited who haven't joined yet (owner and operations only).
  const invitations = canEdit
    ? (((
        await supabase
          .from("invitations")
          .select("id, email, role, admin_level, expires_at")
          .is("accepted_at", null)
          .in("role", ["tutor", "admin"])
          .order("created_at", { ascending: false })
      ).data ?? []) as Invitation[])
    : [];
  const back =
    viewer.level === "finance"
      ? { href: "/admin/billing", label: "Back to billing" }
      : canEdit
        ? { href: "/admin?section=staff", label: "Back to staff and accounts" }
        : { href: "/admin", label: "Back to admin" };

  return (
    <>
      <RoleTabs roles={viewer.roles} active="admin" />
      <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:py-12">
        <p className="mb-4 text-sm">
          <TextLink href={back.href}>{back.label}</TextLink>
        </p>
        <PageTitle
          role="admin"
          title="Staff directory"
          intro={
            canEdit
              ? "Everyone who works for CLG, with their job title and what they do in the app. Search or filter to find someone. Press Manage on a person to change their job title, send them a link, or add or remove a role."
              : "Everyone who works for CLG, with their job title and what they do in the app. Search or filter to find someone."
          }
        />
        {error ? (
          <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
            Couldn&apos;t load the staff directory. Please refresh the page.
          </p>
        ) : (
          <StaffDirectory
            staff={staff}
            invitations={invitations}
            canEdit={canEdit}
            isOwner={viewer.level === "owner"}
            viewerId={viewer.id}
          />
        )}
      </main>
    </>
  );
}
