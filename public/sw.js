// Summary: the CLG app's service worker. It is a small script the browser
// keeps on the device, so pop-up notifications can arrive even when the app
// is closed or the person has been signed out for being inactive (Carla,
// 18 Nov 2026). It does nothing else: no saving pages for offline use.

// Turns on straight away when a new version is installed, instead of
// waiting for every CLG tab to be closed first.
self.addEventListener("install", () => { // When the browser installs this script:
  self.skipWaiting(); // start using it now.
}); // End of the install step.

// Takes charge of any CLG tabs that are already open.
self.addEventListener("activate", (event) => { // When this script becomes active:
  event.waitUntil(self.clients.claim()); // look after the open CLG tabs too.
}); // End of the activate step.

// Shows a pop-up when CLG's server sends one. The server only ever sends a
// plain title and message with no names or details, because pop-ups can
// show on a locked screen.
self.addEventListener("push", (event) => { // When a pop-up arrives from the push service:
  let data = {}; // the pop-up's details, empty to start.
  try { // Reading them could fail if the message is not as expected,
    data = event.data ? event.data.json() : {}; // so reads the details sent by CLG (if any).
  } catch { // If they cannot be read:
    data = {}; // carries on with no details (the usual words are used below).
  } // End of reading the details.
  const title = typeof data.title === "string" && data.title ? data.title : "CLG Tutoring"; // The heading, or "CLG Tutoring" if none.
  const options = { // How the pop-up looks and behaves:
    body: typeof data.body === "string" && data.body ? data.body : "You have a new notice. Open the CLG app to see it.", // the message, or the usual words,
    icon: "/icons/icon-192-book.png", // the CLG book icon,
    badge: "/icons/icon-192-book.png", // the small icon shown in the phone's top bar,
    tag: typeof data.tag === "string" ? data.tag : undefined, // a label so a newer pop-up of the same kind replaces the older one,
    renotify: typeof data.tag === "string", // still buzzes when it replaces an older one,
    requireInteraction: data.urgent === true, // urgent ones stay on screen until tapped,
    data: { link: typeof data.link === "string" && data.link.startsWith("/") ? data.link : "/dashboard" }, // and which CLG page to open when tapped (only pages inside CLG).
  }; // End of the settings.
  event.waitUntil(self.registration.showNotification(title, options)); // Shows the pop-up (the browser waits until it is shown).
}); // End of the push step.

// Opens the right CLG page when someone taps a pop-up. If they have been
// signed out, the app asks them to sign in first.
self.addEventListener("notificationclick", (event) => { // When a pop-up is tapped:
  event.notification.close(); // closes the pop-up,
  const link = (event.notification.data && event.notification.data.link) || "/dashboard"; // the page to open (the dashboard if none was given),
  const target = new URL(link, self.location.origin).href; // turned into a full CLG web address.
  event.waitUntil( // The browser waits while it:
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => { // looks for CLG windows already open,
      for (const win of windows) { // and for each one:
        if (win.url.startsWith(self.location.origin) && "focus" in win) { // if it is a CLG window that can be brought forward,
          return win.focus().then(() => win.navigate(target)); // brings it forward and opens the page there.
        } // End of the check.
      } // End of the loop.
      return self.clients.openWindow(target); // No CLG window open: opens a new one at the page.
    }), // End of the window search.
  ); // End of the wait.
}); // End of the tap step.

// If the browser replaces this device's delivery address (it does this now
// and then), tell CLG the new one so pop-ups keep arriving. This only works
// while the person is signed in; otherwise the app updates it next time
// they open it.
self.addEventListener("pushsubscriptionchange", (event) => { // When the device's delivery address changes:
  event.waitUntil( // the browser waits while it:
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => { // finds any open CLG windows,
      windows.forEach((win) => win.postMessage({ type: "clg-push-refresh" })); // and asks each to save the new address.
    }), // End of the search.
  ); // End of the wait.
}); // End of the address change step.
