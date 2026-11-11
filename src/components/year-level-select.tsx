// Summary: a drop-down list of year levels.
//
// The labelled drop-down list.
import { Select } from "@/components/ui";
// The year levels and the names families see.
import { YEAR_LEVELS, YEAR_LEVEL_NAMES } from "@/lib/students";

// Required: CLG uses the year level to match the right tutor. "optional"
// lets an admin leave it for the family to fill in.
export function YearLevelSelect({
  label = "Year level", // The words above the list ("Year level" by default).
  name = "year_level", // The form field's name ("year_level" by default).
  defaultValue = "", // The year chosen to start with (none by default).
  optional = false, // Whether it can be left blank (no by default).
}: { // The settings' types:
  label?: string; // words are text,
  name?: string; // name is text,
  defaultValue?: string; // starting choice is text,
  optional?: boolean; // optional is yes/no.
}) { // End of the settings.
  return ( // Shows:
    <Select label={label} name={name} defaultValue={defaultValue} required={!optional}>{/* the drop-down, required unless optional, */}
      <option value="" disabled={!optional}>{/* a blank first choice (can't be picked unless optional): */}
        {optional ? "Leave for the family" : "Choose…"}{/* saying "Leave for the family" or "Choose…". */}
      </option>{/* End of the blank choice. */}
      {YEAR_LEVELS.map((y) => ( // Then for each year level:
        <option key={y} value={y}>{/* a choice whose value is the year level, */}
          {YEAR_LEVEL_NAMES[y]}{/* showing the name families see. */}
        </option> // End of the choice.
      ))}{/* End of the loop. */}
    </Select> // End of the drop-down.
  ); // End of what's shown.
} // End of YearLevelSelect.
