// Summary: proves that a change only added or edited comments, with no change
// to what the code does. For every changed code file, it removes all comments
// from the old and new versions and checks what's left is identical.
// Run it with: node scripts/check-comments-only.mjs [branch to compare with]

// Lets this script use the TypeScript tool (which knows how to strip comments).
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

// Removes every comment and tidies spacing, leaving only the working code.
const withoutComments = (source, fileName) =>
  ts.transpileModule(source, { // Runs TypeScript's converter on the file,
    fileName, // telling it the file name (so it knows if it's .tsx),
    compilerOptions: { // with these settings:
      removeComments: true, // drop all comments,
      jsx: ts.JsxEmit.Preserve, // leave page markup as it is,
      target: ts.ScriptTarget.ESNext, // keep modern code as it is,
      module: ts.ModuleKind.ESNext, // keep imports as they are.
    }, // End of the settings.
  }).outputText; // Takes the converted code.

let problems = 0; // Counts files whose code changed.
for (const file of changed) { // Checks each changed file in turn.
  if (!existsSync(file)) { // The file was deleted:
    console.log(`DELETED      ${file}`); // reports it,
    problems++; // and counts it as a problem.
    continue; // Moves on to the next file.
  } // End of the deleted check.
  let before; // Will hold the old version.
  try { // Reading the old version fails if the file is new.
    before = execSync(`git show ${base}:${file}`, { encoding: "utf8", maxBuffer: 1e8 }); // Reads the old version from git.
  } catch { // There was no old version:
    console.log(`NEW FILE     ${file}`); // reports it (new files are fine to check by eye),
    continue; // and moves on.
  } // End of reading the old version.
  const after = readFileSync(file, "utf8"); // Reads the new version from disk.
  const same = withoutComments(before, file) === withoutComments(after, file); // True if the code without comments is identical.
  console.log(`${same ? "comments only" : "CODE CHANGED "} ${file}`); // Reports the result for this file.
  if (!same) problems++; // Counts a code change as a problem.
} // End of the loop over files.
process.exit(problems ? 1 : 0); // Finishes with "failed" if any code changed, so it can stop a check.
