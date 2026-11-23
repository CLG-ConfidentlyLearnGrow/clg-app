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

Your dashboard opens on **Overview**, a quick look at everything that needs you. Your side menu has **Overview**, **Your students**, **Sessions**, **Weekly calendar**, **What you teach**, **Child safety checks**, **Hours and availability**, **CLG materials**, **Training**, **Handbooks**, **App guide** and **My Pay**. Once CLG sends you an employment contract, **My contract** appears too. A number next to an item means something is waiting for you there. A menu item with smaller items under it (for example **Sessions**) has an arrow at the end of its row. Click the arrow to open or close those smaller items from any page, without leaving the page you are on. When they are folded away, the number beside the menu item adds up all of theirs.

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
4. Under **Acknowledgements**, choose the **Open** button for each document (the Fair Work Information Statement, the Casual Employment Information Statement if you are casual, the Child Safe Policy and the Staff Code of Conduct), tick that you have read it, type your name and acknowledge it. CLG's own policies open as pages inside the app, and buttons in the contract open them too.
5. CLG then sends you an email from Xero to enter your tax, bank and superannuation details.

Tip: Your signed contract stays in **My contract**, so you can read it again at any time.

Tip: When CLG updates a policy linked to your contract, **My contract** shows a number. Open your contract, read the new version (what changed is shown) and tick it again with your name.

### See what needs you on the Overview
**Home** (top of every page) and the **Tutor** tab open your **Overview**. It shows:
- **Next 7 days** (sessions and hours), **Next session**, **Your students** and **Child safety checks**. Tap a box to open that page.
- **Needs your attention**: one line for each thing waiting for you (for example session notes or term reviews to write, a booking to accept, a check to renew, or training to do). Tap a line to go straight to it. When nothing is waiting, it says **All caught up**.
- **Coming up**: your next sessions in the coming week.
- **Plans for your coming sessions**: the focus of your plan for each coming session, or **No plan linked yet**, with a link to open it.
- **Child safety checks to sort out**: any check that is missing, expired or due to renew within 60 days, with a link to add or renew it.

### Set up and use two-step login
Tutors and admins need two-step login, because the app holds children's information.
1. Install an authenticator app on your phone (for example Microsoft Authenticator or Google Authenticator).
2. After you sign in the first time, choose **Set up two-step login**.
3. Scan the code with your authenticator app, enter the 6-digit code it shows, and choose **Turn on two-step login**.
4. Each time you sign in, enter the 6-digit code from your authenticator app.

### Put CLG on your phone's home screen
Choose **Add CLG to your home screen** at the bottom of any page and follow the steps for your phone.

### Get a refresher on the page you are on
Every page has a **Show me how** button next to its heading. Choose it to see the App guide steps for that page, without leaving it. From there you can also choose **Open the whole App guide**, or **Take the app tour again**.

### Take the app tour again
The first time you open your dashboard, a short **app tour** shows the main parts of the app and why each one matters. To take it again, choose **Show me how** next to any page heading, then **Take the app tour again**. You can also open **App guide** in the side menu and choose **Take the tour again** at the top. If you stopped part-way, the button says **Carry on the tour** and starts where you left off.

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
4. Add each time you are available: the day, from and to, and where you can teach. Casual tutors give each time as a block of at least 2 hours, because casual work is paid in blocks of at least 2 hours. A shorter time is refused, and any older time shorter than 2 hours is marked so you can replace it. This does not apply to part-time or full-time staff with agreed weekly hours. Tick **Online**, **At public libraries within my travel distance**, **At learners' homes within my travel distance**, or a mix. For in-person times, choose the address you are **Travelling from** and the **Most km I will travel** (in a straight line). Choose **Add time**.
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

### Tell the family and CLG you are running late
1. From 3 hours before a session until 30 minutes after it starts, **Running late?** shows next to it on the Overview (until you sign on).
2. Open it, choose about how late you will be, and say briefly why. Only CLG sees the reason.
3. Choose **Tell the family and CLG**. The parents (and the learner, if they have their own login) get an app notice and an email. CLG gets an app notice.
4. If you sign on more than 5 minutes after the start, the app records a late start, whether or not you sent a notice. Session pay starts from when you sign on.
5. **Your late starts (last 90 days)** on the Overview lists your own late starts. CLG reviews these.

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
3. Add times you could offer instead that week, if any. CLG uses them when it contacts the families.
4. Choose **Save away dates**. New bookings skip those days. If you made a mistake, choose **Remove** within 2 hours.
5. After 2 hours, CLG is told about your booked sessions on those days. CLG contacts each family to offer another time or tutor, or cancels the session.

