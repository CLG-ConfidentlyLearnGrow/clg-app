# CLG App

CLG Tutoring's app: one place for tutors, admins, parents and students, with lessons, homework, assessments, progress tracking and programs added as modules on a secure base.

This first version is the base: accounts, roles, families, tutor assignments, the access rules, sign-up and login, two-step login, account lock, audit log and tutor child safety checks. The plan behind it is the [CLG App foundation plan](https://claude.ai/artifact/5nWGE5ciMxGMVrTSnJTTKy).

## How it's built

| Part | Tool |
| --- | --- |
| App | Next.js 16 (TypeScript), hosted on Vercel in Sydney (`vercel.json`) |
| Database, logins, files | Supabase (Postgres), Sydney region |
| Access rules | Postgres row level security, in `supabase/migrations` |

## Who can see what

The database enforces these rules, so a bug in a screen can't leak another family's data.

- **Parents** see their own children and the tutors currently assigned to them.
- **Tutors** see only students they are currently assigned to, and only while their Working With Children Check and RRHAN-EC Fundamentals and Masterclass are verified and in date. If one expires, their access stops until an admin records a new one.
- **Students 15 and over** can have their own login. Under-15s use their parent's account (OAIC guidance presumes under-15s can't make their own privacy decisions).
- **Admins** see everything, and the owner manages other admins.
- Admins and tutors must sign in with **two-step login**. Without it, the database gives them no extra access.
- Contact details are only visible to the person themselves and admins. Tutors and families see each other's names, never emails or phone numbers.
- Learning needs are read and saved only through functions that record every view and change in the **audit log**. The log stores ids and changed column names, never the content, and nobody can edit or delete it.
- **Sign-up is open** to parents and adult learners (18+). A new account sees nothing beyond its own profile until an admin confirms a parent link or a paid enrolment is added. Tutors and admins join only by invitation.
- **Account lock:** 5 failed sign-ins within 15 minutes locks the account for 30 minutes. A password reset or an admin unlocks it.

## Setting up Supabase (once)

1. Create a Supabase project in the **Sydney** region.
2. Apply the database: install the [Supabase CLI](https://supabase.com/docs/guides/cli), run `supabase link`, then `supabase db push`.
3. In **Authentication > Sign In / Providers > Email**: turn on "Confirm email" and "Secure password change". Set the minimum password length to 12 with lower, upper case and digits. Turn on leaked password protection if your plan includes it.
4. In **Authentication > Multi-Factor**: turn on TOTP (authenticator app).
5. In **Authentication > URL Configuration**: set the Site URL to the app's address, and add `<site>/auth/confirm` as a redirect URL.
6. In **Authentication > Emails**: copy the three templates from `supabase/templates` into Confirm signup, Invite user and Reset password.
7. In **Authentication > Sessions** (paid plans): set an inactivity timeout of 8 hours.
8. Create the owner account. In the SQL editor run:
   `select private.create_owner_invitation('owner@example.com');`
   then invite that email from **Authentication > Users > Invite user**. The owner sets a password, then sets up two-step login.

## Setting up Vercel (once)

Import the GitHub repository into Vercel and add the variables from `.env.example`. `SUPABASE_SECRET_KEY` must only ever be set as a server environment variable.

## Working on the app

```bash
npm install
cp .env.example .env.local   # then fill in the values
npm run dev                  # http://localhost:3000
npm run lint
npm run typecheck
npm run test:db              # migrations + access-rule tests on a throwaway local Postgres
```

`npm run test:db` needs Postgres 15 or later installed locally (`initdb`, `pg_ctl`, `psql`). The tests sign in as each kind of person and check exactly what they can and can't see or change. Run it for every database change.

## Adding a feature module

Each feature (lessons, homework, assessments, progress, programs) gets:

1. A short research brief in `docs/features/`, naming the evidence it relies on (Evidence for Learning, AERO, EEF) and how its impact will be measured.
2. Its own migration, with tables that point at `students` and `tutor_assignments` so they inherit the access rules, plus tests in `supabase/tests`.
3. A note of which privacy and child safety rules it touches.

Modules read the shared core (people, links, subjects, calendar) and never change another module's tables directly.
