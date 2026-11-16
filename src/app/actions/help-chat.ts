// Summary: the server actions for the help chat (Carla, 16 Nov 2026).
// Anyone signed in can start a chat with CLG and reply in their own chats.
// Help desk admins can start a chat with chosen people, reply for CLG, close
// or reopen chats, and choose who looks after each one. The database checks
// every one of these rules again, so nobody can get round them from here.
//
"use server"; // Marks every function in this file as a server action (it runs only on the server).

import { revalidatePath } from "next/cache"; // Lets the code refresh pages after a change, so they show the new data.
import { redirect } from "next/navigation"; // Sends the person to another page (the new chat).
import { z } from "zod"; // The form-checking library.
import { requireViewer } from "@/lib/auth"; // Makes sure someone is signed in.
import type { FormState } from "@/lib/forms"; // The form reply shape.
import { HELP_TOPICS, isMissingItem } from "@/lib/help-chat"; // The topic list and the missing detail check.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// Turns a database refusal into a plain message. Messages the database wrote
// for people (codes 42501, 22023 and 54000) are shown as they are; anything
// else gets the general message given.
function plainError(error: { code?: string; message: string }, fallback: string): string { // Takes the database error and a general message.
  return ["42501", "22023", "54000"].includes(error.code ?? "") ? error.message : fallback; // The database's own words, or the general message.
} // End of plainError.

// The rules shared by both "start a chat" forms.
const startFields = { // Each field and its rule:
  topic: z.string().refine((t) => t in HELP_TOPICS, "Please choose what your question is about."), // the topic must be on the list,
  subject: z.string().trim().min(3, "Please give your chat a short title (at least 3 letters).").max(120, "Please keep the title under 120 characters."), // a short title,
  body: z.string().trim().min(1, "Please write your message.").max(4000, "Please keep your message under 4000 characters."), // the first message,
  student: z.union([z.uuid(), z.literal("")]).optional(), // the student it is about (optional),
  item: z.string().optional(), // the missing detail it is about (optional).
}; // End of the shared rules.

// Refreshes every help chat page, so lists and numbers show the change.
function refreshHelpPages(chatId?: string) { // Takes the chat that changed, if known.
  revalidatePath("/help"); // the person's list of chats,
  revalidatePath("/admin/help"); // the help desk list,
  if (chatId) revalidatePath(`/help/${chatId}`); // and the chat itself.
} // End of refreshHelpPages.

// Starts a chat with CLG, then opens it.
export async function startHelpChat(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message if something is wrong.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object(startFields).safeParse(Object.fromEntries(formData)); // Checks the form against the rules.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("help_start_chat", { // Asks the database to start the chat:
    p_topic: d.topic, // what it is about,
    p_subject: d.subject, // its title,
    p_body: d.body, // the first message,
    p_student: d.student || null, // the student (if any),
    p_item: d.student && isMissingItem(d.item) ? d.item : null, // and the missing detail (only with a student, and only a known one).
  }); // End of the request.
  if (error || typeof data !== "string") return { error: error ? plainError(error, "We could not start the chat. Please try again.") : "We could not start the chat. Please try again." }; // Failed: plain message.
  refreshHelpPages(data); // Refreshes the lists.
  redirect(`/help/${data}`); // Opens the new chat.
} // End of startHelpChat.

// A help desk admin starts a chat with chosen people, then opens it.
export async function startHelpChatWith(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message if something is wrong.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object(startFields).safeParse(Object.fromEntries(formData)); // Checks the shared fields.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const people = formData.getAll("people").map(String).filter((p) => z.uuid().safeParse(p).success); // The people ticked (only real ids).
  if (people.length === 0) return { error: "Please choose who to start the chat with." }; // Nobody ticked.
  const d = parsed.data; // The checked answers.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { data, error } = await supabase.rpc("help_start_chat_with", { // Asks the database to start the chat:
    p_people: people, // who it is with,
    p_topic: d.topic, // what it is about,
    p_subject: d.subject, // its title,
    p_body: d.body, // the first message,
    p_student: d.student || null, // the student (if any),
    p_item: d.student && isMissingItem(d.item) ? d.item : null, // and the missing detail (only with a student).
  }); // End of the request.
  if (error || typeof data !== "string") return { error: error ? plainError(error, "We could not start the chat. Please try again.") : "We could not start the chat. Please try again." }; // Failed: plain message.
  refreshHelpPages(data); // Refreshes the lists.
  redirect(`/help/${data}`); // Opens the new chat.
} // End of startHelpChatWith.

// Adds a reply to a chat.
export async function replyHelpChat(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    chat: z.uuid(), // which chat,
    body: z.string().trim().min(1, "Please write your message.").max(4000, "Please keep your message under 4000 characters."), // and the message.
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("help_reply", { p_chat: parsed.data.chat, p_body: parsed.data.body }); // Saves the reply.
  if (error) return { error: plainError(error, "We could not send that. Please try again.") }; // Failed: plain message.
  refreshHelpPages(parsed.data.chat); // Refreshes the chat and the lists.
  return { message: "Sent." }; // Confirms.
} // End of replyHelpChat.

// Closes or reopens a chat, and (help desk only) changes who looks after it.
export async function updateHelpChat(_prev: FormState, formData: FormData): Promise<FormState> { // Takes the form; gives back a message.
  await requireViewer(); // Makes sure someone is signed in.
  const parsed = z.object({ // The rules:
    chat: z.uuid(), // which chat,
    status: z.enum(["waiting_on_clg", "waiting_on_you", "closed"], { message: "Please choose where this chat is up to." }), // its new stage,
    assign: z.union([z.uuid(), z.literal("")]).optional(), // and who should look after it (optional).
  }).safeParse(Object.fromEntries(formData)); // Checks the form.
  if (!parsed.success) return { error: parsed.error.issues[0].message }; // Shows the first rule that failed.
  const supabase = await createClient(); // Connects to the database as the signed-in person.
  const { error } = await supabase.rpc("help_update_chat", { p_chat: parsed.data.chat, p_status: parsed.data.status, p_assign_to: parsed.data.assign || null }); // Saves the change.
  if (error) return { error: plainError(error, "We could not save that. Please try again.") }; // Failed: plain message.
  refreshHelpPages(parsed.data.chat); // Refreshes the chat and the lists.
  return { message: parsed.data.status === "closed" ? "Chat closed. Write a new message any time to reopen it." : "Saved." }; // Confirms.
} // End of updateHelpChat.
