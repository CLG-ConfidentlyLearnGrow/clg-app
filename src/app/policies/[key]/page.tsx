// Summary: a CLG document kept inside the app, such as the Child Safe Policy
// or the Staff Code of Conduct (Carla, 18 Nov 2026). Contracts and their
// acknowledgement steps link here as buttons, instead of out to Claude. The
// owner pastes the wording on the Contract templates page; until they tick
// "Approved", the page shows a draft label. Anyone signed in can read it.
// See docs/features/employment-contracts.md.
//
import { notFound } from "next/navigation"; // Shows the "page not found" screen.
import { ContractText } from "@/components/contract-text"; // Shows Markdown wording safely.
import { Card, Page } from "@/components/ui"; // The page frame (with its heading) and a card.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Shows one document.
export default async function PolicyPage({ params }: PageProps<"/policies/[key]">) {
  await requireViewer(); // Must be signed in (the database checks this too).
  const { key } = await params; // Which document, from the address.
  if (!/^[a-z_]{2,40}$/.test(key)) notFound(); // An odd address: not found.
  const supabase = await createClient(); // Connects to the database.
  const { data } = await supabase.from("employment_contract_documents").select("title, url, body, approved_at, updated_at").eq("key", key).maybeSingle(); // Reads the document.
  if (!data || data.url !== `/policies/${key}`) notFound(); // Not there, or not kept in the app: not found.
  return ( // Shows:
    <Page title={data.title as string}>{/* the page frame, with the document's name as the heading: */}
      <Card>{/* a card: */}
        {!data.approved_at && <p className="mb-4 rounded-xl bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900">Draft: CLG is still finalising this document. The final version will replace this one.</p>}{/* a draft label until approved, */}
        {(data.body as string).trim() ? <ContractText text={data.body as string} /> : <p className="text-sm text-zinc-600">CLG is finalising this document. Please check back soon, or ask CLG in the Help chat.</p>}{/* the wording, or a note if there is none yet, */}
        <p className="mt-6 text-xs text-zinc-500">Last updated {new Date(data.updated_at as string).toLocaleDateString("en-AU", { timeZone: "Australia/Adelaide", dateStyle: "long" })}.</p>{/* and when it was last changed. */}
      </Card>{/* End of the card. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of PolicyPage.
