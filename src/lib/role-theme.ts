// Summary: the colour and heading for each role's dashboard, so it's always
// obvious which profile (admin, tutor, parent, student) you're in.

// The list of role names, for type checking only.
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
}; // End of the theme shape.

// The actual colours and heading for each role.
export const ROLE_THEME: Record<Role, RoleTheme> = {
  admin: { // The admin dashboard's look.
    title: "Admin dashboard", // Heading shown above the page title.
    accent: "bg-admin-accent", // Accent-coloured background.
    accentBorder: "border-admin-accent", // Accent-coloured border.
    accentTopBorder: "border-t-admin-accent", // Accent-coloured top border.
    strongText: "text-admin-strong", // Deep-shade text.
    strongBg: "bg-admin-strong", // Deep-shade filled background.
    tintBg: "bg-admin-tint", // Pale background.
    hoverTint: "hover:bg-admin-tint", // Pale background when hovered.
  }, // End of this role's look.
  tutor: { // The tutor dashboard's look.
    title: "Tutor dashboard", // Heading shown above the page title.
    accent: "bg-tutor-accent", // Accent-coloured background.
    accentBorder: "border-tutor-accent", // Accent-coloured border.
    accentTopBorder: "border-t-tutor-accent", // Accent-coloured top border.
    strongText: "text-tutor-strong", // Deep-shade text.
    strongBg: "bg-tutor-strong", // Deep-shade filled background.
    tintBg: "bg-tutor-tint", // Pale background.
    hoverTint: "hover:bg-tutor-tint", // Pale background when hovered.
  }, // End of this role's look.
  parent: { // The parent dashboard's look.
    title: "Parent dashboard", // Heading shown above the page title.
    accent: "bg-parent-accent", // Accent-coloured background.
    accentBorder: "border-parent-accent", // Accent-coloured border.
    accentTopBorder: "border-t-parent-accent", // Accent-coloured top border.
    strongText: "text-parent-strong", // Deep-shade text.
    strongBg: "bg-parent-strong", // Deep-shade filled background.
    tintBg: "bg-parent-tint", // Pale background.
    hoverTint: "hover:bg-parent-tint", // Pale background when hovered.
  }, // End of this role's look.
  student: { // The student dashboard's look.
    title: "Student dashboard", // Heading shown above the page title.
    accent: "bg-student-accent", // Accent-coloured background.
    accentBorder: "border-student-accent", // Accent-coloured border.
    accentTopBorder: "border-t-student-accent", // Accent-coloured top border.
    strongText: "text-student-strong", // Deep-shade text.
    strongBg: "bg-student-strong", // Deep-shade filled background.
    tintBg: "bg-student-tint", // Pale background.
    hoverTint: "hover:bg-student-tint", // Pale background when hovered.
  }, // End of this role's look.
}; // End of the role themes.
