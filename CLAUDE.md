# CLG App: working rules

@AGENTS.md

- CLG is based in South Australia (Australia), planning to go international. Design to Australian law first (Privacy Act and APPs, Children's Online Privacy Code, SA child safety rules, WWCC, RRHAN-EC, police check within 5 years); keep UK and EU rules in mind.
- The app holds children's data. Access rules live in the database (row level security), not only in the UI. Every change to tables or rules needs tests in `supabase/tests` and `npm run test:db` passing.
- Every feature starts with a research brief in `docs/features/` grounded in education research (Evidence for Learning, AERO, EEF), and a note of the legal rules it touches.
- Keep features as modules on the shared core. A module never writes another module's tables.
- Write for a non-specialist owner: plain comments, plain error messages.
