// Summary: shows one app guide ("how to use the app" handbook): a contents
// list of its parts, then each part with its short intro and its tasks.
// Each task is a fold-out with numbered steps, so people open only what
// they need. With search words, only the tasks containing every word are
// shown, already opened. Text is never treated as HTML, so nothing in a
// guide can run as code; **words in stars** are shown in bold.
//
import type { ReactNode } from "react"; // The type for "anything that can be shown".
import type { Guide, GuideBlock, GuideTask } from "@/lib/app-guides"; // The guide shapes (for type checking only).

// Shows a line of text with **starred** words in bold (the names of buttons and menu items).
function Rich({ text }: { text: string }) { // Takes the line.
  const pieces = text.split(/\*\*(.+?)\*\*/g); // Splits around starred words: odd pieces are the starred ones.
  return ( // Shows:
    <>{/* (a group) */}
      {pieces.map((piece, i) => (i % 2 === 1 ? <strong key={i} className="font-semibold text-zinc-900">{piece}</strong> : piece))}{/* each piece, starred ones in bold. */}
    </> // End of the group.
  ); // End of what's shown.
} // End of Rich.

// Shows one block: a paragraph, a tip, numbered steps or bullet points.
function Block({ block }: { block: GuideBlock }) { // Takes the block.
  if (block.kind === "steps") { // Numbered steps:
    return ( // shows:
      <ol className="list-decimal space-y-1.5 pl-6 marker:font-semibold marker:text-zinc-500">{/* a numbered list, */}
        {block.items.map((item, i) => <li key={i} className="pl-1"><Rich text={item} /></li>)}{/* with each step. */}
      </ol> // End of the list.
    ); // End of the steps.
  } // End of steps.
  if (block.kind === "bullets") { // Bullet points:
    return ( // shows:
      <ul className="list-disc space-y-1.5 pl-6">{/* a bulleted list, */}
        {block.items.map((item, i) => <li key={i}><Rich text={item} /></li>)}{/* with each point. */}
      </ul> // End of the list.
    ); // End of the bullets.
  } // End of bullets.
  if (block.kind === "tip") { // A tip:
    return ( // shows:
      <p className="rounded-lg border border-teal-100 bg-teal-50 px-3 py-2 text-teal-900">{/* a soft box, */}
        <strong className="font-semibold">Tip: </strong><Rich text={block.text} />{/* starting with "Tip:". */}
      </p> // End of the box.
    ); // End of the tip.
  } // End of a tip.
  return <p><Rich text={block.text} /></p>; // Otherwise a plain paragraph.
} // End of Block.

// Shows a list of blocks with space between them.
function Blocks({ blocks }: { blocks: GuideBlock[] }) { // Takes the blocks.
  return <div className="space-y-3">{blocks.map((b, i) => <Block key={i} block={b} />)}</div>; // Each block, spaced out.
} // End of Blocks.

// All the words in a task (its heading and every line), for searching.
function taskWords(task: GuideTask): string { // Takes the task.
  const lines = task.blocks.flatMap((b) => (b.kind === "steps" || b.kind === "bullets" ? b.items : [b.text])); // Every line of its blocks.
  return `${task.title} ${lines.join(" ")}`.replace(/\*\*/g, "").toLowerCase(); // With the heading, stars removed, in lower case.
} // End of taskWords.

// Shows a whole guide, or only the tasks matching the search words.
export function AppGuideView({ guide, query }: { guide: Guide; query: string }) { // Takes the guide and the search words.
  const words = query.toLowerCase().split(/\s+/).filter(Boolean); // The search words, one by one.
  const matches = (task: GuideTask) => words.every((w) => taskWords(task).includes(w)); // Whether a task has every word.
  const parts = guide.parts // The parts to show:
    .map((p) => ({ ...p, tasks: words.length ? p.tasks.filter(matches) : p.tasks })) // with only matching tasks when searching,
    .filter((p) => !words.length || p.tasks.length > 0); // and, when searching, only parts with a match.
  const found = parts.reduce((n, p) => n + p.tasks.length, 0); // How many tasks are shown.

  const sections: ReactNode[] = parts.map((p) => ( // Each part:
    <section key={p.id} id={p.id} className="scroll-mt-24 rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm">{/* a card, which the contents can jump to: */}
      <h2 className="text-lg font-semibold text-zinc-900">{p.heading}</h2>{/* its heading, */}
      {!words.length && p.blocks.length > 0 && <div className="mt-3 text-sm leading-relaxed text-zinc-800"><Blocks blocks={p.blocks} /></div>}{/* its intro (not while searching), */}
      {p.tasks.length > 0 && ( // its tasks, if any:
        <ul className="mt-3 divide-y divide-zinc-100">{/* a list with lines between: */}
          {p.tasks.map((t, i) => ( // each task:
            <li key={i}>{/* a row: */}
              <details className="group py-2" open={words.length > 0}>{/* a fold-out (open when searching): */}
                <summary className="cursor-pointer list-none py-1 text-sm font-medium text-teal-800 hover:underline">{/* its heading: */}
                  <span aria-hidden className="mr-2 inline-block transition-transform group-open:rotate-90">›</span>{/* an arrow that turns when open, */}
                  {t.title}{/* and the task's name. */}
                </summary>{/* End of the heading. */}
                <div className="mt-2 pb-2 pl-5 text-sm leading-relaxed text-zinc-800"><Blocks blocks={t.blocks} /></div>{/* the steps. */}
              </details>{/* End of the fold-out. */}
            </li> // End of the row.
          ))}{/* End of the tasks. */}
        </ul> // End of the list.
      )}{/* End of the tasks. */}
    </section> // End of the part.
  )); // End of the parts.

  return ( // Shows:
    <div className="space-y-6">{/* the guide, with space between parts: */}
      {words.length > 0 && ( // When searching:
        <p className="text-sm text-zinc-600">{found} task{found === 1 ? "" : "s"} found for &ldquo;{query}&rdquo;.</p> // how many were found.
      )}{/* End of the count. */}
      {!words.length && ( // When not searching:
        <nav aria-label="Contents" className="rounded-2xl border border-zinc-200 bg-white p-5 shadow-sm">{/* the contents: */}
          <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-500">Contents</h2>{/* a small heading, */}
          <ol className="mt-2 grid gap-1 text-sm sm:grid-cols-2">{/* the parts, in two columns on wider screens: */}
            {guide.parts.map((p, i) => ( // each part:
              <li key={p.id}><a href={`#${p.id}`} className="text-teal-800 underline underline-offset-4">{i + 1}. {p.heading}</a></li> // a link that jumps to it.
            ))}{/* End of the parts. */}
          </ol>{/* End of the list. */}
        </nav> // End of the contents.
      )}{/* End of this part. */}
      {sections}{/* The parts themselves. */}
    </div> // End of the guide.
  ); // End of what's shown.
} // End of AppGuideView.
