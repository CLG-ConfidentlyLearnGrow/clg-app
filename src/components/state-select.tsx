// Summary: a drop-down list of Australian states.
//
// The labelled drop-down list.
import { Select } from "@/components/ui";
// The state codes and their full names.
import { STATES, STATE_NAMES } from "@/lib/checks";

// "optional" adds a "Leave for the family" choice (admin family setup).
export function StateSelect({
  label = "State", // The words above the list ("State" by default).
  name = "state", // The form field's name ("state" by default).
  defaultValue = "SA", // The state chosen to start with (SA by default).
  optional = false, // Whether it can be left blank (no by default).
}: { // The settings' types:
  label?: string; // words are text,
  name?: string; // name is text,
  defaultValue?: string; // starting choice is text,
  optional?: boolean; // optional is yes/no.
}) { // End of the settings.
  return ( // Shows:
    <Select label={label} name={name} defaultValue={optional ? "" : defaultValue} required={!optional}>{/* the drop-down: blank to start if optional, and required unless optional, */}
      {optional && <option value="">Leave for the family</option>}{/* a "Leave for the family" choice if optional, */}
      {STATES.map((s) => ( // then for each state:
        <option key={s} value={s}>{/* a choice whose value is the state code, */}
          {STATE_NAMES[s]}{/* showing its full name. */}
        </option> // End of the choice.
      ))}{/* End of the loop. */}
    </Select> // End of the drop-down.
  ); // End of what's shown.
} // End of StateSelect.
