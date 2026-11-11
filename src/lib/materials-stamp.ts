// Summary: makes the copy of a material a tutor opens, stamping every page
// with their name, email and the date so any shared copy can be traced.
//
// Stops this file ever being sent to the browser.
import "server-only";
// The PDF tool: make and load PDFs, fonts, angles, colours, and font and page types.
import { PDFDocument, StandardFonts, degrees, rgb, type PDFFont, type PDFPage } from "pdf-lib";
// The local time zone (Adelaide).
import { LOCAL_TIME_ZONE } from "@/lib/scheduling";

// Makes the copy a tutor opens: every page carries their name, email and
// the date, across the middle and along the bottom. If a copy turns up
// somewhere it shouldn't, it shows whose it was. It doesn't stop screenshots
// (nothing in a browser can); it makes sharing traceable, which is what
// stops most of it.

// The built-in PDF font only has Western European letters, so other
// characters are simplified ("é" becomes "e") or replaced.
function plain(text: string): string {
  return text // Starting from the text,
    .normalize("NFKD") // splits accented letters into letter plus accent,
    .replace(/[̀-ͯ]/g, "") // removes the accents,
    .replace(/[^\x20-\x7E]/g, "?"); // and replaces anything else unusual with "?".
} // End of plain.

export type Stamp = { name: string; email: string; openedAt: Date }; // Who opened the material and when.

// Builds the two lines of stamp text.
function stampText(s: Stamp) {
  const when = new Intl.DateTimeFormat("en-AU", { // Formats the opening time:
    timeZone: LOCAL_TIME_ZONE, // in Adelaide time,
    day: "numeric", // with the day number,
    month: "short", // short month name,
    year: "numeric", // year,
    hour: "numeric", // hour,
    minute: "2-digit", // and two-digit minutes.
  }).format(s.openedAt); // Applies it to the opening time.
  return { // Hands back:
    middle: plain(`${s.name} - ${s.email}`), // the large middle text (name and email),
    footer: plain(`CLG material opened by ${s.name} (${s.email}) on ${when}. For CLG sessions only. Do not share or upload.`), // and the small footer text.
  }; // End of the text.
} // End of stampText.

// Draws the stamp onto one page.
function stampPage(page: PDFPage, font: PDFFont, text: ReturnType<typeof stampText>) {
  const { width, height } = page.getSize(); // The page's width and height.
  const grey = rgb(0.45, 0.45, 0.45); // A mid-grey colour.

  // Three faint diagonal lines down the page, so cropping one off isn't enough.
  const size = Math.max(10, Math.min(28, (Math.hypot(width, height) * 0.7) / Math.max(10, text.middle.length) * 1.3)); // Text size that fits across the page diagonal (between 10 and 28).
  const textWidth = font.widthOfTextAtSize(text.middle, size); // How wide the text will be at that size.
  const angle = Math.atan2(height, width); // The angle of the page's diagonal.
  for (const share of [0.25, 0.5, 0.75]) { // A quarter, half and three-quarters down the page:
    const cx = width / 2; // the middle across,
    const cy = height * share; // that far down,
    page.drawText(text.middle, { // draws the name and email:
      x: cx - (Math.cos(angle) * textWidth) / 2, // centred across,
      y: cy - (Math.sin(angle) * textWidth) / 2, // and down, along the diagonal,
      size, // at the chosen size,
      font, // in the chosen font,
      color: grey, // in grey,
      opacity: 0.13, // very faint,
      rotate: degrees((angle * 180) / Math.PI), // tilted to the diagonal angle.
    }); // End of this line's settings.
  } // End of the loop.

  // A small line along the bottom, shrunk to fit the page width.
  let footerSize = 7; // Starts the footer at size 7.
  while (footerSize > 4 && font.widthOfTextAtSize(text.footer, footerSize) > width - 24) footerSize -= 0.5; // Shrinks it in half steps (not below 4) until it fits the page width.
  page.drawText(text.footer, { x: 12, y: 8, size: footerSize, font, color: grey, opacity: 0.85 }); // Draws it near the bottom left, in grey, mostly solid.
} // End of stampPage.

