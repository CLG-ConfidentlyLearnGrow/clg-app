import { Select } from "@/components/ui";
import { YEAR_LEVELS, YEAR_LEVEL_NAMES } from "@/lib/students";

// Required: CLG uses the year level to match the right tutor.
export function YearLevelSelect({ label = "Year level", name = "year_level" }: { label?: string; name?: string }) {
  return (
    <Select label={label} name={name} defaultValue="" required>
      <option value="" disabled>
        Choose…
      </option>
      {YEAR_LEVELS.map((y) => (
        <option key={y} value={y}>
          {YEAR_LEVEL_NAMES[y]}
        </option>
      ))}
    </Select>
  );
}
