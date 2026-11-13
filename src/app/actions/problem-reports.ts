// Summary: the server actions for problem reports: anyone signed in sends a
// report with screenshots; reviewers change a report's status, reply and
// notes; the owner chooses the reviewer list, deletes a report, and can turn
// an approved report into a GitHub issue for the developer.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

// The database decides who may do each of these (see the problem_reports
// migration); the checks here only give plainer messages.

import { randomUUID } from "node:crypto"; // Makes random file names, so no one can guess a screenshot's address.
import { revalidatePath } from "next/cache"; // Refreshes pages after a change, so they show the new data.
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import { documentType } from "@/lib/documents"; // Works out a file's real type from its contents.
import type { FormState } from "@/lib/forms"; // The shape of a form's reply (error or message), for type checking.
import { MAX_SCREENSHOT_BYTES, MAX_SCREENSHOTS, PROBLEM_PRIORITIES, PROBLEM_STATUSES, pageWithoutIds } from "@/lib/problem-reports"; // Limits, statuses, priorities and the id remover.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

const BUCKET = "problem-screenshots"; // The private file store for screenshots.

// The plain database messages we're happy to show as they are (they start
// with these words); anything else gets a general message.
const PLAIN = /^(Please|You've|That |A screenshot|Only |Choose)/; // The starts of the database's own plain messages.

// The rules for the report form:
const reportSchema = z.object({
  what_happened: z.string().trim().min(10, "Please say what went wrong in a sentence or two.").max(4000, "Please keep \"What went wrong\" under 4,000 characters."), // what went wrong,
  trying_to: z.string().trim().max(1000, "Please keep \"What were you trying to do\" under 1,000 characters.").optional(), // what they were trying to do (optional),
  page: z.string().trim().max(300).optional(), // the page they were on (filled in by the app),
  device: z.string().trim().max(400).optional(), // their browser and device (filled in by the app).
}); // End of the rules.

// Sends a problem report. Screenshots are checked (real pictures, not too
// big), put in the person's own private folder, then the report is saved.
// If saving fails, the uploaded screenshots are removed again.
export async function submitProblemReport(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = reportSchema.safeParse({ // Checks the typed fields against the rules:
    what_happened: formData.get("what_happened") ?? "", // what went wrong,
    trying_to: formData.get("trying_to") ?? undefined, // what they were trying to do,
    page: formData.get("page") ?? undefined, // the page,
    device: formData.get("device") ?? undefined, // the device.
  }); // End of the check.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.

  const files = formData.getAll("screenshots").filter((f): f is File => f instanceof File && f.size > 0); // The screenshots chosen (skipping empty ones).
  if (files.length > MAX_SCREENSHOTS) return { error: `Please attach no more than ${MAX_SCREENSHOTS} screenshots.` }; // Too many: says the limit.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: auth } = await supabase.auth.getUser(); // Reads who is signed in (for their folder name).
  const me = auth.user?.id; // Their account id.
  if (!me) return { error: "Please sign in again, then send your report." }; // Not signed in after all: asks them to.

  const uploaded: { path: string; type: string }[] = []; // The screenshots stored so far.
  const removeUploaded = async () => { // Removes stored screenshots if the report can't be saved:
    if (uploaded.length) await supabase.storage.from(BUCKET).remove(uploaded.map((u) => u.path)); // removes them all at once (if any).
  }; // End of the clean-up helper.
  for (const [i, file] of files.entries()) { // For each screenshot (with its number):
    if (file.size > MAX_SCREENSHOT_BYTES) { // Too big:
      await removeUploaded(); // removes any already stored,
      return { error: `Screenshot ${i + 1} is too big. Please try a smaller picture, or crop it.` }; // and says which one.
    } // End of the size check.
    const bytes = new Uint8Array(await file.arrayBuffer()); // Reads the picture's bytes.
    const kind = documentType(bytes); // Works out its real type from the bytes (not the name).
    if (!kind || kind.type === "application/pdf") { // Not a picture:
      await removeUploaded(); // removes any already stored,
      return { error: `Screenshot ${i + 1} isn't a picture. Please use a JPG, PNG or WebP screenshot.` }; // and says which one.
    } // End of the type check.
    const path = `${me}/${randomUUID()}.${kind.ext}`; // Their folder and a random name.
    const stored = await supabase.storage.from(BUCKET).upload(path, bytes, { contentType: kind.type, upsert: false }); // Stores it privately, never replacing another file.
    if (stored.error) { // Couldn't store it:
      await removeUploaded(); // removes any already stored,
      return { error: `Screenshot ${i + 1} didn't upload. Please try again.` }; // and says which one.
    } // End of the failure case.
    uploaded.push({ path, type: kind.type }); // Notes it as stored.
  } // End of the screenshots loop.

  const { error } = await supabase.rpc("problem_report_submit", { // Saves the report with its screenshots:
    p_what_happened: v.what_happened, // what went wrong,
    p_trying_to: v.trying_to ?? "", // what they were trying to do,
    p_page: v.page ?? "", // the page,
    p_device: v.device ?? "", // the device,
    p_screenshots: uploaded, // and the stored screenshots.
  }); // End of the save.
  if (error) { // Saving failed:
    await removeUploaded(); // removes the stored screenshots so nothing is left behind,
    return { error: PLAIN.test(error.message) ? error.message : "Couldn't send your report. Please try again." }; // and shows the database's plain message, or a general one.
  } // End of the failure case.

  revalidatePath("/report-problem"); // Refreshes the page so the report shows under "Your reports".
  revalidatePath("/admin/problems"); // Refreshes the reviewers' queue.
  return { message: "Thanks, your report has been sent. CLG will check it and reply here." }; // Thanks them.
} // End of submitProblemReport.

// The rules for a reviewer's changes:
const updateSchema = z.object({
  id: z.uuid(), // which report,
  status: z.enum(PROBLEM_STATUSES, "Choose a status."), // its status,
  priority: z.enum(PROBLEM_PRIORITIES, "Choose a priority."), // its priority,
  reply: z.string().trim().max(2000, "Please keep the reply under 2,000 characters.").optional(), // the reply the reporter sees,
  reviewer_notes: z.string().trim().max(4000, "Please keep the notes under 4,000 characters.").optional(), // private notes,
  fix_summary: z.string().trim().max(4000, "Please keep the fix summary under 4,000 characters.").optional(), // the fix for the developer.
}); // End of the rules.

// Saves a reviewer's changes to a report.
export async function updateProblemReport(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = updateSchema.safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const v = parsed.data; // The checked values.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("problem_report_update", { // Asks the database to save the changes:
    p_id: v.id, // the report,
    p_status: v.status, // its status,
    p_priority: v.priority, // its priority,
    p_reply: v.reply ?? "", // the reply,
    p_notes: v.reviewer_notes ?? "", // the private notes,
    p_fix_summary: v.fix_summary ?? "", // the fix summary.
  }); // End of the request.
  if (error) return { error: PLAIN.test(error.message) ? error.message : "Couldn't save. Please try again." }; // Failed: the plain message, or a general one.
  revalidatePath("/admin/problems"); // Refreshes the queue.
  return { message: "Saved." }; // Confirms it.
} // End of updateProblemReport.

