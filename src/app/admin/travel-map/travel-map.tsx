// Summary: the map on the admin Travel map page (Carla, 16 Nov 2026). It
// shows CLG's approved libraries, each tutor's travel areas (one circle per
// starting address and distance) and each family's travel area, so admins
// can see where tutors and families overlap. It runs in the browser only.
// Map pictures come from OpenStreetMap; only the map area being viewed is
// asked for, never names or addresses.
"use client"; // Marks this file as code that runs in the browser.

import "leaflet/dist/leaflet.css"; // The map library's own styles (map tiles, zoom buttons).
import { useEffect, useMemo, useRef, useState } from "react"; // React tools: run code after showing, remember a worked-out value, point at a page element, remember a value.
import type { Circle, CircleMarker, LayerGroup, Map as LeafletMap } from "leaflet"; // The map library's types, for type checking only.

export type MapLibrary = { id: string; name: string; suburb: string | null; latitude: number; longitude: number }; // A library: its name, suburb and map point.
export type MapTutorArea = { // One tutor travel area:
  key: string; // a unique key,
  tutorId: string; // the tutor,
  tutorName: string; // their name,
  placeLabel: string; // the starting address's short name (for example Home),
  latitude: number; // its map point (north to south),
  longitude: number; // (west to east)
  km: number; // how far they travel,
  times: string[]; // the weekly times that use this area, in words,
  libraries: boolean; // whether any of those times are at libraries,
  homes: boolean; // and whether any are at learners' homes.
}; // End of MapTutorArea.
export type MapFamilyArea = { key: string; studentName: string; latitude: number; longitude: number; km: number }; // A family travel area: the learner, the map point and the distance.

const TUTOR_COLOUR = "#a8815b"; // Tutor bronze (the tutor dashboard colour).
const FAMILY_COLOUR = "#7c9a78"; // Parent sage (the parent dashboard colour).
const LIBRARY_COLOUR = "#414042"; // Charcoal for libraries.
const ADELAIDE: [number, number] = [-34.93, 138.6]; // Where the map starts: Adelaide.

