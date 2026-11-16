// Summary: the app guides for CLG's admin staff, one for each admin level:
// Owner (everything), Operations (day-to-day running), Support (families
// and bookings) and Finance (invoices and pay). Each guide only covers what
// that level can see and do, so nobody is shown steps for screens they
// can't open. Shared parts (such as Sessions or your own pay) are written
// once below and put into each guide that needs them.
//
// The text is the guide itself, in the simple layout read by parseGuide in
// ./index.ts ("##" a part, "###" a task, "1." a step, "-" a bullet point,
// "Tip:" a tip; **stars** mark the exact names of buttons and menu items).
// Update this text whenever an admin feature changes.
//
import type { AdminLevel } from "@/lib/auth"; // The admin level type (for type checking only).
import type { GuideSource } from "./index"; // The shape of a guide's words (for type checking only).

// (Text inside the backticks below is guide text, not code, so its lines
// don't carry code comments.)

// Signing in with two-step login, and getting around (every admin level).
const START = `
## Getting started

### Join CLG from your invitation
1. Open the invitation email from CLG. The link works once, for 7 days, and only for your email.
2. Enter your first and last name and choose a password.
3. Set up two-step login (below).

### Set up and use two-step login
All admins need two-step login, because the app holds children's information.
1. Install an authenticator app on your phone (for example Microsoft Authenticator or Google Authenticator).
2. After you sign in the first time, choose **Set up two-step login**.
3. Scan the code with your authenticator app, enter the 6-digit code, and choose **Turn on two-step login**.
4. Each time you sign in, enter the 6-digit code from your authenticator app.

### Get around the admin dashboard
- Choose the **Admin** tab at the top. If you also tutor or are a parent, the other tabs take you to those dashboards.
- The side menu shows only what your admin level can use. A number next to an item means something is waiting there.
- **Home**, **Child safety** (in red), **Help chat**, **Feedback**, **Your privacy** and **Report app issue** are at the top of every page. On a phone, **Child safety** stays in the top bar and the rest are under the **Menu** button (top right), along with your name and **Sign out**.
- When you open something from a list (a report, an application, a training module, a handbook page, a material, a student's progress, or a student in Matching on a phone), a **Back** button at the top (and at the bottom of long pages) takes you back to the list.
- **App guide** in the side menu opens this guide. If you help families and tutors, their guides are listed under **Other guides you can open** at the bottom, so you can talk them through the app.

### Take the app tour again
The first time you open the admin dashboard, a short **app tour** shows the parts your admin level uses and why each one matters. To take it again, open **App guide** in the side menu and choose **Take the tour again** at the top. If you stopped part-way, the button says **Carry on the tour** and starts where you left off.

Tip: If you help families and tutors, the App guide for parents, students or tutors has **See their tour**, so you know what they were shown.
`;

