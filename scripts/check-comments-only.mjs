// Summary: proves that a change only added or edited comments, with no change
// to what the code does. For every changed code file, it reads the old and
// new versions into a tree of their working parts (ignoring comments, and
// the empty {/* */} holders used for comments inside page markup) and checks
// the two trees are identical.
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
const changed = execSync(`git diff --name-only ${base} -- "*.ts" "*.tsx" "*.js" "*.mjs"`, { encoding: "utf8" })
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
    let children = 0; // Counts the parts inside this one.
    ts.forEachChild(node, (child) => { children++; walk(child); }); // Visits each inner part.
    out.push(")"); // Marks the end of this part.
  }; // End of walk.
  walk(file); // Starts at the top of the file.
  if (file.parseDiagnostics?.length) out.push("PARSE-ERROR"); // Broken code never counts as the same.
  return out.join(" "); // Hands back the whole description.
} // End of shape.

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
  const same = shape(before, file) === shape(after, file); // True if the working parts are identical.
  console.log(`${same ? "comments only" : "CODE CHANGED "} ${file}`); // Reports the result for this file.
  if (!same) problems++; // Counts a code change as a problem.
} // End of the loop over files.
process.exit(problems ? 1 : 0); // Finishes with "failed" if any code changed, so it can stop a check.
