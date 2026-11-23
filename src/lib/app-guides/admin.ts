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
- Choose the **Admin** tab at the top. If you also tutor or have a **Family** profile, the other tabs take you to those dashboards.
- **Home** and the **Admin** tab open your **Overview** (first in the side menu). See **See what needs you on the Overview** below.
- The side menu shows only what your admin level can use. A number next to an item means something is waiting there. A menu item with smaller items under it (for example **Sessions**) has an arrow at the end of its row. Click the arrow to open or close those smaller items from any page, without leaving the page you are on. When they are folded away, the number beside the menu item adds up all of theirs.
- **Home**, **Child safety** (in red), **Help chat**, **Feedback**, **Your privacy** and **Report app issue** are at the top of every page. On a phone, **Child safety** stays in the top bar and the rest are under the **Menu** button (top right), along with your name and **Sign out**.
- When you open something from a list (a report, an application, a training module, a handbook page, a material, a student's progress, or a student in Matching on a phone), a **Back** button at the top (and at the bottom of long pages) takes you back to the list.
- **App guide** in the side menu opens this guide. If you help families and tutors, their guides are listed under **Other guides you can open** at the bottom, so you can talk them through the app.

### See what needs you on the Overview
Your admin dashboard opens on **Overview**. It only shows what your admin level can open:
- Quick-look boxes. Owner, Operations and Support see **Sessions today**, **Next 7 days** and **Waiting for a tutor**. Owner, Operations and Finance see **Families on hold** and **Invoices to approve** (Finance also sees **Pay to approve**). Owner and Operations see **Checks to renew**. Tap a box to open that page.
- **Needs your attention**: one line for each side-menu item with something waiting (for example children to check, check-ins to follow up, help chats waiting for CLG, or new reports). Child safety concerns and flagged words show first, in red, for the Child Safety Officer and Deputy. When nothing is waiting, it says **All caught up**.
- **Tutor checks to renew** (Owner and Operations): tutors whose checks have expired or expire within 60 days, soonest first, with a link to **Tutors and checks**.

### Get a refresher on the page you are on
Every page has a **Show me how** button next to its heading. Choose it to see the App guide steps for that page, without leaving it. From there you can also choose **Open the whole App guide**, or **Take the app tour again**.

### Take the app tour again
The first time you open the admin dashboard, a short **app tour** shows the parts your admin level uses and why each one matters. To take it again, choose **Show me how** next to any page heading, then **Take the app tour again**. You can also open **App guide** in the side menu and choose **Take the tour again** at the top. If you stopped part-way, the button says **Carry on the tour** and starts where you left off.

Tip: If you help families and tutors, the App guide for parents, students or tutors has **See their tour**, so you know what they were shown.

### Get pop-up notifications on your phone or computer
Pop-ups tell you straight away about help chat messages, session notices and (if you are the Child Safety Officer or deputy) child safety concerns sent to you, even when the app is closed or you have been signed out. They never show names or details. A concern marked as immediate danger pops up even in quiet hours.
1. Choose **Turn on pop-ups** on the note at the top of your dashboard (or, if you have **Sessions**, choose **Notices** there and use the **Pop-up notifications** card).
2. When your browser asks, choose **Allow**.
3. Choose **Send me a test** to check it works.

Tip: If a family or tutor says pop-ups are not arriving: on an iPhone or iPad CLG must be added to the home screen first; if they said no before, they need to allow CLG in their phone or browser notification settings.
`;

// Sessions, as seen by front-desk admins (Owner, Operations, Support).
const SESSIONS = `
## Sessions and bookings

Open **Sessions** in the side menu. Its sections include **Overview**, **Bookings**, **Book a session**, **How long to book**, **Away dates**, **Requests**, **Blocks**, **Notices**, **Book again** and **Waitlist**. Times are Adelaide time.

### Tick off notices
1. In **Sessions**, choose **Notices**.
2. Under a notice, choose **Mark as seen** once you have read it, or **Mark as done** once you have dealt with it (for example, confirmed a library). Done notices move to the **Done** list at the bottom.
3. Ticked by mistake? Open **Done** and choose **Not done yet: put it back**. **Mark all as read** marks every notice as seen at once.

### Book a session for a family
1. In **Sessions**, choose **Book a session**.
2. Choose who it is for, the subject, how long (1 hr minimum, in half-hour steps) and the first week. Narrow the days and times if you like.
3. Choose **Find times**. **Available times** shows only tutors who suit: checks in date for the student's state, teach the subject at the student's level, free then, and under their weekly hours. Libraries are offered when they are within the tutor's travel distance for that time and the family's travel distance (or you ticked them). **At home** times are offered when the learner's address is within a tutor's distance, the tutor ticked learners' homes for that time, and the session is 2 hr or longer.
4. Choose a time. If you did not pick the suggested one, say why (it helps improve the suggestions).
5. Add a note for the tutor and family if needed, and choose **Send to tutor and family**. They each have 3 days to approve, with a reminder after 2 days. It is confirmed once both say yes. If not, the offer closes for now: the tutor and family are told, you get a notice saying who did not answer, and the student is back in **Matching**.

Tip: A student needs their details, preferred times and **How long to book** filled in before times can be offered. The family's address and travel distance are under **Session places** (from **Matching**). Libraries need a map point to be matched by distance; libraries loaded from OpenStreetMap have one.

### Book a home or school session (special circumstances)
Home and school sessions are only arranged by CLG. Home sessions are booked for at least 2 hr at a time, because the tutor travels there.
1. Check with the family and the tutor first. For a home session, confirm the address and that the tutor can travel there. For a school session, confirm the room, the school's sign-in rules and who the tutor reports to.
2. In **Matching**, choose the student, then **Offer this tutor** (or use the recommended offer).
3. In **Time and place**, choose **Another time or place…**, then the day, start time and length, and choose **At the student's home** or **At the student's school** as the **Place**. For home, only 2 hr or longer can be chosen.
4. Put the address and any arrangements in **Note for the tutor and family**, give the reason, and choose **Send to tutor and family**. The app still checks the tutor's weekly maximum and other bookings.
5. For a single extra session, use **Sessions**, **Requests**, and choose **At home** or **At school** under **Where** (home sessions are 2 to 4 hr).

Tip: **Times to check** does not list home or school sessions for a missing location, because there is no place to check against. A missing sign-on or a different finish time is still listed.

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

### Follow up a new significant date from a family
When a parent or student adds a test, exam or assignment due date on a student's roadmap, you get a notice: **New significant date from a family**. Check the student's tutor knows about it, and whether an extra session before that day would help. Dates added by tutors or admins do not send a notice.

### Follow up a block
When a family blocks a tutor, or a tutor blocks a student, it shows in **Sessions**, **Blocks**. The other person is not told. Contact the person who made the block, then record what happened and choose **Save follow-up**.

### Look after the waitlist
1. In **Sessions**, choose **Waitlist**. Everyone waiting is listed, oldest first, with how many times would now suit.
2. Check in with each family every week. **Check in due** shows on a place when 7 days have passed since the last check-in (or since they joined), and the **Waitlist** tab shows how many are due. After you contact the family, choose **Checked in** to start the next 7 days.
3. Booking that subject takes the student off the waitlist.

### Add away dates for a student or tutor
In **Sessions**, choose **Away dates**, choose who will be away and the dates, and choose **Save away dates**. A student's booked sessions on those days are cancelled. A tutor's are not: see below.

### Sort out sessions when a tutor is away
A tutor's away dates do not cancel sessions on their own. Two hours after a tutor adds away dates, you get a **Tutor away** notice listing the booked sessions on those days, and a number shows on **Away dates**.
1. In **Sessions**, choose **Away dates**. **Sessions during tutor away dates** lists each one, with any times the tutor can offer instead.
2. Contact the family and offer another time or another tutor. Changing the session to another time or tutor takes it off the list.
3. If nothing suits, choose **Cancel session**. The family gets full credit and is told, with the tutor's other times and how to ask for another time or tutor.

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
2. Choose who the account is for (a family, or a student with their own login), then enter their full name and email, and the child's details. Add one child at a time, using the same parent email for each child.
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

### Change a student's details (Owner and Operations)
Use this when checking a new family, or when a family asks CLG to correct something.
1. In **Families**, open **Change a student's details**.
2. Choose the student and choose **Open**. (From **Matching**, **Fill in** next to a missing year level or school opens this for that student.)
3. Correct the year level, school, subjects and levels, goals, other information or learning needs, and choose **Save changes**.

Tip: Preferred days and times, places and study dates are on the **Schedule** page, under the student's places.

### Approve places in the Student Success Program (Owner and Operations)
Families ask about the program from their dashboard (a tick box under each child). Places are limited, and a student is only in the program once the $500 deposit is paid.
1. In **Families**, open **Student Success Program**. The title shows how many places are used and left. It lists **Requests waiting**, places **Waiting for the deposit** (amber once overdue) and students **In the program**.
2. Choose a student's name. This opens **Change a student's details** at the **Student Success Program** part.
3. To offer a place, fill in the sessions planned, **Book sessions until**, whether sessions go ahead in school holidays and on public holidays, and any note for CLG (every box is optional), then choose **Approve the place and send the $500 deposit invoice**. The place now counts as used, and the family gets a notice and an email saying how to pay it in **Billing**. The family must have billing set up (a bill payer) first. You can also approve a student who has not asked in the app, for example after a phone call.
4. To say no, add a reason for the family (optional) and choose **Decline the request**.
5. When the family pays the deposit (Pay now in the app, or a payment entered in Xero), the student is in the program straight away and the family is told.

Being in the program gives the student a study plan, includes each term review at no charge (the tutor's draft is made straight away and the family is told it is included), shows a **Student Success Program** label in **Matching**, and puts them at the top of the Matching queue and of **Fill a tutor's times**. The book-until date is also saved as the student's **How long to book**, so it must be within a year.

- **Change the details** of a place: change them and choose **Save program details**.
- **Withdraw the place** (deposit not paid yet): give a reason for the family. The place is freed and the deposit invoice is cancelled. If it is already in Xero, void it there too. If the deposit invoice is cancelled in Xero, the place is freed and the request goes back to **Requests waiting**.
- **Remove from the program** (deposit paid): the place is freed, the program study plan ends today, term reviews are offered as usual again, and booked sessions stay booked. Any refund follows CLG's terms and is done in **Billing**.
- **Places and payment time**: at the bottom of the card, set the number of places and the days families have to pay the deposit (7 to start), then choose **Save places**. The deposit amount is the **Student Success Program deposit** price in **Billing**, **Prices and settings** (Owner and Finance).

The deposit is never charged automatically, and an unpaid deposit never puts the family's sessions on hold.

### Give a student their own login
1. In **Families**, open **Give a student their own login** (students 16 and over).
2. Choose the student and enter their own email, then send. They keep their details, history and tutor, and their parent can still see everything.

### Send a new login link
If a family's or student's link ran out before they used it, open **Send a new login link**, enter their email and send.

### See which families are paused
**Families paused for an overdue bill** lists families whose sessions are on hold until they pay. Do not discuss the bill with the tutor: tutors are only told sessions are on hold.

While a family is on hold, the people who pay get a notice 48 hr before each session. If the payment is not made, or the pause lifted with a payment plan, at least 2 hr before the session, the app cancels that session with no charge and tells the family and tutor (the tutor is not told why). You get a **Session cancelled for no payment** notice: set up a meeting between Carla and the person who pays, to talk about whether anything needs to change, how to support them, and how to stop it happening again.
`;

// Matching students with tutors (front-desk admins).
const MATCHING = `
## Matching

Open **Matching** in the side menu.

### Find a tutor for a student
1. In **Matching**, choose a tab along the top: **Needs a tutor**, **Waiting for tutor**, **Waiting for family**, **Waitlist**, **Assigned, no time** or **Active**. Each tab shows how many are in it. Search or filter by year level and state if needed. Students in the Student Success Program are at the top, with a violet **Student Success Program** label, because they have paid the deposit. Everyone else follows, longest waiting first.
2. **Waitlist** means no suitable tutor is available yet. It is not the first weeks with a new tutor (those students are in **Active**).
3. Choose a student. An amber dot beside a name means a detail is missing.
4. **Ready to offer** (or **details missing**) at the top lists year level, school, session places and how long to book. For anything missing, choose **Fill in**, or choose **Ask the family**. The family gets an app notice and an email with a link to fill it in, and a pointer to the help chat if they have questions. You can ask once a day for each detail, and the list shows when you last asked.
5. A summary line shows the year, school, working level, places and preferred times. Choose **More details** for goal, learning needs, tutor preferences, siblings and past tutors.
6. **Recommended offer** shows the best fit tutor with the offer ready: teaches the subject at the student's working level, then a sibling's tutor, then spare hours, then a place and time that suit. Pay rates are not shown. A tutor is never offered for their own child or anyone in their own family.
7. Check the time and place, and send it to the tutor and family to approve. To choose someone else, open **Other tutors who suit** and choose **Offer this tutor**.
8. Choose **Next student** to keep going.

### Fill a tutor's free times
1. In **Matching**, choose **Fill a tutor's times** at the top.
2. Choose the tutor and choose **Show students**. The line under it shows how many hours a week they already have booked, and their weekly maximum if one is set.
3. The list shows every student still waiting for a tutor (**Needs a tutor** or **Waitlist**) who fits one of that tutor's free times: Student Success Program students first, then longest waiting first. Each row shows the subject, how long they have waited, how many times suit and the best time and place. **Teaches a sibling** and **Over their weekly maximum** are shown when they apply.
4. Choose **Make an offer** to open the student in Matching and send the offer as usual.

The same rules apply as when you start from the student: the tutor teaches the subject at the student's level, their checks are current, neither has blocked the other, and a time suits both. A student with no year level yet is not listed, so fill it in first.

### Set when a student started waiting
If a student was on CLG's waitlist before they were added to the app, open them in **Needs a tutor** or **Waitlist**, open **Waiting since**, choose the day they first asked, and choose **Save date**. Leave it empty and save to go back to the day they were added.

### Reports
Choose **Reports** at the top of Matching to see:
- **Response times**: the average time families and each tutor take to answer an offer, and how many offers ran out with no answer (last 180 days).
- **Gaps**: subjects and levels students are waiting for where no tutor with current checks teaches them. It shows who to recruit next.
- **Why suggestions were changed** (Owner and Operations admins).

### See the travel map
1. In the side menu, choose **Travel map** (Owner and Operations admins).
2. The map shows CLG's approved libraries (charcoal dots), each tutor's travel areas (solid bronze circles) and each family's travel area (dashed green circles). Circles are straight-line distances.
3. Click a circle to see who it is, the distance, and (for tutors) the weekly times that use it. Street addresses are not shown on the map.
4. Use the tick boxes to show or hide libraries, tutor areas or family areas. Choose one tutor in the **Tutor** list to zoom to their areas.

### See the list of libraries
1. In **Sessions**, choose **Libraries** (Owner and Operations admins).
2. Type a name, suburb or address in the search box and choose **Search**. Choose **Clear search** to see them all again.
3. Use the buttons at the top of the list: **Active (ready for sessions)** shows libraries that are shown, confirmed and have opening hours, so sessions can be offered there. **★ Asked for, to confirm** shows libraries a tutor, family or student has asked for that are not confirmed yet (they also have a ★ in the list). **To confirm or add hours** shows libraries still needing a look. **Hidden** shows libraries you have hidden. **All** shows every library. Each button shows how many are in it.
4. To make a library active, add its opening hours under **Add opening hours**, then confirm it.

### Libraries on public holidays
Every library is set as closed on public holidays, so no session is held at a library on one. A weekly booking simply has no session that week, and the family can ask for a one-off at another time.
1. If a library does open on public holidays, choose **Set as open on public holidays** under it in **Sessions**, **Libraries**.
2. To change it back, choose **Set as closed on public holidays**.
`;

// What every admin has for themselves: training, handbook, staff directory, pay.
const YOUR_OWN = `
## Your own training, handbook and pay

### Do your training
1. In the side menu, choose **Training**. **To do now** lists your compulsory and due modules.
2. Open a module, read the lessons, then do the quiz (100% needed, unlimited tries). To stop part way, choose **Done, save my place** under a lesson or **Save my answers and finish later** in the quiz. Compulsory and assigned modules are paid for their set time, however long they take. Other training is only paid if it was approved first.
3. Download your certificate when you finish.

### Use the handbook
Choose **Handbooks** in the side menu, and search for a word. **Something has happened** is pinned at the top in red.

### Keep and share learnings
1. Choose **Learnings** in the side menu. Under **My learnings**, write a **Short title** and **What was learned**, then choose **Save learning**. Only you see it until you open it and choose **Suggest for the team**.
2. Owner and Operations: a number next to **Learnings** shows suggestions waiting. Under **Suggested for the team**, change the words so they work for everyone and choose **Add to team learnings**, or write a note and choose **Decline for now**. The person is told either way.
3. Owner and Operations: under **Team learnings**, open **Change or remove** to update one, or choose **Add a team learning** to add one directly.

### Find a colleague
Choose **Staff directory** (from Admin or Billing) to search staff by name, email, job title or subject.

### Sign your own contract
When CLG sends you a contract, a card on your dashboard and **My contract** in the side menu take you to it. Read it, tick both boxes, type your full name and choose **Sign and accept**. Then open each document listed, tick that you have read it, type your name and acknowledge it. When a policy gets a new version, **My contract** shows a number: open your contract, read the new version and tick it again.

### Log your office hours
1. In the side menu, choose **My Pay**.
2. Under **Log hours**, choose **What kind of work?** (**Office admin** for office work), then the day and hours. Write **What you did** and **What you finished or achieved**. Log each pay week by the day after it ends.
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
Families, students, tutors and staff ask CLG questions in the **Help chat**. Owner, Operations and Support admins answer general chats. Owner, Operations and Finance admins answer **Billing and payments** and **My Pay (CLG staff)** chats.
1. Choose **Help chats** in the side menu. The number shows chats waiting for CLG.
2. **Waiting for CLG** lists the longest waiting first. Open a chat by its title.
3. Write your reply and choose **Send**. It is sent as CLG, and they get an email saying there is a reply (never the message itself, and not between 9pm and 5am their time).
4. The first admin to reply looks after the chat. To hand it over, choose someone under **Looked after by** and choose **Save**. You can also mark it **Closed** there.

### Start a chat with a family or person
1. In **Help chats**, choose **Start a chat with a family or person**.
2. To ask a family, choose the student and **Choose**. Tick who should be in the chat: parents start ticked; the student (if they have their own login) and their tutors do not. Only tick the people who should see it.
3. Owner and Operations admins can instead pick a tutor or staff member.
4. Choose the topic, write a short title and message, and choose **Start the chat**.

### Keep a chat past 2 years (Owner and Operations)
Chats are deleted 2 years after their last message. Chats with writing flagged by the child safety check (not closed as "No concern") are kept by themselves.
1. Open the chat. Under **For CLG**, find **Keep this chat past 2 years?**.
2. Choose **Testimonial**, **Practice scenario for staff training** or **Tracking a concern**, and choose **Save**.
3. A testimonial is only allowed when everyone who wrote in the chat is 18 or over and has turned on **Quoting what you write** on their Your privacy page. Never show a name or anything that could identify them or their child.

Tip: Billing details should only go to the person who pays. Messages are checked for child safety words like other writing in the app.

### Give feedback or report an app issue
- **Feedback** (top of the page, or under **Menu** on a phone): praise, ideas or worries.
- **Report app issue**: something in the app is not working. Add a screenshot if you can.

### Your privacy and name
Choose **Your privacy** to download your information or ask CLG about it. Tap your name under **Signed in as** to change it (on a phone, tap **Menu** at the top right first).
`;

// Staff employment contracts: sending, following and the Xero invite (Owner,
// Operations and Finance; split out 18 Nov 2026 so the Finance guide has it too).
const CONTRACTS = `
## Employment contracts

Open **Contracts** in the side menu. Staff read and sign their contract in the app, then acknowledge the Fair Work Information Statement, the Casual Employment Information Statement (casual staff only), the Child Safe Policy and the Staff Code of Conduct.

### Send a contract
1. Under **Send a contract**, choose the **Contract**, the **Staff member** and the **Employment type**.
2. Fill in each box under **Details to fill in** (for example the start date, award levels and rates). Their name, email, employment type and the date fill in by themselves. Leave an optional box empty to show "Not applicable".
3. Choose **Send contract**. They are emailed a link, and a card on their dashboard asks them to sign.
4. If a mistake is spotted before they sign, open the contract and use **Withdraw this contract**, then send a corrected one. Sending a new contract to the same person also replaces one still waiting.

### Follow a contract
1. **Waiting on staff** lists contracts not yet signed or not yet finished. Choose **Open** to see where it is up to.
2. The contract page shows the exact wording sent, when and how they signed, each document they acknowledged (and which version), and any pay sent to Xero since (accepting pay is also acceptance of the contract).
3. **New policy versions still to read** (at the top of **Contracts**) lists staff who have not yet read and ticked the newest version of a policy. Choose **Open contract** to check, and remind them if needed.

### Send the Xero self-setup invite
Once a contract is signed, the **Xero** column says **To do**, and the number next to **Contracts** counts these.
1. Open the contract and follow the steps under **Xero self-setup**: in Xero, choose Payroll, then Employees, then New employee, then **Invite to self-onboard**, using the name and email shown.
2. Choose **I have sent the Xero invite**.
3. When they finish the Xero form, approve it in Xero, then match them to Xero under **Billing**, **Staff pay**.

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

${CONTRACTS}## Progress

Open **Progress** in the side menu.

### Check term reviews before families see them
1. **Term reviews to check** lists reviews tutors have written.
2. Check each one: is it written to the family, honest about progress, and clear about next term?
3. Approve it, or send it back with what needs changing. Approving it pays the tutor 1 hour at their tutor rate.
4. Tutors cannot send a term review until they have finished the term review training modules.

### Keep notes on track
- **Notes overdue** lists sessions still without a note 12 hr after they ended. The tutor was already reminded at 6 hr, when the note was due, so follow up with the tutor. Families are promised the note within 48 hr.
- **Plan for the next session missing**: you get this notice when a summary is in but its plan is still missing 12 hr after the session, the student came, and a next session with that tutor is booked. The tutor was reminded at 6 hr. No plan is needed when there is no next session.
- **Students to check** lists students with no goals, or whose skills have not moved for a while.
- **Recent notes to spot-check**: is the next step specific, and the tip for home a small habit?
- **How progress tracking is going** shows the measures for any dates you choose.
- Each tutor sends a session summary and a plan for the next session together, in the 15 paid minutes after the session. To read a plan, open the student's progress page: **Plan for the next session** shows the newest one with its materials, and older plans sit under **Recent sessions**. You can correct a plan or remove a session file at any time; tutors can for 7 days.

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

### Tutor lateness
A late start is recorded when a tutor signs on more than 5 minutes after the booked start, or sends a **Running late?** notice from their Sessions page (the family gets a notice and an email, and you get an app notice with the reason).
1. Open **Tutor lateness** in the side menu (Owner and Operations). A number shows how many are waiting for review.
2. **Waiting for review** lists each late start, how late the tutor signed on, and whether they gave notice before the start.
3. Talk with the tutor if needed, write a private note, then choose **Mark reviewed**. Tutors see their own late starts, but not your notes.
4. **Late starts in the last 90 days, by tutor** shows who is often late, so you can follow up early.

### Staff probation
Tutors finish probation at 3 months or 30 completed sessions, and admin staff at 3 months or 40 approved hours (one full-time work week of 8 hours a day for 5 days), whichever comes first. The app sets up a probation for each new tutor and admin staff member from the start date on their pay details.
1. Open **Staff probation** in the side menu (Owner only). A number shows how many are due for review. You also get an app notice on the day someone becomes due.
2. **Due for review** lists each person, why they are due and their progress. Talk with them, then choose **Passed**, **Extend probation** (with a new review date) or **Ended (not continuing)**, add a private note and choose **Save review**. An extended probation reminds you again on the new date.
3. **On probation** shows everyone else still on probation, with their progress and due date. Choose **Change the start date** if a start date is wrong.
4. To add someone the app did not set up (for example, with no start date on their pay details), open **Set up a probation**.

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
2. To give someone a module, open it and use **Assign to someone** (who, a due date and why). It goes on their To do list, they are told, and it is paid for its set time when they finish. **Must be done in order** makes a module wait for the ones above it with the same tick (the safety modules 1 to 8). **Needed before a job** marks modules needed before drafting work, a term review, or study plan work (the paid study plan add-on).
3. To add a screenshot to a quiz question, open the question and use **Screenshot or picture** (PNG, JPEG or WebP), with a short description of what it shows. To add a practice task, write it in **Practice task checked by CLG** on the module. Tasks people send in appear under **Practice tasks** (with a count). Approve each one, or choose **Send back** with what to change. You cannot check your own.
4. **Progress** shows everyone's compulsory modules. The **Ready for** column shows which tutors are ready for drafting, term reviews and study plans (check it before giving someone a drafting job). If a tutor is given a term review before they have done its modules, the modules are assigned to them and you are told. The same happens when a tutor teaches a student whose family pays for study plans: the study plan module is assigned to them, due before their next session with that student. While study plans are free for everyone, nothing is assigned.
5. **Handbooks** is where you write the tutor handbook pages.
`;

// Billing for every level that can open it (Owner, Operations, Finance).
const BILLING = `
## Billing

Open **Billing** in the side menu. Its sections are **Family billing**, **Invoices**, **Staff pay**, **Prices and settings**, and **Stripe and Xero**.

### Set a family's plan or bill payer
1. In **Family billing**, find the family.
2. Choose how often they pay and the bill payer, then choose **Save plan**.
3. If two people share invoices, choose who also pays and their share, then **Save split** (Owner and Finance).

Tip: A family must choose how often they pay before they can ask for a booking or approve a time you offer. If they are stuck, you can set the plan here. The person who pays can change the plan later in their Billing page: once they have an invoice, the change is booked and starts from their next invoice, and you get a notice. A booked change shows next to the family's plan. Saving the plan here sets it straight away and clears the booked change.

Tip: Only the bill payer and any extra payers see a family's billing (plan, invoices and credit). Other parents and students do not, but they are still told when sessions are on hold. Until a bill payer is set, the first parent to choose the plan or agree to the terms becomes the bill payer, so set it here if someone else should pay.

### Add credit (Owner and Finance)
In **Family billing**, find the family, enter the amount and reason, and choose **Add credit**. Credit comes off their next invoice.

### Waive a late cancellation (Owner)
1. In **Family billing**, open **Late-cancel waivers**. It lists family cancels and no-shows from the last 60 days and the next 14. Operations admins can see the list, but only the owner waives.
2. Find the session, write briefly why (no health details), and choose **Waive**. The family gets a full credit for it.
3. Each learner gets one waiver a calendar year. After that, see proof and an explanation first, then tick **Proof seen**. Do not keep a copy of the proof. Tutors never see waivers.

### Paused families
**Paused families** lists families on hold for an overdue invoice. Sessions start again as soon as they pay. Only the owner (or admins, if the owner allows it in Settings) can choose **Lift the pause** without payment, with a new due date or an agreed payment plan.

### Run billing and check invoices (Owner and Finance)
1. In **Invoices**, choose **Run billing now** to make this period's invoices. Drafts go to Xero on their send date.
2. Check each invoice in the list. To cancel one, open **Cancel…**, give a reason, and choose **Cancel invoice**.
3. For something unusual, use **Build an invoice by hand**.
`;

// Staff pay, for the levels that change it (Owner and Finance).
const PAY = `
## Staff pay

Open **Billing**, then **Staff pay**.

### Approve logged hours
1. **Hours waiting for approval** lists work outside sessions logged by staff (with the kind of work, what they did and what they finished or achieved), training, and guaranteed hours top-ups added by the app.
2. Choose **Approve**, or **Decline** with a reason. Approved hours are paid in the next send to Xero. **Work during a no-show or late cancel** is already paid with the session, so approving it only marks the work checked.
3. **Work outside sessions (last 8 weeks)** lists everything each person logged and what they achieved. Open a person to check their entries.

### Send a pay period to Xero
1. Open the pay period (use **Earlier** and **Later** to move between periods).
2. Check the lines, then choose **Send to Xero Payroll**. If something changed, choose **Work out pay again** first.
3. Each term review you approve adds a **Term review** line: 1 hour at the tutor's rate, on the day you approved it. A tutor needs a tutor rate entered for it to be added.

### Record admin hours for someone
Under **Record admin hours**, choose the person, day, hours and what it was for, then **Record hours**.

### Xero self-setup for new staff
Open **Contracts**. Once a contract is signed, open it and follow **Xero self-setup** to send Xero's **Invite to self-onboard**, then choose **I have sent the Xero invite**.

### Pay rates and the Xero to-do list
- **Pay rates**: each person's employment type, agreed hours, **Start date with CLG**, **School tutoring award level** (tutors), and an hourly rate for each role. Choose **Save pay details**.
- **Start date and Level 2**: under the Miscellaneous Award, a tutor is Level 1 for their first 3 months, then Level 2. The app works this out from **Start date with CLG**. At 3 months it raises their school rate if it is below the Level 2 minimum, tells the owner and Finance admins, and adds a **Xero to-do** to change their classification. Choose Level 3 or 4 only when a tutor has the qualifications for it. **Start dates needed** lists tutors with no start date yet.
- **Penalty rate top-ups**: when a tutor's own rate is below the award rate for school tutoring on a weekday before 7am or after 7pm, a Saturday, a Sunday or a public holiday, **Work out pay** adds a **Penalty rate top-up** line with the difference. Its note shows the minutes and award rate. Public holiday rates apply only on a public holiday in the state the tutor is based in (their work state; SA if not set), whatever the learner's state. Top-ups are not sent to Xero as hours: **Send to Xero Payroll** adds a **Xero to-do** with the amount to add to that pay run.
- **Xero to-do**: changes to make in Xero so Xero pays the same as the app, including penalty rate top-ups to add to a pay run. Choose **Done in Xero** once Xero matches.
- **Award rates**: upload next year's award minimum rates before 1 July. From 1 June each year, until they are uploaded, the owner and Finance admins get an app notice every 14 days, Billing shows a to-do number, and **New award pay rates are due** shows at the top of Staff pay. Each line of the file has work, employment, level (1 to 4), hourly rate and award name; **Download this year's rates** gives a file to change. Once uploaded, the app raises any rate below the new minimum for each person's level on the start date and adds a **Xero to-do** line for each change.
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
Open **Reports**. The app makes a report each month, each quarter and each financial year, with matching waits, enquiries, how full each tutor's week is, why people left, and money and profit per hour. Use **Report for your dates** for any dates, and **Settings** for super and running costs. Operations admins can open every report too, but never see the money part, the spreadsheet download, **Report for your dates** or **Settings**.

### Set quarterly and yearly goals
1. Open **Reports**, then **Goals**.
2. Under **Set a goal**, choose the period (this or next quarter, or this or next financial year), the figure (for example students matched within 2 weeks, or the average wait), and the target. Add a note if it helps.
3. Choose **Save goal**. Saving a goal for a figure that already has one in that period changes it. Use **Remove** to take a goal away.
4. Each month, **Goals** shows each goal with the figure so far, what is expected by now, and **On track** or **Behind**. Quarterly and yearly reports show whether each goal was **Met**. Goals never use money, so Operations admins see them too.

### Records, roles and deleting
In **Privacy and records**:
- **How long records are kept**: change a keeping period.
- **Remove a role or delete an account**: when someone's role changes, or to clear test accounts. Type their full name to confirm.
- **Delete a student on request**: when a family asks. Type the student's full name to confirm. Billing and child safety records are kept as the law requires.

### Contract templates
1. Open **Contracts**, then **Contract templates and document links**.
2. To update a contract, open the version **In use** and paste the new wording: in the contract's Claude Doc, choose Export, then Markdown, then paste everything into **Wording**. Put gaps in square brackets, for example [Start date]. **Gaps found** shows which fill in by themselves and which an admin types.
3. Choose **Save as a new draft version**, check the **Preview**, then tick the box and choose **Publish this version**. Contracts already sent keep their own wording.
4. Under **Documents staff acknowledge**, each document shows **Link set** when it has a link, and **Open link** lets you check it opens the right document. Change the name or **Link (Australia)**, add any **Links for other countries** (one per line, for example NZ then the link), then choose **Save name and links**.
5. The Child Safe Policy and the Staff Code of Conduct are kept in the app, so contracts show them as buttons that open a page in the app. Paste each one's wording into **Wording** (from its Claude Doc: Export, then Markdown), choose **Save wording**, and tick **Approved** once the wording is final. Until then, staff see a draft label on the page.
6. When a document changes in a way staff need to know about, save it as a new version. For a document kept in the app, tick **This is a new version** (it must also be approved) and add **What changed**, then choose **Save wording**. For a document kept elsewhere (such as a Fair Work statement), tick the box and choose **Ask staff to read the new version**. Every staff member whose contract includes it is asked to read and tick it again, and each tick is kept. Leave the box unticked for small fixes such as spelling.

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
    who: "For Operations admins, who run CLG day to day: families, matching, bookings, tutors and progress, and who can see billing.", // who it's for,
    text: START + FAMILIES + MATCHING + SESSIONS + RUNNING + BILLING + `
### What you can change in Billing
You can see **Billing** so you can help families and tutors: prices, each family's plan, invoices, credit and split payments. You can set a family's plan and bill payer. Only the owner or a Finance admin builds, approves or cancels invoices, adds credit, or changes split payments, and only the owner waives a late cancellation. Pass those requests to Carla.

### Staff pay (view only)
You can see **Staff pay** under Billing, but only the owner and Finance admins change pay or approve hours.

## Reports and goals

### Open a report
Open **Reports**. The app makes a report each month, each quarter and each financial year, with matching waits, enquiries, how full each tutor's week is and why people left. Choose **Open** on a report to see it. Money (income, wages and profit) is only shown to the owner, so it is not in the reports you see.

### Check how the goals are going
1. Open **Reports**, then **Goals**. The owner sets goals for each quarter and financial year.
2. Each goal shows the figure so far, what is expected by now, and **On track** or **Behind**. Figures that add up over time, such as students matched, are compared with the share of the goal expected by now.
3. Use this at the monthly check-in with the owner to talk about why each goal is on track or behind. Quarterly and yearly reports show whether each goal was **Met**.

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
Tip: As a Finance admin you work in **Billing** and **Contracts**. You see names on invoices, but not student records, sessions, notes or tutor checks.
` + BILLING + PAY + CONTRACTS + SAFETY + YOUR_OWN + HELP, // its parts,
  }, // End of the finance guide.
}; // End of the admin guides.
