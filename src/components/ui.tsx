// Summary: the basic building blocks every page uses, so the whole app looks
// the same: page layout and heading, cards, sub-headings, empty-list notes,
// tables, form fields, drop-down lists, form messages and links.
//
// The Next.js link, for moving between pages without a full reload.
import Link from "next/link";
// Type names from React: an HTML element's normal settings, and "anything that can be shown".
import type { ComponentProps, ReactNode } from "react";
// The list of role names, for type checking only.
import type { Role } from "@/lib/auth";
// The shape of a form's reply (error or message).
import type { FormState } from "@/lib/forms";
// The colours and heading for each role's dashboard.
import { ROLE_THEME } from "@/lib/role-theme";

// A whole page: a centred column with the heading at the top and the contents below.
export function Page({
  title, // The page heading.
  intro, // An optional sentence under the heading.
  role, // Which dashboard this is, if any (for its colour).
  children, // The page's contents.
}: { // The settings' types:
  title: string; // heading is text,
  intro?: ReactNode; // intro can be anything shown,
  role?: Role; // role is optional,
  children: ReactNode; // contents can be anything shown.
}) { // End of the settings.
  return ( // Shows:
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:py-12">{/* a main area, centred, up to a set width, with padding, */}
      {/* The heading, intro and coloured label. */}
      <PageTitle title={title} intro={intro} role={role} />
      {/* The contents, with space between each part. */}
      <div className="space-y-6">{children}</div>
    </main> // End of the main area.
  ); // End of what's shown.
} // End of Page.

// The page heading. With "role", a coloured label above it names the
// dashboard (e.g. "Parent dashboard") and the bar under it takes that
// dashboard's colour, so it's clear which profile you're in.
export function PageTitle({ title, intro, role }: { title: string; intro?: ReactNode; role?: Role }) {
  const theme = role ? ROLE_THEME[role] : null; // The role's colours, if a role was given.
  return ( // Shows:
    <div className="mb-8">{/* a block with space below it, */}
      {/* Only when a role was given: */}
      {theme && (
        <p // a small rounded label,
          className={`mb-3 inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-wide ${theme.tintBg} ${theme.strongText}`} // in the role's pale background and deep text,
        >{/* (end of the label's settings) */}
          {/* A small dot in the role's colour (hidden from screen readers). */}
          <span className={`h-2 w-2 rounded-full ${theme.accent}`} aria-hidden />
          {/* The dashboard's name, e.g. "Parent dashboard". */}
          {theme.title}
        </p> // End of the paragraph.
      )}{/* End of the label. */}
      {/* The heading itself, in the role's deep colour if there is one. */}
      <h1 className={`text-2xl font-semibold tracking-tight sm:text-3xl ${theme ? theme.strongText : ""}`}>{title}</h1>
      {/* A short bar under the heading, in the role's colour (or CLG bronze). */}
      <div className={`mt-3 h-1 w-12 rounded-full ${theme ? theme.accent : "bg-brand"}`} aria-hidden />
      {/* The intro sentence, if there is one. */}
      {intro && <p className="mt-4 max-w-2xl text-zinc-600">{intro}</p>}
    </div> // End of the block.
  ); // End of what's shown.
} // End of PageTitle.

