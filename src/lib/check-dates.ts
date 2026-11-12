// Summary: works out when a tutor's child safety check or certificate
// expires, and catches common mistakes (future dates, expired checks,
// missing card numbers) with plain-English messages.

// The list of checks needing a card number, and the names of check kinds.
import { NEEDS_REFERENCE, type CheckKind } from "@/lib/checks";

// How many years a check lasts from the date done, where it has a set life
// (matches private.check_life in the database).
const CHECK_LIFE_YEARS: Partial<Record<CheckKind, number>> = {
  rrhan_ec_fundamentals: 3, // RRHAN-EC Fundamentals lasts 3 years.
  rrhan_ec_masterclass: 3, // RRHAN-EC Masterclass lasts 3 years.
  first_aid: 3, // A first aid certificate lasts 3 years.
}; // End of the list of check lives.

// Works out a check's expiry and spots common mistakes, in plain words.
// A police check counts for 5 years from the date it was issued.
export function checkDates(
  kind: CheckKind, // Which kind of check this is.
  reference: string | undefined, // The card or registration number, if given.
  completedOn: string | undefined, // The date it was done or issued, if given.
  expiresOn: string | undefined, // The expiry date, if given.
): { expiresOn: string } | { error: string } {
  if (NEEDS_REFERENCE.has(kind) && !reference) return { error: "Enter the card or registration number." }; // Screening checks need a number.
  const today = new Date().toISOString().slice(0, 10); // Today's date as YYYY-MM-DD.
  if (completedOn && completedOn > today) return { error: "The date done can't be in the future." }; // Catches a typo in the year.

  if (kind === "police_check") { // Police checks follow their own rule:
    if (!completedOn) return { error: "Enter the date the police check was issued." }; // The issue date is needed.
    const expiry = new Date(completedOn); // Starts from the issue date.
    expiry.setFullYear(expiry.getFullYear() + 5); // Adds 5 years.
    const iso = expiry.toISOString().slice(0, 10); // Turns it back into YYYY-MM-DD.
    if (iso < today) return { error: "That police check is more than 5 years old. A new one is needed." }; // Too old.
    return { expiresOn: iso }; // Hands back the worked-out expiry.
  } // End of the police check case.
  // Training with a set life: the expiry can be worked out from the date done.
  const life = CHECK_LIFE_YEARS[kind]; // How many years this kind lasts, if fixed.
  if (!expiresOn && completedOn && life) { // No expiry typed, but we can work it out:
    const expiry = new Date(completedOn); // Starts from the date done.
    expiry.setFullYear(expiry.getFullYear() + life); // Adds its life in years.
    const iso = expiry.toISOString().slice(0, 10); // Turns it back into YYYY-MM-DD.
    if (iso < today) return { error: "That certificate has already expired. Please renew it first." }; // Already out of date.
    return { expiresOn: iso }; // Hands back the worked-out expiry.
  } // End of the set-life case.
  if (!expiresOn) { // Still no expiry date:
    return { error: life ? "Enter the date it was done or the date it expires." : "Enter the expiry date shown on the card." }; // Asks for the right date.
  } // End of the missing-expiry case.
  if (expiresOn < today) return { error: "That check has already expired." }; // Typed expiry is in the past.
  return { expiresOn }; // The typed expiry is fine.
} // End of checkDates.