// Shows the map with tick boxes to choose what is shown.
export function TravelMap({ libraries, tutors, families }: { libraries: MapLibrary[]; tutors: MapTutorArea[]; families: MapFamilyArea[] }) { // Takes the libraries, tutor areas and family areas.
  const box = useRef<HTMLDivElement>(null); // The page element the map is drawn in.
  const map = useRef<LeafletMap | null>(null); // The map, once made.
  const layers = useRef<{ libs: LayerGroup; tutors: LayerGroup; families: LayerGroup } | null>(null); // The three groups of shapes, once made.
  const [showLibs, setShowLibs] = useState(true); // Whether libraries are shown.
  const [showTutors, setShowTutors] = useState(true); // Whether tutor areas are shown.
  const [showFamilies, setShowFamilies] = useState(true); // Whether family areas are shown.
  const [tutorId, setTutorId] = useState(""); // The one tutor to show (blank for all).
  const [ready, setReady] = useState(false); // Whether the map has loaded.

  const tutorNames = useMemo( // The tutors for the drop-down:
    () => [...new Map(tutors.map((t) => [t.tutorId, t.tutorName])).entries()].sort((a, b) => a[1].localeCompare(b[1])), // each tutor once, by name.
    [tutors], // (worked out again only if the tutor areas change)
  ); // End of the tutor list.

  // Makes the map once, after the page shows.
  useEffect(() => { // Runs after the first showing:
    let cancelled = false; // Whether the page was left before the map loaded.
    (async () => { // Loads the map library (browser only):
      const L = (await import("leaflet")).default; // the map library,
      if (cancelled || !box.current || map.current) return; // stops if the page was left or the map already exists,
      const m = L.map(box.current).setView(ADELAIDE, 10); // makes the map, starting over Adelaide,
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { // adds the map pictures from OpenStreetMap,
        maxZoom: 18, // up to street level,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors', // with the credit their rules ask for.
      }).addTo(m); // (on this map)
      layers.current = { libs: L.layerGroup().addTo(m), tutors: L.layerGroup().addTo(m), families: L.layerGroup().addTo(m) }; // makes the three shape groups,
      map.current = m; // keeps the map,
      setReady(true); // and says it is ready.
    })(); // (runs straight away)
    return () => { // When the page is left:
      cancelled = true; // marks it as left,
      map.current?.remove(); // removes the map,
      map.current = null; // and forgets it.
    }; // End of the clean-up.
  }, []); // (only once)

  // Draws the shapes whenever the choices change.
  useEffect(() => { // Runs when the choices or data change:
    if (!ready || !layers.current) return; // Waits for the map.
    let cancelled = false; // Whether this drawing was replaced by a newer one.
    (async () => { // Draws:
      const L = (await import("leaflet")).default; // the map library (already loaded),
      if (cancelled || !layers.current) return; // stops if replaced,
      const { libs, tutors: tutorLayer, families: familyLayer } = layers.current; // the three shape groups,
      libs.clearLayers(); // clears the libraries,
      tutorLayer.clearLayers(); // the tutor areas,
      familyLayer.clearLayers(); // and the family areas.
      const shown: (Circle | CircleMarker)[] = []; // The shapes drawn (to fit the map to them).
      if (showLibs) { // Libraries, if ticked:
        for (const l of libraries) { // for each library:
          const dot = L.circleMarker([l.latitude, l.longitude], { radius: 5, color: LIBRARY_COLOUR, weight: 1, fillColor: LIBRARY_COLOUR, fillOpacity: 0.9 }); // a small charcoal dot,
          dot.bindTooltip(escapeHtml(l.suburb ? `${l.name} (${l.suburb})` : l.name)); // its name (and suburb) on hover,
          dot.addTo(libs); // added to the libraries group.
        } // End of the libraries.
      } // End of the libraries part.
      if (showTutors) { // Tutor areas, if ticked:
        for (const t of tutors) { // for each area:
          if (tutorId && t.tutorId !== tutorId) continue; // skips other tutors when one is chosen,
          const ring = L.circle([t.latitude, t.longitude], { radius: t.km * 1000, color: TUTOR_COLOUR, weight: 2, fillColor: TUTOR_COLOUR, fillOpacity: 0.12 }); // a bronze circle of their distance,
          const where = [t.libraries ? "libraries" : "", t.homes ? "learners' homes" : ""].filter(Boolean).join(" and "); // libraries, homes or both,
          ring.bindPopup(`<strong>${escapeHtml(t.tutorName)}</strong><br>${escapeHtml(t.placeLabel)}, ${t.km} km (${where})<br>${t.times.map(escapeHtml).join("<br>")}`); // their name, address name, distance and times when clicked,
          ring.addTo(tutorLayer); // added to the tutor group,
          shown.push(ring); // and noted.
        } // End of the tutor areas.
      } // End of the tutor part.
      if (showFamilies && !tutorId) { // Family areas, if ticked (hidden while one tutor is chosen):
        for (const f of families) { // for each area:
          const ring = L.circle([f.latitude, f.longitude], { radius: f.km * 1000, color: FAMILY_COLOUR, weight: 2, dashArray: "6 4", fillColor: FAMILY_COLOUR, fillOpacity: 0.12 }); // a dashed sage circle of their distance,
          ring.bindPopup(`<strong>${escapeHtml(f.studentName)}</strong><br>Family travels up to ${f.km} km`); // the learner's name and distance when clicked,
          ring.addTo(familyLayer); // added to the family group,
          shown.push(ring); // and noted.
        } // End of the family areas.
      } // End of the family part.
      if (tutorId && shown.length > 0) map.current?.fitBounds(L.featureGroup(shown).getBounds(), { padding: [20, 20] }); // Zooms to the chosen tutor's areas.
    })(); // (runs straight away)
    return () => { // When replaced:
      cancelled = true; // marks this drawing as replaced.
    }; // End of the clean-up.
  }, [ready, showLibs, showTutors, showFamilies, tutorId, libraries, tutors, families]); // (runs again when any of these change)

  const tick = "flex items-center gap-2 text-sm"; // The look of each tick box line.
  return ( // Shows:
    <div className="space-y-3">{/* a stack: */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-2">{/* a row of choices: */}
        <label className={tick}>{/* a tick box line: */}
          <input type="checkbox" checked={showLibs} onChange={(e) => setShowLibs(e.target.checked)} />{/* the tick box, */}
          <span className="inline-block h-3 w-3 rounded-full" style={{ background: LIBRARY_COLOUR }} /> Libraries ({libraries.length}){/* a charcoal dot and the count. */}
        </label>{/* End of the line. */}
        <label className={tick}>{/* a tick box line: */}
          <input type="checkbox" checked={showTutors} onChange={(e) => setShowTutors(e.target.checked)} />{/* the tick box, */}
          <span className="inline-block h-3 w-3 rounded-full" style={{ background: TUTOR_COLOUR }} /> Tutor areas ({tutors.length}){/* a bronze dot and the count. */}
        </label>{/* End of the line. */}
        <label className={tick}>{/* a tick box line: */}
          <input type="checkbox" checked={showFamilies} onChange={(e) => setShowFamilies(e.target.checked)} />{/* the tick box, */}
          <span className="inline-block h-3 w-3 rounded-full" style={{ background: FAMILY_COLOUR }} /> Family areas ({families.length}){/* a sage dot and the count. */}
        </label>{/* End of the line. */}
        <label className={tick}>{/* a drop-down line: */}
          Tutor{/* its label, */}
          <select className="rounded border border-zinc-300 px-2 py-1 text-sm" value={tutorId} onChange={(e) => setTutorId(e.target.value)}>{/* the drop-down: */}
            <option value="">All tutors</option>{/* all tutors, */}
            {tutorNames.map(([id, name]) => ( // for each tutor:
              <option key={id} value={id}>{/* an option: */}
                {name}{/* their name. */}
              </option> // End of the option.
            ))}{/* End of the loop. */}
          </select>{/* End of the drop-down. */}
        </label>{/* End of the line. */}
      </div>{/* End of the row. */}
      <div ref={box} className="h-[70vh] min-h-[360px] w-full overflow-hidden rounded-lg border border-zinc-200" aria-label="Map of libraries and travel areas" />{/* The map itself. */}
    </div> // End of the stack.
  ); // End of what is shown.
} // End of TravelMap.

// Makes text safe to put inside the map's pop-ups (so a name cannot add page code).
function escapeHtml(text: string): string { // Takes the text.
  return text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] ?? c); // Swaps each special character for its safe form.
} // End of escapeHtml.
