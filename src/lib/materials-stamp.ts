import "server-only";
import { PDFDocument, StandardFonts, degrees, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import { LOCAL_TIME_ZONE } from "@/lib/scheduling";

// Makes the copy a tutor opens: every page carries their name, email and
// the date, across the middle and along the bottom. If a copy turns up
// somewhere it shouldn't, it shows whose it was. It doesn't stop screenshots
// (nothing in a browser can); it makes sharing traceable, which is what
// stops most of it.

// The built-in PDF font only has Western European letters, so other
// characters are simplified ("é" becomes "e") or replaced.
function plain(text: string): string {
  return text
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^\x20-\x7E]/g, "?");
}

export type Stamp = { name: string; email: string; openedAt: Date };

function stampText(s: Stamp) {
  const when = new Intl.DateTimeFormat("en-AU", {
    timeZone: LOCAL_TIME_ZONE,
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(s.openedAt);
  return {
    middle: plain(`${s.name} - ${s.email}`),
    footer: plain(`CLG material opened by ${s.name} (${s.email}) on ${when}. For CLG sessions only. Do not share or upload.`),
  };
}

function stampPage(page: PDFPage, font: PDFFont, text: ReturnType<typeof stampText>) {
  const { width, height } = page.getSize();
  const grey = rgb(0.45, 0.45, 0.45);

  // Three faint diagonal lines down the page, so cropping one off isn't enough.
  const size = Math.max(10, Math.min(28, (Math.hypot(width, height) * 0.7) / Math.max(10, text.middle.length) * 1.3));
  const textWidth = font.widthOfTextAtSize(text.middle, size);
  const angle = Math.atan2(height, width);
  for (const share of [0.25, 0.5, 0.75]) {
    const cx = width / 2;
    const cy = height * share;
    page.drawText(text.middle, {
      x: cx - (Math.cos(angle) * textWidth) / 2,
      y: cy - (Math.sin(angle) * textWidth) / 2,
      size,
      font,
      color: grey,
      opacity: 0.13,
      rotate: degrees((angle * 180) / Math.PI),
    });
  }

  // A small line along the bottom, shrunk to fit the page width.
  let footerSize = 7;
  while (footerSize > 4 && font.widthOfTextAtSize(text.footer, footerSize) > width - 24) footerSize -= 0.5;
  page.drawText(text.footer, { x: 12, y: 8, size: footerSize, font, color: grey, opacity: 0.85 });
}

// Pictures go on a page sized to fit inside A4, the right way round.
async function pictureToPdf(bytes: Uint8Array, type: "image/jpeg" | "image/png"): Promise<PDFDocument> {
  const doc = await PDFDocument.create();
  const image = type === "image/png" ? await doc.embedPng(bytes) : await doc.embedJpg(bytes);
  const landscape = image.width > image.height;
  const [pw, ph] = landscape ? [841.89, 595.28] : [595.28, 841.89];
  const margin = 24;
  const scale = Math.min((pw - margin * 2) / image.width, (ph - margin * 2 - 12) / image.height);
  const page = doc.addPage([pw, ph]);
  const w = image.width * scale;
  const h = image.height * scale;
  page.drawImage(image, { x: (pw - w) / 2, y: (ph - h) / 2 + 6, width: w, height: h });
  return doc;
}

export async function stampMaterial(
  bytes: Uint8Array,
  type: string,
  title: string,
  stamp: Stamp,
): Promise<Uint8Array> {
  const doc =
    type === "application/pdf"
      ? await PDFDocument.load(bytes, { updateMetadata: false })
      : await pictureToPdf(bytes, type as "image/jpeg" | "image/png");
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const text = stampText(stamp);
  for (const page of doc.getPages()) stampPage(page, font, text);

  doc.setTitle(plain(title));
  doc.setAuthor("CLG");
  doc.setSubject(plain(`Opened by ${stamp.name} (${stamp.email})`));
  doc.setProducer("CLG app");
  doc.setModificationDate(stamp.openedAt);
  return doc.save();
}

// Checks an uploaded PDF can be stamped (not locked with a password, not
// damaged) and counts its pages.
export async function checkPdf(bytes: Uint8Array): Promise<{ pages: number } | { error: string }> {
  try {
    const doc = await PDFDocument.load(bytes, { updateMetadata: false });
    const pages = doc.getPageCount();
    if (pages < 1) return { error: "That PDF has no pages." };
    if (pages > 500) return { error: "That PDF has more than 500 pages. Please split it into smaller materials." };
    return { pages };
  } catch (e) {
    const locked = e instanceof Error && /encrypt/i.test(e.message);
    return {
      error: locked
        ? "That PDF is locked with a password, so the app can't add the tutor's name to it. Save it again without a password and try again."
        : "That PDF couldn't be read. Try saving it again as a PDF and uploading it again.",
    };
  }
}