// The owner adds an admin to the reviewer list.
export async function addProblemReviewer(formData: FormData): Promise<void> {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("account_id")); // Checks the account id looks right.
  if (!id.success) return; // Not a real id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("problem_reviewer_add", { p_account: id.data }); // Asks the database to add them (it checks for the owner).
  revalidatePath("/admin/problems"); // Refreshes the page.
} // End of addProblemReviewer.

// The owner takes someone off the reviewer list.
export async function removeProblemReviewer(formData: FormData): Promise<void> {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("account_id")); // Checks the account id looks right.
  if (!id.success) return; // Not a real id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("problem_reviewer_remove", { p_account: id.data }); // Asks the database to remove them (it checks for the owner).
  revalidatePath("/admin/problems"); // Refreshes the page.
} // End of removeProblemReviewer.

// The owner deletes a report (and its screenshots).
export async function deleteProblemReport(formData: FormData): Promise<void> {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Checks the report id looks right.
  if (!id.success) return; // Not a real id: does nothing.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  await supabase.rpc("problem_report_delete", { p_id: id.data }); // Asks the database to delete it (it checks for the owner).
  revalidatePath("/admin/problems"); // Refreshes the queue.
} // End of deleteProblemReport.

// Whether the GitHub settings are in place (both must be set in Vercel).
function githubSettings(): { token: string; repo: string } | null { // Gives back the token and repository, or nothing.
  const token = process.env.GITHUB_ISSUES_TOKEN; // A GitHub key that can only add issues to the app's repository.
  const repo = process.env.GITHUB_ISSUES_REPO; // The repository, written as "owner/name".
  if (!token || !repo || !/^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/.test(repo)) return null; // Missing or oddly written: not set up.
  return { token, repo }; // Both set: hands them back.
} // End of githubSettings.

