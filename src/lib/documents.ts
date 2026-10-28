// Uploaded copies (certificates, school reports, photos of work): a PDF or
// a photo. Server actions accept up to 4MB in total (see next.config.ts).
export const MAX_DOCUMENT_BYTES = 3.5 * 1024 * 1024;

export const DOCUMENT_ACCEPT = "application/pdf,image/jpeg,image/png,image/webp";

// Works out the file type from its first bytes, not from its name.
export function documentType(bytes: Uint8Array): { ext: string; type: string } | null {
  const starts = (...sig: number[]) => sig.every((b, i) => bytes[i] === b);
  if (starts(0x25, 0x50, 0x44, 0x46)) return { ext: "pdf", type: "application/pdf" };
  if (starts(0xff, 0xd8, 0xff)) return { ext: "jpg", type: "image/jpeg" };
  if (starts(0x89, 0x50, 0x4e, 0x47)) return { ext: "png", type: "image/png" };
  if (starts(0x52, 0x49, 0x46, 0x46) && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
    return { ext: "webp", type: "image/webp" };
  }
  return null;
}
