# Removing unused code (20 Nov 2026)

Carla asked for code that is no longer used to be deleted, to keep the app lean.

## What was checked

- Every exported function, component and value in `src/` was traced with the TypeScript tool to find anything nothing else uses.
- Every npm package in `package.json` was searched for in the code.
- Every picture in `public/` was searched for in the code, the email templates and the git history.
- Every database function still in place after all migrations was searched for in the app code, other migrations, triggers and scheduled jobs.

## What was removed

- App code: the old "Assign tutor" form and its server action (tutors are matched on the Matching page now), and three unused values (`STUDENT_SECTIONS`, `PrivacyRequestKind`, `FAMILY_NOTE_PROMISE_HOURS`).
- Pictures: `clg-book.png`, `clg-logo.png` and `clg-logo-tagline.png` in `public/brand/` (never used in emails; the originals are still in the project brand folder).
- Database (migration `20261122400100_remove_unused_functions.sql`): `list_matching`, `matching_pipeline`, `count_booking_sessions`, `queue_monthly_summaries` and `monthly_summary_text`.

## What was kept on purpose

- All npm packages: each one is used.
- The session, progress and billing email "claim" functions: kept on 3 Nov 2026 so notice emails can be turned back on with a code change only.
- `read_student_sensitive`, `save_student_sensitive`, `withdraw_consent` and `create_owner_invitation`: not called by the app today, but they guard children's data, consent, or first set-up, so they need Carla's decision before removal.

## Legal rules touched

None. No stored information is deleted; only code and functions nothing calls.
