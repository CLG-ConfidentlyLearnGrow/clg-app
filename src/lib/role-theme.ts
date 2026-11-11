import type { Role } from "@/lib/auth";

// The colour and heading for each dashboard, so it's obvious which profile
// you're in. Colours are set in globals.css. Class names are written out in
// full so the styling tool can find them.
export type RoleTheme = {
  title: string; // shown above the page heading, e.g. "Parent dashboard"
  accent: string; // background in the accent colour (bars, dots)
  accentBorder: string; // border in the accent colour
  accentTopBorder: string; // top border in the accent colour
  strongText: string; // text in the deep shade
  strongBg: string; // filled background in the deep shade (white text on top)
  tintBg: string; // pale background
  hoverTint: string; // pale background on hover
};

export const ROLE_THEME: Record<Role, RoleTheme> = {
  admin: {
    title: "Admin dashboard",
    accent: "bg-admin-accent",
    accentBorder: "border-admin-accent",
    accentTopBorder: "border-t-admin-accent",
    strongText: "text-admin-strong",
    strongBg: "bg-admin-strong",
    tintBg: "bg-admin-tint",
    hoverTint: "hover:bg-admin-tint",
  },
  tutor: {
    title: "Tutor dashboard",
    accent: "bg-tutor-accent",
    accentBorder: "border-tutor-accent",
    accentTopBorder: "border-t-tutor-accent",
    strongText: "text-tutor-strong",
    strongBg: "bg-tutor-strong",
    tintBg: "bg-tutor-tint",
    hoverTint: "hover:bg-tutor-tint",
  },
  parent: {
    title: "Parent dashboard",
    accent: "bg-parent-accent",
    accentBorder: "border-parent-accent",
    accentTopBorder: "border-t-parent-accent",
    strongText: "text-parent-strong",
    strongBg: "bg-parent-strong",
    tintBg: "bg-parent-tint",
    hoverTint: "hover:bg-parent-tint",
  },
  student: {
    title: "Student dashboard",
    accent: "bg-student-accent",
    accentBorder: "border-student-accent",
    accentTopBorder: "border-t-student-accent",
    strongText: "text-student-strong",
    strongBg: "bg-student-strong",
    tintBg: "bg-student-tint",
    hoverTint: "hover:bg-student-tint",
  },
};
