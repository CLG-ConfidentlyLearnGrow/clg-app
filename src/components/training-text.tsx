// Summary: shows lesson and handbook text with simple formatting. A line
// starting "## " is a heading, a line starting "- " is a bullet point, and
// a blank line starts a new paragraph. Web addresses become links. Text is
// never treated as HTML, so nothing written there can run as code.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".

// Turns web addresses in a line into links that open in a new tab.
function withLinks(line: string, key: string): ReactNode[] { // Takes one line and a key prefix.
  const parts = line.split(/(https:\/\/[^\s)]+)/g); // Splits the line around secure web addresses.
  return parts.map((part, i) => // For each piece:
    part.startsWith("https://") ? ( // a web address:
      <a key={`${key}-${i}`} href={part} target="_blank" rel="noopener noreferrer" className="text-teal-800 underline">{/* becomes a link that opens safely in a new tab, */}
        {part}{/* showing the address. */}
      </a> // End of the link.
    ) : ( // other text:
      part // stays as it is.
    ), // (end of the choice)
  ); // End of the pieces.
} // End of withLinks.

// Shows formatted text.
export function TrainingText({ text }: { text: string }) { // Takes the text.
  const blocks: ReactNode[] = []; // The headings, paragraphs and lists to show.
  let bullets: string[] = []; // Bullet points waiting to be shown as one list.
  let para: string[] = []; // Lines waiting to be shown as one paragraph.
  const flush = () => { // Shows any waiting list or paragraph:
    if (bullets.length) { // waiting bullet points:
      const k = `ul-${blocks.length}`; // a key for the list,
      blocks.push( // add a list:
        <ul key={k} className="list-disc space-y-1 pl-6">{/* a bulleted list, */}
          {bullets.map((b, i) => <li key={`${k}-${i}`}>{withLinks(b, `${k}-${i}`)}</li>)}{/* with each point (links made clickable). */}
        </ul>, // End of the list.
      ); // (end of adding it)
      bullets = []; // nothing waiting now.
    } // End of the list.
    if (para.length) { // waiting lines:
      const k = `p-${blocks.length}`; // a key for the paragraph,
      blocks.push(<p key={k}>{withLinks(para.join(" "), k)}</p>); // add them as one paragraph (links made clickable),
      para = []; // nothing waiting now.
    } // End of the paragraph.
  }; // End of flush.
  for (const raw of text.split(/\r?\n/)) { // For each line of the text:
    const line = raw.trim(); // without spaces at the ends.
    if (line === "") { flush(); continue; } // A blank line: ends the paragraph or list.
    if (line.startsWith("## ")) { // A heading:
      flush(); // ends what came before,
      blocks.push(<h3 key={`h-${blocks.length}`} className="pt-2 text-base font-semibold text-zinc-900">{line.slice(3)}</h3>); // and shows the heading.
      continue; // On to the next line.
    } // End of the heading.
    if (line.startsWith("- ")) { // A bullet point:
      if (para.length) flush(); // ends a paragraph before it,
      bullets.push(line.slice(2)); // and waits to join the list.
      continue; // On to the next line.
    } // End of the bullet point.
    if (bullets.length) flush(); // Ordinary text after a list: ends the list.
    para.push(line); // Waits to join the paragraph.
  } // End of the lines.
  flush(); // Shows anything still waiting.
  return <div className="space-y-3 text-sm leading-relaxed text-zinc-800">{blocks}</div>; // Shows the blocks with space between them.
} // End of TrainingText.
