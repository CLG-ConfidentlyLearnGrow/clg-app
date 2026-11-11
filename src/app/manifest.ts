// Summary: the app's install details (name, colours, icons) for phones and computers.
//
import type { MetadataRoute } from "next"; // The type for an install details file.

// Lets people install CLG on their phone or computer from the browser, so it
// opens like an app. A store app can come later.
export default function manifest(): MetadataRoute.Manifest {
  return { // Gives back:
    name: "CLG Tutoring", // the full name,
    short_name: "CLG", // the short name under the icon,
    description: "Tutoring, homework and learning support from CLG.", // a one-line description,
    start_url: "/dashboard", // the page it opens on,
    display: "standalone", // opens without the browser's address bar,
    background_color: "#ede8e4", // the background colour while it opens,
    theme_color: "#ede8e4", // the colour of the top bar,
    icons: [ // the icons:
      { src: "/icons/icon-192-book.png", sizes: "192x192", type: "image/png" }, // a small one,
      { src: "/icons/icon-512-book.png", sizes: "512x512", type: "image/png" }, // a large one,
      { src: "/icons/icon-maskable-512-book.png", sizes: "512x512", type: "image/png", purpose: "maskable" }, // and one that phones can crop to a shape.
    ], // (end of the icons)
  }; // End of the details.
} // End of manifest.