// Sessions, as seen by front-desk admins (Owner, Operations, Support).
const SESSIONS = `
## Sessions and bookings

Open **Sessions** in the side menu. Its sections include **Overview**, **Bookings**, **Book a session**, **How long to book**, **Away dates**, **Requests**, **Blocks**, **Notices**, **Book again** and **Waitlist**. Times are Adelaide time.

### Book a session for a family
1. In **Sessions**, choose **Book a session**.
2. Choose who it is for, the subject, how long (1 hr minimum, in half-hour steps) and the first week. Narrow the days and times if you like.
3. Choose **Find times**. **Available times** shows only tutors who suit: checks in date for the student's state, teach the subject at the student's level, free then, and under their weekly hours. Libraries are offered when they are within the tutor's travel distance for that time and the family's travel distance (or you ticked them). **At home** times are offered when the learner's address is within a tutor's distance and the tutor ticked learners' homes for that time.
4. Choose a time. If you did not pick the suggested one, say why (it helps improve the suggestions).
5. Add a note for the tutor and family if needed, and choose **Send to tutor and family**. They each have 3 days to approve, with a reminder after 2 days. It is confirmed once both say yes. If not, the offer closes for now: the tutor and family are told, you get a notice saying who did not answer, and the student is back in **Matching**.

Tip: A student needs their details, preferred times and **How long to book** filled in before times can be offered. The family's address and travel distance are under **Session places** (from **Matching**). Libraries need a map point to be matched by distance; libraries loaded from OpenStreetMap have one.

### Cancel a session for someone
1. In **Sessions**, choose **Overview**, find the session and choose **Cancel**.
2. Choose a reason and who asked (the family, the tutor or CLG).
3. Offer two other times that week. When CLG offers the times, one side picks and the other confirms before it is booked.
4. Choose **Cancel this session**.

### Stop a booking
1. In **Sessions**, choose **Bookings**, find the booking and choose **Stop booking**.
2. Add a reason and who asked, then choose **Stop booking and cancel future sessions**.

### Change the tutor on booked sessions
1. In **Sessions**, choose **Bookings**, then **Change tutor on booked sessions**.
2. Search for the student or tutor and choose **Choose** next to the booking.
3. Choose the date to change from, and a new day and start time if they change too. Choose **Update the list**.
4. Choose the new tutor and the reason (only matching admins see it), then send.
5. The new tutor and the family both confirm before anything moves. **Waiting for confirmation** shows where each change is up to.

### Help with requests for extra or one-off sessions
1. In **Sessions**, choose **Requests**. Families' requests are listed oldest first.
2. To offer a time, choose the tutor, date, start, length and place, add a note for the family, and choose **Offer this time**. The family approves it.
3. If it cannot be arranged, choose **Could not arrange it** and say why.

### Follow up a block
When a family blocks a tutor, or a tutor blocks a student, it shows in **Sessions**, **Blocks**. The other person is not told. Contact the person who made the block, then record what happened and choose **Save follow-up**.

### Look after the waitlist
1. In **Sessions**, choose **Waitlist**. Everyone waiting is listed, oldest first, with how many times would now suit.
2. Check in with anyone who has waited 4 weeks or more.
3. Booking that subject takes the student off the waitlist.

### Add away dates for a student or tutor
In **Sessions**, choose **Away dates**, choose who will be away and the dates, and choose **Save away dates**. Booked sessions on those days are cancelled.

### Book again answers
About 3 weeks before each student's book-till date (or the booking's last date, if that comes first), families are asked whether they want to keep going. They choose a new book-till date and answer the school holiday and public holiday questions again. If they choose the same again, the tutor is asked to confirm. See their answers in **Sessions**, **Book again**, and arrange any changes they asked for.
`;

// Families: setting up, linking parents, logins (front-desk admins).
const FAMILIES = `
## Families

Open **Families** in the side menu.

### Set up a family for them
Use this during a phone call, or when a family would rather CLG fills it in.
1. In **Families**, open **Set up a family**.
2. Choose who the account is for (a parent, or an adult student), then enter their full name and email, and the child's details. Add one child at a time, using the same parent email for each child.
3. Choose **Set up and add child** (or **Set up student**).
4. The family gets an email link to choose a password, and sees **Please finish (name)'s details** for anything still missing.

### Link another parent or guardian
1. In **Families**, open **Link another parent or guardian**.
2. Choose the student, and enter the parent's email, their full name (if they are new to CLG) and their relationship to the student.
3. Save. Both parents see the same profile.

Tip: **Parents of each student** shows who can see each student. Use **Remove this link** to undo a link made by mistake.

### Sort out possible double-ups
**Possible double-ups** lists students with the same name and date of birth, usually because a second parent added a child CLG already has. The parent's link waits until you decide.
1. Check with the family if you are not sure.
2. Choose **Same child: merge**, **Same child: keep the newer one**, or **Different children**.

### Give a student their own login
1. In **Families**, open **Give a student their own login** (students 16 and over).
2. Choose the student and enter their own email, then send. They keep their details, history and tutor, and their parent can still see everything.

### Send a new login link
If a family's or student's link ran out before they used it, open **Send a new login link**, enter their email and send.

### See which families are paused
**Families paused for an overdue bill** lists families whose sessions are on hold until they pay. Do not discuss the bill with the tutor: tutors are only told sessions are on hold.
`;

