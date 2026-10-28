import { Select } from "@/components/ui";
import { YEAR_LEVELS, YEAR_LEVEL_NAMES } from "@/lib/students";

// Required: CLG uses the year level to match the right tutor. "optional"
// lets an admin leave it for the family to fill in.
export function YearLevelSelect({
  label = "Year level",
  name = "year_level",
  defaultValue = "",
  optional = false,
}: {
  label?: string;
  name?: string;
  defaultValue?: string;
  optional?: boolean;
}) {
  return (
    <Select label={label} name={name} defaultValue={defaultValue} required={!optional}>
      <option value="" disabled={!optional}>
        {optional ? "Leave for the family" : "Choose…"}
      </option>
      {YEAR_LEVELS.map((y) => (
        <option key={y} value={y}>
          {YEAR_LEVEL_NAMES[y]}
        </option>
      ))}
    </Select>
  );
}
