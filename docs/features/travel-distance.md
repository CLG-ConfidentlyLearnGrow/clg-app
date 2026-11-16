# Travel distances for tutors and families

Asked for by Carla, 16 Nov 2026:

- "The travel distance from their home is determined by the tutor (this is
  km by straight line from residence)."
- "It could also be km by straight line from an address set by the tutor
  too." "This can change for each set/day of availability the tutor
  provides."
- "That is much easier than them saying which libraries. This can be the
  same for clients too (km in a straight line from residence or set
  location - this would be the limit of where clients are willing to travel
  for tutoring)."
- On suburbs or exact addresses: "it kind of doesn't work if it is not the
  exact street address though." Exact street addresses are used.

Scheduling module. Migration
`supabase/migrations/20261119700100_travel_distance.sql`; tests in
`supabase/tests/scheduling_travel_distance.test.sql`. The tutor contracts
(1.2) already say the tutor sets the distance and address.

## What it is for

Until now, tutors ticked the libraries they could work at and chose one
library for each time, and CLG ticked libraries for each family. That takes
a lot of ticking, misses new libraries, and does not say how far anyone is
really willing to go. A distance from a real address is simpler: each side
says how far they will travel, and the app offers the libraries both can
reach. Tutors can also say they will go to learners' homes within their
distance, which CLG can then arrange.

## What the evidence says

- **Attendance and dosage** (EEF one to one tuition, +5 months; Stanford
  National Student Support Accelerator "high-impact tutoring" design
  principles; AERO, *Attendance matters*): tutoring works when sessions are
  regular and actually happen. Long or awkward travel is a common reason
  sessions are missed or dropped. Matching only within the distance each
  side has chosen keeps travel realistic for both.
- **Consistent tutor relationships** (EEF; NSSA): learners do better with
  the same tutor over time. A tutor who is not stretched across far-away
  places is more likely to keep a regular weekly slot for the whole term.
- **Parental engagement** (EEF, +4 months): families engage more when
  arrangements fit their lives. Letting the family set its own travel limit
  respects that and avoids offers they will turn down.

## How it works

### Tutors
1. **Hours and availability** on the tutor dashboard has **Where you travel
   from**: the tutor adds one or more addresses (for example Home or Uni).
2. Each time they add, they tick **Online**, **At public libraries within my
   travel distance**, **At learners' homes within my travel distance**, or a
   mix, then choose the address they are travelling from and the most km
   (straight line, 1 to 100). Each time can have a different address and
   distance.
3. Times set up the old way (one library, or the tutor's ticked libraries)
   keep working until the tutor re-adds them.

### Families and learners
1. **Sessions > Preferred times** (families) and **Session places** (admins)
   have **How far you will travel**: an address (home or another place) and
   the most km to a library.
2. Families and learners with their own login (16 and over) can set it, as
   well as CLG front desk admins.

### Matching
- A library is offered when it is a confirmed library in use, open then,
  within the tutor's distance for that time, and within the family's
  distance (or the family or CLG ticked it, as before).
- **At home** is offered only to CLG front desk admins (CLG arranges home
  sessions), when the learner's address is within the tutor's distance and
  the tutor ticked learners' homes for that time.
- Libraries need a map point. Libraries loaded from OpenStreetMap have one;
  libraries added by hand need latitude and longitude filled in.

### Finding the map point
When someone saves an address, the server looks it up once with
OpenStreetMap's free address search (Nominatim) and saves the map point.
Only the address is sent, with a generic app name, never a person's name or
email. If it cannot be found, the person is asked to check the street
number, street, suburb and postcode.

## Privacy, child safety and the law

- **Privacy Act 1988, APP 3 (collect only what is needed)**: exact
  addresses are needed because a suburb is not accurate enough for a
  distance limit (Carla's decision). Only the address and its map point are
  kept, nothing more.
- **APP 6 and need to know**: a tutor's starting addresses are readable only
  by the tutor and Owner and Operations admins (row level security on
  `tutor_travel_places`). A family's address sits on `student_places`, which
  only the family, the learner themselves and front desk admins can read.
  Tutors never see a family's address through matching, and families never
  see a tutor's. Sibling privacy is kept: a learner's own login sees only
  their own row.
- **APP 8 (sending information overseas)**: OpenStreetMap's address search
  is run by the OpenStreetMap Foundation outside Australia. The privacy
  policy needs a line saying addresses are sent to it to find their map
  point. Suggested wording: "When you save an address for travel distances,
  we send only that address to OpenStreetMap's address search (run by the
  OpenStreetMap Foundation, outside Australia) to find its map point. We do
  not send your name or contact details." Carla approved it on 16 Nov 2026;
  it is now in the privacy policy document (section 7 and the providers
  table) and on the app's Privacy policy page.
- **APP 11 (security)**: addresses are protected by the database's access
  rules, and every change to a tutor's addresses is in the audit log.
- **Children's Online Privacy Code**: a child's address is treated as
  personal information collected only for arranging sessions, and is not
  shown to tutors.
- **Child safety**: home sessions are still arranged only by CLG admins, so
  CLG keeps oversight of every home visit.
- **Fair Work / tutor contract**: the tutor chooses their own distance
  (contract 1.2). Travel between home sessions is not paid (contract 2.7).
- **UK and EU**: the same approach meets UK GDPR / GDPR data minimisation;
  the overseas lookup would need noting in those privacy notices too.

## Database

- `tutor_travel_places`: a tutor's addresses (name, address, map point).
- `tutor_availability`: new `travel_place_id`, `travel_km`, `home_visits`.
- `student_places`: new `travel_address`, `travel_latitude`,
  `travel_longitude`, `travel_km`.
- `find_session_times` (edited in place): libraries and homes by distance.

## How we will know it works

- how many tutor times and families have a travel distance set
- offers turned down because of the place, before and after
- share of in-person sessions that run without travel-related cancels

## Travel map (admins)

Carla, 16 Nov 2026: "Maybe CLG has an internal map with all the approved
libraries and the tutor and client travel areas...?"

- **Admin > Travel map** (Owner and Operations only) shows approved
  libraries with a map point, each tutor's travel areas (one circle per
  starting address and distance, listing the weekly times that use it) and
  each family's travel area. Admins can show or hide each kind and pick one
  tutor to zoom to.
- **Why it helps**: seeing where tutors and families overlap shows which
  areas are short of tutors (who to recruit next) and which libraries sit
  where most families and tutors meet. This supports the same aim as the
  matching itself: regular sessions with travel that suits both sides.
- **Privacy**: only Owner and Operations admins can open it, and the
  database access rules decide what is read (they already let these admins
  see tutors' and families' travel details). Street addresses are not shown
  on the map, only names, distances and circles. Pop-up text is made safe
  before showing.
- **Map pictures**: the background map comes from OpenStreetMap's map
  picture service (tile.openstreetmap.org), added to the app's content
  security rules for images only. The admin's browser asks only for the map
  area on screen; no names or addresses are sent. OpenStreetMap is credited
  on the map, as its rules ask.

## Not done (could come later)

- A tutor seeing the family's address once a home session is booked (for
  now CLG passes it on).
- The waitlist still needs online or a ticked library.
- Showing families which libraries fall within their distance.
- Families and learners booking home sessions themselves.
