# Privacy laws baseline (six regions)

Requested by Carla, 2026-11-02: "ensure that all security of the app passes
the legal requirements for Australia, US, Canada, Europe, UK, and New
Zealand. This needs to be a base for it."

**Not legal advice.** Carla is CLG's interim legal adviser. A privacy lawyer
must review this, the privacy notice and the app before CLG serves any family
outside Australia. Full plain-English checklist (Claude Doc):
https://claude.ai/artifact/VnnkUbPAfuxRm3MAhFQpPt

## What it's for

CLG holds children's names, schools, learning notes and family contact
details, and plans to work overseas. Instead of a different app per country,
the app meets one baseline: wherever the six regions differ, the strictest
rule wins.

## What the evidence and the law say

This is a legal feature, so most of the evidence is the law itself:

- **Australia**: Privacy Act 1988 and APPs 1, 5, 7, 8, 11, 12, 13; the
  Notifiable Data Breaches scheme (assess within 30 days); Privacy and Other
  Legislation Amendment Act 2024 (automated decisions in the privacy policy
  from 10 December 2026); OAIC's draft Children's Online Privacy Code
  (released 31 March 2026, to be registered by 10 December 2026: parental
  consent under 15, consent lasts at most 12 months, not bundled or
  pre-ticked, best interests of the child, deletion on request).
- **New Zealand**: Privacy Act 2020 (access answered within 20 working
  days, breach notice "as soon as practicable"); IPP 3A from 1 May 2026
  (tell people when their information came from someone else).
- **UK**: UK GDPR, Data Protection Act 2018, Data (Use and Access) Act 2025
  (complaints to the organisation, acknowledged within 30 days, from 19 June
  2026), ICO Age Appropriate Design Code.
- **EU**: GDPR Articles 8, 12 to 22, 30, 32 to 35 (1 month to answer, 72 hr
  to tell the regulator about a breach).
- **Canada**: PIPEDA (keep every breach record 24 months), Quebec Law 25,
  CASL (express consent for marketing email).
- **US**: COPPA (amended rule in force 22 April 2026: verifiable parental
  consent under 13, written security program, published retention policy),
  state student-privacy laws such as SOPIPA (no selling, profiling or ads),
  state breach laws.

Education research: the EEF guidance report *Working with Parents to Support
Children's Learning* (2021) and Evidence for Learning's Australian edition
find that parental engagement works best when schools and services build
trust and make information easy for parents to see and act on. A clear
"Your privacy" page, a once-a-year consent check and plain answers to
requests support that trust without adding work for busy parents (one tick
per child per year). https://educationendowmentfoundation.org.uk/education-evidence/guidance-reports/supporting-parents

## How the design follows it (the strictest rule)

| Rule | Strictest source | What the app does |
| --- | --- | --- |
| Answer privacy requests | NZ 20 working days, EU/UK 1 month | Due 28 days after it arrives; one extension with a reason, within 90 days |
| Complaints | UK: acknowledge within 30 days | Complaint is a request type; saving any update marks it acknowledged |
| Access and portability | GDPR Art. 15 and 20 | "Download your information" JSON file, using the person's own access rules |
| Breach decision | EU/UK 72 hr | Breach register shows the 72-hr deadline and flags it when overdue |
| Breach assessment | Australia 30 days | Second deadline shown; regulators per region linked |
| Breach records | Canada: all breaches, 24 months | Every suspected breach recorded; kept 7 years; can't be deleted or changed once closed |
| Parental consent | Draft AU children's code, COPPA, GDPR Art. 8 | Separate tick per child, never pre-ticked, renewed every 12 months |
| Own login | GDPR highest age of consent (16) | Unchanged: students log in alone from 16 |
| Marketing email | CASL, GDPR, Spam Act | Off unless the person turns it on |
| Notice | APP 5, GDPR 13/14, IPP 3A, Law 25, COPPA | New privacy page: children's summary, overseas services, automated decisions, retention, rights, regulators |
| Location | ICO code (location off by default) | Only tutors, asked each time; browser rule now allows it only for the app itself |

Also fixed: the browser rule from PR #52 blocked location completely, which
stopped tutors' location sign-on for in-person sessions. It now allows
location for the app only (`geolocation=(self)`).

## How we'll know it works

- Every request in the admin privacy page is closed before its due date.
- Every breach has a decision recorded within 72 hr of being found.
- No parent reaches their dashboard without a current consent for each child.

## Privacy and child safety

- Requests hold the person's words, kept 7 years after closing, readable by
  the person and by owner and operations admins only. Support and finance
  admins see nothing.
- Breach records: owner and operations admins only. The time found can't be
  changed, so the clocks can't be reset.
- The download runs with the person's own access rules: it cannot show
  anything the app would not already show them. Each download is logged.
- Migration: `supabase/migrations/20261102000100_privacy_rights.sql`
  (safe to run twice). Tests: `supabase/tests/privacy_rights.test.sql`.
