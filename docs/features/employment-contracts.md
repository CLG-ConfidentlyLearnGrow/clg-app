# Employment contracts (send, sign and acknowledge in the app)

Requested by Carla, 17 Nov 2026: "Please ensure things like [Tutor name] can
be auto filled, and what can't be auto filled can be filled in by writing in
the needed information from an admin standpoint within the app then sent to
them. Rather than having to actually edit each contract. It would be great if
there was an ability to have an auto Xero employee fill in link sent to the
email in which is connected to the CLG app once the contract is accepted."

## What it is for

- **One place for staff contracts.** Every tutor must agree to the new
  contract to keep tutoring in 2027, and CLG plans to grow from 5 to 20+
  tutors within a year. Editing and emailing a Word document for each person
  does not scale and makes it hard to prove who signed what.
- **Fill in once, send in minutes.** Templates hold the wording. Gaps such
  as [Tutor name] fill in by themselves; an admin types the rest (start date,
  award levels, rates) and sends it.
- **A clear record.** The exact wording sent is kept with a fingerprint
  (SHA-256), with when and how it was signed, and when each linked document
  was acknowledged.
- **Straight into payroll.** Once signed, the app prompts an admin to send
  Xero's employee self-setup invite, so the new staff member enters their own
  tax, bank and super details.
- **Templates per kind of contract.** Tutor casual and tutor part-time or
  full-time now; admin-only staff contracts can be added later as their own
  kinds without changing the app.

## What the evidence says

- **Well-supported tutors get better results.** The EEF's guidance on
  tutoring (*Making a difference with effective tutoring*, 2021,
  https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/tutoring)
  stresses that tutoring works best when tutors are well trained, supported
  and clear on what is expected of them. A contract that states duties
  (session summaries, preparation, notice, child safety) plainly, and that
  every tutor has read and accepted, is part of that support.
- **Stable tutors matter for learners.** Evidence for Learning's Toolkit
  entry on one-to-one tuition
  (https://evidenceforlearning.org.au/education-evidence/teaching-learning-toolkit/one-to-one-tuition)
  links impact to regular, consistent sessions. Clear notice periods and
  expectations in the contract support the steady tutor-learner
  relationships that make tutoring work.
- **Child safe organisations set clear expectations for staff.** The
  National Principles for Child Safe Organisations, Principle 5
  (https://childsafe.humanrights.gov.au/national-principles), expect staff to
  understand and agree to the organisation's code of conduct and child safe
  policy. Here each staff member acknowledges the Child Safe Policy and Staff
  Code of Conduct separately, with their typed name and the date, after
  signing.

## How it works

1. **Templates (owner only).** Open **Contracts**, then **Contract templates
   and document links**. Paste the wording from the contract's Claude Doc
   (Export, then Markdown). Gaps are written in square brackets, as in the
   documents, for example [Start date], or in double curly brackets. The
   editor lists every gap found and how it is filled. A gap ending
   ", or Not applicable" (or any ", or ..." words) may be left empty and then
   shows those words. Gaps with the same words always get the same value, so
   gaps that need different values need different words (for example
   [School tutoring rate] and [Tertiary tutoring rate, or Not applicable]).
   Save as a draft, check the preview, then publish. A published version never
   changes: editing it starts the next version as a draft. Contracts already
   sent keep their own wording.
2. **Gaps that fill in by themselves:** [Tutor name] (also [Staff name],
   [Employee name], [Full name]), [First name], [Last name], [Tutor email]
   (also [Email], [Staff email], [App email]), [Phone], [Employment type]
   (also [Full-time or Part-time]), [Date sent], [CLG name], [CLG ABN] and
   [CLG signatory].
3. **Sending (owner and Operations admins).** Choose the contract, the staff
   member (only people with the matching role are listed) and the employment
   type, fill in the remaining gaps, and send. The database refuses to send
   while a required gap is empty, and names the empty gaps. Sending a new
   contract to someone with one still waiting withdraws the old one. The
   staff member is emailed a link (and links to the documents they will
   acknowledge), and a card on their dashboard asks them to sign.
4. **Signing (the staff member).** They read the contract in the app, tick
   that they have read it and agree, tick that they agree to sign
   electronically, type their full name and press **Sign and accept**. The
   pay notice ("accepting pay is also acceptance of the terms") is shown
   right above the boxes, and the record notes that it was shown.
5. **Acknowledgements.** After signing they open and acknowledge, one by one
   with their typed name: the Fair Work Information Statement, the Casual
   Employment Information Statement (casual staff only), the CLG Child Safe
   Policy and the CLG Staff Code of Conduct. The contract is then complete.
   The owner can change each document's name and link (for example when the
   policies move into the app); each acknowledgement keeps the name and link
   it was given.
6. **Xero self-setup.** Xero Payroll Australia added "Invite to
   self-onboard" in March 2026, but it can only be started inside Xero (no
   public API). So once a contract is signed, the contract page shows the
   steps and the name and email to use, and the admin presses **I have sent
   the Xero invite**. The **Contracts** menu number counts signed contracts
   still needing this step.
