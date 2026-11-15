// Summary: words and small helpers for "What's new" (Carla, 15 Nov 2026),
// shared by the pop-up, the "What's new" page and the admin page, so they
// all use the same labels. Nothing here talks to the database, so the
// pop-up (which runs in the browser) can use it too.

// The three kinds of change, with the word and colours shown for each.
export const WHATS_NEW_KINDS: Record<string, { label: string; className: string }> = { // kind id -> word and look:
  added: { label: "New", className: "bg-emerald-100 text-emerald-900" }, // something added, in green,
  updated: { label: "Updated", className: "bg-sky-100 text-sky-900" }, // something changed, in blue,
  removed: { label: "Removed", className: "bg-zinc-200 text-zinc-800" }, // something taken away, in grey.
}; // End of the kinds.

// The most updates shown in the pop-up at once (the rest are on the page).
export const POPUP_MAX_UPDATES = 3; // Keeps the pop-up short.

// One change, as the database gives it (one row per change).
export type WhatsNewRow = { // Its fields:
  note_id: string; // the update it belongs to,
  title: string; // the update's title,
  show_from: string; // when the update started showing,
  item_id: string; // the change's id,
  kind: string; // added, updated or removed,
  body: string; // what changed.
}; // End of the shape.

// One update with its changes, ready to show.
export type WhatsNewUpdate = { // Its fields:
  id: string; // its id,
  title: string; // its title,
  showFrom: string; // when it started showing,
  items: { id: string; kind: string; body: string }[]; // its changes, in order.
}; // End of the shape.

// Groups the database rows into updates, keeping their order (newest first).
export function groupUpdates(rows: WhatsNewRow[]): WhatsNewUpdate[] { // Takes the rows; gives back the updates.
  const updates: WhatsNewUpdate[] = []; // The updates, in order.
  const byId = new Map<string, WhatsNewUpdate>(); // Each update by its id, to add changes to it.
  for (const r of rows) { // For each change:
    let u = byId.get(r.note_id); // finds its update,
    if (!u) { // or, if it's the first change seen for that update:
      u = { id: r.note_id, title: r.title, showFrom: r.show_from, items: [] }; // starts it,
      byId.set(r.note_id, u); // remembers it,
      updates.push(u); // and adds it to the list.
    } // End of the new-update case.
    u.items.push({ id: r.item_id, kind: r.kind, body: r.body }); // Adds the change to its update.
  } // End of the loop.
  return updates; // Hands back the updates.
} // End of groupUpdates.