### Offer a time for a family's request
1. In **Sessions**, choose **Requests**.
2. Find the request from your student's family (for example an extra session before a significant date, such as a test, exam or assignment due date).
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
In **Sessions**, choose **Notices**. Under a notice, choose **Mark as seen** once you have read it, or **Mark as done** once you have dealt with it (it moves to the **Done** list at the bottom; choose **Not done yet: put it back** if you ticked one by mistake). You get a reminder 24 hr before each session and another 1 hr before. Nothing is sent between 9pm and 5am your local time.

### Get pop-up notifications on your phone or computer
Pop-ups tell you straight away about reminders, booking news, progress note reminders and help chat replies, even when the app is closed or you have been signed out. They never show a student's name or other details, so they are safe on a locked screen.
1. On your phone or computer, choose **Turn on pop-ups** on the note at the top of your dashboard, or go to **Sessions**, choose **Notices**, and choose **Turn on pop-ups on this device** on the **Pop-up notifications** card.
2. When your browser asks, choose **Allow**.
3. Choose **Send me a test** to check it works.

Tip: On an iPhone or iPad, add CLG to your home screen first, open it from there, then turn on pop-ups. To stop them on a device, choose **Turn off on this device**.

## Students and progress

### See your students
1. In the side menu, choose **Your students**.
2. Each student shows their subject and a **Progress and notes** link.
3. You only see students you are matched with, and only what you need to teach them.

### Write the session summary and plan
After each session you send two things in one form: the session summary and your plan for the next session. You are paid 15 minutes for both: about 5 minutes for the summary and about 10 minutes for the plan. The form shows the minutes so far. Both are due within 6 hr of the session. The app reminds you at 6 hr if one is missing, and CLG follows up anything still missing at 12 hr. Families are promised the summary within 48 hr.
1. On **Your students**, **Session notes to write** lists what is due. Choose **Write summary and plan**.
2. **Part 1: Session summary**: fill in what went well, the next step, any homework or practice and its due date, and one thing to try at home. Use **Note for CLG staff only** for anything just for CLG.
3. To share a photo of the whiteboard or a worked example, choose a file under **File from this session** (a PDF or photo up to 3.5 MB) and give it a name. Photograph the work only, never the student.
4. **Part 2: Plan for the next session**: write the **Focus for the next session** and **How you will teach it**. You can add what to **Review first** and **How you will know it worked**. The plan is optional when the student was absent, or when no next session with you is booked yet.
5. Tick the **Materials for the next session** you will use from the materials library, and add any **Other resources** (textbook pages, websites, equipment).
6. Choose **Save summary and plan**. The family and student see the summary and any files (not the staff-only part). The plan is only for you, any cover tutor and CLG staff.

Tip: Build the plan's focus on the next step you just wrote. One clear focus is enough. For a session that was not booked in the app, use the link under **Session summary and plan**.

### Use your plan before the next session
1. Your **Overview** has **Plans for your coming sessions**, with each plan's focus. Choose **Open plan**.
2. On the student's progress page, **Plan for the next session** shows the focus, the steps and the materials. Choose a material to open it.
3. To add or change the plan (for 7 days after the summary), open **Change this plan** on that card, then choose **Save changes to the plan**.

### Add or remove a session file later
For 7 days after the summary, open the student's progress page. Under **Recent sessions**, choose **Add a file to this session**, pick the file and choose **Add file**. Choose **Remove** next to a file to take it away.

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
4. Before you can send a term review, finish the term review modules in **Training**. You can save your draft at any time.
5. Allow about 1 hour to write it. Once CLG approves it, 1 hour at your tutor rate is added to your pay for you. Do not log it.

### Find materials
1. In the side menu, choose **CLG materials**.
2. **For your students' goals** shows materials tagged with skills your students are working on.
3. Use **Find a material** to search by subject or year level. You see materials for the subjects and year levels you teach.

