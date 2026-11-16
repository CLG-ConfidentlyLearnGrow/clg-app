// Summary: the app guide for parents and carers: what they can do in the
// CLG app and how, step by step. The text below is the guide itself, in
// the simple layout read by parseGuide in ./index.ts ("##" a part, "###" a
// task, "1." a step, "-" a bullet point, "Tip:" a tip). Words in **stars**
// are shown in bold: they are the exact names of buttons and menu items,
// so people can find them on screen. Update this text whenever a feature
// for parents changes.
//
import type { GuideSource } from "./index"; // The shape of a guide's words (for type checking only).

// The parent guide's words. (Text inside the backticks is the guide itself,
// not code, so its lines don't carry code comments.)
export const PARENT_GUIDE: GuideSource = { // The guide:
  title: "App guide for parents and carers", // its title,
  who: "For parents and carers with a CLG account.", // who it's for,
  text: `
## Getting around

The app has a few parts that are always there:

- **Home** (top of every page) takes you back to your dashboard.
- A page you open from your dashboard, such as a child's progress page, has a **Back** button at the top that takes you back.
- The side menu on your dashboard has **Your children**, **Sessions**, **Weekly calendar**, **Add a child**, **Billing** (only if you pay) and **App guide**. A number next to a menu item means something is waiting for you there.
- **Child safety** (in red, top of every page) is where to go if you are ever worried about a child.
- **Help chat**, **Feedback**, **Your privacy** and **Report app issue** are at the top of every page too. On a phone, tap **Menu** (top right) to see them, your name and **Sign out**.
- If you have more than one role (for example you are a parent and also learn with CLG yourself), tabs at the top let you switch between your dashboards.

### Sign in
1. Go to app.clgtutoring.com and choose **Sign in**.
2. Enter your email and password.
3. Forgot your password? Choose **Forgot your password?** and follow the email from CLG.

Tip: If CLG set up your account for you, open the link in your welcome email to choose your password. The link works once. If it has run out, ask CLG to send a new one.

### Create an account yourself
1. Choose **Create an account** on the sign-in page.
2. Under **I am signing up as**, choose parent.
3. Enter your name, email and a password (at least 12 characters, with upper and lowercase letters and a number).
4. Tick that you agree to the privacy policy and terms, then choose **Create account**.
5. Check your email and open the link to confirm your account.

### Agree to the family terms
The first time you sign in, the app shows **Welcome to CLG**. Read the summary of the privacy policy and terms, then agree to carry on. You can read them again at any time from **Privacy** at the bottom of each page.

### Put CLG on your phone's home screen
1. Choose **Add CLG to your home screen** at the bottom of any page.
2. Follow the steps for your phone or computer (iPhone uses Safari's **Share** button, Android uses Chrome's three dots).

### Change your name
Your name is shown at the top right under **Signed in as** (on a phone, tap **Menu** at the top right to see it). Tap it to change your first or last name.

### See what has changed in the app
After an app update, a **What is new** box shows the changes for your dashboard once. To see them again, choose **What is new** at the bottom of any page.

### Take the app tour again
The first time you open your dashboard, a short **app tour** shows the main parts of the app and why each one matters. To take it again, open **App guide** in the side menu and choose **Take the tour again** at the top. If you stopped part-way, the button says **Carry on the tour** and starts where you left off.

## Your children

### Add a child
1. In the side menu, choose **Add a child**.
2. Enter your child's full name, date of birth, the state they live in, their year level this year and their school (or "Home schooled").
3. Choose the subjects they would like help with, and the level they work at if you know it.
4. Add what you would like CLG's support to achieve, and anything else that helps (please leave out medical details; CLG will ask privately if needed).
5. If your child has learning needs, you can add them and give consent for CLG to use them to plan support.
6. Choose **Add child**.

Tip: If another parent or guardian has already added this child, say so on the form. CLG links you to the same profile instead of making a second one.

### What happens after you add a child
1. CLG checks your child's details. The child shows "CLG is checking the details" until this is done.
2. CLG matches your child with a tutor who suits their year level, subject and location.
3. CLG sends you a session time to approve (see **Sessions** below).
4. Once matched, you see your child's tutor on **Your children**, and a **Progress** link.

### Finish details CLG started for you
If CLG set up your child's profile during a phone call, **Your children** shows a card saying **Please finish (name)'s details**. Fill in what it asks for and save. CLG needs these details to choose the right tutor.

### See or change your child's details
1. In the side menu, choose **Your children**.
2. Under your child's name, choose **See or change details**.
3. Make your changes and save.

### Give your child their own login (16 and over)
A child aged 16 or over can have their own login. They keep their details, history and tutor, and you can still see everything. Each child with their own login sees only their own profile, never a brother's or sister's.
1. In **Your children**, choose **Give (name) their own login** under their name.
2. Enter your child's own email address.
3. Choose **Send login link**. Your child gets an email to choose their password.

## Sessions

Sessions are booked by CLG for now. CLG finds a time with a tutor who suits, and you approve it in the app. Open **Sessions** in the side menu. Along the top (or in the side menu on a phone) are its sections: **Overview**, **Bookings**, **Preferred times**, **How long to book**, **Away dates**, **Requests**, **Blocks**, **Notices** and **Book again**. All times are Adelaide time.

### Tell CLG which days and times suit
1. In **Sessions**, choose **Preferred times**.
2. For each child, tick the days and parts of the day that suit (morning, middle of the day, afternoon, evening).
3. Add any tutor preferences, for example experience with dyslexia or exam preparation.
4. Choose **Save preferences**.
5. Under **How far you will travel**, enter your street address (or another place you travel from) and the most km you will travel to a library, in a straight line. Choose **Save travel distance**. Only your family and CLG admins can see the address; tutors do not.
6. Under the study period, choose your child's school terms (SA government or SA private), or add your own study dates for university or TAFE.
7. Add your child's last day of school in Term 4 (this changes by school and year level), then save.

Tip: These are preferences, not guarantees. CLG offers libraries within your travel distance and within the tutor's.

### Say how long to book sessions for
1. In **Sessions**, choose **How long to book**.
2. Choose the last date for sessions (up to a year ahead), or pick the end of a term.
3. Say whether you want sessions in the school holidays and on public holidays.
4. Save. You can change this later.

### Approve a session time CLG offers
When CLG offers a time, you see a notice and a number on **Sessions**.
1. In **Sessions**, choose **Bookings** (or **See offers** on the Overview).
2. Check the day, time, tutor and place.
3. Choose **Approve**, or **This time does not suit** and say why.
4. The booking is confirmed once you and the tutor have both said yes. You have 3 days to answer, with a reminder after 2. If it is not approved by everyone in time, the offer closes for now and CLG gets in touch about another time.

Tip: One parent (or a child 16+ with their own login) can answer for the family. The first answer counts.

### See upcoming sessions and join online
1. In **Sessions**, choose **Overview**.
2. **Upcoming sessions** lists each session with the tutor, subject and place.
3. For an online session, choose **Join** a few minutes before it starts. It opens Microsoft Teams. You do not need a Microsoft account.

### See your week, and add sessions to your own calendar
1. In the side menu, choose **Weekly calendar** to see one week at a time. Use **Last week**, **This week** and **Next week** to move around.
2. To see sessions in Google, Outlook or Apple calendar, choose **Make my calendar link** under **Add to your own calendar**, then follow the steps shown.
3. The link is private. If you share it by mistake, choose **Make a new link** and the old one stops working.

Tip: Calendar apps can take a few hours to update, and online session links stay in the app. Check the app for last-minute changes.

### Cancel one session
1. In **Sessions**, choose **Overview** and find the session.
2. Choose **Cancel**.
3. Choose a reason (please do not include health details).
4. Offer two other times that week for a make-up session. Your tutor picks one. If no other time works, tick that box and CLG will help.
5. Choose **Cancel this session**.

Credit for a session you cancel with no make-up: more than 24 hr before gets full credit, 24 to 2 hr before gets half credit, and under 2 hr (or a missed session) gets none. If a make-up is booked, there is nothing extra to pay with 2 hr notice or more, or half the cancelled session with less. Notice counts from when you save the cancel in the app. If CLG or the tutor cancels, you get full credit.

Tip: If your child is suddenly unwell or there is a family emergency, contact CLG (not your tutor). CLG can waive the late-cancel rule once a year for each child; after that, CLG needs to see proof.

### Pick or confirm a make-up time
If your tutor or CLG cancels a session, a **Pick a make-up time** card shows on the **Overview**.
1. Choose one of the two times to book it, or choose **Neither works** and say why.
2. If CLG offered the times and the tutor picked one, you see **Confirm a make-up time** instead. Confirm it, or say it does not work.

### Confirm a change of tutor or time
Sometimes CLG needs to move sessions to a new tutor or a new day and time. A **Please confirm a change** card shows on the **Overview**.
1. Read what will change and from when.
2. Choose **Confirm**, or **Decline** and say why it does not suit.
3. Nothing changes until you and the new tutor have both confirmed.

### Stop a booking
1. In **Sessions**, choose **Bookings**.
2. Find the booking and choose **Stop booking**.
3. Add a reason if you like, then choose **Stop booking and cancel future sessions**.

### Add away dates
1. In **Sessions**, choose **Away dates**.
2. Choose who will be away, then the first and last day away.
3. Add a reason if you like (for example family holiday or school camp).
4. Choose **Save away dates**. Sessions on those days are cancelled, and new bookings skip them.

Tip: Adding away dates early gets you full credit for those sessions.

### Ask for an extra or one-off session
1. In **Sessions**, choose **Requests**, then **Ask for a session**.
2. Choose your child, the subject and what you would like: an extra session before a test or exam, a one-off in a public holiday week, or another time or tutor while your tutor is away.
3. Add the date and any times that suit.
4. Choose **Send request**. CLG or your tutor offers a time for you to approve.

### Skip public holidays
1. In **Sessions**, choose **Requests**.
2. **Public holiday weeks** lists sessions that fall on a public holiday.
3. Choose **Skip public holidays** for that booking, then ask for a one-off at another time that week if you like.

### Book again before your book-till date
About 3 weeks before your child's book-till date (the date you chose in **How long to book**), CLG asks whether you would like to keep going. You get a notice called **Book again?**.
1. In **Sessions**, choose **Book again**.
2. Say whether you want the same day, time and tutor again.
3. Choose a new book-till date. You can pick the end of a term from the list.
4. Say again whether you want sessions during school holidays and on public holidays.
5. If you want a change, say what (day and time, tutor, or both) and why.
6. Choose **Send answer**. If you chose the same again, the tutor is asked to confirm the new dates.

### Answer a check-in about a new tutor
After your child starts with a new tutor, a card asks how it is going 1 week, 2 weeks and 6 weeks after the first session. It appears at the top of your dashboard.
1. Choose how the sessions are going (1 to 5) and whether you would like your child to keep working with the tutor.
2. Add anything else you would like CLG to know, and tick **Please contact me about this** if you would like a call or message.
3. Choose **Send**, or **Skip this check-in** if you would rather not answer.

When your child finishes with a tutor (for example after a change of tutor), a card asks how the sessions went and how well the ending was handled. Answer it the same way.

Tip: Only CLG's office team sees your answers. The tutor does not.

### If a tutor is not the right fit
1. In **Sessions**, choose **Blocks**, then **Block a tutor**.
2. Choose the tutor and write why. Only CLG sees the reason, and the tutor is not told.
3. Choose **Block this tutor**. The app stops suggesting that tutor for your child, and CLG will contact you to talk it through.

### Read notices and choose when reminders come
1. In **Sessions**, choose **Notices** to read news about bookings and reminders before each session.
2. Open **Reminder settings** to choose when your first reminder comes (48 hr before by default). A final reminder always comes 1 hr before.

Tip: Nothing is sent between 9pm and 5am your local time. Notices also come by email.

## Progress and learning

### See your child's progress
1. In **Your children**, choose **Progress** next to your child.
2. **Next step** shows what your tutor suggests next, with a tip to try at home.
3. **Roadmap** shows this week's steps and what is coming up.
4. **Goals and skills** shows what your child is working on and how far they have come.
5. **Recent sessions** shows the notes from each session.

### Tell the tutor how it went
1. On the progress page, use **How did it go?** after a session to share how your child felt about it.
2. Use **Tell the tutor** to share feedback, or how practice is going at home. The tutor and CLG see it.

### Share school reports and marked work
1. On the progress page, find **Work and reports**.
2. Choose the file or photo, say what it is, and add any grade or comment.
3. Choose **Upload**. The tutor sees it and can use it to plan.

### Add steps to the roadmap
1. On the progress page, find **Roadmap**.
2. Choose **Add a step**, or add a school assessment or goal with its date.
3. If your child has study plans with CLG, choose **Plan study steps for me** next to an upcoming assessment, and the app breaks it into small weekly steps.

### Term reviews
Before a term ends, you may be offered a written review of the term from your tutor. It is a paid extra, and the price is shown.
1. On the progress page, find **Term review for (term)?**
2. Under **Would you like a review?**, choose **Yes, please** (it goes on an invoice) or **No, thanks**, then **Save answer**. You can change your mind until the term ends.
3. Once your tutor has written it and CLG has checked it, the review shows on the progress page. You can reply to it there.

## Billing and payments

Only the person or people paying see billing. If you pay, open **Billing** in the side menu. If another parent or carer pays, you will not see Billing, but you will still see **Sessions on hold** on your dashboard if an invoice is overdue.

Tip: Until your family has a bill payer, any parent can set it up. The first parent to choose how often to pay (or agree to the payment terms) becomes the bill payer. To change who pays, or to share invoices between two people, contact CLG.

### Choose how often to pay
1. In **Billing**, find **How often would you like to pay?**
2. Choose weekly, monthly, per term or upfront.
3. Save. You can change it until CLG sends your first invoice.

### Agree to the payment terms
Before your first invoice, read the **Payment terms** card and agree. Sessions are paid in advance, and if an invoice is overdue, all your family's sessions go on hold until it is paid.

### Set up automatic payment
1. In **Billing**, choose **Set up automatic payment**.
2. Enter your card or bank details on Stripe's secure page. CLG never sees or stores them.
3. To change them later, choose **Change card or bank account**.

Tip: Weekly plans pay by card. Bank debit gets a small discount on monthly plans, because it costs CLG less.

### Pay an invoice now
1. In **Billing**, find the invoice under **Invoices**.
2. Choose **Pay (amount) now**. If your family shares invoices, it shows your share.

### Credit and sessions on hold
- Your credit is shown on your Billing card. Credit comes off your next invoice.
- If you see **Sessions on hold**, an invoice is overdue. Once the person who pays has paid it, sessions start again straight away. Your tutor is told sessions are on hold, but not why.

## Help, privacy and safety

### If you are worried about a child
1. If a child is in danger right now, call 000.
2. Choose **Child safety** (in red, top of every page) and follow the steps: report to the child protection line, then tell CLG using the form.
3. Your concern is kept confidential. **Concerns you have raised** on that page shows only you what you sent.

### Ask CLG a question (Help chat)
1. Choose **Help chat** at the top of any page (on a phone, tap **Menu** at the top right first).
2. Choose **Ask CLG a question**.
3. Choose what it is about and, if it is about one of your children, choose them under **Who is it about?**.
4. Give it a short title, write your message and choose **Send to CLG**.
5. CLG replies in the chat. You get an email when there is a reply (the email does not include the message, so sign in to read it). A number next to **Help chat** shows chats with a new reply.
6. When your question is answered, choose **Close this chat**. Write in it again any time to reopen it.

Tip: If CLG asks you for a missing detail (such as your child's school or year level), the notice has a link to ask CLG about it. It opens the help chat with your child and the detail already filled in.

Tip: Only you and CLG's admins can read your chats. Other parents, your child's tutor and your other children cannot see them. Do not use the help chat for child safety worries: use **Child safety** instead.

### Give feedback
1. Choose **Feedback** at the top of any page.
2. Choose what it is about (the app, CLG's service, or people at CLG), and whether it is praise, an idea or a worry.
3. Write your feedback and choose **Send feedback**. You can see your past feedback on the same page.

### Report something not working in the app
1. Choose **Report app issue** at the top of any page (on a phone, tap **Menu** at the top right first).
2. Say what went wrong and what you were trying to do. Add screenshots if you can.
3. Send it. **Your reports** shows where each report is up to.

### Your privacy
1. Choose **Your privacy** at the top of any page.
2. Choose **Download your information** for a copy of what CLG holds about you and your children.
3. Use **Ask CLG about your information** to see, fix or delete information, withdraw consent, or make a complaint. CLG replies within 28 days.
4. Under **Emails from CLG**, choose whether you get CLG news and offers (off unless you turn it on).
5. Under **Quoting what you write**, choose whether CLG may use short quotes from what you write in its advertising, without your name or anything that could identify you or your child (off unless you turn it on).

### Learn with CLG yourself
At the bottom of your dashboard, choose **Add a student profile**. You keep the same login and get a Student tab. You need to be 16 or over.
`, // End of the guide's text.
}; // End of the parent guide.
