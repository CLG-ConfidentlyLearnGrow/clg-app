# Pop-up notifications (web push)

Requested by Carla, 18 Nov 2026: "People need to be able to see the notifications for the app, so the app needs to send pop-up notifications (even when needing to sign back in), if this can not be done, the time out time may need to be turned off."

## The short answer

Pop-ups can be sent to people who have been signed out, so the 8 hr inactivity timeout can stay on. A pop-up is tied to the device (phone, tablet or computer browser), not to the sign-in. When someone taps one after being signed out, the app asks them to sign in, then they read the notice inside the app.

## What it does

- **Turn on pop-ups.** In **Sessions > Notices**, a **Pop-up notifications** card has **Turn on pop-ups on this device**. The browser asks for permission (it must be after a button press, phones refuse otherwise). Each dashboard also shows a small note inviting people to turn pop-ups on, with **Not now** to hide it on that device. Nothing is ever turned on by itself.
- **Which notices pop up.**
  - Session notices: reminders (48 hr and 1 hr before, or the person's own setting), booking news and cancellations.
  - Progress notices (session updates and note reminders).
  - Help chat: "You have a new message".
  - "Your tutor is running late" (only within the hour, after that it no longer helps).
  - Child safety concerns, to the Child Safety Officer or deputy they were sent to.
- **What a pop-up says.** Only the kind of notice and "Open the CLG app for the details", for example "Session reminder: You have a session coming up." Never a child's name, a tutor's name, a subject, a place or a message, because pop-ups can show on a locked screen.
- **Quiet hours.** Nothing pops up between 9pm and 5am in the person's own local time (the shared quiet hours setting). A notice due then pops up at 5am if it is still unread. The one exception is a child safety concern marked "immediate danger", which pops up straight away for the Child Safety Officer, matching its email.
- **No repeats, no stale pop-ups.** Each notice pops up once per person. A notice already read in the app does not pop up. Old notices (more than 2 hr for sessions and progress, 12 hr for help chat and safety, after quiet hours) do not pop up.
- **Several devices.** A person can have pop-ups on up to 10 devices. The card lists their other devices with **Remove**, and has **Send me a test**.
- **Shared devices.** A device belongs to one person at a time. If a second person signs in on a shared family computer and turns pop-ups on, the device moves to them, so the first person's notices stop appearing there.
- **Tapping a pop-up** opens the right page (for example the help chat, or Sessions > Notices). If the person was signed out, they sign in first, then go to their dashboard.
- **iPhone and iPad.** Apple only allows pop-ups once CLG is added to the home screen (iOS 16.4 or later). The card and the note explain this and link to the existing **Add CLG to your home screen** guide (`/install`). Android, Windows, Mac and Chromebook work in Chrome, Edge, Firefox and Safari without installing, though installing is still recommended.

## How it works (for whoever maintains it)

- **Database (shared core):** `supabase/migrations/20261121500100_push_notifications.sql`.
  - `push_subscriptions`: one row per device (its private delivery address and keys). People see only their own devices, and change them only through `push_subscribe`, `push_unsubscribe` and `push_remove_device`. Admins cannot see other people's devices.
  - `push_sent`: which notice was sent to whom, so nothing repeats. Server only. Rows go after 30 days.
  - `private.push_due(time)`: the list of pop-ups due. It only **reads** other modules' notice tables (`session_notices`, `progress_notices`, `help_chat_emails`, `session_lateness_emails`, `safety_concerns`); it never writes them, following the module rule.
  - `push_claim` and `push_release`: the server collects due pop-ups (marking them sent) and puts them back if no device took them.
  - A Supabase scheduled job (`clg-send-pop-ups`) checks every minute and calls the app only when a pop-up is waiting. It uses the same Vault values as the email sender (`clg_app_url`, `clg_cron_secret`), which are already saved.
- **App:** `src/lib/push.ts` (locks and sends each pop-up with the `web-push` library), `src/app/api/push/cron/route.ts` (the sender), `src/app/actions/push.ts` (turn on, turn off, remove, test), `src/components/push-settings.tsx` (the card and the dashboard note) and `public/sw.js` (the small background script that shows the pop-up and opens the page when tapped).
- **Adding another kind of notice later:** add a `union all` block to `private.push_due` that reads the new module's notice table, and add its name to the `push_sent.source` check. Keep the words generic.
- **Tests:** `supabase/tests/push_notifications.test.sql` (own devices only, nobody sees others' devices, shared device moves, only the server collects pop-ups, no repeats, quiet hours, read notices skipped, no names in the words, removed with the account).

### One-time setup (Carla)

1. Add three settings in Vercel (Project > Settings > Environment Variables, Production and Preview), then redeploy:
   - `NEXT_PUBLIC_VAPID_PUBLIC_KEY`: CLG's public pop-up key.
   - `VAPID_PRIVATE_KEY`: CLG's private pop-up key (secret).
   - `VAPID_SUBJECT`: `mailto:` followed by CLG's admin email address.
   The two keys are a matching pair made once. Never change them after people turn pop-ups on, or every device has to turn pop-ups on again.
2. Run `20261121500100_push_notifications.sql` in the Supabase SQL editor.

Until both are done, the card says pop-ups are not set up yet, and nothing else changes.

## Why (education research, and what other education apps do)

- **Timely, specific messages to families help learning.** The EEF's *Texting Parents* trial (Miller and others, 2016) found that short, regular messages to parents about upcoming tests, homework and what was being learned gave pupils about one month's additional progress in maths, at very low cost, and reduced absence. The EEF Teaching and Learning Toolkit rates parental engagement at about +4 months overall, and its guidance report *Working with Parents to Support Children's Learning* recommends communication that is specific, timely and easy to act on. A pop-up is the most timely channel the app has: a reminder or a "running late" notice is only useful if it is seen before the session.
- **Attendance.** Missed and late sessions are the biggest loss in one-to-one tuition (EEF rates one-to-one tuition at about +5 months when sessions happen regularly). Pop-up reminders before each session support the attendance the family terms rely on.
- **Not too many messages.** The same EEF work warns that too many or vague messages are ignored. That matches Carla's 2 Nov 2026 decision to keep day-to-day notices out of email. Pop-ups follow the same rule: only notices the app already shows, once each, no marketing, nothing in quiet hours, and the newest of a kind replaces the older one on screen instead of stacking up.
- **What other education apps do.** School and tutoring apps such as Compass (used by many Australian schools), Seesaw, ClassDojo and Google Classroom all use phone notifications for messages and reminders, let families turn them off per device, and keep the details inside the app. ClassDojo and Seesaw also offer quiet hours. CLG's design follows the same pattern, with stricter wording (no names at all) because CLG's notices are often about one named child. (Based on these apps' public help pages as generally described; check them again before quoting externally.)
- **Opt-in, not nudged.** Pop-ups are only asked for after a button press, with a clear **Not now**. This follows the UK Age Appropriate Design Code's standards on default settings and nudge techniques, which the Australian Children's Online Privacy Code is expected to mirror.

## How we will know it works

- How many active families, students and tutors have pop-ups on at least one device (count of `push_subscriptions` by role), aiming for most trial families by the end of the trial.
- Fewer late or missed sessions where the family had pop-ups on (from session records; Carla to judge during the trial).
- Time from a help chat reply to the family reading it, before and after pop-ups.
- Devices removed for repeated failures (server log), to catch problems with a particular browser.

## Legal notes

- **Privacy Act 1988 and the APPs.**
  - APP 3 and APP 11 (collect only what is needed, keep it secure): the app stores only each device's delivery address, its two keys, a device name such as "iPhone (Safari)" and dates. No location, contacts or phone number. Access is enforced in the database (row level security): a person sees only their own devices, admins cannot see them, and only the server can read the sent record. Rows are removed with the account, after 5 failed sends in a row, and when a person removes the device. Sent records go after 30 days.
  - APP 8 (overseas disclosure): pop-ups travel through the browser maker's push service (Apple, Google, Microsoft or Mozilla), which may be overseas. Each pop-up is locked (encrypted, to the web push standard RFC 8291) so only the person's own device can read it; the push service sees only the device address and the time. The words contain no personal details in any case. **Suggested privacy policy line for Carla to approve:** "If you turn on pop-up notifications, your browser's notification service (for example Apple, Google, Microsoft or Mozilla) delivers them to your device. These services may be outside Australia. Each pop-up is encrypted so only your device can read it, and pop-ups never include names or details, only the kind of notice."
  - Children's Online Privacy Code (being developed by the OAIC) and the UK Age Appropriate Design Code: pop-ups are off until the person turns them on, there is no repeated pressure (one note, with **Not now**), and nothing personal shows on a locked screen.
  - Sibling and family privacy: a pop-up goes only to the person the notice was already for, so it never tells anyone more than the app already would. Shared devices move to whoever turned pop-ups on last.
- **Child safety (SA child safe environments, Child Safe Policy):** safety concern pop-ups say only that a concern was sent, never who or what. Opening it still needs two-step sign-in.
- **Spam Act 2003:** these are service notices about the person's own sessions and messages, not marketing, and they can be turned off on each device at any time. Never use pop-ups for promotions without a separate opt-in.
- **UK and EU (later):** the device address counts as personal data under the UK and EU GDPR. Consent is given by the browser's permission prompt, and turning off is one tap, which fits the ePrivacy rules for device storage.

## Not built (could come later)

- Choosing which kinds of notice pop up (for now, all of the kinds above, or none on that device).
- Pop-ups for billing notices to tutors, check-ins, renewals ("Book again?") and the matching "Ask the family" notice. Each is one more block in `private.push_due`.
- A store app for iPhone and Android, which would not need the home screen step.
