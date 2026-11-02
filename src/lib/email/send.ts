import "server-only";
import { createHash } from "node:crypto";
import { siteUrl } from "@/lib/env";

// Sends the app's own emails (reminders, updates, notices, staff invite
// links) through Resend. Other sign-in emails (password reset, family
// invitations) are sent by Supabase, which uses the same Resend account
// through its SMTP setting.
//
// Settings (in Vercel's Environment Variables):
//   RESEND_API_KEY  the key from resend.com > API Keys (starts with re_)
//   EMAIL_FROM      who emails come from; default CLG Tutoring <noreply@clgtutoring.com>
//   EMAIL_REPLY_TO  where replies go, for example CLG's main inbox (optional)

export type OutgoingEmail = {
  id: string;
  email: string;
  first_name: string | null;
  subject: string;
  body: string;
  link: string;
  // Optional: the button's words and the small print at the bottom, for
  // emails that aren't reminders (for example staff invitations).
  button?: string;
  footer?: string;
};

export const emailIsSetUp = () => Boolean(process.env.RESEND_API_KEY);

const BRAND = { text: "#414042", cream: "#ede8e4", button: "#76573a" };

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Plain, short emails: the same words as the app, a button to open it, and
// where to change email settings.
function render(e: OutgoingEmail) {
  const site = siteUrl();
  const url = `${site}${e.link.startsWith("/") ? e.link : `/${e.link}`}`;
  const settings = `${site}/schedule`;
  const hello = e.first_name ? `Hi ${e.first_name},` : "Hi,";
  const button = e.button ?? "Open the CLG app";
  const footerText =
    e.footer ?? `You get this email because you use the CLG app. To stop emails like this, change your reminder settings: ${settings}`;
  const footerHtml = e.footer
    ? escapeHtml(e.footer)
    : `You get this email because you use the CLG app. To stop emails like this, <a href="${escapeHtml(settings)}" style="color:${BRAND.button}">change your reminder settings</a>.`;
  const text = `${hello}\n\n${e.body}\n\n${button}: ${url}\n\n--\nCLG Tutoring. ${footerText}`;
  const html = `<!doctype html><html><body style="margin:0;background:${BRAND.cream};font-family:Poppins,Arial,sans-serif;color:${BRAND.text}">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.cream};padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:12px;padding:28px">
<tr><td style="font-size:13px;letter-spacing:.04em;text-transform:uppercase;color:${BRAND.button}">CLG Tutoring</td></tr>
<tr><td style="padding-top:12px;font-size:20px;font-weight:600">${escapeHtml(e.subject)}</td></tr>
<tr><td style="padding-top:16px;font-size:15px;line-height:1.55">${escapeHtml(hello)}</td></tr>
<tr><td style="padding-top:8px;font-size:15px;line-height:1.55;white-space:pre-line">${escapeHtml(e.body)}</td></tr>
<tr><td style="padding-top:24px"><a href="${escapeHtml(url)}" style="display:inline-block;background:${BRAND.button};color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:600">${escapeHtml(button)}</a></td></tr>
</table>
<p style="max-width:520px;font-size:12px;line-height:1.5;color:${BRAND.text};padding:16px 8px 0">${footerHtml}</p>
</td></tr></table></body></html>`;
  return { html, text };
}

// Sends up to 100 emails in one request. Returns a plain problem message, or
// null when Resend accepted them all.
export async function sendEmails(emails: OutgoingEmail[]): Promise<string | null> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return "Email isn't set up yet (RESEND_API_KEY is missing).";
  if (emails.length === 0) return null;
  const from = process.env.EMAIL_FROM || "CLG Tutoring <noreply@clgtutoring.com>";
  const replyTo = process.env.EMAIL_REPLY_TO || undefined;

  const payload = emails.map((e) => ({
    from,
    to: [e.email],
    subject: e.subject.slice(0, 200),
    ...render(e),
    ...(replyTo ? { reply_to: replyTo } : {}),
  }));
  // Same emails, same key: if a retry repeats a batch Resend already took,
  // Resend ignores it instead of sending twice.
  const idempotencyKey = createHash("sha256")
    .update(emails.map((e) => e.id).sort().join(","))
    .digest("hex");

  try {
    const res = await fetch("https://api.resend.com/emails/batch", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        "Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify(payload),
    });
    if (res.ok) return null;
    const detail = await res.text().catch(() => "");
    return `Resend refused the emails (${res.status}): ${detail.slice(0, 300)}`;
  } catch (err) {
    return `Couldn't reach Resend: ${err instanceof Error ? err.message : String(err)}`;
  }
}
