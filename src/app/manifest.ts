import type { MetadataRoute } from "next";

// Lets people install CLG on their phone or computer from the browser, so it
// opens like an app. A store app can come later.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "CLG Tutoring",
    short_name: "CLG",
    description: "Tutoring, homework and learning support from CLG.",
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#ede8e4",
    theme_color: "#ede8e4",
    icons: [
      { src: "/icons/icon-192-logo.png", sizes: "192x192", type: "image/png" },
      { src: "/icons/icon-512-logo.png", sizes: "512x512", type: "image/png" },
      { src: "/icons/icon-maskable-512-logo.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
