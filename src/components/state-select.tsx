import { Select } from "@/components/ui";
import { STATES, STATE_NAMES } from "@/lib/checks";

export function StateSelect({ label = "State", name = "state" }: { label?: string; name?: string }) {
  return (
    <Select label={label} name={name} defaultValue="SA" required>
      {STATES.map((s) => (
        <option key={s} value={s}>
          {STATE_NAMES[s]}
        </option>
      ))}
    </Select>
  );
}
