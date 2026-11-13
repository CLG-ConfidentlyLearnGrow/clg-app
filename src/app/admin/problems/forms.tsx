// Summary: the reviewers' forms on the Problem reports page: change a
// report's status, priority, reply and notes; and (owner only) send an
// approved report to GitHub for the developer to fix.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { sendProblemToGitHub, updateProblemReport } from "@/app/actions/problem-reports"; // The server actions that save changes and send to GitHub.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Select, TextArea } from "@/components/ui"; // The drop-down list and multi-line text box.
import { PROBLEM_PRIORITIES, PROBLEM_PRIORITY_LABELS, PROBLEM_STATUSES, PROBLEM_STATUS_LABELS, type ProblemReport } from "@/lib/problem-reports"; // Status and priority lists and words, and the report type.

// The reviewer's form for one report.
export function UpdateProblemForm({ report }: { report: ProblemReport }) {
  return ( // Shows:
    <ActionForm action={updateProblemReport} submitLabel="Save">{/* a form that saves the changes: */}
      <input type="hidden" name="id" value={report.id} />{/* the report's id, hidden, */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{/* two columns on wider screens: */}
        <Select label="Status" name="status" defaultValue={report.status}>{/* the status list, starting on the saved one: */}
          {PROBLEM_STATUSES.map((s) => <option key={s} value={s}>{PROBLEM_STATUS_LABELS[s]}</option>)}{/* one choice per status. */}
        </Select>{/* End of the status list. */}
        <Select label="Priority" name="priority" defaultValue={report.priority}>{/* the priority list, starting on the saved one: */}
          {PROBLEM_PRIORITIES.map((p) => <option key={p} value={p}>{PROBLEM_PRIORITY_LABELS[p]}</option>)}{/* one choice per priority. */}
        </Select>{/* End of the priority list. */}
      </div>{/* End of the columns. */}
      <TextArea // the reply box:
        label="Reply to the person who reported it" // its words,
        name="reply" // its name,
        maxLength={2000} // up to 2,000 characters,
        defaultValue={report.reply ?? ""} // starts with the saved reply,
        hint="They see this on their Report a problem page." // help under the box.
      />{/* End of the reply box. */}
      <TextArea // the notes box:
        label="Private notes (reviewers only)" // its words,
        name="reviewer_notes" // its name,
        maxLength={4000} // up to 4,000 characters,
        defaultValue={report.reviewer_notes ?? ""} // starts with the saved notes.
      />{/* End of the notes box. */}
      <TextArea // the fix summary box:
        label="The fix, for the developer" // its words,
        name="fix_summary" // its name,
        rows={4} // four lines tall,
        maxLength={4000} // up to 4,000 characters,
        defaultValue={report.fix_summary ?? ""} // starts with the saved summary,
        hint="First line is the title. Say what's wrong and what should happen instead. No names, emails, children's details or anything copied from a screenshot: this is what goes to GitHub." // help under the box.
      />{/* End of the fix summary box. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of UpdateProblemForm.

// The owner's "Send to GitHub" button for an approved report.
export function SendToGitHubForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={sendProblemToGitHub} submitLabel="Send to GitHub">{/* a form that makes the GitHub issue: */}
      <input type="hidden" name="id" value={id} />{/* the report's id, hidden, */}
      <p className="text-sm text-zinc-600">{/* a note on what's sent: */}
        Only the fix summary and the page name (with ids taken out) are sent. Names, the reporter&apos;s words, notes and screenshots stay in CLG.{/* (its words) */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SendToGitHubForm.