// Matching students with tutors (front-desk admins).
const MATCHING = `
## Matching

Open **Matching** in the side menu.

### Find a tutor for a student
1. In **Matching**, choose a stage along the top: **Needs a tutor**, **Waitlist**, **Waiting for confirmation**, **Assigned, no time** or **Active**. Search or filter by year level and state if needed.
2. Choose a student. Their year, working level, goal, learning needs, tutor preferences, places, preferred times, siblings and past tutors are shown.
3. **Tutors who suit** lists the best fit first: teaches the subject at the student's working level, then a sibling's tutor, then spare hours, then a place and time that suit. Pay rates are not shown. A tutor is never offered for their own child or anyone in their own family.
4. Choose **Offer this tutor**, pick the time and place, and send it to the tutor and family to approve.
5. Choose **Next student** to keep going.

Tip: Check **Gaps** to see subjects and levels students are waiting for where no tutor with current checks teaches them. It shows who to recruit next.

### See the travel map
1. In the side menu, choose **Travel map** (Owner and Operations admins).
2. The map shows CLG's approved libraries (charcoal dots), each tutor's travel areas (solid bronze circles) and each family's travel area (dashed green circles). Circles are straight-line distances.
3. Click a circle to see who it is, the distance, and (for tutors) the weekly times that use it. Street addresses are not shown on the map.
4. Use the tick boxes to show or hide libraries, tutor areas or family areas. Choose one tutor in the **Tutor** list to zoom to their areas.
`;

// What every admin has for themselves: training, handbook, staff directory, pay.
const YOUR_OWN = `
## Your own training, handbook and pay

### Do your training
1. In the side menu, choose **Training**. **To do now** lists your compulsory and due modules.
2. Open a module, read the lessons, then do the quiz (100% needed, unlimited tries).
3. Download your certificate when you finish.

### Use the handbook
Choose **Handbooks** in the side menu, and search for a word. **Something has happened** is pinned at the top in red.

### Find a colleague
Choose **Staff directory** (from Admin or Billing) to search staff by name, email, job title or subject.

### Log your office hours
1. In the side menu, choose **My pay**.
2. Under **Log hours**, add your office admin hours with the day, hours and what you did. Log each pay week by the day after it ends.
3. **Last 8 weeks** shows your hours and pay.
`;

// Child safety: raising a concern (everyone) and handling one (officer and deputy).
const SAFETY = `
## Child safety

### Raise a concern
1. If a child is in danger now, call 000.
2. Choose **Child safety** (in red, top of every page). Report to the child protection line for the child's state, then tell CLG with the form.
3. Concerns are confidential. If a concern is about someone at CLG, they never see it.

### If you are the Child Safety Officer or deputy
The **Child safety** button shows a number when something is waiting for you.
1. Choose **Child safety**, then **Open concerns sent to you**.
2. For each concern, read it, add follow-up notes with **Add note**, and set where it is up to.
3. If it names a tutor, you can take quiet steps while it is looked into: **Stop new students** (they keep their current students), or end a match so the child is marked **Urgent: needs a new tutor**. Lift a step later with a reason.
4. If needed, choose **Pass it on** or **Share it**, with a reason.
5. Choose **Flagged words** to review writing the app has flagged. A match is only a prompt to look: read it in context, choose what you decided, add a note, and choose **Save decision**. Nobody is told about a flag.

Tip: Keep concerns confidential. Do not copy details into emails, Teams or other parts of the app.
`;