// Pictures go on a page sized to fit inside A4, the right way round.
async function pictureToPdf(bytes: Uint8Array, type: "image/jpeg" | "image/png"): Promise<PDFDocument> {
  const doc = await PDFDocument.create(); // Makes a new empty PDF.
  const image = type === "image/png" ? await doc.embedPng(bytes) : await doc.embedJpg(bytes); // Adds the picture (PNG or JPEG).
  const landscape = image.width > image.height; // True if the picture is wider than tall.
  const [pw, ph] = landscape ? [841.89, 595.28] : [595.28, 841.89]; // A4 size, sideways for wide pictures.
  const margin = 24; // A small border around the picture.
  const scale = Math.min((pw - margin * 2) / image.width, (ph - margin * 2 - 12) / image.height); // How much to shrink the picture so it fits inside the border.
  const page = doc.addPage([pw, ph]); // Adds the page.
  const w = image.width * scale; // The picture's shrunk width.
  const h = image.height * scale; // The picture's shrunk height.
  page.drawImage(image, { x: (pw - w) / 2, y: (ph - h) / 2 + 6, width: w, height: h }); // Draws the picture in the middle, nudged up to leave room for the footer.
  return doc; // Hands back the PDF.
} // End of pictureToPdf.

// Makes the stamped copy of a material for one tutor.
export async function stampMaterial(
  bytes: Uint8Array, // The file's contents.
  type: string, // The file's type (PDF or picture).
  title: string, // The material's title.
  stamp: Stamp, // Who's opening it and when.
): Promise<Uint8Array> {
  const doc = // The PDF to stamp:
    type === "application/pdf" // if it's already a PDF,
      ? await PDFDocument.load(bytes, { updateMetadata: false }) // loads it (without changing its details),
      : await pictureToPdf(bytes, type as "image/jpeg" | "image/png"); // otherwise turns the picture into a PDF.
  const font = await doc.embedFont(StandardFonts.Helvetica); // Adds the standard Helvetica font.
  const text = stampText(stamp); // Builds the stamp text.
  for (const page of doc.getPages()) stampPage(page, font, text); // Stamps every page.

  doc.setTitle(plain(title)); // Sets the PDF's title.
  doc.setAuthor("CLG"); // Sets its author to CLG.
  doc.setSubject(plain(`Opened by ${stamp.name} (${stamp.email})`)); // Notes who opened it in the PDF's details.
  doc.setProducer("CLG app"); // Notes the app made it.
  doc.setModificationDate(stamp.openedAt); // Sets its changed date to the opening time.
  return doc.save(); // Hands back the finished PDF.
} // End of stampMaterial.

// Checks an uploaded PDF can be stamped (not locked with a password, not
// damaged) and counts its pages.
export async function checkPdf(bytes: Uint8Array): Promise<{ pages: number } | { error: string }> {
  try { // Loading could fail.
    const doc = await PDFDocument.load(bytes, { updateMetadata: false }); // Loads the PDF.
    const pages = doc.getPageCount(); // Counts its pages.
    if (pages < 1) return { error: "That PDF has no pages." }; // No pages: plain message.
    if (pages > 500) return { error: "That PDF has more than 500 pages. Please split it into smaller materials." }; // Too many pages: plain message.
    return { pages }; // Fine: hands back the page count.
  } catch (e) { // Loading failed:
    const locked = e instanceof Error && /encrypt/i.test(e.message); // true if it failed because of a password,
    return { // hands back:
      error: locked // if locked,
        ? "That PDF is locked with a password, so the app can't add the tutor's name to it. Save it again without a password and try again." // the password message,
        : "That PDF couldn't be read. Try saving it again as a PDF and uploading it again.", // otherwise the damaged-file message.
    }; // End of the message.
  } // End of the error handling.
} // End of checkPdf.
