import { NEEDS_REFERENCE, type CheckKind } from "@/lib/checks";

// How many years a check lasts from the date done, where it has a set life
// (matches private.check_life in the database).
const CHECK_LIFE_YEARS: Partial<Record<CheckKind, number>> = {
  rrhan_ec_fundamentals: 3,
  rrhan_ec_masterclass: 3,
  first_aid: 3,
};

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
  // Training with a set life: the expiry can be worked out from the date done.
  const life = CHECK_LIFE_YEARS[kind];
  if (!expiresOn && completedOn && life) {
    const expiry = new Date(completedOn);
    expiry.setFullYear(expiry.getFullYear() + life);
    const iso = expiry.toISOString().slice(0, 10);
    if (iso < today) return { error: "That certificate has already expired. Please renew it first." };
    return { expiresOn: iso };
  }
  if (!expiresOn) {
    return { error: life ? "Enter the date it was done or the date it expires." : "Enter the expiry date shown on the card." };
  }
  if (expiresOn < today) return { error: "That check has already expired." };
  return { expiresOn };
}
