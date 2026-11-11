// Summary: splits one line of a spreadsheet saved as CSV (comma-separated) or
// tab-separated text into its cells, used when importing lists from files.

// Splits one CSV (or tab-separated) line, allowing "quoted, text" with
// commas inside.
export function splitCsvLine(line: string): string[] {
  const cells: string[] = []; // The finished cells, in order.
  let cell = ""; // The cell currently being built up, letter by letter.
  let quoted = false; // True while inside "double quotes", where commas don't split.
  for (let i = 0; i < line.length; i++) { // Looks at each character of the line in turn.
    const ch = line[i]; // The current character.
    if (quoted) { // Inside quotes:
      if (ch === '"' && line[i + 1] === '"') { // Two quotes in a row mean one real quote mark.
        cell += '"'; // Keeps one quote mark in the cell.
        i++; // Skips the second quote so it isn't read again.
      } else if (ch === '"') { // A single quote mark ends the quoted part.
        quoted = false; // Back to normal splitting.
      } else { // Any other character inside quotes.
        cell += ch; // Kept as part of the cell, even commas.
      } // End of the inside-quotes cases.
    } else if (ch === '"') { // A quote mark outside quotes starts a quoted part.
      quoted = true; // Commas now stop splitting until the closing quote.
    } else if (ch === "," || ch === "\t") { // A comma or tab ends the cell.
      cells.push(cell.trim()); // Saves the cell without spaces at either end.
      cell = ""; // Starts a fresh cell.
    } else { // Any other ordinary character.
      cell += ch; // Added to the current cell.
    } // End of the character cases.
  } // End of the loop over characters.
  cells.push(cell.trim()); // Saves the last cell, which has no comma after it.
  return cells; // Hands back all the cells.
} // End of splitCsvLine.
