// Summary: a card at the top of the tutor and parent dashboards that says
// when session times are waiting for this person's answer, and when they
// have new notices (Carla, 12 Nov 2026). Before this, those only showed
// under Sessions, so they were easy to miss. Shows nothing when there's
// nothing to answer or read.

import { cache } from "react"; // Lets the count load once per page, even if two dashboards ask.
import Link from "next/link"; // The Next.js link, for moving between pages without a full reload.
import { createClient } from "@/lib/supabase/server"; // Talks to the database as the signed-in person.

type OfferCounts = { as_tutor: number; as_family: number }; // The two numbers the database sends back.

// Asks the database how many session times are waiting for the viewer's
// answer, as a tutor and as a parent. Loaded once per page.
export const getOffersToAnswer = cache(async (): Promise<OfferCounts> => {
  const supabase = await createClient(); // Connects as the signed-in person.
  const { data } = await supabase.rpc("my_offers_to_answer"); // Asks for the two counts (only the viewer's own).
  const row = (data as OfferCounts[] | null)?.[0]; // The one row of numbers, if any came back.
  return { as_tutor: row?.as_tutor ?? 0, as_family: row?.as_family ?? 0 }; // Zero when nothing came back.
}); // End of getOffersToAnswer.

// The card itself. "waiting" is how many times need this person's answer,
// "notices" how many unread notices they have, and "who" picks the wording.
export function SessionAnswersCard({
  waiting, // Session times waiting for this person's answer.
  notices, // Unread session notices.
  who, // "tutor" or "family", for the wording.
}: { // The settings' types:
  waiting: number; // waiting is a number,
  notices: number; // notices is a number,
  who: "tutor" | "family"; // who is one of two words.
}) { // End of the settings.
  if (waiting === 0 && notices === 0) return null; // Nothing to answer or read: show nothing.
  const times = waiting === 1 ? "1 session time" : `${waiting} session times`; // "1 session time" or "3 session times".
  const ask = who === "tutor" ? "Please accept or decline" : "Please approve or decline"; // Tutors accept; families approve.
  return ( // What's shown:
    <div className="rounded-2xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 shadow-sm" role="status">{/* Amber box so it stands out; "status" lets screen readers announce it. */}
      {waiting > 0 && ( // Only when there are times to answer:
        <p>{/* The first line: */}
          <span className="font-medium">{times} waiting for your answer.</span>{/* how many, in bold, */}{" "}
          {ask} before the time runs out.{/* what to do, */}{" "}
          <Link href="/schedule?section=bookings" className="font-medium underline">{/* a link straight to the bookings list, */}
            Answer now{/* with these words. */}
          </Link>{/* (end of the link) */}
        </p> // End of the first line.
      )}{/* (end of the first line's check) */}
      {notices > 0 && ( // Only when there are unread notices:
        <p className={waiting > 0 ? "mt-2" : undefined}>{/* The second line, with a gap above when both lines show: */}
          You have {notices === 1 ? "1 new session notice" : `${notices} new session notices`}.{/* how many notices are new, */}{" "}
          <Link href="/schedule?section=notices" className="font-medium underline">{/* a link straight to the notices, */}
            Read them{/* with these words. */}
          </Link>{/* (end of the link) */}
        </p> // End of the second line.
      )}{/* (end of the second line's check) */}
    </div> // End of the box.
  ); // End of what's shown.
} // End of SessionAnswersCard.
