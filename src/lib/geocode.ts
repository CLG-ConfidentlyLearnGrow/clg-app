// Summary: finds the map point (latitude and longitude) of a street address,
// so the app can work out straight-line travel distances (Carla, 16 Nov 2026).
// Uses OpenStreetMap's free address search (Nominatim). Only the address is
// sent: no name, email or other details. It runs on the server only, and is
// used once each time someone saves an address.
import "server-only"; // Stops this file from ever being sent to a web browser.

const NOMINATIM = "https://nominatim.openstreetmap.org/search"; // The OpenStreetMap address search's web address.

export type MapPoint = { // A found address:
  latitude: number; // north to south (negative in Australia),
  longitude: number; // west to east,
  label: string; // and the full address as OpenStreetMap knows it.
}; // End of MapPoint.

// Rounds a number to 6 decimal places (about 10 cm), the most the database keeps.
function round6(n: number): number { // Takes a number.
  return Math.round(n * 1_000_000) / 1_000_000; // Gives it back rounded to 6 decimal places.
} // End of round6.

// Looks up an Australian street address. Gives back its map point, or null
// when it cannot be found (or the search service cannot be reached).
export async function findMapPoint(address: string): Promise<MapPoint | null> { // Takes the address typed in.
  const query = new URLSearchParams({ // The search settings:
    q: address, // the address,
    format: "jsonv2", // answers as JSON,
    countrycodes: "au", // only places in Australia,
    limit: "1", // just the best match,
    addressdetails: "0", // without the address split into parts.
  }); // End of the settings.
  try { // Tries the search:
    const res = await fetch(`${NOMINATIM}?${query}`, { // asks OpenStreetMap,
      headers: { "User-Agent": "clg-app address lookup", "Accept-Language": "en-AU" }, // naming the app (their rules ask for this) and asking for Australian English,
      cache: "no-store", // without keeping a copy,
      signal: AbortSignal.timeout(15_000), // giving up after 15 seconds.
    }); // End of the request.
    if (!res.ok) return null; // An error reply: counts as not found.
    const rows = (await res.json()) as { lat?: string; lon?: string; display_name?: string }[]; // Reads the answers.
    const best = rows[0]; // The best match (if any).
    const latitude = Number(best?.lat); // Its latitude as a number.
    const longitude = Number(best?.lon); // Its longitude as a number.
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null; // No usable match: not found.
    if (latitude < -44 || latitude > -9 || longitude < 112 || longitude > 154) return null; // Outside Australia: not found.
    return { latitude: round6(latitude), longitude: round6(longitude), label: best?.display_name ?? address }; // Gives back the point and full address.
  } catch { // If the search failed (for example, no connection):
    return null; // counts as not found.
  } // End of the fallback.
} // End of findMapPoint.

// The message shown when an address cannot be found.
export const ADDRESS_NOT_FOUND = // The words:
  "We could not find that address. Please check the street number, street, suburb and postcode, then try again."; // asks them to check it.
