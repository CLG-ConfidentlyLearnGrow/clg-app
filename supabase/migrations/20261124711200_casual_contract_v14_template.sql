-- Summary: puts the casual tutor contract wording (v1.4, 22 Nov 2026) into
-- the CLG App as a draft template (Carla, 22 Nov 2026).
--
-- Carla asked for the contract Word copy to go into the app's contract
-- template. v1.2 was asked for first; v1.3 and v1.4 followed the same day
-- (quiet hours at 5am, How We Do Things as a policy), so the newest, v1.4,
-- is loaded. Source: /mnt/project-files/tutor-contracts/CLG Casual Tutor
-- Employment Contract v1.4.docx, turned into the simple Markdown the app
-- shows (headings, lists, tables, bold, links). The logo box at the top is
-- left out, and "(draft)" is taken off the version line.
--
-- It is saved as a DRAFT of the "Tutor, casual" contract, so nothing changes
-- for anyone until the owner checks it and publishes it under Contracts >
-- Templates. If the casual tutor draft is still the app's starter wording,
-- the v1.4 wording replaces it. If there is no draft, a new one is added. If
-- the owner has already edited a draft, it is left exactly as it is and a
-- notice says so, so running this again never overwrites edits.
--
-- The gaps in square brackets are filled when a contract is sent: the app
-- fills [Tutor name], [Tutor email] and the CLG signatory; an admin types
-- the start date, award levels and rates.
--
-- The contract's lines below are wording, not code, so they carry no
-- comments.
--
-- Safe to run more than once. Run after 20261124710800_policy_versions_read_again.sql.

do $do$ -- a one-off block
declare -- working values
  v_body text := $ct$
| **Version** | **Published**            | **Team**     | **Responsible for this version** |
|-------------|--------------------------|--------------|----------------------------------|
| 1.4         | 22 November 2026      | The CLG Team | Carla Gore                       |

# Details for this contract

The CLG App fills in these details from your records. A CLG admin types in anything the app cannot fill before the contract is sent to you. Check these details as soon as you receive this contract. If anything is wrong, tell CLG through the CLG App. Errors must be fixed before the contract can be confirmed.

| **Detail**                                                                   | **Entry**                                             |
|------------------------------------------------------------------------------|-------------------------------------------------------|
| Tutor name                                                                   | **\[Tutor name\]**                                    |
| Email you use for the CLG App                                                | **\[Tutor email\]**                                   |
| Start date                                                                   | **\[Start date\]**                                    |
| School tutoring classification                                               | **\[Miscellaneous Award level\]**                     |
| Tertiary tutoring classification                                             | **\[Post-Secondary Award level, or Not applicable\]** |
| Non-tutoring admin work classification (only if CLG has accepted you for it) | **\[Clerks Award level, or Not applicable\]**         |
| Your rates                                                                   | Schedule B                                            |

# The short version

- You are a casual employee of CLG, paid weekly through Xero Payroll for the work you do.

- You must hold a current Working With Children Check and child safety training for the state of each learner you teach, and tell CLG straight away if anything changes.

- You follow CLG's [Child Safe Policy](https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC) and [Staff Code of Conduct](https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz) at all times.

- Give notice of changes in the CLG App: at least 2 weeks for a change to your availability, and at least 4 weeks if you plan to leave (at the end of a school term where possible).

- CLG's materials and learner records stay with CLG. Do not copy or take them.

- After you sign, you read and acknowledge the Fair Work Information Statement and the Casual Employment Information Statement (see Acknowledgements, after the signatures).

# 1 Your employment

**1.1** This contract is between CLG Tutoring, ABN 61 247 841 912 (**CLG**), and **\[Tutor name\]** (**you**).

**1.2 Position:** Tutor. **Start date:** **\[Start date\]**. **Location:** online, at CLG-approved learners' homes, or at CLG-approved venues. For in-person sessions, you choose how far you will travel, measured in kilometres in a straight line from your home or from another address you set in the CLG App. You can set a different distance and address for each block of availability. **Work week:** Monday to Sunday.