// The owner turns an approved report into a GitHub issue for the developer
// (for example, for Claude to fix). Only the reviewer's fix summary and the
// page (with ids taken out) are sent: never names, the reporter's words,
// notes or screenshots, because GitHub is outside CLG and overseas.
export async function sendProblemToGitHub(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireViewer(); // Makes sure someone is signed in.
  const id = z.uuid().safeParse(formData.get("id")); // Checks the report id looks right.
  if (!id.success) return { error: "That report wasn't found." }; // Not a real id: says so.
  const settings = githubSettings(); // The GitHub settings.
  if (!settings) return { error: "GitHub isn't set up yet. Add GITHUB_ISSUES_TOKEN and GITHUB_ISSUES_REPO in Vercel first." }; // Not set up: says what's needed.

  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data: level } = await supabase.rpc("my_admin_level"); // Reads the person's admin level.
  if (level !== "owner") return { error: "Only the owner can send reports to GitHub." }; // Not the owner: refuses.
  const { data: report } = await supabase // Reads the report:
    .from("problem_reports") // from the reports table,
    .select("id, status, page, fix_summary, github_issue_url, created_at") // only what's needed,
    .eq("id", id.data) // this one,
    .maybeSingle(); // (one or none).
  if (!report) return { error: "That report wasn't found." }; // Not found (or not allowed): says so.
  if (report.github_issue_url) return { error: "This report is already on GitHub." }; // Already sent: says so.
  if (report.status !== "approved") return { error: "Mark the report \"Approved to fix\" and save before sending it to GitHub." }; // Not approved: a person must check it first.
  if (!report.fix_summary || report.fix_summary.length < 10) return { error: "Write the fix for the developer (no names or personal details) and save before sending." }; // No fix summary: asks for one.

  const body = [ // The issue's text, line by line:
    report.fix_summary, // the reviewer's fix summary,
    "", // a blank line,
    `**Page:** ${pageWithoutIds(report.page)}`, // the page, with ids taken out,
    `**Reported:** ${report.created_at.slice(0, 10)}`, // the date it was reported,
    `**CLG reference:** ${report.id.slice(0, 8)}`, // a short reference (only meaningful inside the app),
    "", // a blank line,
    "_Made from an approved problem report in the CLG app. No personal details or screenshots are included; ask the owner if more detail is needed._", // a note on what's left out.
  ].join("\n"); // Joined into one block of text.
  const title = report.fix_summary.split("\n")[0].slice(0, 120); // The title: the first line of the fix summary (up to 120 characters).

  let url: string | undefined; // The new issue's address, once made.
  try { // Tries to make the issue:
    const res = await fetch(`https://api.github.com/repos/${settings.repo}/issues`, { // asks GitHub to add an issue
      method: "POST", // (adding something new)
      headers: { // with:
        Authorization: `Bearer ${settings.token}`, // the key,
        Accept: "application/vnd.github+json", // GitHub's answer format,
        "X-GitHub-Api-Version": "2022-11-28", // the version of GitHub's rules we follow,
        "Content-Type": "application/json", // and that we're sending JSON.
      }, // (end of the headers)
      body: JSON.stringify({ title, body, labels: ["app-problem"] }), // the title, text and an "app-problem" label.
    }); // End of the request.
    if (res.ok) url = ((await res.json()) as { html_url?: string }).html_url; // Worked: reads the issue's address.
    else console.error("GitHub issue:", res.status, await res.text()); // Didn't work: notes why in the server log.
  } catch (e) { // The request itself failed (for example, no connection):
    console.error("GitHub issue:", e); // notes why in the server log.
  } // End of the attempt.
  if (!url) return { error: "GitHub didn't accept the issue. Check the key in Vercel can add issues to the repository, then try again." }; // Failed: says what to check.

  const { error } = await supabase.rpc("problem_report_github_saved", { p_id: report.id, p_url: url }); // Saves the issue's address on the report.
  if (error) return { error: `The issue was made (${url}) but couldn't be saved on the report.` }; // Saving failed: gives the address anyway.
  revalidatePath("/admin/problems"); // Refreshes the queue.
  return { message: `Sent to GitHub: ${url}` }; // Confirms it, with the address.
} // End of sendProblemToGitHub.
