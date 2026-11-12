// Summary: sends the app's own emails (reminders, updates, notices, staff
// invite links) through Resend, in CLG's colours with the logo and a button.

// Stops this file ever being sent to the browser, because it uses the email key.
import "server-only";
// A tool for making a fixed code from text (used to stop double sending).
import { createHash } from "node:crypto";
// The app's own web address, for links in emails.
import { siteUrl } from "@/lib/env";

// The logo always comes from the main public address. Email apps fetch
// images without signing in, and Vercel's own *.vercel.app addresses can be
// behind Vercel's login, which shows a broken image instead of the logo.
const EMAIL_LOGO_URL = "https://app.clgtutoring.com/brand/clg-logo-email.png";

// Sends the app's own emails (reminders, updates, notices, staff invite
// links) through Resend. Other sign-in emails (password reset, family
// invitations) are sent by Supabase, which uses the same Resend account
// through its SMTP setting.
//
// Settings (in Vercel's Environment Variables):
//   RESEND_API_KEY  the key from resend.com > API Keys (starts with re_)
//   EMAIL_FROM      who emails come from; default CLG Tutoring <noreply@clgtutoring.com>
//   EMAIL_REPLY_TO  where replies go, for example CLG's main inbox (optional)

// One email waiting to be sent.
export type OutgoingEmail = {
  id: string; // The email's id in the database.
  email: string; // Who it goes to.
  first_name: string | null; // Their first name, for "Hi ...", if known.
  subject: string; // The subject line.
  body: string; // The main message.
  link: string; // The app page the button opens.
  // Optional: the button's words and the small print at the bottom, for
  // emails that aren't reminders (for example staff invitations).
  button?: string; // The button's words, if not the usual ones.
  footer?: string; // The small print, if not the usual words.
}; // End of the email shape.

// True once the Resend key is set, so emails can be sent.
export const emailIsSetUp = () => Boolean(process.env.RESEND_API_KEY);

// CLG's colours: charcoal text, cream background, deep bronze button.
const BRAND = { text: "#414042", cream: "#ede8e4", button: "#76573a" };