// Help: feedback and app issues (every admin level).
const HELP = `
## Help

### Answer help chats (the help desk)
Families, students, tutors and staff ask CLG questions in the **Help chat**. Owner, Operations and Support admins answer general chats. Owner, Operations and Finance admins answer **Billing and payments** and **My pay (CLG staff)** chats.
1. Choose **Help chats** in the side menu. The number shows chats waiting for CLG.
2. **Waiting for CLG** lists the longest waiting first. Open a chat by its title.
3. Write your reply and choose **Send**. It is sent as CLG, and they get an email saying there is a reply (never the message itself, and not between 9pm and 5am their time).
4. The first admin to reply looks after the chat. To hand it over, choose someone under **Looked after by** and choose **Save**. You can also mark it **Closed** there.

### Start a chat with a family or person
1. In **Help chats**, choose **Start a chat with a family or person**.
2. To ask a family, choose the student and **Choose**. Tick who should be in the chat: parents start ticked; the student (if they have their own login) and their tutors do not. Only tick the people who should see it.
3. Owner and Operations admins can instead pick a tutor or staff member.
4. Choose the topic, write a short title and message, and choose **Start the chat**.

Tip: Billing details should only go to the person who pays. Messages are checked for child safety words like other writing in the app.

### Give feedback or report an app issue
- **Feedback** (top of the page, or under **Menu** on a phone): praise, ideas or worries.
- **Report app issue**: something in the app is not working. Add a screenshot if you can.

### Your privacy and name
Choose **Your privacy** to download your information or ask CLG about it. Tap your name under **Signed in as** to change it (on a phone, tap **Menu** at the top right first).
`;

