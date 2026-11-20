// Summary: shows a contract's wording on screen. Contracts are written in
// simple Markdown (the format a Claude Doc exports to): # headings,
// paragraphs, bullet and numbered lists, tables, quotes, **bold**, *italic*
// and [links](https://...). This turns that text into page parts without
// ever treating it as HTML, so nothing in a contract can run as code. Links
// only work for web addresses (https) and pages in this app. Links to pages
// in this app (such as CLG's policies) show as buttons (Carla, 18 Nov 2026),
// and old outside addresses of those documents can be swapped for their app
// page with the "links" setting.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".

// Removes Markdown's backslash escapes (for example \[ becomes [).
function unescape(text: string): string { // Takes some text.
  return text.replace(/\\([\\`*_{}[\]()#+\-.!|>~])/g, "$1"); // Drops the backslash before any character Markdown lets you escape.
} // End of unescape.

// Whether a link is safe to follow: a web address or a page in this app.
function safeHref(href: string): string | null { // Takes the link.
  const h = href.trim(); // Without spaces at the ends.
  return /^https:\/\//i.test(h) || (h.startsWith("/") && !h.startsWith("//")) ? h : null; // Allowed: https addresses and app pages; anything else is shown as plain text.
} // End of safeHref.

// Old addresses swapped for app pages (old address -> app page), set by ContractText.
type LinkMap = Record<string, string>; // The shape of the swap list.

// Turns one line's inline Markdown (bold, italic, links) into page parts.
function inline(text: string, keyBase: string, links: LinkMap = {}): ReactNode[] { // Takes the text, a key prefix and the swap list.
  const parts: ReactNode[] = []; // The page parts made so far.
  const pattern = /\*\*([^*]+?)\*\*|\[([^\]]+?)\]\(([^)\s]+)\)|(?<![\w*])\*([^*]+?)\*(?!\w)|(?<!\w)_([^_]+?)_(?!\w)/g; // Bold, links, then italic (with * or _).
  let last = 0; // Where the plain text before the next match starts.
  let n = 0; // Counts matches, for keys.
  for (const m of text.matchAll(pattern)) { // Goes through each match:
    if (m.index > last) parts.push(unescape(text.slice(last, m.index))); // the plain text before it,
    const key = `${keyBase}-${n++}`; // a key for this part,
    if (m[1] !== undefined) parts.push(<strong key={key}>{inline(m[1], key, links)}</strong>); // bold text (which may hold links),
    else if (m[2] !== undefined) { // a link:
      const href = safeHref(links[m[3].trim()] ?? m[3]); // swaps an old address for its app page, then checks the address is safe,
      parts.push( // and shows:
        !href ? <span key={key}>{unescape(m[2])}</span> // just its words when the address is not safe,
        : href.startsWith("/") ? <a key={key} href={href} target="_blank" rel="noreferrer" className="mx-0.5 inline-flex items-center rounded-lg border border-brand bg-brand px-2.5 py-0.5 text-sm font-medium text-white no-underline hover:opacity-90">{unescape(m[2])}</a> // a button for a page in this app (opens in a new tab, so the contract stays open),
        : <a key={key} href={href} target="_blank" rel="noreferrer" className="text-teal-800 underline">{unescape(m[2])}</a>, // or a plain link to an outside page (in a new tab).
      ); // End of what is shown.
    } // End of the link case.
    else parts.push(<em key={key}>{unescape(m[4] ?? m[5] ?? "")}</em>); // italic text.
    last = m.index + m[0].length; // Moves past the match.
  } // End of the matches.
  if (last < text.length) parts.push(unescape(text.slice(last))); // The plain text after the last match.
  return parts; // Hands back the parts.
} // End of inline.

// Splits a table row like "| a | b |" into its cells.
function cells(row: string): string[] { // Takes the row's text.
  return row.trim().replace(/^\|/, "").replace(/\|$/, "").split(/(?<!\\)\|/).map((c) => c.trim()); // Drops the outer bars, then splits on bars that are not escaped.
} // End of cells.

// Shows a contract's wording. "links" swaps old addresses for app pages.
export function ContractText({ text, links = {} }: { text: string; links?: LinkMap }) { // Takes the wording and the swap list.
  const lines = text.replace(/\r\n?/g, "\n").split("\n"); // The wording, one line at a time (any line ending).
  const blocks: ReactNode[] = []; // The page parts made so far.
  let i = 0; // The line being read.
  while (i < lines.length) { // Goes through every line:
    const line = lines[i]; // this line,
    const key = `b${i}`; // a key for the part it starts.
    if (!line.trim()) { i++; continue; } // A blank line: skip it.
    const heading = line.match(/^(#{1,4})\s+(.*)$/); // A heading ("# Title")?
    if (heading) { // Yes:
      const level = heading[1].length; // how many # marks (1 is the biggest),
      const size = level === 1 ? "text-xl" : level === 2 ? "text-lg" : "text-base"; // its size,
      blocks.push(<p key={key} role="heading" aria-level={level + 1} className={`${size} mt-6 mb-2 font-semibold first:mt-0`}>{inline(heading[2], key, links)}</p>); // shown as a heading,
      i++; continue; // and moves on.
    } // End of the heading case.
    if (/^\s*\|/.test(line)) { // A table (lines starting with "|"):
      const rows: string[] = []; // its rows,
      while (i < lines.length && /^\s*\|/.test(lines[i])) rows.push(lines[i++]); // gathers every table line,
      const body = rows.filter((r) => !/^\s*\|?\s*:?-{2,}/.test(r)); // leaves out the "| --- |" line under the headings,
      const [head, ...rest] = body.map(cells); // the heading row and the other rows,
      blocks.push( // shows:
        <div key={key} className="my-3 overflow-x-auto rounded-lg border border-zinc-200">{/* a box that scrolls sideways on small screens, */}
          <table className="w-full text-left text-sm">{/* holding the table: */}
            {head && head.some(Boolean) && <thead className="bg-zinc-50"><tr>{head.map((c, j) => <th key={j} className="px-3 py-2 font-semibold">{inline(c, `${key}h${j}`, links)}</th>)}</tr></thead>}{/* the heading row (if it has words), */}
            <tbody className="divide-y divide-zinc-100">{rest.map((r, ri) => <tr key={ri}>{r.map((c, j) => <td key={j} className="px-3 py-2 align-top">{inline(c, `${key}r${ri}c${j}`, links)}</td>)}</tr>)}</tbody>{/* and the other rows. */}
          </table>{/* End of the table. */}
        </div> // End of the box.
      ); // End of the table part.
      continue; // Moves on (the loop already moved past the table).
    } // End of the table case.
    if (/^\s*([-*+]|\d+\.)\s+/.test(line)) { // A list item ("- item" or "1. item"):
      const numbered = /^\s*\d+\.\s+/.test(line); // whether the list is numbered,
      const items: string[] = []; // its items,
      while (i < lines.length && /^\s*([-*+]|\d+\.)\s+/.test(lines[i])) items.push(lines[i++].replace(/^\s*([-*+]|\d+\.)\s+/, "").replace(/^\[[ xX]\]\s+/, "")); // gathers each item's words (and drops tick-box marks),
      const List = numbered ? "ol" : "ul"; // a numbered or bullet list,
      blocks.push(<List key={key} className={`my-2 space-y-1 pl-5 text-sm ${numbered ? "list-decimal" : "list-disc"}`}>{items.map((t, j) => <li key={j}>{inline(t, `${key}i${j}`, links)}</li>)}</List>); // shown with each item,
      continue; // and moves on.
    } // End of the list case.
    if (/^\s*>/.test(line)) { // A quote ("> note"):
      const quoted: string[] = []; // its lines,
      while (i < lines.length && /^\s*>/.test(lines[i])) quoted.push(lines[i++].replace(/^\s*>\s?/, "")); // gathers each quoted line,
      blocks.push(<blockquote key={key} className="my-3 border-l-4 border-brand bg-zinc-50 px-4 py-2 text-sm">{inline(quoted.join(" "), key, links)}</blockquote>); // shown as a note with a bronze bar,
      continue; // and moves on.
    } // End of the quote case.
    const para: string[] = []; // A paragraph: its lines,
    while (i < lines.length && lines[i].trim() && !/^(#{1,4}\s|\s*\||\s*([-*+]|\d+\.)\s+|\s*>)/.test(lines[i])) para.push(lines[i++].trim()); // gathers lines until a blank line or another kind of part,
    blocks.push(<p key={key} className="my-2 text-sm leading-relaxed">{inline(para.join(" "), key, links)}</p>); // shown as one paragraph.
  } // End of the lines.
  return <div className="max-w-none">{blocks}</div>; // Hands back every part, in order.
} // End of ContractText.
