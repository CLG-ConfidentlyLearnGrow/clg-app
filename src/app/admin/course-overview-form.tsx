// Summary: the admin form for writing a university or TAFE unit's overview.
//
"use client"; // Runs in the browser, so the form can show its result straight away.

import { setCourseOverview } from "@/app/actions/course"; // The server action that saves the overview.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { TextArea } from "@/components/ui"; // A larger text box.

// An admin writes or changes the overview of one university or TAFE unit.
export function CourseOverviewForm({ subjectId, overview }: { subjectId: string; overview: string | null }) {
  return ( // Shows:
    <details className="mt-1">{/* a section that opens when clicked: */}
      <summary className="cursor-pointer text-xs text-teal-800 underline">{/* its clickable heading: */}
        {overview ? "Change the overview" : "Write an overview for the tutor"}{/* "change" if there's an overview, otherwise "write". */}
      </summary>{/* End of the heading. */}
      <div className="mt-2">{/* A block with a little space above: */}
        <ActionForm action={setCourseOverview} submitLabel="Save overview">{/* a form that saves the overview: */}
          <input type="hidden" name="subject_id" value={subjectId} />{/* the unit's id (hidden), */}
          <TextArea // a text box:
            label="Course overview" // its label,
            name="overview" // its field name,
            rows={4} // four lines tall,
            maxLength={4000} // up to 4,000 characters,
            defaultValue={overview ?? ""} // starting with the current overview,
            hint="A few lines from the course page: what the unit covers, how it's assessed, and key dates. Leave blank to remove it." // and a hint about what to write.
          />{/* (end of the text box) */}
        </ActionForm>{/* End of the form. */}
      </div>{/* End of the block. */}
    </details> // End of the section.
  ); // End of what's shown.
} // End of CourseOverviewForm.
