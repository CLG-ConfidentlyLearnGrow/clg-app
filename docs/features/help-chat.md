# Help chat

Requested by Carla, 16 Nov 2026 (as part of the matching redesign: "provide a space to ask questions about it if needing support ... maybe have a chat space where families, tutors, and students alike can ask admin (even one that admin can use too). Maybe send an email too").

## What it does

- **Ask CLG a question.** Anyone signed in (parents, students with their own login, tutors and staff) chooses **Help chat** in the top bar, then **Ask CLG a question**. They pick what it is about, optionally which child or student, give it a short title and write a message. The chat stays in the app so everyone can look back at it.
- **Topics decide who answers.** Owner, Operations and Support admins answer general chats (missing information, sessions, finding a tutor, using the app, something else). Owner, Operations and Finance admins answer billing and staff pay chats. Support admins do not handle money, so they do not see those.
- **The help desk.** Admins get a **Help chats** tab with a number for chats waiting for CLG. The longest waiting is at the top, so nobody is left waiting. The first admin to reply looks after the chat; it can be handed to another admin. Chats move between "Waiting for CLG", "Waiting for them" and "Closed" by themselves as people reply.
- **CLG can start a chat.** An admin can start a chat about a student with the people they tick: the student's parents (ticked to start), the student if they have their own login, and the student's current tutors. Owner and Operations admins can also start a chat with a tutor or staff member.
- **"Ask the family" (matching).** When the matching page asks a family for a missing detail (year level, school, session places, how long to book), the notice links to `/help/new?student=<id>&item=<detail>`. That opens the help chat with the child, the topic and the title filled in, so the family only writes their question. The matching module sends that notice and email itself; it never writes help chat tables, and the help chat never writes matching tables.
- **Emails.** When CLG replies, each person in the chat gets an email that only says there is a new message, with a button to open it. When a family or tutor writes, the admin looking after the chat is emailed, or the Owner and Operations admins if nobody is yet. Emails wait 5 minutes (in case it is read in the app first), are skipped if it has been read, never pile up (one waiting email per person per chat), and wait until quiet hours end (9pm to 5am in the person's own time).
- **Numbers.** **Help chat** in the top bar shows how many of the person's chats have a reply they have not read.

## Why (education research)

- **Parental engagement works when it is easy and specific.** The EEF Teaching and Learning Toolkit rates parental engagement at about +4 months' progress, and its guidance report *Working with Parents to Support Children's Learning* recommends communication that is two-way, personalised and easy to act on, rather than general contact. A chat tied to one child and one question does that, and keeps a record both sides can see.
- **Removing barriers for families.** EEF and AERO both note that families who find school (or service) contact hard are the ones most likely to miss out. Letting families ask in the app, at any time, in writing, with no need to phone during business hours, lowers that barrier. Asking "how do I add this?" next to the missing detail helps families complete what is needed so matching, and therefore tutoring, starts sooner.
- **Tutors stay focused on teaching.** Carla asked that tutors do not get caught in back and forth with families about missing details. One-to-one tuition (EEF, about +5 months) is most effective when tutor time goes on teaching and planning, so admin questions go to admin.
- **Closing the loop.** Clear "waiting for" stages and the longest-waiting-first list follow the same idea as the feedback and check-in features: a question raised should always get an answer.

(EEF figures are the Toolkit's headline estimates. Check them again before quoting externally.)

## How we will know it works

- Time from a family's or tutor's message to CLG's first reply, and how many chats wait longer than one working day (from message times; no extra data needed).
- How long families take to reply when CLG asks, which also feeds Carla's planned "average time for each family to respond" metric on a future business overview tab.
- For "Ask the family" chats: how often the missing detail is added within a week of asking.
- Fewer questions arriving by phone, text and personal email (Carla to judge during the trial).

## Legal notes

- **Privacy Act 1988 and the APPs, Children's Online Privacy Code (being developed).**
  - APP 11 (security): access is enforced in the database (row level security), not only on screen. A chat is read only by its members and the admins who answer its topic. Admins need two-step sign-in. Tested in `supabase/tests/help_chat.test.sql`.
  - Sibling privacy: a chat about a student can only include that student's parents, the student and their tutors. A brother or sister with their own login never sees it. A parent who is no longer linked to a child stops seeing chats about that child.
  - Separated families: CLG chooses which parents are in a chat it starts, so a parent is never added without someone deciding to.
  - Billing visibility (Carla, 16 Nov 2026: only payers see billing): the admin pages remind admins to share billing details only with the person who pays.
  - APP 3 (data minimisation): the form asks people not to include medical details. Emails never include the message, title or child's name, because email is less secure than the app.
  - APP 6 (use): messages are used to answer the question and for child safety checks, which the privacy policy already describes ("writing is checked for child safety").
  - Retention: chats are deleted 2 years after their last message (the same as other student records), and straight away when the student is erased. Sent email records go after 30 days. The activity log holds ids only.
  - Resend (US) already appears in the privacy policy as the email provider.
- **Child safety (SA Child Safe Environments, National Principles for Child Safe Organisations).** Every message and title goes through the concerning-words check (`/safety/flags`). The page tells people not to use the chat for safety worries, links to **Child safety**, and says to call 000 if a child is in danger. Every chat includes CLG (its help desk can always read it), so there is never a private tutor-to-family or tutor-to-child channel. A tutor is only in a chat about a student if an admin ticks them.
- **Spam Act 2003.** The emails are transactional (a reply to a question the person asked, or a message about their account), not marketing.
- **UK and EU (later).** The same design fits UK GDPR and the Age Appropriate Design Code: data minimisation in emails, default privacy, and a set retention period.
- **For the lawyer to check:** whether the privacy policy should name the help chat explicitly (it is covered by "messages you send us" and the child safety check), and the 2-year retention period.

## How it is built

- Module `help_chat`. Migration `supabase/migrations/20261119910100_help_chat.sql`: tables `help_chats`, `help_chat_members`, `help_messages`, `help_chat_reads`, `help_chat_emails`; functions `help_start_chat`, `help_start_chat_with`, `help_reply`, `help_mark_read`, `help_update_chat`, `help_chat_list`, `help_my_students`, `help_desk_admins`, email `help_chat_emails_claim` and `help_chat_emails_release`; adds rows to `to_do_counts` and extends `emails_waiting` in place; nightly `clg-help-chat-tidy` job.
- Pages: `/help`, `/help/new`, `/help/[id]`, `/admin/help`, `/admin/help/new`. Words in `src/lib/help-chat.ts`, actions in `src/app/actions/help-chat.ts`.
