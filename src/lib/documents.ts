// Summary: rules for uploaded copies (certificates, school reports, photos of
// work): the largest size allowed, the file types accepted, and a check of
// the file's real type from its contents.

// Uploaded copies (certificates, school reports, photos of work): a PDF or
// a photo. Server actions accept up to 4MB in total (see next.config.ts), so
// one file may be up to 3.5MB, leaving room for the rest of the form.
export const MAX_DOCUMENT_BYTES = 3.5 * 1024 * 1024;

// The file types the file picker offers: PDF, JPEG, PNG and WebP.
export const DOCUMENT_ACCEPT = "application/pdf,image/jpeg,image/png,image/webp";

// Works out the file type from its first bytes, not from its name, because a
// name can be changed to hide a harmful file. Returns null if not allowed.
export function documentType(bytes: Uint8Array): { ext: string; type: string } | null {
  // Helper: true if the file starts with exactly these byte values.
  const starts = (...sig: number[]) => sig.every((b, i) => bytes[i] === b);
  if (starts(0x25, 0x50, 0x44, 0x46)) return { ext: "pdf", type: "application/pdf" }; // "%PDF" marks a PDF.
  if (starts(0xff, 0xd8, 0xff)) return { ext: "jpg", type: "image/jpeg" }; // These bytes mark a JPEG photo.
  if (starts(0x89, 0x50, 0x4e, 0x47)) return { ext: "png", type: "image/png" }; // "‰PNG" marks a PNG image.
  // "RIFF" at the start and "WEBP" at bytes 8 to 11 mark a WebP image.
  if (starts(0x52, 0x49, 0x46, 0x46) && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
    return { ext: "webp", type: "image/webp" }; // Reports it as a WebP image.
  } // End of the WebP check.
  return null; // Anything else is refused.
} // End of documentType.
