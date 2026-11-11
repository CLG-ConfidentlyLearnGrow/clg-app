// Summary: proves that a change only added or edited comments, with no change
// to what the code does. For every changed code file, it reads the old and
// new versions into a tree of their working parts (ignoring comments, and
// the empty {/* */} holders used for comments inside page markup) and checks
// the two trees are identical. Database (.sql) files are compared word by
// word instead, skipping -- and /* */ comments but keeping every quoted text exactly.
// Run it with: node scripts/check-comments-only.mjs [branch to compare with]

// Lets this script use the TypeScript tool (which can read code into a tree).
import { createRequire } from "node:module";
// Lets this script run git commands.
import { execSync } from "node:child_process";
// Lets this script read files.
import { existsSync, readFileSync } from "node:fs";

// Loads TypeScript the old-style way, since it's not an ES module.
const ts = createRequire(import.meta.url)("typescript");
// The version to compare against: the branch named when running, or main.
const base = process.argv[2] ?? "origin/main";
// Asks git which code files differ from that version.
const changed = execSync(`git diff --name-only ${base} -- "*.ts" "*.tsx" "*.js" "*.mjs" "*.sql"`, { encoding: "utf8" })
  .split("\n") // One file name per line.
  .filter(Boolean); // Drops the blank line at the end.

// Works out the words page markup really shows, using React's rule: spaces
// next to a line break are dropped, and the remaining lines are joined with
// one space. Comments never affect this.
function shownText(raw) {
  const lines = raw.split(/\r\n|\n|\r/); // Splits the text into lines.
  const kept = []; // The tidied lines that still have words.
  lines.forEach((line, i) => { // Goes through each line:
    let t = line.replace(/\t/g, " "); // treats tabs as spaces,
    if (i > 0) t = t.replace(/^[ ]+/, ""); // drops leading spaces, except on the first line,
    if (i < lines.length - 1) t = t.replace(/[ ]+$/, ""); // drops trailing spaces, except on the last line,
    if (t) kept.push(t); // and keeps it if anything is left.
  }); // End of the loop.
  return kept.join(" "); // Joins the lines with single spaces.
} // End of shownText.

// Writes out a file's working parts as one long line of text, skipping comments.
function shape(source, fileName) {
  const kind = fileName.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS; // Page files contain markup.
  const file = ts.createSourceFile(fileName, source, ts.ScriptTarget.Latest, false, kind); // Reads the code into a tree.
  const out = []; // The pieces written out so far.
  const walk = (node) => { // Visits one part of the tree:
    if (ts.isJsxExpression(node) && !node.expression && !node.dotDotDotToken) return; // skips empty {/* comment */} holders,
    if (ts.isJsxText(node)) { // for words in page markup,
      const t = shownText(node.text); // works out what's really shown,
      if (t) out.push(`text(${JSON.stringify(t)})`); // and writes that (nothing if it's only spacing),
      return; // then stops here.
    } // End of the markup words case.
    out.push(ts.SyntaxKind[node.kind]); // Writes the kind of part (e.g. "IfStatement").
    if (node.kind < ts.SyntaxKind.FirstNode) out.push(JSON.stringify(node.getText(file))); // For single words and values, writes the exact text.
    ts.forEachChild(node, walk); // Visits each inner part.
    out.push(")"); // Marks the end of this part.
  }; // End of walk.
  walk(file); // Starts at the top of the file.
  if (file.parseDiagnostics?.length) out.push("PARSE-ERROR"); // Broken code never counts as the same.
  return out.join(" "); // Hands back the whole description.
} // End of shape.