## Training, handbook and pay

### Do your training
1. In the side menu, choose **Training**. **To do now** lists your compulsory and due modules.
2. Open a module, read each lesson, then do the quiz. You need 100%, and you can try as often as you like.
   - Short of time? Choose **Done, save my place** under each lesson you finish, or **Save my answers and finish later** in the quiz. Next time, **Carry on from lesson** takes you back to where you were.
   - Compulsory modules, and modules CLG assigns to you, are paid for their set time (for example 15 minutes) once you finish, however long you take. Other modules you choose to do in your own time are only paid if CLG approved it first.
   - Some quiz questions show a screenshot of the app and ask what you would press or where you would write.
   - Some modules end with a **Practice task (checked by CLG)**, for example a session summary for a made-up student. Write it in the box and choose **Send to CLG to check**. Lauren or Carla approves it or sends it back with what to change. The module is finished once the quiz is passed and the task is approved. Never write about a real student in a practice task.
   - The safety modules (1 to 8) are done in order. If an earlier one is not finished, the module tells you which one to do first.
   - Before your first term review or drafting job, finish the modules for it. If you are given a term review before you have done them, they are added to your To do list and you are told.
   - If you teach a student whose family pays for study plans, the study plan module is added to your To do list, due before your next session with them, and you are told. It is paid for its set time.
3. When you finish, download your certificate from the module. Compulsory safety modules must be done before new students are matched with you.

### Use the handbook
In the side menu, choose **Handbooks**. Search for a word (for example late, concern, sick or privacy). **Something has happened** is pinned at the top in red.

### Check your pay and log extra hours
1. In the side menu, choose **My Pay**. **Your rates** shows your pay rates.
2. Under **Log hours**, choose **What kind of work?** (for example **Lesson preparation and planning** or **Making learning materials**), then the day and hours. Write **What you did** and **What you finished or achieved**. CLG checks both before approving. Log each pay week's hours by the day after the pay week ends.
   - For **Work during a no-show or late cancel**, also choose the session under **Which session?**. That time is already paid with the session, so it is recorded and checked, not paid again.
   - If a family or CLG cancels with under 2 hr notice, or the student does not come, you get late-cancel pay. A cancel saved in quiet hours (9pm to 5am Adelaide time) counts from 5am, so a 7am session cancelled at 11pm the night before counts as 2 hr notice.
   - The 15 minutes after each session (summary and planning), app training modules, and 1 hour for each term review CLG approves are added for you. Do not log them.
3. Changed your mind? Choose **Take back** before it is approved.
4. **Last 8 weeks** shows your sessions and hours. If you tutor school students on a weekday before 7am or after 7pm, a weekend or a public holiday, and your rate is below the award rate for that time, a **Penalty rate top-up** line pays the difference. Under the award you move from Level 1 to Level 2 after 3 months with CLG, and the app raises your school rate then if it is below the Level 2 minimum. If a time looks wrong, record the right finish time on the session, or contact CLG.

### Check your decision steps
1. In the side menu, choose **Decision steps**. **My decision steps** has one line for each kind of problem, for example a student who does not show up. It shows your step (how much you need Carla before you act), your goal, and when it last moved. Open **What each step means** for the five steps.
2. Carla moves your steps at your check-ins and you get an app notice. During probation everything is at Step 1.
3. At Step 4, open **Record a decision** under **My decisions log**. Write **The problem**, the **Options you considered** (at least three) and **The one you chose, and why**, then choose **Record decision**. Carla and Emma can read your log and add notes, which you see under **Notes on this record**.

## Help and safety

### If you are worried about a child
1. If a child is in danger now, call 000.
2. Choose **Child safety** (in red, top of every page). Report to the child protection line for the child's state, then tell CLG with the form.
3. Concerns are confidential. If your concern is about someone at CLG, they never see it.

### Ask CLG a question (Help chat)
1. Choose **Help chat** at the top of any page (on a phone, tap **Menu** first), then **Ask CLG a question**.
2. Choose what it is about (for example **My Pay (CLG staff)** or **Sessions and bookings**). If it is about one of your students, choose them under **Who is it about?**.
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