// Running CLG day to day: tutors, progress, curriculum, staff, records (Owner and Operations).
const RUNNING = `
## Tutors and checks

Open **Tutors and checks** in the side menu.

### Confirm a tutor's check
1. **Checks to confirm** lists checks tutors have sent, each with a copy of the certificate.
2. Open the copy and check it against the official record (for a Working with Children Check, the state's online check).
3. Choose **Confirm**. A tutor is only matched, and only sees sessions, while their checks are confirmed and in date.

### Record a check yourself
Under **Record a check**, choose the tutor and check, enter the number, dates and state, and save.

### See tutors' states, subjects and work state
**States each tutor is cleared for**, **What each tutor teaches** and **Tutor work state** show each tutor's details. Tutors add their own subjects in their dashboard.

### When a tutor finishes with CLG
Use **Tutor finished with CLG** to end their matches. Then move their students to a new tutor with **Change tutor on booked sessions** in Sessions.

## Tutor applications

People who want to tutor apply on the public page **app.clgtutoring.com/apply** (also linked from the home and sign-up pages). Open **Tutor applications** in the side menu. A number shows how many are new.

### Review an application
1. Choose **Open** next to an application to see every answer, the referees and the CV.
2. Set the status to **Shortlisted** if you would like to interview them, and choose **Save screening record**.
3. Use the child-safe questions under **Questions to use** (choose **Show**) in the interview and when you phone each referee.
4. Record the **Interview date**, each **Referee checked on** date and what was said, then choose **Save screening record**.
5. If they hold a Working with Children Check, verify it with the state's screening unit and record **Working with Children Check verified on**.

Tip: Set the status to **Withdrawn** if they pull out or stop replying. It is deleted 12 months later.

### Approve an application
1. Record the interview and both referee checks first. **Approve and send invite** will not work without them.
2. Choose **Approve and send invite**. They get the usual tutor invite link (works once, for 7 days).
3. If the email cannot be sent, the link is shown for you to pass on. Choose **Send invite again** for a fresh link.
4. Once they join, confirm their checks under **Checks to confirm** as usual before they are matched with students.

### Decline an application
1. Under **Decline**, choose a reason (only admins see it) and add a note if useful.
2. Leave **Email them a polite "not this time"** ticked to let them know, then choose **Decline**.

Declined applications are deleted 12 months after the decision.

## Progress

Open **Progress** in the side menu.

### Check term reviews before families see them
1. **Term reviews to check** lists reviews tutors have written.
2. Check each one: is it written to the family, honest about progress, and clear about next term?
3. Approve it, or send it back with what needs changing.

### Keep notes on track
- **Notes overdue** lists sessions with no note after the due time. Follow up with the tutor.
- **Students to check** lists students with no goals, or whose skills have not moved for a while.
- **Recent notes to spot-check**: is the next step specific, and the tip for home a small habit?
- **How progress tracking is going** shows the measures for any dates you choose.

### Record a family's term review answer
If a family tells you directly whether they want a term review, record it under **Paid term review offers**.

## Curriculum

Open **Curriculum** in the side menu.

### Load and confirm a curriculum
1. Under **Upload a curriculum**, load the file (or the Australian Curriculum subjects you need) and press **Load**.
2. It arrives as a draft. Open it under **Curricula to check and confirm**, check how many skills it has for each year, then confirm it.

### Set a student's curriculum
Under **Set a student's curriculum**, choose the student and the confirmed curriculum they follow. Tutors then choose skills from it for goals.

## Staff, leaving and records

### Add staff
1. Open **Staff and accounts** in the side menu.
2. Under **Add staff**, enter the person's email and role, and send. The link works once, for 7 days, only for that email.
3. **Invitations not used yet** shows who has not joined. Choose **Cancel** to withdraw an invitation, or add them again for a new link.

### Unlock an account
If someone is locked out after too many wrong tries, enter their email under **Unlock an account**. They can sign in straight away.

### Record someone leaving
1. Open **Leaving** in the side menu.
2. Under **Record someone leaving**, choose who left, the day, the main reason, and whether they left happy.
3. For families who leave happy, ask for a testimonial or Google review.

### Privacy requests and breaches
1. Open **Privacy and records**, then **Open privacy requests and the breach register**.
2. Reply to each request by its due date (28 days). Acknowledge complaints straight away. You can extend once, before the due date, if a request is complex.
3. Record every suspected data breach under **Record a suspected breach** as soon as you know, even small ones.

### Records due for deletion
**Privacy and records** lists records that have reached the end of their keeping period. To keep one longer (for example during a complaint), add a hold with a reason. **Holds** lists what is being kept; choose **Release** when it is no longer needed.

## Other admin tools

### Check-ins after a new match
After a new match, the tutor, the parents and the learner (if they have their own login) are each asked how it is going 1 week, 2 weeks and 6 weeks after the first session.
1. Open **Check-ins** in the side menu. A number shows how many answers need follow-up.
2. **Needs follow-up** lists answers rated 1 or 2, answers that say it is not a good fit, endings rated 1 or 2, and anyone who asked CLG to make contact.
3. Contact the person, then choose **Has this been followed up?**, add a private note and choose **Save**.
4. **Matches being checked in** shows each check-in that has opened, how many people answered, and the average rating.

When a match ends (for example a change of tutor, or the bookings finish), the same people are asked how the sessions went and how well the ending was handled. An ending rated 1 or 2 is flagged in **Needs follow-up** too.

### App feedback
**Feedback** in the side menu shows what people are saying, grouped by area. Set where each item is up to and add private notes.

### What is new pop-ups
1. Open **What is new**, start a new update with a short title, and add each change (added, updated or removed), ticking the dashboards it applies to.
2. Publish now, or choose a day to start showing it. People see only changes for their own dashboards, once.

### Teams links
**Teams links** shows online sessions for the next 4 weeks and their meeting links. Choose **Make links now** if one is missing.

### Materials library
1. Open **Materials library**, then **Add materials** to upload one file or many. They are saved as drafts.
2. Open each one, tag its curriculum skills, and publish it. Tutors only see published materials for subjects and year levels they teach.
3. **Who opened what** shows recent use.

### Training setup
1. Open **Training setup**. Under **Modules**, add a module, then its lessons and quiz questions, and publish it. Saving keeps you on the module. **Back to all modules** (top and bottom of the page) returns to the list. Safety modules (ticked **Needed before new students**) never count towards the training hours each quarter. The app sets this itself.
2. **Progress** shows everyone's compulsory modules. **Handbooks** is where you write the tutor handbook pages.
`;