7. **Pay evidence.** The contract page shows how many pay lines have been sent
   to Xero for that person since the contract was sent, and the first work
   day paid. This backs up clause 2.12 (casual) and 2.13 (part-time and
   full-time): accepting pay is further acceptance of the contract.

## Legal notes

- **Electronic signature.** Australian law lets an employment contract be
  signed electronically. The Electronic Transactions Act 1999 (Cth) s 10 and
  the Electronic Communications Act 2000 (SA) s 9 need a method that
  identifies the person and shows their intention, that is as reliable as
  appropriate, and that the other party consents to. The app uses: their own
  account with two-step login (required to sign), their typed full name
  matching their account name, a tick to agree to the terms, a separate tick
  to agree to sign electronically, the date and time, and a fingerprint of
  the exact wording. Sending the contract is CLG's side of the agreement
  (the sender and time are recorded; the wording names Carla Gore, Director,
  as signing for CLG). No witness or wet signature is needed for an
  employment contract. Lawyer to confirm as part of the contract review.
- **Fair Work Information Statement** (Fair Work Act 2009 s 125): must be
  given to every new employee before, or as soon as possible after, they
  start. Fair Work lists "by emailing a link to our website" as an accepted
  way to give it
  (https://www.fairwork.gov.au/employee-entitlements/national-employment-standards/fair-work-information-statement).
  The app emails and shows the official Fair Work link, and records the
  acknowledgement.
- **Casual Employment Information Statement** (s 125B): must be given to every
  new casual employee at the same time; a link is accepted; it need not be
  given more than once in 12 months. The 2024 casual employment changes may
  also require giving it again later in employment (for example after 12
  months); the lawyer is to confirm when. This is not automated yet; see
  "Later".
- **Records.** Fair Work Regulations 2009 reg 3.31 to 3.44: employee records
  are kept for 7 years. Contracts and acknowledgements are never deleted by
  the app; if an account is ever deleted, the contract keeps the name and
  email it was sent to. They are only visible to the staff member and to the
  owner, Operations and Finance admins (row level security, two-step login).
- **Privacy (APP 11).** Contracts hold staff names, emails and pay details, so
  only the people above can read them. Every change is written to the shared
  change log.

## Access rules (database)

| Who | Templates | Send / withdraw | See contracts | Xero step | Sign / acknowledge |
| --- | --- | --- | --- | --- | --- |
| Owner | Write, publish, change document links | Yes | All | Yes | Their own |
| Operations | Read | Yes | All | Yes | Their own |
| Finance | Read | No | All | Yes | Their own |
| Support | No | No | No (only their own) | No | Their own |
| Tutor | No | No | Their own | No | Their own |

## Files

- Database: `supabase/migrations/20261121200100_employment_contracts.sql`
- Tests: `supabase/tests/employment_contracts.test.sql`
- Admin pages: `src/app/admin/contracts/` (list, send, contract record,
  templates)
- Staff page: `src/app/contract/` (read, sign, acknowledge)
- Shared words and gap reader: `src/lib/employment-contracts.ts`
- Contract wording display: `src/components/contract-text.tsx`
- Dashboard card: `src/components/contract-prompt.tsx`

## Later

- Remind admins to give the Casual Employment Information Statement again
  when the law requires (timing to be confirmed by the lawyer).
- Admin-only staff contract templates (the kinds already exist).
- Move the Child Safe Policy and Staff Code of Conduct links to app pages
  once those pages exist (change the links on the templates page).
- Optionally block tutor matching in 2027 until the new contract is signed.