// A white panel. The title and any description sit together at the top so
// the panel's contents read as belonging to it.
// A card. With "collapsible", the person can open and close it by tapping
// the title; "defaultOpen" sets whether it starts open.
export function Card({
  title, // The card's title (optional).
  description, // A sentence under the title (optional).
  children, // The card's contents.
  collapsible = false, // Whether it can be opened and closed (no by default).
  defaultOpen = true, // Whether it starts open (yes by default).
}: { // The settings' types:
  title?: string; // title is text,
  description?: ReactNode; // description can be anything shown,
  children: ReactNode; // contents can be anything shown,
  collapsible?: boolean; // collapsible is yes/no,
  defaultOpen?: boolean; // starts-open is yes/no.
}) { // End of the settings.
  const box = // The card's look:
    "rounded-2xl border border-zinc-200/80 bg-white p-6 shadow-[0_1px_3px_rgba(65,64,66,0.06),0_8px_24px_-12px_rgba(65,64,66,0.12)]"; // rounded, thin border, white, padded, soft shadow.
  if (collapsible && title) { // Collapsible cards with a title:
    return ( // show:
      <details open={defaultOpen} className={`group ${box}`}>{/* an open-and-close box with the card look, */}
        {/* The clickable title row (the browser's own arrow is hidden). */}
        <summary className="flex cursor-pointer list-none items-start justify-between gap-3 [&::-webkit-details-marker]:hidden">
          {/* The left side: */}
          <span>
            {/* the title, */}
            <span className="block text-lg font-semibold tracking-tight">{title}</span>
            {/* and the description, if any. */}
            {description && <span className="mt-1 block text-sm text-zinc-600">{description}</span>}
          </span>{/* End of the text. */}
          {/* The right side: words showing what a tap will do. */}
          <span className="mt-1 shrink-0 text-sm text-teal-800">
            {/* "Show" while closed, */}
            <span className="group-open:hidden">Show</span>
            {/* "Hide" while open. */}
            <span className="hidden group-open:inline">Hide</span>
          </span>{/* End of the text. */}
        </summary>{/* End of the clickable title. */}
        {/* The contents, under a thin line. */}
        <div className="mt-5 border-t border-zinc-100 pt-5">{children}</div>
      </details> // End of the open-and-close box.
    ); // End of what's shown.
  } // End of the collapsible case.
  return ( // Otherwise shows:
    <section className={box}>{/* a plain card, */}
      {/* Only if there's a title or description: */}
      {(title || description) && (
        // a header with a thin line under it,
        <header className="mb-5 border-b border-zinc-100 pb-4">
          {/* the title, */}
          {title && <h2 className="text-lg font-semibold tracking-tight">{title}</h2>}
          {/* and the description. */}
          {description && <p className="mt-1 text-sm text-zinc-600">{description}</p>}
        </header> // End of the header.
      )}{/* End of this part. */}
      {/* The contents. */}
      {children}
    </section> // End of the section.
  ); // End of what's shown.
} // End of Card.

// A heading inside a card, for a smaller part of it.
export function SubHeading({ children }: { children: ReactNode }) {
  return ( // Shows:
    <h3 className="mt-8 mb-3 flex items-center gap-2 text-sm font-semibold text-zinc-800 first:mt-0">{/* a small heading with space above (none if it's first), */}
      {/* a short bronze bar before the words (hidden from screen readers), */}
      <span className="h-4 w-1 rounded-full bg-brand" aria-hidden />
      {/* and the heading's words. */}
      {children}
    </h3> // End of the heading.
  ); // End of what's shown.
} // End of SubHeading.

// Shown when a list or table has nothing in it yet.
export function Empty({ children }: { children: ReactNode }) {
  return <p className="rounded-xl bg-zinc-50 px-4 py-3 text-sm text-zinc-500">{children}</p>; // A pale grey box with small grey text.
} // End of Empty.

// A simple table: headings in a tinted band, rows separated by thin lines.
export function Table({ headings, children }: { headings: string[]; children: ReactNode }) {
  return ( // Shows:
    <div className="overflow-x-auto rounded-xl border border-zinc-200">{/* a rounded box that scrolls sideways on small screens, */}
      <table className="w-full text-left text-sm">{/* holding the table, full width, */}
        <thead className="bg-zinc-50 text-xs uppercase tracking-wide text-zinc-600">{/* with a tinted heading band, */}
          {/* in one row: */}
          <tr>
            {/* each heading: */}
            {headings.map((h) => (
              // as a column heading cell,
              <th key={h} scope="col" className="px-4 py-2.5 font-semibold">
                {/* showing its words. */}
                {h}
              </th> // End of the heading cell.
            ))}{/* End of the loop. */}
          </tr>{/* End of the row. */}
        </thead>{/* End of the heading band. */}
        {/* The rows, with thin lines between and padding in each cell. */}
        <tbody className="divide-y divide-zinc-100 [&_td]:px-4 [&_td]:py-2.5">{children}</tbody>
      </table>{/* End of the table. */}
    </div> // End of the block.
  ); // End of what's shown.
} // End of Table.

