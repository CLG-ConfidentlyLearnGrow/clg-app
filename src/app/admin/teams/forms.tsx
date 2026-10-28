"use client";

import { runTeamsNow, saveTeamsSettings, setMeetingLink } from "@/app/actions/teams";
import { ActionForm } from "@/components/action-form";
import { Field } from "@/components/ui";

export function TeamsSettingsForm({
  enabled,
  organiser,
  daysAhead,
}: {
  enabled: boolean;
  organiser: string;
  daysAhead: number;
}) {
  return (
    <ActionForm action={saveTeamsSettings} submitLabel="Save settings">
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" name="enabled" defaultChecked={enabled} /> Make Teams links for online sessions
      </label>
      <Field
        label="Microsoft 365 account that owns the meetings"
        name="organiser_email"
        type="email"
        defaultValue={organiser}
        placeholder="sessions@clgtutoring.com"
        hint="Must have a Teams licence, and be the account named in the access policy step."
      />
      <Field
        label="Make links this many days ahead"
        name="days_ahead"
        type="number"
        min={1}
        max={28}
        defaultValue={daysAhead}
        hint="Shorter means fewer meetings to delete when sessions are cancelled. 7 suits most families."
      />
    </ActionForm>
  );
}

export function RunTeamsNowForm() {
  return (
    <ActionForm action={runTeamsNow} submitLabel="Make links now">
      <p className="text-sm text-zinc-600">
        Links are made by themselves: every morning, after bookings and cancellations, and when people open their
        schedule. This runs it now, and is the quickest way to test the Microsoft 365 setup.
      </p>
    </ActionForm>
  );
}

export function MeetingLinkForm({ sessionId, url }: { sessionId: string; url: string | null }) {
  return (
    <ActionForm action={setMeetingLink} submitLabel={url ? "Change link" : "Save link"}>
      <input type="hidden" name="session_id" value={sessionId} />
      <Field
        label="Meeting link"
        name="url"
        type="url"
        defaultValue={url ?? ""}
        placeholder="https://teams.microsoft.com/…"
        hint="Paste a link to use instead of an automatic one. Leave empty and save to clear it."
      />
    </ActionForm>
  );
}
