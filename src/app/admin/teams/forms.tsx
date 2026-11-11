// Summary: the admin forms for Teams links: settings, "make links now", and a manual link.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { runTeamsNow, saveTeamsSettings, setMeetingLink } from "@/app/actions/teams"; // The server actions for the three forms.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // A labelled input box.

// The Teams settings form.
export function TeamsSettingsForm({
  enabled, // whether links are turned on,
  organiser, // the account that owns the meetings,
  daysAhead, // how many days ahead to make links.
}: { // (their types:)
  enabled: boolean; // on or off,
  organiser: string; // an email,
  daysAhead: number; // a number.
}) { // (end of the settings)
  return ( // Shows:
    <ActionForm action={saveTeamsSettings} submitLabel="Save settings">{/* a form that saves the settings: */}
      <label className="flex items-center gap-2 text-sm">{/* a line holding: */}
        <input type="checkbox" name="enabled" defaultChecked={enabled} /> Make Teams links for online sessions{/* a tick box to turn links on. */}
      </label>{/* End of the line. */}
      <Field // The meetings account box:
        label="Microsoft 365 account that owns the meetings" // its label,
        name="organiser_email" // its field name,
        type="email" // an email address,
        defaultValue={organiser} // starting with the current account,
        placeholder="sessions@clgtutoring.com" // an example,
        hint="Must have a Teams licence, and be the account named in the access policy step." // and a hint about the licence.
      />{/* (end of the box) */}
      <Field // The days ahead box:
        label="Make links this many days ahead" // its label,
        name="days_ahead" // its field name,
        type="number" // a number,
        min={1} // at least 1,
        max={28} // at most 28,
        defaultValue={daysAhead} // starting with the current number,
        hint="Shorter means fewer meetings to delete when sessions are cancelled. 7 suits most families." // and a hint.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of TeamsSettingsForm.

// The "make links now" button, with a note on when links are made.
export function RunTeamsNowForm() {
  return ( // Shows:
    <ActionForm action={runTeamsNow} submitLabel="Make links now">{/* a form that runs it now: */}
      <p className="text-sm text-zinc-600">{/* a grey note: */}
        Links are made by themselves: every morning, after bookings and cancellations, and when people open their
        schedule. This runs it now, and is the quickest way to test the Microsoft 365 setup.{/* when links are made, and why to run it now. */}
      </p>{/* End of the note. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of RunTeamsNowForm.

// A form to save (or clear) a manual meeting link for one session.
export function MeetingLinkForm({ sessionId, url }: { sessionId: string; url: string | null }) {
  return ( // Shows:
    <ActionForm action={setMeetingLink} submitLabel={url ? "Change link" : "Save link"}>{/* a form that saves the link: */}
      <input type="hidden" name="session_id" value={sessionId} />{/* the session's id (hidden), */}
      <Field // the link box:
        label="Meeting link" // its label,
        name="url" // its field name,
        type="url" // a web address,
        defaultValue={url ?? ""} // starting with the current link,
        placeholder="https://teams.microsoft.com/…" // an example,
        hint="Paste a link to use instead of an automatic one. Leave empty and save to clear it." // and a hint.
      />{/* (end of the box) */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MeetingLinkForm.