// Billing for every level that can open it (Owner, Operations, Finance).
const BILLING = `
## Billing

Open **Billing** in the side menu. Its sections are **Family billing**, **Invoices**, **Staff pay**, **Prices and settings**, and **Stripe and Xero**.

### Set a family's plan or bill payer
1. In **Family billing**, find the family.
2. Choose how often they pay and the bill payer, then choose **Save plan**.
3. If two people share invoices, choose who also pays and their share, then **Save split**.

Tip: Only the bill payer and any extra payers see a family's billing (plan, invoices and credit). Other parents and students do not, but they are still told when sessions are on hold. Until a bill payer is set, the first parent to choose the plan or agree to the terms becomes the bill payer, so set it here if someone else should pay.

### Add credit
In **Family billing**, find the family, enter the amount and reason, and choose **Add credit**. Credit comes off their next invoice.

### Waive a late cancellation (Owner and Operations)
1. In **Family billing**, open **Late-cancel waivers**. It lists family cancels and no-shows from the last 60 days and the next 14.
2. Find the session, write briefly why (no health details), and choose **Waive**. The family gets a full credit for it.
3. Each learner gets one waiver a calendar year. After that, see proof and an explanation first, then tick **Proof seen**. Do not keep a copy of the proof. Tutors never see waivers.

### Paused families
**Paused families** lists families on hold for an overdue invoice. Sessions start again as soon as they pay. Only the owner (or admins, if the owner allows it in Settings) can choose **Lift the pause** without payment, with a new due date or an agreed payment plan.

### Run billing and check invoices
1. In **Invoices**, choose **Run billing now** to make this period's invoices. Drafts go to Xero on their send date.
2. Check each invoice in the list. To cancel one, open **Cancel…**, give a reason, and choose **Cancel invoice**.
3. For something unusual, use **Build an invoice by hand**.
`;

// Staff pay, for the levels that change it (Owner and Finance).
const PAY = `
## Staff pay

Open **Billing**, then **Staff pay**.

### Approve logged hours
1. **Hours waiting for approval** lists tutoring work and office admin logged by staff, and guaranteed hours top-ups added by the app.
2. Choose **Approve**, or **Decline** with a reason. Approved hours are paid in the next send to Xero.

### Send a pay period to Xero
1. Open the pay period (use **Earlier** and **Later** to move between periods).
2. Check the lines, then choose **Send to Xero Payroll**. If something changed, choose **Work out pay again** first.

### Record admin hours for someone
Under **Record admin hours**, choose the person, day, hours and what it was for, then **Record hours**.

### Pay rates and the Xero to-do list
- **Pay rates**: each person's employment type, agreed hours, and an hourly rate for each role. Choose **Save pay details**.
- **Xero to-do**: changes to make to employee records in Xero so Xero pays the same as the app. Choose **Done in Xero** once Xero matches.
- **Award rates**: upload next year's award minimum rates before 1 July.
`;

