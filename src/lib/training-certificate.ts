// Summary: makes a CLG training certificate as a one-page PDF: either for
// one finished module, or the "CLG certified" certificate.
//
import "server-only"; // Stops this file being sent to the browser.

import { PDFDocument, StandardFonts, rgb } from "pdf-lib"; // The PDF maker, its built-in fonts, and colours.

// What goes on a certificate.
export type CertificateDetails = { // the details:
  heading: string; // the big heading, e.g. "Certificate of completion",
  personName: string; // who it's for,
  achievement: string; // what they did, e.g. the module's name,
  lines: string[]; // smaller lines under it (date, hours, expiry),
  certificateNo: string; // the certificate number,
  signer: string; // who signs it for CLG,
  logo: Uint8Array | null; // CLG's logo (PNG), if it could be read.
}; // End of the shape.

// CLG's brand colours as PDF colours.
const BRONZE = rgb(0xa8 / 255, 0x81 / 255, 0x5b / 255); // bronze #a8815b
const CHARCOAL = rgb(0x41 / 255, 0x40 / 255, 0x42 / 255); // charcoal #414042
const SAND = rgb(0xed / 255, 0xe8 / 255, 0xe4 / 255); // sand #ede8e4

// Keeps only characters the built-in PDF font can draw (others would stop the PDF being made).
const clean = (text: string) => text.replace(/[^\x20-\x7E\u00A0-\u00FF]/g, ""); // Removes anything outside basic Latin letters and symbols.

// Makes the certificate and gives back the PDF's bytes.
export async function makeCertificate(d: CertificateDetails): Promise<Uint8Array> { // Takes the details.
  const doc = await PDFDocument.create(); // A new, empty PDF.
  doc.setTitle(clean(`${d.heading} - ${d.personName}`)); // The PDF's title (shown in the browser tab).
  doc.setAuthor("CLG Tutoring"); // Who made it.
  const page = doc.addPage([842, 595]); // One A4 page, landscape (in points).
  const { width, height } = page.getSize(); // The page's width and height.
  const regular = await doc.embedFont(StandardFonts.Helvetica); // The plain font.
  const bold = await doc.embedFont(StandardFonts.HelveticaBold); // The bold font.

  page.drawRectangle({ x: 0, y: 0, width, height, color: SAND }); // A sand background.
  page.drawRectangle({ x: 24, y: 24, width: width - 48, height: height - 48, borderColor: BRONZE, borderWidth: 3, color: rgb(1, 1, 1) }); // A white panel with a bronze border.

  // Writes one line of text centred across the page.
  const centre = (text: string, y: number, size: number, font = regular, color = CHARCOAL) => { // Takes the words, height, size, font and colour.
    const safe = text.replace(/[^\x20-\x7E -ÿ]/g, ""); // Keeps only characters the built-in font can draw.
    const w = font.widthOfTextAtSize(safe, size); // How wide the words are.
    page.drawText(safe, { x: (width - w) / 2, y, size, font, color }); // Draws them in the middle.
  }; // End of centre.

  let top = height - 70; // Where the next thing goes (from the top).
  if (d.logo) { // If the logo could be read:
    try { // tries:
      const img = await doc.embedPng(d.logo); // adding the logo,
      const scale = 60 / img.height; // shrinks it to 60 points tall,
      page.drawImage(img, { x: (width - img.width * scale) / 2, y: top - 50, width: img.width * scale, height: 60 }); // and draws it in the middle at the top.
      top -= 95; // Moves down below it.
    } catch { // The logo couldn't be added:
      top -= 10; // carries on without it.
    } // End of the try.
  } // End of the logo.

  centre(d.heading.toUpperCase(), top, 26, bold, BRONZE); // The heading, in bronze capitals.
  centre("This certifies that", top - 50, 13); // "This certifies that",
  centre(d.personName, top - 95, 30, bold); // the person's name, large,
  page.drawLine({ start: { x: width / 2 - 200, y: top - 105 }, end: { x: width / 2 + 200, y: top - 105 }, thickness: 1, color: BRONZE }); // a bronze line under the name,
  centre("has completed", top - 135, 13); // "has completed",
  centre(d.achievement, top - 170, 20, bold); // what they completed.
  d.lines.forEach((line, i) => centre(line, top - 205 - i * 20, 12)); // The smaller lines, one under another.

  page.drawLine({ start: { x: 90, y: 110 }, end: { x: 330, y: 110 }, thickness: 1, color: CHARCOAL }); // The signature line on the left.
  page.drawText(clean(d.signer), { x: 90, y: 92, size: 11, font: bold, color: CHARCOAL }); // Who signs, under it.
  page.drawText("Director, CLG Tutoring", { x: 90, y: 77, size: 10, font: regular, color: CHARCOAL }); // Their title.
  const no = clean(`Certificate no. ${d.certificateNo}`); // The certificate number in words.
  page.drawText(no, { x: width - 90 - regular.widthOfTextAtSize(no, 10), y: 92, size: 10, font: regular, color: CHARCOAL }); // The number on the right.
  return doc.save(); // Hands back the finished PDF.
} // End of makeCertificate.
