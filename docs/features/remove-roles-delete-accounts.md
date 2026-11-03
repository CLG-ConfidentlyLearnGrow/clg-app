# Removing a role, and deleting an account

Requested by Carla, 2026-11-02.

## What it does

- **Where:** Admin, "Records" section, "Remove a role or delete an account". Only the owner sees it. The owner enters the account's email, chooses what to do, and types the person's full name to confirm.
- **Removing a role** keeps the person's records under the usual keeping rules (the "timebomb"), so nothing is deleted early:
  - **Tutor:** tutor access ends today. They're marked as finished, any open assignments end, and their tutor records are deleted 7 years later. This is refused while they still have sessions booked, so move or cancel those first.
  - **Admin:** admin access ends. The owner can't remove their own admin role, or another owner's.
  - **Parent:** they stop seeing their children. Children with no other parent are kept, and deleted 2 years after their last activity.
  - **Student:** their login no longer opens the student record. The record is kept, and deleted 2 years after the last activity.
  - An account with no roles left is deleted after 12 months unused (the existing rule).
- **Deleting an account** removes the login straight away. An optional box also deletes their student records: their own, and children with no other parent. That box is meant for test accounts.
  - It is refused for the owner's own account, any owner account, an account with a hold, and an account with billing or session records CLG must keep. For those, remove the roles instead.

## Why (research)

- **Least privilege.** The Australian Cyber Security Centre's *Essential Eight* (restrict administrative privileges) and the OAIC's guidance on securing personal information both say access should end as soon as someone's role no longer needs it. Removing just the role a person no longer holds does that, without losing records CLG must keep.
- **Child safety.** The National Principles for Child Safe Organisations (Principle 1) and SA's child safe environment rules expect organisations to control who can reach children's information. A former tutor losing access the same day supports that.

## Legal notes

- **Keeping records:**
  - APP 11.2 says to destroy personal information once it's no longer needed.
  - Tax law (5 years) and child safety records (7 years for former tutors) say some records must be kept. Role removal follows the existing keeping rules for this.
  - Deletion is refused where billing or session records must be kept.
- **Access rules (database):** `admin_remove_role` and `admin_delete_account` work only for the owner with two-step login, and need the typed name. Every use is written to the activity log. Tests: `supabase/tests/remove_roles.test.sql`.
