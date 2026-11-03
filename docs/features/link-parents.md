# More than one parent per student, and double-ups

Requested by Carla, 2026-11-03. Migration `20261103620100_link_parents.sql`, tests in `supabase/tests/link_parents.test.sql`.

## What it does

- **Parents see their child straight away.** A child a parent adds is confirmed at once. There's no admin "confirm" step any more (Carla: it was unnecessary). The one exception is a possible double-up (below).
- **One profile per child.** The Add a child form tells parents: if another parent or guardian has already added this child, don't add them again; contact CLG to be linked instead.
- **Link another parent or guardian (admin).** Admin, "Families and matching", "Link another parent or guardian". Choose the student, enter the adult's email, and choose parent, guardian, carer or other.
  - If the email already has a CLG account (for example a tutor who is also a parent), that account is used and given the parent role.
  - If not, an account is made and the adult gets a link to choose a password, the same as "Set up a family".
  - "Can change details and bookings" can be unticked for an adult who should only see progress, for example where a court order limits a parent.
- **Parents of each student (admin).** Lists everyone linked to each student. A link made by mistake can be removed. The last adult who can manage a child without their own login can't be removed.
- **Possible double-ups (admin).** Students with the same name (ignoring capitals and spaces), and the same date of birth or one missing, are listed. The new parent's link waits until CLG decides. Parents are never told that another family has a child with that name, for privacy.
  - **Same child: merge.** Every parent is linked to the kept profile, subjects and parental consent move across, missing details are filled in, and the other profile is deleted. The older profile is kept by default; there's also a button to keep the newer one.
  - To keep history safe, a profile that already has a tutor, bookings, progress notes, invoices or anything else can't be the one deleted. Keep that one instead.
  - **Different children.** The pair stops showing and the waiting link is confirmed.

## Who can do this

Owner, operations and support admins, with two-step login. Checked in the database (row level security and function checks), not only on screen.

## Research

- Family engagement is one of the strongest levers on learning when it is about the child's learning, and both parents' involvement counts: EEF, *Working with Parents to Support Children's Learning* (2021) recommends making it easy for every parent to stay informed. One shared profile means every parent gets the same progress updates.
- AERO's guidance on family–school partnerships stresses consistent, two-way communication with all carers.

## Legal notes

- **Privacy Act 1988 (APP 6, APP 11) and the Children's Online Privacy Code:** a child's details are only shown to adults CLG has linked. Double-up checks never reveal one family's child to another family.
- **Family law:** separated parents usually both have the right to information about their child unless a court order says otherwise. The "can only see" option and removing a link cover court orders; CLG should ask for a copy of any order.
- **Child safety (SA Child Safe Environments):** a double-up is held for CLG to check, because a second adult adding a child could be someone who shouldn't have access. Check with the known parent before merging if unsure.
- **UK and EU (GDPR):** data minimisation is helped by keeping one record per child instead of copies.
