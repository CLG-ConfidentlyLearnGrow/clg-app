// Summary: small admin-level forms: the level label, changing a level, and emergency owner access.
//
"use client"; // Runs in the browser, so the forms can react straight away.

import { approveEmergencyAccess, cancelEmergencyAccess, requestEmergencyAccess, setAdminLevel } from "@/app/actions/admin"; // The server actions for these forms.
import { useActionState } from "react"; // Lets a form run a server action and remember its reply.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { initialFormState } from "@/lib/forms"; // The starting (empty) form reply.
import { TextArea } from "@/components/ui"; // A larger text box.

// A short label for an admin level, for example in the staff list.
export function LevelBadge({ level }: { level: string }) {
  const names: Record<string, string> = { owner: "Owner", operations: "Operations", support: "Support", finance: "Finance" }; // Each level's name.
  return ( // Shows:
    <span className="inline-block rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-800">{/* a small grey pill: */}
      {names[level] ?? level}{/* the level's name. */}
    </span> // End of the pill.
  ); // End of what's shown.
} // End of LevelBadge.

// The owner changes another admin's level: one small dropdown that saves
// as soon as a level is picked, with a one-word note.
export function SetLevelForm({ accountId, level }: { accountId: string; level: string }) {
  const [state, formAction, pending] = useActionState(setAdminLevel, initialFormState); // The reply, the action to send, and whether it's saving.
  return ( // Shows:
    <form action={formAction} className="flex items-center gap-2">{/* a form in one row: */}
      <input type="hidden" name="account_id" value={accountId} />{/* which admin (hidden), */}
      <select // a drop-down:
        name="level" // its field name,
        defaultValue={level} // starting on the current level,
        aria-label="Admin level" // its name for screen readers,
        disabled={pending} // greyed out while saving,
        onChange={(e) => e.currentTarget.form?.requestSubmit()} // sends the form as soon as a level is picked,
        className="rounded-full border border-zinc-300 bg-white px-2.5 py-1 text-xs font-medium shadow-sm focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // styled as a small pill.
      >{/* (end of its settings) */}
        <option value="operations">Operations</option>{/* operations, */}
        <option value="support">Support</option>{/* support, */}
        <option value="finance">Finance</option>{/* finance. */}
      </select>{/* End of the drop-down. */}
      {pending ? ( // While saving:
        <span className="text-xs text-zinc-500">Saving…</span> // "Saving…",
      ) : state.error ? ( // if there's an error:
        <span role="alert" className="text-xs text-red-700">{/* a red message: */}
          {state.error}{/* the error. */}
        </span> // (end of the message)
      ) : state.message ? ( // if it worked:
        <span role="status" className="text-xs text-teal-800">{/* a short note: */}
          Saved{/* "Saved". */}
        </span> // (end of the note)
      ) : null}{/* otherwise nothing. */}
    </form> // End of the form.
  ); // End of what's shown.
} // End of SetLevelForm.

// An Operations admin asks for emergency owner access. A reason is required.
export function EmergencyRequestForm() {
  return ( // Shows:
    <ActionForm action={requestEmergencyAccess} submitLabel="Ask for owner access">{/* a form that sends the request: */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        The owner is emailed straight away with your reason. Your owner access starts after 24 hr unless they cancel
        it, or sooner if they approve it. It lasts 7 days, then ends by itself. Everything you do with it is recorded.{/* what happens next and how long it lasts. */}
      </p>{/* End of the note. */}
      <TextArea // The reason box:
        label="Why do you need owner access?" // its label,
        name="reason" // its field name,
        required // that must be filled in,
        minLength={10} // at least 10 characters,
        maxLength={1000} // up to 1,000,
        hint="For example: what needs doing, and why the owner can't be reached." // and a hint.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EmergencyRequestForm.

// Cancel a request (owner), end running access early (owner), or withdraw
// your own request.
export function EmergencyCancelForm({ id, label }: { id: string; label: string }) {
  return ( // Shows:
    <ActionForm action={cancelEmergencyAccess} submitLabel={label}>{/* a form with the given button words: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EmergencyCancelForm.

// The owner approves a waiting request so it starts now.
export function EmergencyApproveForm({ id }: { id: string }) {
  return ( // Shows:
    <ActionForm action={approveEmergencyAccess} submitLabel="Approve now">{/* a form with an "Approve now" button: */}
      <input type="hidden" name="id" value={id} />{/* which request (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of EmergencyApproveForm.
