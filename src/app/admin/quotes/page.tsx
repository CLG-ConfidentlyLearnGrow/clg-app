// Summary: the Quotes page for CLG's owner (Carla, 22 Nov 2026). The quote
// of the day at the top of every Overview goes through this list, one a day,
// before any repeat. The quote of the month shows on the loading screen
// under "Confidently Learn and Grow". Carla adds, changes and removes
// quotes and chooses the quote for this month and next. See docs/features/quotes.md.
//
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // Shared page parts: card and "nothing yet" line.
import { requireAdminLevel } from "@/lib/auth"; // Makes sure the person is the owner.
import { adelaideToday } from "@/lib/billing/run"; // Today's date in Adelaide.
import { getTodayQuotes } from "@/lib/quotes"; // Today's quotes.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { MonthQuoteForm, QuoteForm, RemoveQuoteForm } from "./forms"; // The page's forms.

// One quote as the page reads it.
type QuoteRow = { id: string; body: string; who: string; theme: string | null; active: boolean; position: number }; // Its fields.

// The first day of the month a number of months after the given day ("YYYY-MM-DD").
function monthStart(day: string, add: number): string { // Takes the day and how many months on.
  const d = new Date(`${day.slice(0, 7)}-01T12:00:00Z`); // The month's first day at midday.
  d.setUTCMonth(d.getUTCMonth() + add); // Moves on that many months.
  return d.toISOString().slice(0, 10); // Hands back "YYYY-MM-01".
} // End of monthStart.

// A month's name, for example "December 2026".
function monthName(first: string): string { // Takes the month's first day.
  return new Date(`${first}T12:00:00Z`).toLocaleDateString("en-AU", { month: "long", year: "numeric", timeZone: "UTC" }); // The month and year in words.
} // End of monthName.

// Shows the page (owner only).
export default async function QuotesPage() {
  const viewer = await requireAdminLevel(["owner"]); // Must be the owner, with two-step sign-in.
  const supabase = await createClient(); // Connects to the database.
  const today = adelaideToday(); // Today in Adelaide.
  const months = [monthStart(today, 0), monthStart(today, 1)]; // This month and next.
  const [{ data: quotes }, { data: chosen }, now] = await Promise.all([ // Reads three things at once:
    supabase.from("quotes").select("id, body, who, theme, active, position").order("position").order("created_at"), // every quote,
    supabase.from("quote_months").select("month, quote_id").in("month", months), // the choices for this month and next,
    getTodayQuotes(), // and today's quotes.
  ]); // End of the reads.
  const list = (quotes ?? []) as QuoteRow[]; // The quotes.
  const inUse = list.filter((q) => q.active); // The quotes in use.
  const choice = new Map(((chosen ?? []) as { month: string; quote_id: string }[]).map((c) => [c.month, c.quote_id])); // Each month's choice.
  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="quotes">{/* the dashboard frame, */}
      <div className="space-y-6">{/* the cards, with space between: */}
        <Card title="Today" description="What everyone sees today.">{/* today's quotes: */}
          <div className="space-y-3 text-sm">{/* a block: */}
            <p><span className="font-semibold">Quote of the day (Overview): </span>{now.day ? `“${now.day.body}” ${now.day.who}` : "None"}</p>{/* the day's quote, */}
            <p><span className="font-semibold">Quote of the month (loading screen): </span>{now.month ? `“${now.month.body}” ${now.month.who}` : "None"}</p>{/* and the month's quote. */}
          </div>{/* End of the block. */}
        </Card>{/* End of the card. */}
        <Card title="Quote of the month" description="Shown on the loading screen under Confidently Learn and Grow. If you do not choose one, the month uses the next quote in the list.">{/* the month choices: */}
          <div className="grid gap-6 sm:grid-cols-2">{/* side by side on wider screens: */}
            {months.map((m) => <MonthQuoteForm key={m} month={m} label={monthName(m)} chosen={choice.get(m) ?? ""} quotes={inUse} />)}{/* a form for each month. */}
          </div>{/* End of the forms. */}
        </Card>{/* End of the card. */}
        <Card title="All quotes" description="The quote of the day goes through these in order, one a day, before any repeat. New quotes go to the end of the list.">{/* the list: */}
          <div className="space-y-4">{/* a block: */}
            <details><summary className="cursor-pointer text-sm font-medium underline">Add a quote</summary><div className="mt-3"><QuoteForm /></div></details>{/* adding a new one, */}
            {list.length === 0 ? <Empty>No quotes yet.</Empty> : ( // None, or the list:
              <ul className="divide-y divide-zinc-100">{list.map((q) => ( // Each quote:
                <li key={q.id} className="py-3 text-sm">{/* a row: */}
                  <details>{/* an open-and-close box: */}
                    <summary className="cursor-pointer list-none"><span className="italic">“{q.body}”</span> <span className="text-zinc-500">{q.who}{q.theme ? ` · ${q.theme}` : ""}{q.active ? "" : " · Not in use"}</span></summary>{/* the quote, who and theme, */}
                    <div className="mt-3 space-y-3"><QuoteForm quote={q} /><RemoveQuoteForm id={q.id} /></div>{/* changing or removing it. */}
                  </details>{/* End of the box. */}
                </li> // End of the row.
              ))}</ul> // End of the list.
            )}{/* End of the choice. */}
          </div>{/* End of the block. */}
        </Card>{/* End of the card. */}
      </div>{/* End of the cards. */}
    </DashboardFrame> // End of the frame.
  ); // End of what's shown.
} // End of QuotesPage.
