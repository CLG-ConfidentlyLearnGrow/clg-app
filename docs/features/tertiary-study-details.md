# University and TAFE study details

Asked for by Carla on 3 November 2026.

## What it does

- A university or TAFE student (or adult learner) names each **unit** they
  want help with, instead of ticking school subjects. For each unit they can
  add the **unit code** (for example ENGC 3000) and a **link to the course
  page**.
- They can also add their **degree or course** overall (for example
  Bachelor of Engineering (Civil)(Honours)). Where they study goes in the
  existing "School, university or TAFE" box.
- An admin (owner, operations or support) can write a short **course
  overview** for each unit, from the course page: what it covers, how it is
  assessed, and key dates. Later this may be gathered automatically.
- The student's tutors and CLG admins see all of this on the student's page,
  under "What the family asked for", with the link opening the course page.
- Assessments and due dates already work for every student, including
  university and TAFE students: add an upcoming assessment on the student's
  roadmap and attach the task sheet and rubric.

## Why (research)

- The EEF's guidance on effective tutoring says tutoring works best when it
  is closely linked to what the learner is studying and the tutor knows the
  curriculum and level. For tertiary students there is no shared curriculum
  like the Australian Curriculum, so the unit outline is the curriculum: it
  sets the learning outcomes, assessments and due dates.
- Planning sessions around upcoming assessments is the tertiary equivalent
  of a school roadmap. Australia's Higher Education Standards Framework
  expects courses to set out learning outcomes and assessment, so unit
  outlines are a reliable public source for this.

## Legal notes

- Privacy Act (APP 3, collect only what is needed): unit, code and link are
  needed to plan tutoring; all three are optional. None is sensitive
  information.
- APP 6 (use only for the purpose): the details are only shown to the
  student's family, the student, their tutors and CLG admins, using the
  existing student access rules in the database.
- Links must start with http:// or https://, so a link can't run code when
  a tutor clicks it. Links open in a new tab and don't pass on the CLG page.
- Course overviews copy facts from public course pages in CLG's own words.
  Don't paste whole course outlines: they are usually the university's
  copyright.

## Where it lives

- Database: `supabase/migrations/20261103600100_tertiary_study_details.sql`
  (`students.program`; `student_subjects.course_code`, `course_url`,
  `course_overview`; `admin_set_course_overview`).
- Tests: `supabase/tests/tertiary_study_details.test.sql`.
- Forms: `src/components/subject-picker.tsx` switches to units when the year
  level is "University or TAFE" or "Adult learner".
- Saving: `src/lib/study-details.ts`. Showing: `src/components/course-details.tsx`.