// The guide for each admin level, built from the parts above.
export const ADMIN_GUIDES: Record<AdminLevel, GuideSource> = { // level -> guide:
  owner: { // The owner's guide:
    title: "App guide for the owner", // its title,
    who: "For the owner, and anyone using emergency owner access. You can do everything in the app.", // who it's for,
    text: START + FAMILIES + MATCHING + SESSIONS + RUNNING + BILLING + PAY + `
## Owner only

### Change an admin's level
1. Open **Staff and accounts**. **Staff and levels** lists every staff member.
2. Choose a new level for an admin: Operations (day-to-day), Support (families and bookings) or Finance (invoices and pay). Nobody can change the owner's own access.

### Invite an admin
Under **Add staff**, choose the admin role and level. Only the owner can invite admins.

### Change prices, kept rates and billing settings
- **Billing**, **Prices and settings**: change each price. New invoices use these.
- In **Family billing**, use **Save kept rate** for a family keeping an older rate.
- **Settings**: choose whether new invoices go to Xero as drafts, and who can lift a pause without payment.
- **Stripe and Xero**: connect CLG's Stripe and Xero accounts.

### Reports
Open **Reports**. The app makes a report each month, each quarter and each financial year, with matching waits, enquiries, how full each tutor's week is, why people left, and money and profit per hour. Use **Report for your dates** for any dates, and **Settings** for super and running costs.

### Records, roles and deleting
In **Privacy and records**:
- **How long records are kept**: change a keeping period.
- **Remove a role or delete an account**: when someone's role changes, or to clear test accounts. Type their full name to confirm.
- **Delete a student on request**: when a family asks. Type the student's full name to confirm. Billing and child safety records are kept as the law requires.

### Staff leaving CLG
In the **Staff directory**, open the person and use the "left CLG" panel. Their matches end and their records are kept for 7 years. Then follow the checklist shown (final pay, Microsoft 365, materials, Working with Children Check link).

### App issues
Open **App issues** to check each report, reply to the person, set its priority, and use **Send to the developer** to turn an approved report into a fix. Under **Who checks app issues**, add admins who should also check them.

### Child safety contacts and watch words
On the **Child safety** page, **Who receives concerns** sets the Child Safety Officer and deputy. On **Flagged words**, add or remove the words the app watches for.

### Emergency owner access
If an Operations admin asks for emergency owner access, you are emailed at once with their reason. Cancel it if it is not needed. Otherwise it starts 24 hr later, lasts 7 days and ends by itself. Everything is logged.

### Quiet hours and summary time
- **Sessions**, **Notices**: **Quiet hours (all of CLG)** sets when nothing is sent (9pm to 5am now).
- **Sessions**, **Book a session**: **Time to write session summaries** sets the paid minutes after each session.
` + SAFETY + YOUR_OWN + HELP, // its parts,
  }, // End of the owner's guide.
  operations: { // The operations guide:
    title: "App guide for Operations admins", // its title,
    who: "For Operations admins, who run CLG day to day: families, matching, bookings, tutors, progress and invoices.", // who it's for,
    text: START + FAMILIES + MATCHING + SESSIONS + RUNNING + BILLING + `
### Staff pay (view only)
You can see **Staff pay** under Billing, but only the owner and Finance admins change pay or approve hours.

## Emergency owner access

### Ask for emergency owner access
Use this only if the owner cannot be reached and something only the owner can do is urgent.
1. Open **Staff and accounts**, then **Emergency owner access**.
2. Write why you need owner access (required), and send. The owner is emailed at once with your reason.
3. Access starts 24 hr later unless the owner cancels or approves it sooner, lasts 7 days, then ends by itself. You are emailed when it starts and ends.
4. While it runs, use the **owner guide** for owner tasks. Withdraw your request any time with **Withdraw my request**.
` + SAFETY + YOUR_OWN + HELP, // its parts,
  }, // End of the operations guide.
  support: { // The support guide:
    title: "App guide for Support admins", // its title,
    who: "For Support admins, who help families with setting up, logins and bookings.", // who it's for,
    text: START + `
Tip: As a Support admin you see **Families**, **Matching** and **Sessions**. Progress notes, tutor checks and money details are kept to other levels. If a family asks about those, pass it to an Operations admin.
` + FAMILIES + MATCHING + SESSIONS + SAFETY + YOUR_OWN + HELP, // its parts,
  }, // End of the support guide.
  finance: { // The finance guide:
    title: "App guide for Finance admins", // its title,
    who: "For Finance admins, who look after invoices, payments, credits and staff pay.", // who it's for,
    text: START + `
Tip: As a Finance admin you work in **Billing**. You see names on invoices, but not student records, sessions, notes or tutor checks.
` + BILLING + PAY + SAFETY + YOUR_OWN + HELP, // its parts,
  }, // End of the finance guide.
}; // End of the admin guides.