// Makes text safe to put inside an email's HTML, so names or messages
// containing < > & or quotes show as typed and can't break the layout.
function escapeHtml(text: string): string {
  return text // Starting from the text,
    .replace(/&/g, "&amp;") // turns & into its safe code (done first so later codes aren't changed),
    .replace(/</g, "&lt;") // turns < into its safe code,
    .replace(/>/g, "&gt;") // turns > into its safe code,
    .replace(/"/g, "&quot;") // turns " into its safe code,
    .replace(/'/g, "&#39;"); // and turns ' into its safe code.
} // End of escapeHtml.

// Plain, short emails: the same words as the app, a button to open it, and
// where to change email settings.
function render(e: OutgoingEmail) {
  const site = siteUrl(); // The app's web address.
  const url = `${site}${e.link.startsWith("/") ? e.link : `/${e.link}`}`; // The full link for the button (adds a "/" if missing).
  const settings = `${site}/schedule`; // Where people change their reminder settings.
  const hello = e.first_name ? `Hi ${e.first_name},` : "Hi,"; // The greeting, with their name if known.
  const button = e.button ?? "Open the CLG app"; // The button's words.
  const footerText = // The small print for the plain-text version:
    e.footer ?? `You get this email because you use the CLG app. To stop emails like this, change your reminder settings: ${settings}`; // the custom words, or the usual note with the settings link.
  const footerHtml = e.footer // The small print for the styled version:
    ? escapeHtml(e.footer) // the custom words, made safe,
    : `You get this email because you use the CLG app. To stop emails like this, <a href="${escapeHtml(settings)}" style="color:${BRAND.button}">change your reminder settings</a>.`; // or the usual note with a clickable settings link.
  // The plain-text version, for email apps that don't show styling.
  const text = `${hello}\n\n${e.body}\n\n${button}: ${url}\n\n--\nCLG Tutoring. ${footerText}`; // Greeting, message, button link, then small print.
  // The styled version. Lines inside this block are the email itself, so they
  // can't carry comments without the comments appearing in the email. In
  // order, it builds: a cream page background; a white rounded card up to
  // 520px wide; the CLG logo; the subject as a heading; the greeting; the
  // message (keeping its line breaks); the bronze button; and, below the
  // card, the small print.
  const html = `<!doctype html><html><body style="margin:0;background:${BRAND.cream};font-family:Poppins,Arial,sans-serif;color:${BRAND.text}">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.cream};padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:12px;padding:28px">
<tr><td><img src="${EMAIL_LOGO_URL}" width="132" alt="CLG Tutoring" style="display:block;border:0;height:auto;border-radius:8px"></td></tr>
<tr><td style="padding-top:16px;font-size:20px;font-weight:600">${escapeHtml(e.subject)}</td></tr>
<tr><td style="padding-top:16px;font-size:15px;line-height:1.55">${escapeHtml(hello)}</td></tr>
<tr><td style="padding-top:8px;font-size:15px;line-height:1.55;white-space:pre-line">${escapeHtml(e.body)}</td></tr>
<tr><td style="padding-top:24px"><a href="${escapeHtml(url)}" style="display:inline-block;background:${BRAND.button};color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:600">${escapeHtml(button)}</a></td></tr>
</table>
<p style="max-width:520px;font-size:12px;line-height:1.5;color:${BRAND.text};padding:16px 8px 0">${footerHtml}</p>
</td></tr></table></body></html>`;
  return { html, text }; // Hands back both versions.
} // End of render.

// Sends up to 100 emails in one request. Returns a plain problem message, or
// null when Resend accepted them all.
export async function sendEmails(emails: OutgoingEmail[]): Promise<string | null> {
  const key = process.env.RESEND_API_KEY; // Reads the Resend key.
  if (!key) return "Email isn't set up yet (RESEND_API_KEY is missing)."; // No key, so nothing can be sent.
  if (emails.length === 0) return null; // Nothing to send.
  const from = process.env.EMAIL_FROM || "CLG Tutoring <noreply@clgtutoring.com>"; // Who the emails come from.
  const replyTo = process.env.EMAIL_REPLY_TO || undefined; // Where replies go, if set.

  const payload = emails.map((e) => ({ // Builds each email for Resend:
    from, // sender,
    to: [e.email], // recipient,
    subject: e.subject.slice(0, 200), // subject, cut to 200 letters,
    ...render(e), // styled and plain-text versions,
    ...(replyTo ? { reply_to: replyTo } : {}), // and the reply address, if set.
  })); // End of building the emails.
  // Same emails, same key: if a retry repeats a batch Resend already took,
  // Resend ignores it instead of sending twice.
  const idempotencyKey = createHash("sha256") // Makes a fixed code
    .update(emails.map((e) => e.id).sort().join(",")) // from the sorted list of email ids,
    .digest("hex"); // written as letters and numbers.

  try { // Reaching Resend could fail.
    const res = await fetch("https://api.resend.com/emails/batch", { // Sends the batch to Resend:
      method: "POST", // as a new request,
      headers: { // with these headers:
        Authorization: `Bearer ${key}`, // the Resend key, proving it's CLG,
        "Content-Type": "application/json", // saying the content is JSON data,
        "Idempotency-Key": idempotencyKey, // and the code that prevents double sending.
      }, // End of the headers.
      body: JSON.stringify(payload), // The emails, as JSON text.
    }); // End of the request.
    if (res.ok) return null; // Accepted: no problem to report.
    const detail = await res.text().catch(() => ""); // Reads Resend's explanation (blank if unreadable).
    return `Resend refused the emails (${res.status}): ${detail.slice(0, 300)}`; // Reports it, cut to 300 letters.
  } catch (err) { // Couldn't reach Resend at all:
    return `Couldn't reach Resend: ${err instanceof Error ? err.message : String(err)}`; // reports why.
  } // End of the error handling.
} // End of sendEmails.
