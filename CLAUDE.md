# CLG App: working rules

@AGENTS.md

- CLG is based in South Australia (Australia), planning to go international. Design to Australian law first (Privacy Act and APPs, Children's Online Privacy Code, SA child safety rules, WWCC, RRHAN-EC; police check and first aid are optional records); keep UK and EU rules in mind.
- The app holds children's data. Access rules live in the database (row level security), not only in the UI. Every change to tables or rules needs tests in `supabase/tests` and `npm run test:db` passing.
- Every feature starts with a research brief in `docs/features/` grounded in education research (Evidence for Learning, AERO, EEF), and a note of the legal rules it touches.
- Keep features as modules on the shared core. A module never writes another module's tables.
- Write for a non-specialist owner: plain comments, plain error messages.
- Comment every line of code (Carla, 11 Nov 2026). Each line gets a plain-English comment saying what it does and why. Each section (file, function, component, SQL block) starts with a summary comment explaining its purpose. Write so anyone can follow it. This applies to all new and changed code, including tests and migrations. Migrations Carla has already run are left as they are.
