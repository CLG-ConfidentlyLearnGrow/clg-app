// Summary: shows a university or TAFE student's degree and units.
//
// A university or TAFE student's degree and units: each unit's code, a link
// to the course page, and the overview CLG wrote. Shown to admins when
// matching and to the student's tutors. Admins also get a box to write the
// overview (pass overviewForm).
import type { ReactNode } from "react"; // The type for "anything that can be shown".

// One unit of study.
export type CourseUnit = {
  id: string; // Its id.
  subject: string; // Its name.
  course_code: string | null; // Its unit code, if known.
  course_url: string | null; // A link to its course page, if known.
  course_overview: string | null; // CLG's overview for the tutor, if written.
}; // End of the unit shape.

// Shows a student's degree and each unit's code, link and overview.
export function CourseDetails({
  program, // The degree or course name.
  units, // The units.
  overviewForm, // An optional form for admins to write each unit's overview.
}: { // The settings' types:
  program: string | null; // degree is text or nothing,
  units: CourseUnit[]; // units is a list of units,
  overviewForm?: (unit: CourseUnit) => ReactNode; // the form maker takes a unit and gives something to show.
}) { // End of the settings.
  const withDetails = units.filter((u) => u.course_code || u.course_url || u.course_overview || overviewForm); // Units with something to show (or a form to fill in).
  if (!program && withDetails.length === 0) return null; // Nothing to show at all: shows nothing.
  return ( // Shows:
    <div className="space-y-2">{/* a block with space between parts, */}
      {program && ( // if there's a degree:
        <p>{/* a line: */}
          <strong>Degree or course:</strong> {program}{/* saying "Degree or course:" and its name. */}
        </p> // End of the line.
      )}{/* End of the degree. */}
      {withDetails.length > 0 && ( // if any units have details:
        <ul className="space-y-2">{/* a list: */}
          {withDetails.map((u) => ( // for each unit:
            <li key={u.id} className="rounded-lg border border-zinc-200 bg-white p-2">{/* a small bordered box: */}
              <p className="font-medium">{/* a line in medium weight: */}
                {u.subject}{/* the unit's name, */}
                {u.course_code && <span className="font-normal text-zinc-600"> ({u.course_code})</span>}{/* and its code in brackets, if any. */}
              </p>{/* End of the line. */}
              {u.course_url && ( // if there's a course link:
                <p>{/* a line: */}
                  <a // a link:
                    href={u.course_url} // to the course page,
                    target="_blank" // opening in a new tab,
                    rel="noopener noreferrer nofollow" // safely (the other site can't control this page or see where it came from),
                    className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 break-all" // styled as a link that wraps long addresses.
                  >{/* (end of the link's settings) */}
                    Course page{/* The link's words. */}
                  </a>{/* End of the link. */}
                </p> // End of the line.
              )}{/* End of the course link. */}
              {u.course_overview && <p className="whitespace-pre-line">{u.course_overview}</p>}{/* The overview, keeping its line breaks, if any. */}
              {overviewForm?.(u)}{/* The admin's overview form, if given. */}
            </li> // End of the box.
          ))}{/* End of the units loop. */}
        </ul> // End of the list.
      )}{/* End of the units. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of CourseDetails.