// Writes out a database file's working words as one long line, skipping
// comments and spacing. Quoted text ('...' and "...") is kept exactly, so a
// comment marker typed inside quotes counts as a change. Function bodies
// between $$ marks are read the same way, since they are database code too.
function sqlShape(source) {
  const out = []; // The words written out so far.
  let i = 0; // Where the reading has got to.
  while (i < source.length) { // Reads to the end of the file:
    const c = source[i]; // the next letter,
    if (/\s/.test(c)) { i++; continue; } // spacing is skipped,
    if (c === "\\") { // a backslash starts a psql command (such as \gset), which runs to the end of the line,
      const end = source.indexOf("\n", i); // so it finds the end of the line,
      const stop = end < 0 ? source.length : end; // (or the end of the file),
      out.push(`psql(${source.slice(i, stop).trim()})`); // keeps the rest of the line exactly (a comment there would be read by psql),
      i = stop; // and moves past it.
      continue; // Carries on reading.
    } // End of the psql command case.
    if (source.startsWith("--", i)) { // A -- comment:
      while (i < source.length && source[i] !== "\n") i++; // skips to the end of the line.
      continue; // Carries on reading.
    } // End of the -- comment case.
    if (source.startsWith("/*", i)) { // A /* */ comment (these can sit inside each other):
      let depth = 1; // how many are open,
      i += 2; // moves past the opening mark,
      while (i < source.length && depth > 0) { // until all are closed:
        if (source.startsWith("/*", i)) { depth++; i += 2; } // another opens,
        else if (source.startsWith("*/", i)) { depth--; i += 2; } // one closes,
        else i++; // or moves on one letter.
      } // End of the comment.
      continue; // Carries on reading.
    } // End of the /* */ comment case.
    if (c === "'" || c === '"') { // Quoted text:
      let j = i + 1; // starts after the opening quote,
      while (j < source.length) { // looks for the closing quote:
        if (source[j] === c && source[j + 1] === c) { j += 2; continue; } // a doubled quote is part of the text,
        if (source[j] === c) break; // a single one ends it,
        j++; // otherwise moves on one letter.
      } // End of the search.
      out.push(source.slice(i, j + 1)); // Keeps the quoted text exactly.
      i = j + 1; // Moves past it.
      continue; // Carries on reading.
    } // End of the quoted text case.
    const dollar = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(source.slice(i, i + 100)); // A $$ or $name$ mark?
    if (dollar) { // A function body or $$ text:
      const tag = dollar[0]; // the exact mark,
      const end = source.indexOf(tag, i + tag.length); // finds the matching closing mark,
      const stop = end < 0 ? source.length : end; // (or the end of the file),
      out.push(tag, sqlShape(source.slice(i + tag.length, stop)), tag); // reads the inside the same way,
      i = stop + tag.length; // and moves past the closing mark.
      continue; // Carries on reading.
    } // End of the $$ case.
    const word = /^[A-Za-z0-9_]+/.exec(source.slice(i, i + 200)); // A word or number?
    const token = word ? word[0] : c; // The word, or else the single letter or sign.
    out.push(token); // Keeps it.
    i += token.length; // Moves past it.
  } // End of reading.
  return out.join(" "); // Hands back the whole description.
} // End of sqlShape.

let problems = 0; // Counts files whose code changed.
for (const file of changed) { // Checks each changed file in turn.
  if (!existsSync(file)) { // The file was deleted:
    console.log(`DELETED      ${file}`); // reports it,
    problems++; // and counts it as a problem.
    continue; // Moves on to the next file.
  } // End of the deleted check.
  let before; // Will hold the old version.
  try { // Reading the old version fails if the file is new.
    before = execSync(`git show ${base}:${file}`, { encoding: "utf8", maxBuffer: 1e8, stdio: ["pipe", "pipe", "ignore"] }); // Reads the old version from git.
  } catch { // There was no old version:
    console.log(`NEW FILE     ${file}`); // reports it (new files are checked by eye),
    continue; // and moves on.
  } // End of reading the old version.
  const after = readFileSync(file, "utf8"); // Reads the new version from disk.
  const read = file.endsWith(".sql") ? sqlShape : (src) => shape(src, file); // Database files are read word by word; code files as a tree.
  const same = read(before) === read(after); // True if the working parts are identical.
  console.log(`${same ? "comments only" : "CODE CHANGED "} ${file}`); // Reports the result for this file.
  if (!same) problems++; // Counts a code change as a problem.
} // End of the loop over files.
process.exit(problems ? 1 : 0); // Finishes with "failed" if any code changed, so it can stop a check.
