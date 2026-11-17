// Summary: the app guide for tutors: what they can do in the CLG app and
// how, step by step. This is the "how to use the app" guide. CLG's policies
// and "what to do if" pages stay in the tutor Handbook, which admins write
// in Training setup. The text below is the guide itself, in the simple
// layout read by parseGuide in ./index.ts ("##" a part, "###" a task, "1." a
// step, "-" a bullet point, "Tip:" a tip; **stars** mark the exact names of
// buttons and menu items). Update this text whenever a tutor feature changes.
//
import type { GuideSource } from "./index"; // The shape of a guide's words (for type checking only).

// The tutor guide's words. (Text inside the backticks is the guide itself,
// not code, so its lines don't carry code comments.)
export const TUTOR_GUIDE: GuideSource = { // The guide:
  title: "App guide for tutors", // its title,
  who: "For CLG tutors.", // who it's for,
  text: `
## Getting started

Your side menu has **Your students**, **Sessions**, **Weekly calendar**, **What you teach**, **Child safety checks**, **Hours and availability**, **CLG materials**, **Training**, **Handbooks**, **App guide** and **My pay**. Once CLG sends you an employment contract, **My contract** appears too. A number next to an item means something is waiting for you there.

Tip: When you open a training module, a handbook page or a student's progress page, a **Back** button at the top (and at the bottom of long pages) takes you back to the list.

Tip: This guide is about using the app. For CLG's policies and what to do when something happens, open **Handbooks**.

### Join CLG from your invitation
1. Open the invitation email from CLG. The link works once, for 7 days, and only for your email.
2. Enter your first and last name and choose a password.
3. Set up two-step login (below).

### Sign your employment contract
CLG sends your contract in the app. A card on your dashboard and **My contract** in the side menu take you to it.
1. Read the whole contract. If anything is unclear or looks wrong, ask CLG in **Help chat** before signing.
2. Under **Sign your contract**, tick that you have read it and agree, and that you agree to sign electronically.
3. Type your full name exactly as shown, then choose **Sign and accept**. You need two-step login to sign.
4. Under **Acknowledgements**, open each document (the Fair Work Information Statement, the Casual Employment Information Statement if you are casual, the Child Safe Policy and the Staff Code of Conduct), tick that you have read it, type your name and acknowledge it.
5. CLG then sends you an email from Xero to enter your tax, bank and superannuation details.

Tip: Your signed contract stays in **My contract**, so you can read it again at any time.

### Set up and use two-step login
Tutors and admins need two-step login, because the app holds children's information.
1. Install an authenticator app on your phone (for example Microsoft Authenticator or Google Authenticator).
2. After you sign in the first time, choose **Set up two-step login**.
3. Scan the code with your authenticator app, enter the 6-digit code it shows, and choose **Turn on two-step login**.
4. Each time you sign in, enter the 6-digit code from your authenticator app.

### Put CLG on your phone's home screen
Choose **Add CLG to your home screen** at the bottom of any page and follow the steps for your phone.

### Take the app tour again
The first time you open your dashboard, a short **app tour** shows the main parts of the app and why each one matters. To take it again, open **App guide** in the side menu and choose **Take the tour again** at the top. If you stopped part-way, the button says **Carry on the tour** and starts where you left off.

## Your profile: checks, subjects and hours

CLG can only match you with students, and show you their sessions, while your child safety checks are confirmed and in date for the student's state.

### Add or renew a child safety check
1. In the side menu, choose **Child safety checks**.
2. Under **Add or renew a check**, choose the check (for example Working with Children Check, RRHAN-EC training or first aid).
3. Enter the card or certificate number (not needed for RRHAN-EC or first aid), the date it was done or issued, and the expiry date for a working with children card.
4. Add a copy: a PDF or a clear photo of the whole card or certificate. Only you and CLG admins can open it.
5. Choose **Send to CLG**. CLG checks it against the official record and confirms it.

Tip: **Where you stand** shows what is confirmed and when each check runs out. You get reminders before a check expires. If a check lapses, your sessions are hidden until it is renewed.

### Say what you teach
1. In the side menu, choose **What you teach**.
2. Choose a subject and the year levels you teach it at (for example Maths from Year 3 to Year 10).
3. Choose **Add subject**. Add each subject separately.

### Set your hours and availability
1. In the side menu, choose **Hours and availability**.
2. Enter the most hours you can work each week, then choose **Save hours**.
3. Under **Where you travel from**, add your home or another address you travel from (for example "Home" or "Uni"), then choose **Add address**. Only you and CLG admins can see it.
4. Add each time you are available: the day, from and to, and where you can teach. Tick **Online**, **At public libraries within my travel distance**, **At learners' homes within my travel distance**, or a mix. For in-person times, choose the address you are **Travelling from** and the **Most km I will travel** (in a straight line). Choose **Add time**.
5. The address and distance can be different for each time. Libraries within your distance (and within the family's) are offered for you, so you do not need to pick libraries.
6. Remove a time you no longer have with its remove link. An address cannot be removed while a time still uses it.

### Say where you teach
1. In **Sessions**, choose **Where you teach**.
2. Tick how you teach (online, in person, or both), then save. If you set travel distances on your times, you do not need to tick libraries here.
3. Library not in the list? Add its name and suburb, and choose **Suggest library**. CLG checks it before families can book it.

### Confirm your availability for next term
About 4 weeks before a term ends, CLG asks **Is your availability right for next term?** on your Sessions overview. Check your hours, then choose **No changes** or **I have updated it**.

## Sessions

Open **Sessions** in the side menu. Its sections are **Overview**, **Bookings**, **Away dates**, **Requests**, **Blocks**, **Notices** and **Where you teach**. Times are Adelaide time. Tutors do not book sessions: CLG offers them, and you accept.

### Accept or decline a booking request
1. When you have a request, the Overview shows **You have (number) booking requests to answer**. Choose **See requests**.
2. Check the student, subject, day, time and place.
3. Choose **Accept**, or **Decline** with a note to the family saying why.
4. Answer within 48 hr, or the request runs out and the time is freed.

Tip: When CLG offers a time to both you and the family, you see **Approve** and **This time does not suit** instead. It is confirmed once you both say yes. You have 3 days, with a reminder after 2. After that the offer closes for now.

### Sign on to a session
1. From 30 minutes before the session, **Sign on** appears next to it on the Overview.
2. Choose **Sign on**. For a library session, your phone asks once to share your location. The app only checks that you are at the library and keeps the result, never your location.
3. You are signed off automatically at the booked end time.

### Join an online session
Choose **Join** next to the session on the Overview, or on your **Weekly calendar**. It opens Microsoft Teams.

### Mark whether a session happened
After a session, **Did these sessions happen?** shows on the Overview. Choose **Done** or **No-show** for each one. If the student has not arrived, wait 15 minutes after the start, then log off or leave and choose **No-show**. The app will not take a no-show before then.

### Record a different finish time
1. On the Overview, open **Your recent sessions**.
2. Choose **Finished at a different time?** next to the session.
3. Enter the time you finished and why, then choose **Send to CLG**. Do this within a week. CLG confirms it before pay.

Tip: Only record a finish that is more than 15 minutes early, or a session that ran over. Finishing up to 15 minutes early counts as finishing on time.

### Cancel a session
1. On the Overview, find the session and choose **Cancel**.
2. Choose a reason (please do not include health details).
3. Offer two other times that week. The family picks one. If no time works, tick that box and CLG will help.
4. Choose **Cancel this session**.

### Pick or confirm a make-up time
If a family cancels and offers two times, **Pick a make-up time** shows on the Overview. Pick one to book it, or choose **Neither works** and say why. If CLG offered the times and the family picked one, confirm it under **Confirm a make-up time**.

### Confirm a change of tutor or time
If CLG wants to move a student's sessions to you (or change the day and time), a **Please confirm a change** card shows on the Overview. Choose **Confirm**, or **Decline** and say why. Nothing changes until everyone has confirmed.

### Add away dates
1. In **Sessions**, choose **Away dates**.
2. Choose yourself, then the first and last day away.
3. Add times you could offer instead that week, if any. These are shared with the families whose sessions are cancelled.
4. Choose **Save away dates**. Sessions on those days are cancelled and families are told.

### Offer a time for a family's request
1. In **Sessions**, choose **Requests**.
2. Find the request from your student's family (for example an extra session before a test).
3. If you can, choose a date, time, length and place, add a note for the family, and choose **Offer this time**. The family then approves it.

### Answer a check-in about a new student
When you start with a new student, a card on your dashboard asks how it is going 1 week, 2 weeks and 6 weeks after your first session together.
1. Choose how the sessions are going (1 to 5) and whether you think you are a good fit for the student.
2. Add a comment if you like, and tick **Please contact me about this** if you would like CLG to get in touch.
3. Choose **Send**, or **Skip this check-in**.

When you stop working with a student (for example after a change of tutor), a card asks how the sessions went and how well the ending was handled. Answer it the same way.

Tip: Only CLG's office team sees your answers. The family does not, and you do not see theirs.

### If a match is not working
1. In **Sessions**, choose **Blocks**, then **Block a student**.
2. Write why. Only CLG sees the reason, and the family is not told.
3. Choose **Block this student**. CLG will follow up with you.

### See your week, and add sessions to your own calendar
1. In the side menu, choose **Weekly calendar**.
2. Under **Add to your own calendar**, choose **Make my calendar link** and follow the steps for Google, Outlook or Apple calendar.
3. The calendar shows only each student's first name, the subject, the time and the place. Join online sessions from the app.
4. If you share the link by mistake, choose **Make a new link**.

### Notices and reminders
In **Sessions**, choose **Notices**. Open **Reminder settings** to choose when your first reminder comes before each session. Nothing is sent between 9pm and 5am your local time.

## Students and progress

### See your students
1. In the side menu, choose **Your students**.
2. Each student shows their subject and a **Progress and notes** link.
3. You only see students you are matched with, and only what you need to teach them.

### Write a session note
Notes are due within 6 hr of each session and take about three minutes. Families are promised them within 48 hr, so CLG follows up anything later than 6 hr.
1. On **Your students**, **Session notes to write** lists what is due. Choose **Write note**.
2. Fill in what went well, the next step, any homework or practice and its due date, and one thing to try at home.
3. Use **Note for CLG staff only** for anything just for CLG.
4. Choose **Save note**. The family and student see the note (except the staff-only part).

Tip: Write the next step to the student, and keep it specific. For a session that was not booked in the app, use the link under **Write a session note**.

### Set goals and skills
1. Open the student's **Progress and notes**.
2. Under **Add a goal**, write the goal, choose the curriculum skills it covers, and an aim-by date if you like.
3. Choose **Add goal**. As the student improves, move the skill levels up on **Goals and skills**.

### Look at work the family uploaded
When a family uploads a school report or marked work, it shows under **New uploads from families**. Choose **Have a look**, then **Look at it and link skills** to add a comment and link any skills it shows.

### Write a term review
1. When a family books a term review, it shows under **Term reviews to write**. Choose **Write review**.
2. Write how the term went, the focus for next term and your recommendation.
3. Send it by the date shown. CLG checks it before the family sees it, and may send it back with changes to make.

### Find materials
1. In the side menu, choose **CLG materials**.
2. **For your students' goals** shows materials tagged with skills your students are working on.
3. Use **Find a material** to search by subject or year level. You see materials for the subjects and year levels you teach.

## Training, handbook and pay

### Do your training
1. In the side menu, choose **Training**. **To do now** lists your compulsory and due modules.
2. Open a module, read each lesson, then do the quiz. You need 100%, and you can try as often as you like.
3. When you finish, download your certificate from the module. Compulsory safety modules must be done before new students are matched with you.

### Use the handbook
In the side menu, choose **Handbooks**. Search for a word (for example late, concern, sick or privacy). **Something has happened** is pinned at the top in red.

### Check your pay and log extra hours
1. In the side menu, choose **My pay**. **Your rates** shows your pay rates.
2. Under **Log hours**, add work outside sessions (for example making worksheets), with the day, hours and what you did. Log each pay week's hours by the day after the pay week ends.
3. Changed your mind? Choose **Take back** before it is approved.
4. **Last 8 weeks** shows your sessions and hours. If a time looks wrong, record the right finish time on the session, or contact CLG.

## Help and safety

### If you are worried about a child
1. If a child is in danger now, call 000.
2. Choose **Child safety** (in red, top of every page). Report to the child protection line for the child's state, then tell CLG with the form.
3. Concerns are confidential. If your concern is about someone at CLG, they never see it.

### Ask CLG a question (Help chat)
1. Choose **Help chat** at the top of any page (on a phone, tap **Menu** first), then **Ask CLG a question**.
2. Choose what it is about (for example **My pay (CLG staff)** or **Sessions and bookings**). If it is about one of your students, choose them under **Who is it about?**.
3. Give it a short title, write your message and choose **Send to CLG**. CLG replies in the chat, and you get an email saying there is a reply.
4. CLG may also start a chat with you. A number next to **Help chat** shows chats with a new reply.

Tip: Families talk to CLG in their own chats, which tutors do not see, so you do not need to chase families for missing details.

### Give feedback or report an app issue
- **Feedback**: praise, ideas or worries about the app, CLG's service or people at CLG.
- **Report app issue**: something in the app is not working. Add a screenshot if you can.

### Your privacy and name
Choose **Your privacy** to download your information or ask CLG about it. Under **Quoting what you write**, you can let CLG quote what you write in its advertising without your name (off unless you turn it on). Tap your name under **Signed in as** to change it (on a phone, tap **Menu** at the top right first).
`, // End of the guide's text.
}; // End of the tutor guide.
