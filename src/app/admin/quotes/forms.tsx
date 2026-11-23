// Summary: the forms on the Quotes page (Carla, 22 Nov 2026): adding or
// changing a quote, removing one, and choosing the quote of the month.
//
"use client"; // Runs in the browser, so each form can show its result straight away.

import { removeQuote, saveQuote, setMonthQuote } from "@/app/actions/quotes"; // The server actions.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field, Select, TextArea } from "@/components/ui"; // The input box, drop-down and larger text box.

// Adds or changes a quote.
export function QuoteForm({ quote }: { quote?: { id: string; body: string; who: string; theme: string | null; active: boolean } }) { // Takes the quote (blank for a new one).
  return ( // Shows:
    <ActionForm action={saveQuote} submitLabel={quote ? "Save changes" : "Add quote"}>{/* the form: */}
      <input type="hidden" name="id" value={quote?.id ?? ""} />{/* which quote (hidden), */}
      <TextArea label="Quote" name="body" rows={2} maxLength={400} required defaultValue={quote?.body ?? ""} hint="Write short forms out in full, for example do not, it is." />{/* the quote, */}
      <div className="grid gap-4 sm:grid-cols-2">{/* side by side on wider screens: */}
        <Field label="Who said it" name="who" maxLength={120} required defaultValue={quote?.who ?? ""} hint="If unsure of the source, write Attributed to and the name." />{/* who, */}
        <Field label="Theme (optional)" name="theme" maxLength={60} defaultValue={quote?.theme ?? ""} />{/* and the theme. */}
      </div>{/* End of the row. */}
      {quote && <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="active" defaultChecked={quote.active} />In use (untick to leave it out of the days)</label>}{/* whether it is in use (changes only). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of QuoteForm.

// Removes a quote.
export function RemoveQuoteForm({ id }: { id: string }) { // Takes the quote.
  return ( // Shows:
    <ActionForm action={removeQuote} submitLabel="Remove quote">{/* the form: */}
      <input type="hidden" name="id" value={id} />{/* which quote (hidden). */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of RemoveQuoteForm.

// Chooses the quote of the month.
export function MonthQuoteForm({ month, label, chosen, quotes }: { month: string; label: string; chosen: string; quotes: { id: string; body: string; who: string }[] }) { // Takes the month, its name, the current choice and the quotes in use.
  return ( // Shows:
    <ActionForm action={setMonthQuote} submitLabel={`Save for ${label}`}>{/* the form: */}
      <input type="hidden" name="month" value={month} />{/* which month (hidden), */}
      <Select label={label} name="quote" defaultValue={chosen}>{/* the choice: */}
        <option value="">Next in the list (no choice)</option>{/* none, */}
        {quotes.map((q) => <option key={q.id} value={q.id}>{q.body.length > 90 ? `${q.body.slice(0, 90)}…` : q.body} ({q.who})</option>)}{/* or one of the quotes. */}
      </Select>{/* End of the choice. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of MonthQuoteForm.
