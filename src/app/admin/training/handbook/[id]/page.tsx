// Summary: edit one handbook page (owner and operations).
//
import { notFound } from "next/navigation"; // Shows "not found".
import { deleteHandbookPage } from "@/app/actions/training"; // The server action that deletes a page.
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { BackButton, Card, TextLink } from "@/components/ui"; // The card and link style.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is a full admin.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { HandbookForm, SmallAction, type HandbookRow } from "../../forms"; // The handbook form, the small button, and the page shape.

// Shows the handbook page editor.
export default async function AdminHandbookPage({ params }: PageProps<"/admin/training/handbook/[id]">) { // Reads the address's id.
  const viewer = await requireAdmin(); // Only owner and operations admins.
  const { id } = await params; // The page's id.
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound(); // Odd id: not found.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.from("handbook_pages").select("id, title, body, urgent, audience, status, position").eq("id", id).maybeSingle(); // Reads the page.
  if (!data) notFound(); // No such page: not found.
  const page = data as HandbookRow; // The page.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="training-admin" sub="handbook">{/* the dashboard tabs and menu, with Training setup open: */}
      <p className="flex flex-wrap items-center gap-4"><BackButton href="/admin/training?section=handbook">Back to all handbook pages</BackButton><TextLink href={`/handbook/${page.id}?as=admin`}>Preview</TextLink></p>{/* a button back to the handbook list, and a link to a preview, */}
      <Card title="Handbook page">{/* the editing card: */}
        <HandbookForm page={page} />{/* the form. */}
      </Card>{/* End of the card. */}
      <SmallAction action={deleteHandbookPage} fields={{ id: page.id }} label="Delete this page" confirm="Delete this handbook page?" />{/* the delete button, */}
      <p><BackButton href="/admin/training?section=handbook">Back to all handbook pages</BackButton></p>{/* and the same back button at the bottom, so it's there after scrolling down. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of AdminHandbookPage.
