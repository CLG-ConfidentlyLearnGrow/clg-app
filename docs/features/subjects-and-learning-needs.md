# Subjects by year level, learning needs, and sign-up wording

Requested by Carla, 2026-11-02.

## What changed

- **Subjects follow the year level.** Forms show the list that suits the student's school year, A to Z:
  - **Foundation to Year 10 (Australian Curriculum):** Digital Technologies, Economics and Business, English, Humanities and Social Sciences, Mathematics, Science, Study skills.
  - **Years 11 and 12 (SACE):** Activating Identities and Futures (AIF) / Research Project, Biology, Chemistry, Digital Technologies, Economics and Business, English, Mathematics: Essential, Mathematics: General, Mathematics: Methods, Mathematics: Specialist, Physics, Psychology, Study skills.
  - **University, TAFE, adult learners, or year not given yet:** every subject.
  - **Removed from the list:** Numeracy (covered by Mathematics), Literacy (covered by English), English Literary Studies, Essential English, Geography and History. Families can still type another subject.
- **Maths rules.** "Maths" on its own is refused. "Mathematics" is for Foundation to Year 10. Year 11 and above choose one of the four SACE maths subjects. These rules are checked in the forms and in the database. Existing entries using the old names (General, Essential or Advanced Maths) are left as they are, for CLG to tidy.
- **Learning needs.** There's a new, optional box on the add-child and edit-child forms, and in "Set up a family", where families describe learning needs in their own words. Admins see it, with the school year and the working level in each subject, when assigning a tutor.
- **"Who is the account for?"** The wording now says to use the parent option for most students under 18, including those 16 or over.
- **Agreement page.** The page no longer says families can change the details CLG entered. It now has an optional, unticked "Send me CLG news and offers" box, which is separate from agreeing to the policy.

## Why (research)

- **Matching on curriculum level.** The EEF Toolkit finds one-to-one tuition (about +5 months) works best when it is closely linked to the learner's classroom curriculum and current level. Using the right curriculum names (AC9 for F–10, SACE for 11–12) lets the app attach the right curriculum automatically and match tutors who teach that exact subject.
- **Knowing learning needs early.** The EEF guidance report *Special Educational Needs in Mainstream Schools* (2020) recommends building an accurate, holistic understanding of each pupil's needs, in partnership with parents. A plain-language box gives tutors that before the first session.

## Legal notes

- **Learning needs can include health information,** which is sensitive information under the Privacy Act (APP 3.3). It is collected only when the family chooses to write it, after the privacy notice. The existing student rules in the database decide who can see it: CLG admins, the student's parents, the student, and their assigned tutors. Tests: `supabase/tests/learning_needs.test.sql`.
- **Marketing consent** stays separate and unticked (Spam Act 2003; Privacy Act APP 7). Ticking it uses the same record as "Your privacy".
- **Database rules:** `20261102600100_subjects_by_year.sql` (maths rules, curriculum name matching) and `20261102600200_learning_needs.sql`. Tests are in `supabase/tests/support_requests.test.sql` and `tutor_teaching.test.sql`.