**1.3 Employment type:** casual. There is no firm advance commitment to ongoing work. You accept or decline the sessions CLG offers. After 12 months you may be able to ask to become permanent, as set out in the [Casual Employment Information Statement](https://www.fairwork.gov.au/employment-conditions/information-statements/casual-employment-information-statement). Once you have regular weekly work, CLG may offer you part-time or full-time employment. That happens only if you agree, under the separate [CLG Part-time and Full-time Tutor Employment Contract](https://claude.ai/artifact/7MseYeYMbHspsBwZifYE6A).

**1.4 Awards and classifications:**

- School tutoring is covered by the [Miscellaneous Award 2020 (MA000104)](https://awards.fairwork.gov.au/MA000104.html), with tutors classified at Level 1 to Level 4.

- Tertiary and other post-school tutoring is covered by the [Educational Services (Post-Secondary Education) Award 2020 (MA000075)](https://awards.fairwork.gov.au/MA000075.html), with tutors classified as a Teacher and Tutor/Instructor, Level 1 to Level 4.

- Non-tutoring admin work that CLG has accepted you for is covered by the [Clerks (Private Sector) Award 2020 (MA000002)](https://awards.fairwork.gov.au/MA000002.html).

> Your classifications are listed in Details for this contract. A classification sets the lowest rate the law allows for your work. Where an award or the National Employment Standards give you more than this contract, they apply instead.

**1.5 Introductory period:** your first 3 months or your first 30 sessions, whichever comes first. During this period CLG observes at least one session and gives you feedback.

**1.6** You report to Carla Gore (Director and Child Safety Officer). Day-to-day bookings may come from another CLG admin.

**1.7 Regular check-ins.** CLG meets with you at the end of your introductory period (1.5) and then at least every 6 months, and you can ask for a check-in at any time. A check-in is for you: how your sessions are going, what support or training would help, your goals, and your pay. CLG also uses it to give you feedback on your work.

**1.8 CLG visits to sessions.** A CLG representative may join any session, in-person or online, to support you, check the quality of sessions and keep learners safe. CLG will usually tell the family (the parent or guardian, and the learner) beforehand. CLG may not tell you beforehand, so that it sees sessions as they normally run. CLG gives you feedback on your sessions semi-regularly. If you would like clarification, or anything else, just ask.

# 2 Pay

**2.1** You are paid for each lesson at your own hourly rate for its type. A CLG admin enters your rates in the CLG App, and they are listed in Schedule B.

| **Type of work**                                              | **Award and classification**                                                                                  | **Your rate**                                                                                 |
|---------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| School tutoring                                               | Miscellaneous Award 2020, Level 1 to Level 4.                                                                 | Your school rate in Schedule B, never below the award casual rate for your level.             |
| Tertiary and other post-school tutoring                       | Educational Services (Post-Secondary Education) Award 2020, Teacher and Tutor/Instructor, Level 1 to Level 4. | Your tertiary rate in Schedule B, never below the award casual hourly rate for your level.    |
| Non-tutoring admin work (only if CLG has accepted you for it) | Clerks (Private Sector) Award 2020.                                                                           | Your non-tutoring admin rate in Schedule B, never below the award casual rate for your level. |

> Lessons are paid in half-hour steps. Your rates already include the 25% casual loading. Where an award sets a higher rate for the time you work, such as weekday evenings after 7pm, mornings before 7am, weekends or public holidays, CLG pays that higher rate.

**2.2** For each lesson you are also paid 15 minutes at the same rate: 5 minutes to write the session summary in the CLG App and 10 minutes to prepare. Your total pay for all time worked must never fall below the minimum the law sets. CLG checks this each pay run and tops up your pay if needed.

**2.3 Minimum pay each time you attend.** The awards say a casual must be paid for at least 2 hours each time they attend work. Lessons back to back count as one attendance. CLG groups your lessons into blocks of 2 hours or more where it can, and may fill the rest of a block with paid training, preparation, tutor admin (such as session summaries) or non-tutoring admin work. Gaps between lessons are treated this way:

- A gap of less than 30 minutes is paid work time.

- A gap of 30 to 60 minutes can be your unpaid meal break, once in each attendance, if you are free to use the time as you wish. You must have an unpaid meal break of at least 30 minutes before you work more than 5 hours in a row.

- A gap of more than 60 minutes ends the attendance. Your next lesson starts a new attendance, which is paid for at least 2 hours.

**2.4 Late cancellations and no-shows.** You are paid 50% of a lesson (up to 1 hour) only if a family or CLG cancels it with less than 2 hours' notice, or the learner does not attend. Notice counts from when the cancellation is saved in the CLG App, which is when you are notified, not when you read it. A cancellation saved during quiet hours (3.6) counts from 5am. A lesson cancelled with 2 hours' notice or more is not paid. If a make-up lesson is booked, it is paid in full as its own attendance (see 2.3).

**2.5 When a learner does not arrive.** If the family or CLG has told you the learner is running late, wait, and run the session until its normal finish time (the client loses the time they missed). Otherwise, for your paid time, keep working on the training, preparation or other work CLG has set for you in the CLG App (or on set non-tutoring admin work, if CLG has accepted you for it), and record what you did (2.6). If a learner has not arrived 15 minutes after the start, and neither the family nor CLG has told you the learner is running late, record a no-show in the CLG App.

**2.6 Recording work outside lessons.** For any paid time outside a lesson, such as training, extra preparation, non-tutoring admin work, or work during a no-show, record in the CLG App what you did and how long it took. Your notes must be clear enough for CLG to check that the work was done. CLG reviews these records and may ask you about them. Extra preparation and non-tutoring admin work must be approved in the CLG App before you do it. Not doing the work set for paid time is a performance matter (3.7).

**2.7 Extra non-tutoring admin work** that CLG asks for in advance (for example meetings, training or reports) is paid hourly at your non-tutoring admin rate in Schedule B.

**2.8 More than one type of work.** Each type of work is paid at its own rate in Schedule B, for the time you spend on it. For example, an hour of school tutoring is paid at your school rate and an hour of non-tutoring admin work at your non-tutoring admin rate, even on the same day.

**2.9 How pay works.** You confirm each lesson in the CLG App after it ends. CLG pays the confirmed lessons and approved work weekly through Xero Payroll, with a payslip available within 1 working day of payment.

**2.10 Superannuation** is paid on top of your pay into your chosen fund at the legal rate, on each payday (Payday Super, from 1 July 2026). Your fund can take several business days to receive and show it. The law allows up to 7 business days after payday, or up to 20 business days for the first payment to a new fund.

**2.11 Travel.** Travel time and costs to, from and between home sessions are not paid. Because of this, each home session counts as its own attendance (2.3), so CLG books home sessions for at least 2 hours.

**2.12 Accepting pay.** If you accept pay under this contract and keep working without telling CLG in writing that you disagree with its terms, this also shows that you accept this contract and the acknowledgements below, in addition to your signature.

# 3 Hours, availability and notice of changes

**3.1** You keep your availability and the most hours you want each week up to date in the CLG App. Give your availability in blocks of at least 2 hours, because each attendance is paid for at least 2 hours. CLG offers sessions inside your availability. You may accept or decline an offer, but once you accept a regular session CLG relies on you to keep it.

**3.2 Adequate notice.** Learners do best with a steady tutor and routine, so please give:

| **Change**                                                | **Notice to CLG**                                             |
|-----------------------------------------------------------|---------------------------------------------------------------|
| Ending your work with CLG.                                | At least 4 weeks, at the end of a school term where possible. |
| Dropping a regular learner or changing your availability. | At least 2 weeks.                                             |
| A one-off change for a planned event.                     | At least 1 week.                                              |
| Illness or emergency.                                     | As soon as you know, and at least 2 hours before the session. |

> Give every notice in the CLG App. For time away, add your dates once under **Sessions \> Away dates**. This covers every session in those dates, so you do not need to give notice for each session. For illness or an emergency on the day, also phone or message CLG straight away, because away dates take 2 hours to apply. To end your employment, send CLG your notice in writing through the CLG App or by email to a @clgtutoring.com address.

**3.3** Tell CLG, not the family. CLG tells the family and arranges a replacement, so the family hears one clear message.

**3.4** CLG will give you as much notice as it can of any change to your sessions. A change to one of your sessions, such as a new day, time, place or learner, is only official once you agree to it in the CLG App. A family or CLG cancelling a session is not a change that needs your agreement (see 2.4). Once a change has been requested, the original session does not count as a no-show for you or the family if the change is not approved in time. CLG follows up and rebooks it.

**3.5 Being on time.** Arrive, or log in, ready to start at the session time. If you will be late, tell CLG and the family in the CLG App as soon as you know. You are paid only for the time you work. If you start late, make up the missed time where you can by running the session for its full length. To make room, you may do the 15 minutes of summary and preparation (2.2) later. Time you do not make up is not paid. CLG records lateness. Being late without a good reason is a performance matter (3.7).

**3.6 Contact outside working hours.** You do not have to read or answer work messages outside your working hours unless it is reasonable for CLG to contact you (the right to disconnect). Reasonable reasons include a change or cancellation of a session within the next 24 hours, a child safety matter, a check that is about to expire, or a question about a learner you teach that only you can answer. Only a child safety matter needs an answer straight away. Anything else can wait until your next working time, unless it affects your next session. Quiet hours are 9pm to 5am (the family's local time). The CLG App holds messages to families sent during quiet hours until 5am, and anything sent or done in the CLG App during quiet hours counts as sent or done at 5am. Check the CLG App for changes before each session.

**3.7 If there is a concern about your work.** If CLG is concerned about your work, for example lateness, missed sessions, set work not done, or poor session notes, CLG will first talk with you and agree how to fix it. If the concern happens again, CLG will give you a written warning that says what must change and by when. If it happens again after a written warning, CLG may end your employment (section 7). Serious misconduct is dealt with under 7.3.

# 4 Screening checks

**4.1** This job is conditional on you holding, and keeping current, all of these:

| **Check**                   | **Rule**                                                                   |
|-----------------------------|----------------------------------------------------------------------------|
| Working With Children Check | Current for the state of every learner you teach.                          |
| Child safety training       | RRHAN-EC Fundamentals, plus Masterclass when due, for Australian learners. |
| First aid certificate       | Upload with its expiry date if you hold one **(optional, not required)**.  |
| Right to work in Australia  | Before your first session.                                                 |

> A National Police Check is not required, because the Working With Children Check already includes a criminal history check.

**4.2** You must upload a copy of each certificate to the CLG App, with its number and expiry date, and upload the new copy each time you renew. CLG verifies each one. Copies are stored privately: only you and CLG admins can open them. CLG keeps them, and its screening records, for 7 years after your employment ends, then deletes them, as set out in the [Privacy Policy](https://claude.ai/artifact/WJfZfxVdnXjNj7hHAdWquS).

**4.3 Tell CLG within 24 hours** if you are charged with or convicted of an offence, if any check is suspended, refused, cancelled or under review, or if you become subject to an order involving children.

**4.4 No current check, no sessions.** If a check lapses, you cannot run sessions until it is renewed. You are not paid for sessions you cannot run for this reason. CLG may end your employment if a check is refused or cancelled.

**4.5** You may only be matched with learners in states where you hold the right checks. The checks follow the learner's state, not yours: for example, a tutor living in Victoria who teaches a South Australian learner online needs the South Australian checks. CLG may ask you to get the checks for another state. The more states you hold checks for, the more learners you can be matched with.

# 5 Child safety and conduct

**5.1** You must follow CLG's [Child Safe Policy](https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC) and [Staff Code of Conduct](https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz). They form part of this contract. Once they are published in the CLG App, the version in the app applies. A serious breach may lead to dismissal.

**5.2 Home sessions.** A parent or guardian aged 18 or over must be in the home from the start of the session until the whole session is complete. If no adult is home when you arrive, do not start the session. If the adult leaves before the session is complete, stop the session. In either case, leave safely and tell CLG straight away. Work in a shared space of the home, never a bedroom with the door closed.

**5.3 Contact.** Only contact learners and families through CLG's channels (the CLG App and CLG's Teams). Never use personal phones, personal email or social media with learners. Never meet a learner outside a booked session, or drive them anywhere.

**5.4 Recording.** Never record a session, or take photos of a learner, unless CLG has written consent from the parent or guardian first.

**5.5 Gifts.** You may accept a small gift worth up to \$100, and must record it in the CLG App. Never accept cash, or gifts worth more than \$100. Never give gifts to a learner.

**5.6 Reporting concerns.** If you are worried about a child's safety, you must report it, whatever your state's mandatory reporting law says. If a child is in immediate danger, call 000. Then report to the child protection line for the child's state as soon as you reasonably can (in South Australia, the Child Abuse Report Line on 13 14 78), and tell the Child Safety Officer, Carla Gore. Telling CLG does not replace your own duty to report. In South Australia, tutors are mandated notifiers under the Children and Young People (Safety) Act 2017, so failing to report a reasonable suspicion of harm can be an offence. Concerns about Carla go to Emma, the deputy Child Safety Officer.

**5.7 Safety at work.** CLG will take reasonable steps to keep you safe, as required by the Work Health and Safety Act 2012 (SA). If you feel unsafe at a session, leave and tell CLG. You will be paid for that session.

**5.8 Checking writing for child safety.** To keep children safe, the CLG App checks what is written in it, including your session summaries and notes, for words that may point to a risk to a child. A match is seen only by CLG's Child Safety Officer or deputy, who decide whether any action is needed. Nothing happens automatically. This clause is your written notice of this check, wherever you work.

# 6 Confidentiality, privacy and CLG materials

**6.1 Confidential information** includes learner and family details, session notes, progress records, prices, and CLG's methods and plans. Use it only to do your job. Do not share it with anyone outside CLG, during or after your employment.

**6.2 Privacy.** Handle personal information as set out in CLG's [Privacy Policy](https://claude.ai/artifact/WJfZfxVdnXjNj7hHAdWquS). Keep learner records in the CLG App only, not on personal devices, personal cloud storage or paper you take home. Report any lost device, wrong message or other possible data breach to CLG within 24 hours, so CLG can follow its [Data Breach Response Plan](https://claude.ai/artifact/KdNCmEibUVrk4VjR7PfrN7).

**6.3 CLG materials stay with CLG.** Lesson plans, worksheets, resources, templates and records that CLG gives you, or that you create for CLG while working for CLG, belong to CLG. You must not copy, download for personal use, share, sell or take them, during or after your employment.

**6.4** Materials you made before joining CLG stay yours. List them in Schedule A. If you use them in CLG sessions, you give CLG a free licence to keep using them, unless you mark them “Not for CLG use” in Schedule A.

**6.5 When you leave,** return or delete all CLG materials and confidential information and confirm this in writing. CLG removes your app access on your last day.

**6.6 Families.** For 12 months after you leave, you must not approach any family that you know has dealt with CLG in any way while you worked for CLG (for example as a client, or by enquiring or booking), to offer them tutoring privately or through another business. If a court finds 12 months too long, the period is 6 months, and if that is too long, 3 months.

**6.7 Work outside CLG.** While you work for CLG, you must tell CLG, through the CLG App, about any educational support or administrative role you do outside CLG, paid or unpaid. This includes tutoring privately or through another business. Tell CLG before you start the role, and again if it changes or ends.

# 7 Leave, ending employment and disputes

**7.1 Leave.** As a casual you do not get paid annual leave or paid personal leave. Your casual loading makes up for this. You are entitled to:

- unpaid carer's leave and unpaid compassionate leave;

- 10 days of paid family and domestic violence leave each year, paid at your full rate for the hours you were rostered to work during the leave;

- long service leave under the Long Service Leave Act 1987 (SA): 13 weeks after 10 years of continuous service (or a pro rata amount after 7 years), paid on the average hours you worked each week over the 3 years before the leave.

**7.2 Ending employment.** Either side can end this contract. You agree to give at least 4 weeks' notice (3.2) so learners can be handed over well. CLG will give you at least 4 weeks' notice, or pay instead, unless 7.3 applies.

**7.3** CLG may end your employment straight away for serious misconduct, a child safety breach, or if a required check is refused or cancelled.

**7.4 Policies.** You must follow all of CLG's policies while you work for CLG, as they are updated from time to time. Most policies are not terms of this contract, so CLG can update them without needing your agreement. The [Child Safe Policy](https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC) and [Staff Code of Conduct](https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz) are the exception: they are also terms of this contract (5.1). How We Do Things sets out CLG's values and ways of working, including how problems are solved and when Carla is told. You must follow it. It is a CLG policy and does not form part of this contract.

**7.5 Disputes.** Raise any concern with Carla Gore first. If it is not resolved, either side may contact the [Fair Work Ombudsman](https://www.fairwork.gov.au) or the Fair Work Commission.

**7.6 Changes** to this contract must be agreed in writing.

# Signatures

You can sign in the CLG App (typing your full name and pressing Accept), or sign in the boxes below by hand or with a digital pen. Either is your signature.

|         | **Name**             | **Signature** | **Date** |
|---------|----------------------|---------------|----------|
| For CLG | Carla Gore, Director |               |          |
| Tutor   | **\[Tutor name\]**   |               |          |

# Acknowledgements

After signing, open and read each document below, then acknowledge it in the CLG App. Each acknowledgement is signed and dated separately. By acknowledging, you confirm that CLG gave you the document as a link and that you have read it. For the Child Safe Policy, Staff Code of Conduct and How We Do Things, you also confirm that you agree to follow them. Each policy is acknowledged separately, and again each time CLG publishes a new version of it.

| **Document**                                                                                                                                                       | **I have read it (signature)** | **Date** |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------|----------|
| [Fair Work Information Statement](https://www.fairwork.gov.au/employment-conditions/information-statements/fair-work-information-statement)                 |                                |          |
| [Casual Employment Information Statement](https://www.fairwork.gov.au/employment-conditions/information-statements/casual-employment-information-statement) |                                |          |
| [Child Safe Policy](https://claude.ai/artifact/X9PAk2dXuhFKpcwsPn1cpC)                                                                                      |                                |          |
| [Staff Code of Conduct](https://claude.ai/artifact/JFWkbD2CVWMp49UCg8s7Kz)                                                                                  |                                |          |
| How We Do Things                                                                                                                                                   |                                |          |

# Schedule A: your own materials

List any materials you made before joining CLG that stay yours (6.4). They remain your property. If you use one in a CLG session, CLG may keep using it for free, unless you mark it “Not for CLG use” below. Leave the table blank if you have none.

| **Item** | **Short description (type, subject, year level)** | **Date made** | **CLG may use it (yes, or Not for CLG use)** |
|----------|---------------------------------------------------|---------------|----------------------------------------------|
| 1        |                                                   |               |                                              |
| 2        |                                                   |               |                                              |
| 3        |                                                   |               |                                              |

# Schedule B: your rates

Entered by a CLG admin in the CLG App. If a rate changes, CLG updates the app and tells you in writing before the change.

| **Type of work**                                               | **Classification**                                    | **Hourly rate**                                   | **From date**                                          |
|----------------------------------------------------------------|-------------------------------------------------------|---------------------------------------------------|--------------------------------------------------------|
| School tutoring (Miscellaneous Award)                          | **\[Miscellaneous Award level\]**                     | **\[School tutoring rate\]**                      | **\[School tutoring rate from\]**                      |
| Tertiary and other post-school tutoring (Post-Secondary Award) | **\[Post-Secondary Award level, or Not applicable\]** | **\[Tertiary tutoring rate, or Not applicable\]** | **\[Tertiary tutoring rate from, or Not applicable\]** |
| Non-tutoring admin work (Clerks Award)                         | **\[Clerks Award level, or Not applicable\]**         | **\[Admin rate, or Not applicable\]**             | **\[Admin rate from, or Not applicable\]**             |
$ct$; -- the v1.4 wording
  v_draft public.employment_contract_templates; -- the casual tutor draft, if there is one
begin -- start
  if exists (select 1 from public.employment_contract_templates where contract_type = 'tutor_casual' and body like '%| 1.4 %22 November 2026%') then -- v1.4 is already in:
    return; -- nothing to do
  end if; -- end of the check
  select * into v_draft from public.employment_contract_templates where contract_type = 'tutor_casual' and status = 'draft'; -- the draft, if any
  if v_draft.id is null then -- no draft yet:
    insert into public.employment_contract_templates (contract_type, version, title, body, status) -- adds one:
    values ('tutor_casual', coalesce((select max(version) from public.employment_contract_templates where contract_type = 'tutor_casual'), 0) + 1, -- the casual tutor contract, the next version number,
            'CLG Casual Tutor Employment Contract', btrim(v_body, E'\n'), 'draft'); -- its title and wording (without the blank first line), as a draft
  elsif strpos(v_draft.body, 'The owner pastes the final wording here before publishing') > 0 then -- the draft is still the starter wording:
    update public.employment_contract_templates set title = 'CLG Casual Tutor Employment Contract', body = btrim(v_body, E'\n'), updated_at = now() where id = v_draft.id; -- puts the v1.4 wording in it
  else -- the owner has already edited the draft:
    raise notice 'The casual tutor contract draft has your own edits, so it was left as it is. Paste the v1.4 wording into it by hand if you want it.'; -- says so, and changes nothing
  end if; -- end of the choices
end; -- finish
$do$; -- end of the block
