# "Family" profile (20 Nov 2026)

Carla chose to rename the "Parent" profile to "Family" everywhere people read it. Her condition: an adult learner who pays for themselves must be able to do everything from their Student profile, with no Family profile.

## What changed for people

- The dashboard tab, dashboard name and phone menu button now say **Family**, **Family dashboard** and **Family menu**.
- Sign-up offers **A family (a parent or carer)** or **A student aged 16 or over, or an adult learner**.
- Staff screens (Staff directory, Remove a role, Family set-up) say **Family** for the role.
- The App guides and app tour use the new names. The parent guide is now **App guide for families**, and the student guide says an adult learner pays from the Student dashboard.
- The database's own messages that name the role were updated (for example "Only someone with a Family profile can add a child").

## Self-paying adult learners

Billing works per family. A student who signed up on their own, was set up by an admin as "a student with their own login", or used "Become a learner", was saved with no family, so they never got a Billing tab, could not choose a plan, agree to the payment terms or pay, and no invoice could be made for them.

Migration `20261122870100_family_profile_adult_learner_billing.sql` fixes this:

- Every new student with their own login and no family is put in one straight away: the family their own children are in (a parent who becomes a learner keeps one household bill), or a new family of their own.
- Every existing student with their own login and no family is given one the same way.

Who may pay is unchanged (see `billing-only-payers.md`): an adult learner aged 18 or over who is the only learner in their family, with no parent linked, may choose the plan or agree to the terms, which makes them the bill payer. A student aged 16 or 17 with no parent on the account cannot start payments themselves; CLG names the bill payer on Admin > Billing.

## Kept as it is, on purpose

- The internal role name (`parent`), page addresses (`/dashboard/parent`) and colour names stay the same. Changing them would touch every access rule and link for no change people can see, which goes against keeping the app efficient.
- Wording about a real parent or guardian stays, for example "I am this child's parent or legal guardian", "Your parent or carer can see your roadmap" and the training content about talking with parents. These describe the person, not the profile.

## Research

- The EEF guidance report *Working with Parents to Support Children's Learning* (2018) finds that how a service talks to and with families shapes how much they take part; plain, consistent naming lowers the effort of using a service. "Family" matches how CLG already talks about the household (family terms, family calendar, family billing).
- AERO's work on family and school partnerships describes the family, not only the parent, as the partner in a child's learning, which includes carers, kinship carers and older siblings who manage a child's support.
- Evidence for Learning's *Parental engagement* Toolkit strand reports the strongest effects when families support habits at home; the Family dashboard keeps the tip for home and the roadmap, unchanged.

## Legal rules touched

- **Privacy Act 1988 and the APPs, and the Children's Online Privacy Code:** consent for a child's information must come from a parent or guardian. The consent wording keeps "parent or legal guardian", so the meaning in law is unchanged. The profile name is only a label.
- **Contracts with minors (SA):** only an adult (18 or over) can start a family's payments, as before.
- **Child safety (SA):** no change to who can see a child's information; access rules are the same.
- No stored information is deleted. Students given a new family see only their own records, as before.