// A labelled text box. Any normal text box setting can be passed in.
export function Field({
  label, // The words above the box.
  hint, // Optional help under the box.
  ...input // Every other setting, passed to the box.
}: { label: string; hint?: string } & ComponentProps<"input">) { // The settings' types.
  return ( // Shows:
    <label className="block space-y-1">{/* a label wrapping everything (tapping the words focuses the box), */}
      {/* the words above the box, */}
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      {/* the text box itself: */}
      <input
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // with CLG's rounded, bordered look and a bronze outline when in use,
        {...input} // and all the other settings passed through.
      />{/* (end of the element) */}
      {/* The help text, if any. */}
      {hint && <span className="block text-xs text-zinc-500">{hint}</span>}
    </label> // End of the label.
  ); // End of what's shown.
} // End of Field.

// A labelled multi-line text box. Any normal setting can be passed in.
export function TextArea({
  label, // The words above the box.
  hint, // Optional help under the box.
  ...input // Every other setting, passed to the box.
}: { label: string; hint?: string } & ComponentProps<"textarea">) { // The settings' types.
  return ( // Shows:
    <label className="block space-y-1">{/* a label wrapping everything, */}
      {/* the words above the box, */}
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      {/* the multi-line box itself: */}
      <textarea
        rows={3} // three lines tall to start,
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // with CLG's rounded, bordered look,
        {...input} // and all the other settings passed through.
      />{/* (end of the element) */}
      {/* The help text, if any. */}
      {hint && <span className="block text-xs text-zinc-500">{hint}</span>}
    </label> // End of the label.
  ); // End of what's shown.
} // End of TextArea.

// A labelled drop-down list. The choices are passed in as children.
export function Select({
  label, // The words above the list.
  children, // The choices.
  ...select // Every other setting, passed to the list.
}: { label: string } & ComponentProps<"select">) { // The settings' types.
  return ( // Shows:
    <label className="block space-y-1">{/* a label wrapping everything, */}
      {/* the words above the list, */}
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      {/* the drop-down list itself: */}
      <select
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none" // with CLG's rounded, bordered look,
        {...select} // and all the other settings passed through.
      >{/* (end of the settings) */}
        {/* The choices. */}
        {children}
      </select>{/* End of the drop-down. */}
    </label> // End of the label.
  ); // End of what's shown.
} // End of Select.

// The main button. It lives in its own file because it watches its form:
// while the form is saving it is switched off and shows a spinner, so it
// can't be pressed twice.
export { Button, BusyButton } from "@/components/busy-button"; // Passes on the two buttons from their own file.

// The message shown after a form is sent: red for a problem, green for success.
export function FormMessage({ state }: { state: FormState }) {
  if (state.error) { // There's an error:
    return ( // shows:
      <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">{/* a red box (read out straight away by screen readers), */}
        {/* with the error's words. */}
        {state.error}
      </p> // End of the paragraph.
    ); // End of what's shown.
  } // End of the error case.
  if (state.message) { // There's a success message:
    return ( // shows:
      <p role="status" className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900 [overflow-wrap:anywhere]">{/* a green box (read out politely by screen readers; long links wrap), */}
        {/* with the message's words. */}
        {state.message}
      </p> // End of the paragraph.
    ); // End of what's shown.
  } // End of the message case.
  return null; // Nothing to show.
} // End of FormMessage.

// A link in CLG's style: teal, underlined, darker underline on hover.
export function TextLink(props: ComponentProps<typeof Link>) {
  return <Link className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 transition hover:decoration-teal-700" {...props} />; // Shows the link with the style, passing every setting through.
} // End of TextLink.
