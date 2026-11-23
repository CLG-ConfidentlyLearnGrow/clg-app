# Quote of the day and quote of the month

Carla, 22 Nov 2026: a quote of the day at the top of the Overview, and a quote of the month on the loading screen with the "Confidently Learn and Grow" slogan. The starting quotes are the 20 in the "CLG quotes: starter list" doc (22 Nov 2026), with contractions written out in full.

## What it is for

A short, well-chosen line each day reminds staff, families and students of the habits CLG values (ownership, effort, learning from mistakes) without adding work. A monthly quote gives the loading screen a calm, consistent message.

## What the evidence says

- **Growth mindset messages** (EEF and Evidence for Learning reviews of metacognition and self-regulation): brief, repeated messages about effort and strategy are cheap and can support motivation when they sit inside a wider culture, but have small effects on their own. So the quotes are light-touch and never replace feedback or teaching.
- **School and workplace culture** (AERO on positive learning environments): shared language and visible values help everyone know what is expected. The themes match How We Do Things (ownership, standards, learning, persistence).

## How the design follows it

- **Quote of the day**: a small box at the top of every Overview (admin, tutor, parent and student). Each day it is the next quote in the list, going through the whole list before any repeat. The same quote for everyone on the same day, in Adelaide time.
- **Quote of the month**: under "Confidently Learn and Grow" on the loading screen, for everyone, signed in or not. Carla chooses it for this month or next; if she does not, the month takes the next quote in the list.
- **Quotes** (owner only, in the admin menu): add, change, take out of use, or remove quotes. Short forms such as "do not" must be written out in full (CLG's rule), and a quote cannot be added twice.

## How we will know it works

- Carla's review of the list each term
- feedback mentioning the quotes

## Privacy, child safety and legal notes

- No personal information is involved. Quotes are public sayings with their source, or "Attributed to" when the source is uncertain.
- **Copyright**: short quotations with attribution; no long passages.
- Quotes are shown to children, so Carla reviews every quote before it is added.

## Technical

- Migration `20261124711800_quotes.sql` (module: quotes). Tables `quotes` (loaded with the 20 starting quotes) and `quote_months`; functions `quotes_today` (anyone, including signed-out visitors), `quote_save`, `quote_remove` and `quote_set_month` (owner only).
- The page frame reads the quote of the month once per request and shares it with the loading screen (`src/components/quote-of-the-month.tsx`). The Overview reads the quote of the day (`src/lib/quotes.ts`). Owner page: `/admin/quotes`.
- Tests: `supabase/tests/quotes_of_the_day.test.sql`.
