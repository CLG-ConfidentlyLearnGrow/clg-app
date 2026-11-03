"use client";

import { setCourseOverview } from "@/app/actions/course";
import { ActionForm } from "@/components/action-form";
import { TextArea } from "@/components/ui";

// An admin writes or changes the overview of one university or TAFE unit.
export function CourseOverviewForm({ subjectId, overview }: { subjectId: string; overview: string | null }) {
  return (
    <details className="mt-1">
      <summary className="cursor-pointer text-xs text-teal-800 underline">
        {overview ? "Change the overview" : "Write an overview for the tutor"}
      </summary>
      <div className="mt-2">
        <ActionForm action={setCourseOverview} submitLabel="Save overview">
          <input type="hidden" name="subject_id" value={subjectId} />
          <TextArea
            label="Course overview"
            name="overview"
            rows={4}
            maxLength={4000}
            defaultValue={overview ?? ""}
            hint="A few lines from the course page: what the unit covers, how it's assessed, and key dates. Leave blank to remove it."
          />
        </ActionForm>
      </div>
    </details>
  );
}
