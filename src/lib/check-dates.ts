import { NEEDS_REFERENCE, type CheckKind } from "@/lib/checks";

// Works out a check's expiry and spots common mistakes, in plain words.
// A police check counts for 5 years from the date it was issued.
export function checkDates(
  kind: CheckKind,
  reference: string | undefined,
  completedOn: string | undefined,
  expiresOn: string | undefined,
): { expiresOn: string } | { error: string } {
  if (NEEDS_REFERENCE.has(kind) && !reference) return { error: "Enter the card or registration number." };
  const today = new Date().toISOString().slice(0, 10);
  if (completedOn && completedOn > today) return { error: "The date done can't be in the future." };

  if (kind === "police_check") {
    if (!completedOn) return { error: "Enter the date the police check was issued." };
    const expiry = new Date(completedOn);
    expiry.setFullYear(expiry.getFullYear() + 5);
    const iso = expiry.toISOString().slice(0, 10);
    if (iso < today) return { error: "That police check is more than 5 years old. A new one is needed." };
    return { expiresOn: iso };
  }
  if (!expiresOn) return { error: "Enter the expiry or renewal date." };
  if (expiresOn < today) return { error: "That check has already expired." };
  return { expiresOn };
}
