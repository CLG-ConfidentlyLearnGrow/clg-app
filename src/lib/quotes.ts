// Summary: reads today's quotes (Carla, 22 Nov 2026): the quote of the day
// for the top of the Overview, and the quote of the month for the loading
// screen. Read once per page request and shared. See docs/features/quotes.md.
//
import { cache } from "react"; // Remembers the answer for the rest of this page request.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the visitor (signed in or not).

// One quote: its words and who said it.
export type Quote = { body: string; who: string }; // Its fields.

// Today's quote of the day and quote of the month. A problem reading them
// gives no quotes, so pages still show without them.
export const getTodayQuotes = cache(async (): Promise<{ day: Quote | null; month: Quote | null }> => { // No inputs.
  try { // Tries to read them:
    const supabase = await createClient(); // Connects to the database.
    const { data } = await supabase.rpc("quotes_today").maybeSingle<{ day_body: string | null; day_who: string | null; month_body: string | null; month_who: string | null }>(); // Asks for the two quotes.
    return { // Hands back:
      day: data?.day_body ? { body: data.day_body, who: data.day_who ?? "" } : null, // the day's quote (if any),
      month: data?.month_body ? { body: data.month_body, who: data.month_who ?? "" } : null, // and the month's quote (if any).
    }; // End of the answer.
  } catch { // Anything went wrong:
    return { day: null, month: null }; // no quotes.
  } // End of the try.
}); // End of getTodayQuotes.
