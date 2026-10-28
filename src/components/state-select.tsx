import { Select } from "@/components/ui";
import { STATES, STATE_NAMES } from "@/lib/checks";

// "optional" adds a "Leave for the family" choice (admin family setup).
export function StateSelect({
  label = "State",
  name = "state",
  defaultValue = "SA",
  optional = false,
}: {
  label?: string;
  name?: string;
  defaultValue?: string;
  optional?: boolean;
}) {
  return (
    <Select label={label} name={name} defaultValue={optional ? "" : defaultValue} required={!optional}>
      {optional && <option value="">Leave for the family</option>}
      {STATES.map((s) => (
        <option key={s} value={s}>
          {STATE_NAMES[s]}
        </option>
      ))}
    </Select>
  );
}
