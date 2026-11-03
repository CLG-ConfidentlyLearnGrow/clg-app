// A university or TAFE student's degree and units: each unit's code, a link
// to the course page, and the overview CLG wrote. Shown to admins when
// matching and to the student's tutors. Admins also get a box to write the
// overview (pass overviewForm).
import type { ReactNode } from "react";

export type CourseUnit = {
  id: string;
  subject: string;
  course_code: string | null;
  course_url: string | null;
  course_overview: string | null;
};

export function CourseDetails({
  program,
  units,
  overviewForm,
}: {
  program: string | null;
  units: CourseUnit[];
  overviewForm?: (unit: CourseUnit) => ReactNode;
}) {
  const withDetails = units.filter((u) => u.course_code || u.course_url || u.course_overview || overviewForm);
  if (!program && withDetails.length === 0) return null;
  return (
    <div className="space-y-2">
      {program && (
        <p>
          <strong>Degree or course:</strong> {program}
        </p>
      )}
      {withDetails.length > 0 && (
        <ul className="space-y-2">
          {withDetails.map((u) => (
            <li key={u.id} className="rounded-lg border border-zinc-200 bg-white p-2">
              <p className="font-medium">
                {u.subject}
                {u.course_code && <span className="font-normal text-zinc-600"> ({u.course_code})</span>}
              </p>
              {u.course_url && (
                <p>
                  <a
                    href={u.course_url}
                    target="_blank"
                    rel="noopener noreferrer nofollow"
                    className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 break-all"
                  >
                    Course page
                  </a>
                </p>
              )}
              {u.course_overview && <p className="whitespace-pre-line">{u.course_overview}</p>}
              {overviewForm?.(u)}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
