// Summary: downloads a training certificate as a PDF. The address ends in a
// completion's id (one module), or "certified" (the CLG certified
// certificate for the signed-in person).
//
import { NextResponse, type NextRequest } from "next/server"; // The reply tools for sending files.
import { z } from "zod"; // The form-checking library (used to check the id).
import { plainDate } from "@/lib/billing/money"; // Dates in words, e.g. "3 November 2026".
import { createAdminClient } from "@/lib/supabase/admin"; // Full database access (only to look up the owner's name for the signature).
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { makeCertificate } from "@/lib/training-certificate"; // Makes the certificate PDF.
import { hrs, type Certification } from "@/lib/training"; // Hours in words, and the certification shape.

// A plain-text reply (for problems), never saved by the browser.
function message(text: string, status: number) { // Takes the words and the status.
  return new NextResponse(text, { status, headers: { "Cache-Control": "no-store", "Content-Type": "text/plain; charset=utf-8" } }); // The reply.
} // End of message.

// Reads CLG's logo from the app's own public files (skipped if it can't be read).
async function readLogo(request: NextRequest): Promise<Uint8Array | null> { // Takes the request (for the app's address).
  try { // Tries:
    const res = await fetch(new URL("/brand/clg-logo-transparent.png", request.url)); // fetching the logo from the app itself,
    return res.ok ? new Uint8Array(await res.arrayBuffer()) : null; // and gives back its bytes (or nothing).
  } catch { // It couldn't be read:
    return null; // carries on without it.
  } // End of the try.
} // End of readLogo.

// The name that signs certificates: CLG's owner (the saved owner admin).
async function signerName(): Promise<string> { // No inputs.
  try { // Tries:
    const db = createAdminClient(); // full access (people can't read admin details),
    const { data } = await db.from("admin_profiles").select("account:accounts(full_name)").eq("level", "owner").limit(1).maybeSingle(); // the owner's name,
    const name = (data as unknown as { account: { full_name: string } | null } | null)?.account?.full_name; // (picked out)
    return name ?? "CLG Tutoring"; // their name, or "CLG Tutoring" if none.
  } catch { // It couldn't be read:
    return "CLG Tutoring"; // uses "CLG Tutoring".
  } // End of the try.
} // End of signerName.

// Makes and sends the certificate.
export async function GET(request: NextRequest, ctx: RouteContext<"/training/certificate/[id]">) { // Gets the request and the address's id.
  const { id } = await ctx.params; // The id from the address.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: auth } = await supabase.auth.getUser(); // Who is signed in.
  if (!auth.user) return message("Please sign in to download your certificate.", 401); // Not signed in: asks them to.

  let details: { heading: string; achievement: string; lines: string[]; certificateNo: string; personId: string }; // What to print.
  if (id === "certified") { // The CLG certified certificate:
    const { data, error } = await supabase.rpc("training_certification").maybeSingle<Certification>(); // reads their certification (two-step login needed),
    if (error || !data) return message("Please sign in with two-step login to download your certificate.", 403); // refused: explains.
    if (data.state !== "certified") return message("You will be able to download this once you are CLG certified.", 403); // not certified: explains.
    details = { // what to print:
      heading: "CLG certified tutor", // the heading,
      achievement: "CLG's tutor training and ongoing professional learning", // what they completed,
      lines: [ // the smaller lines:
        `Certified since ${plainDate(data.certified_since)}`, // since when,
        `Current to ${plainDate(data.quarter_ends)}, with ${hrs(data.target_minutes)} of training each quarter`, // current to the end of this quarter,
      ], // (end of the lines)
      certificateNo: `CLG-C-${auth.user.id.replace(/-/g, "").slice(0, 8).toUpperCase()}-${data.quarter_ends.replace(/-/g, "").slice(0, 6)}`, // a number for this person and quarter,
      personId: auth.user.id, // and who it's for.
    }; // End of the details.
  } else { // One module's certificate:
    if (!z.uuid().safeParse(id).success) return message("That certificate was not found.", 404); // odd id: not found.
    const { data: c } = await supabase // reads the completion (only the person or a full admin can):
      .from("training_completions") // from completions,
      .select("account_id, module_title, minutes, completed_on, expires_on, certificate_no") // its details,
      .eq("id", id) // this one,
      .maybeSingle(); // (one at most).
    if (!c) return message("That certificate was not found, or you need to sign in with two-step login.", 404); // not found (or not theirs): says so.
    details = { // what to print:
      heading: "Certificate of completion", // the heading,
      achievement: c.module_title, // the module's name,
      lines: [ // the smaller lines:
        `Completed ${plainDate(c.completed_on)} (${hrs(c.minutes)})`, // when, and how long,
        ...(c.expires_on ? [`Valid until ${plainDate(c.expires_on)}`] : []), // until when (if it runs out),
      ], // (end of the lines)
      certificateNo: c.certificate_no, // its number,
      personId: c.account_id, // and who it's for.
    }; // End of the details.
  } // End of the choice.

  const { data: person } = await supabase.from("accounts").select("full_name").eq("id", details.personId).maybeSingle(); // The person's name (they or an admin can read it).
  const pdf = await makeCertificate({ ...details, personName: person?.full_name ?? "CLG staff member", signer: await signerName(), logo: await readLogo(request) }); // Makes the PDF.
  const safeName = details.achievement.replace(/[^A-Za-z0-9 ._-]/g, "").trim().slice(0, 60) || "CLG training"; // A safe file name.
  return new NextResponse(Buffer.from(pdf), { // Sends the PDF:
    headers: { // (its details:)
      "Content-Type": "application/pdf", // it's a PDF,
      "Content-Disposition": `inline; filename="CLG certificate - ${safeName}.pdf"`, // opens in the browser, with a clear name,
      "Cache-Control": "private, no-store", // never kept in a shared store,
      "X-Robots-Tag": "noindex, nofollow", // and kept out of search engines.
    }, // (end of the details)
  }); // End of the reply.
} // End of GET.
