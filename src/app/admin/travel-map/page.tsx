// Summary: the admin Travel map page (Carla, 16 Nov 2026): one map of CLG's
// approved libraries, every tutor's travel areas and every family's travel
// area. Owner and operations admins only, because it shows where tutors
// and families are. Street addresses are not shown, only names, distances
// and the circles. The database's access rules decide what is read.
//
import { DashboardFrame } from "@/components/dashboard-frame"; // The dashboard tabs and side menu around the page.
import { Card, Empty } from "@/components/ui"; // The card and "nothing yet" note.
import { requireAdmin } from "@/lib/auth"; // Makes sure the person is an owner or operations admin.
import { WEEKDAY_NAMES } from "@/lib/scheduling"; // The weekday names.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.
import { TravelMap, type MapFamilyArea, type MapLibrary, type MapTutorArea } from "./travel-map"; // The map, and the shapes of what it shows.

// A weekly availability time with a travel distance, as the database gives it.
type TimeRow = { // One time:
  tutor_id: string; // the tutor,
  weekday: number; // the day (1 = Monday),
  starts_at: string; // from,
  ends_at: string; // to,
  travel_km: number; // how far they travel,
  in_person: boolean; // whether it is at libraries,
  home_visits: boolean; // whether it is at learners' homes,
  travel: { id: string; label: string; latitude: number; longitude: number } | { id: string; label: string; latitude: number; longitude: number }[] | null; // and the starting address (one, or a list of one).
}; // End of TimeRow.

// Shows the Travel map page.
export default async function TravelMapPage() { // No settings needed.
  const viewer = await requireAdmin(); // Makes sure the person is an owner or operations admin.
  const supabase = await createClient(); // Connects to the database.
  const [libsRes, timesRes, familiesRes] = await Promise.all([ // Reads three things at once:
    supabase // the libraries:
      .from("libraries") // from libraries,
      .select("id, name, suburb, latitude, longitude") // their name, suburb and map point,
      .eq("active", true) // still in use,
      .not("confirmed_at", "is", null) // confirmed by CLG,
      .not("latitude", "is", null) // with a map point,
      .not("longitude", "is", null), // (both parts).
    supabase // the tutors' times with a distance:
      .from("tutor_availability") // from tutor_availability,
      .select("tutor_id, weekday, starts_at, ends_at, travel_km, in_person, home_visits, travel:tutor_travel_places(id, label, latitude, longitude)") // the time, distance, places and starting address,
      .not("travel_km", "is", null) // only times with a distance,
      .order("weekday") // by day,
      .order("starts_at"), // then start time.
    supabase // the families' travel areas:
      .from("student_places") // from student_places,
      .select("student_id, travel_latitude, travel_longitude, travel_km") // the map point and distance,
      .not("travel_km", "is", null), // only learners with a distance.
  ]); // End of the reads.
  const missingUpdate = Boolean(timesRes.error || familiesRes.error); // True if the travel distance update has not been run in the database yet.

  const times = (timesRes.data ?? []) as TimeRow[]; // The tutors' times.
  const familyRows = (familiesRes.data ?? []) as { student_id: string; travel_latitude: number; travel_longitude: number; travel_km: number }[]; // The families' areas.
  const [namesRes, studentsRes] = await Promise.all([ // Reads the names at once:
    times.length // if there are tutor times:
      ? supabase.from("accounts").select("id, full_name").in("id", [...new Set(times.map((t) => t.tutor_id))]) // the tutors' names,
      : Promise.resolve({ data: [] as { id: string; full_name: string }[] }), // otherwise none.
    familyRows.length // if there are family areas:
      ? supabase.from("students").select("id, full_name").in("id", familyRows.map((f) => f.student_id)) // the learners' names,
      : Promise.resolve({ data: [] as { id: string; full_name: string }[] }), // otherwise none.
  ]); // End of the reads.
  const tutorName = new Map((namesRes.data ?? []).map((a) => [a.id as string, a.full_name as string])); // Each tutor's name, by id.
  const studentName = new Map((studentsRes.data ?? []).map((s) => [s.id as string, s.full_name as string])); // Each learner's name, by id.

  const libraries: MapLibrary[] = (libsRes.data ?? []).map((l) => ({ // The libraries for the map:
    id: l.id as string, // its id,
    name: l.name as string, // name,
    suburb: (l.suburb as string | null) ?? null, // suburb,
    latitude: Number(l.latitude), // and map point.
    longitude: Number(l.longitude), // (west to east)
  })); // End of the libraries.

  // One circle per tutor, starting address and distance, listing its times.
  const areas = new Map<string, MapTutorArea>(); // The tutor areas, by key.
  for (const t of times) { // For each time:
    const from = Array.isArray(t.travel) ? t.travel[0] : t.travel; // its starting address,
    if (!from) continue; // (skipped if missing)
    const key = `${t.tutor_id}-${from.id}-${t.travel_km}`; // one key per tutor, address and distance,
    const words = `${WEEKDAY_NAMES[t.weekday - 1]} ${t.starts_at.slice(0, 5)} to ${t.ends_at.slice(0, 5)}`; // the time in words,
    const area = areas.get(key) ?? { // the area so far, or a new one:
      key, // its key,
      tutorId: t.tutor_id, // the tutor,
      tutorName: tutorName.get(t.tutor_id) ?? "Tutor", // their name,
      placeLabel: from.label, // the address's short name,
      latitude: Number(from.latitude), // its map point,
      longitude: Number(from.longitude), // (west to east)
      km: t.travel_km, // the distance,
      times: [], // no times yet,
      libraries: false, // not yet at libraries,
      homes: false, // nor homes.
    }; // End of the area.
    area.times.push(words); // Adds this time.
    area.libraries ||= t.in_person; // Notes libraries, if this time is at libraries.
    area.homes ||= t.home_visits; // Notes homes, if this time is at homes.
    areas.set(key, area); // Keeps the area.
  } // End of the times.
  const tutors = [...areas.values()]; // The tutor areas as a list.

  const families: MapFamilyArea[] = familyRows.map((f) => ({ // The family areas for the map:
    key: f.student_id, // its key,
    studentName: studentName.get(f.student_id) ?? "Learner", // the learner's name,
    latitude: Number(f.travel_latitude), // the map point,
    longitude: Number(f.travel_longitude), // (west to east)
    km: f.travel_km, // and the distance.
  })); // End of the family areas.

  return ( // Shows:
    <DashboardFrame role="admin" roles={viewer.roles} current="travel-map">{/* the admin dashboard frame, with this page's menu item open: */}
      <Card // a card:
        title="Travel map" // its title,
        description="CLG's approved libraries, each tutor's travel areas and each family's travel area. Click a circle for details. Street addresses are not shown here." // its help text.
      >{/* (end of the card's settings) */}
        {missingUpdate ? ( // If the database update has not been run:
          <Empty>The database is missing an update. The owner needs to run 20261119700100_travel_distance.sql in Supabase.</Empty> // says which one.
        ) : ( // Otherwise:
          <>{/* (a group) */}
            <TravelMap libraries={libraries} tutors={tutors} families={families} />{/* the map, */}
            <p className="mt-3 text-xs text-zinc-600">{/* a small note: */}
              Circles are straight-line distances. Tutor areas are solid bronze; family areas are dashed green. Libraries
              need a map point to show; libraries loaded from OpenStreetMap have one.{/* (end of the text) */}
            </p>{/* End of the note. */}
          </> // End of the group.
        )}{/* End of this part. */}
      </Card>{/* End of the card. */}
    </DashboardFrame> // End of the frame.
  ); // End of what is shown.
} // End of TravelMapPage.
