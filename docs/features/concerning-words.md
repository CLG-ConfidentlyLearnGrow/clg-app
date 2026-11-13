# Flagging concerning words and phrases

Requested by Carla, 13 Nov 2026 ("The app also needs to flag concerning words and phrases"). Builds on the child safety concern flag (`docs/features/child-safety-concerns.md`). Draft for the lawyer's review with the Child Safe Policy and the privacy policy.

## 1. What it's for

People write a lot in the app: session summaries, staff notes, student reflections, family notes, booking and request notes, term reviews, notes on uploaded work, and learning needs. Sometimes that writing holds an early sign that a child may be at risk: a student writing "I want to die" in a reflection, a tutor writing "add me on snapchat", a parent's note that mentions a child being "scared to go home".

A busy person reading a summary for its learning content can miss these. The app now checks new writing against a list of words and phrases, and when one appears it makes a **private flag** for the Child Safety Officer (Carla) or the deputy (Lauren) to read in context.

**A flag is only a prompt for a person to look.** Nothing happens automatically: the text saves as normal, nobody is warned or blocked, and the writer is never told.

## 2. What the evidence and the rules say

- **National Principles for Child Safe Organisations** (Australian Human Rights Commission, endorsed by COAG 2019). Principle 8: "Physical and online environments promote safety and wellbeing while minimising the opportunity for children and young people to be harmed." Principle 5: people working with children are supported to recognise and respond to concerns. Principle 6: concerns are responded to in a child-focused way. A digital learning service like CLG should take reasonable steps to notice risks in its own online spaces.
- **Royal Commission into Institutional Responses to Child Sexual Abuse (2017), Final Report Volume 6, "Making institutions child safe".** It describes grooming as gradual boundary-crossing that often looks harmless on its own: secrecy, special attention, private contact outside the organisation's channels, and gifts. Organisations should have clear codes of conduct about online contact and should watch for these behaviours, not only for abuse once it happens.
- **eSafety Commissioner (Australia).** Its guidance on online grooming lists warning signs such as asking a child to keep the relationship secret, moving the conversation to private apps or platforms, asking for photos, and offering gifts. Its **Safety by Design** principles ask services to build in ways to detect and respond to harm, while staying transparent and respecting users' rights. The starting word list follows these signs.
- **Kids Helpline and Lifeline (Australia)** list warning signs of suicide risk that include talking about wanting to die, being a burden ("better off without me"), or having no reason to live. These are on the starting list as **urgent**.
- **UK Department for Education, "Keeping children safe in education"** and its **filtering and monitoring standards** (2023 onwards) expect schools to monitor online activity for safeguarding risks, with alerts reviewed by a person (the Designated Safeguarding Lead), staff told that monitoring happens, and the setup reviewed regularly. This is the clearest published model for a learning provider and the design follows it, ready for going international.
- **What keyword checking can and can't do.** Simple word lists miss risks that are written in other words, and they also flag harmless writing (a history essay about a war, a novel study on suicide, "he always beats me at chess"). Safeguarding monitoring guidance in the UK and eSafety's Safety by Design both treat automated alerts as a prompt for trained human review, never as a decision. So: every flag is reviewed by a person, every word has a note on when it's likely harmless, and the list can be tuned as false alarms show up.
- **Education research.** Evidence for Learning, AERO and the EEF have no studies on keyword monitoring. What they do support is that learning depends on children feeling safe and known (AERO, "Creating safe and supportive learning environments"; EEF, "Improving behaviour in schools", on knowing pupils and their circumstances). This tool is a safeguarding duty that supports that, not a learning intervention, so the design follows the child safety sources above.

## 3. How the design follows this

- **What is checked.** New and edited text in: session summaries (what went well, next step, homework), staff notes on a session, student reflections, family notes, uploaded work (title, note, tutor comment), session requests, booking notes, term reviews (including family replies), waitlist notes, and learning needs and support strategies. Child safety concerns themselves are not checked (they already go to the officer).
- **Done by the database.** The check is a trigger on each of those tables, so no page can skip it. It writes only to this module's own flag table. If the check itself ever fails, the person's writing still saves.
- **Matching.** Whole words only ("kill" doesn't match "skill"), ignoring capitals, apostrophes ("dont" and "don't" match the same), dashes ("self-harm" matches "self harm") and extra spaces. A `*` at the end of a word means any ending ("bully*" matches bullied and bullying; "want* to die" matches "wants to die").
- **Edits.** When text is edited, only words that weren't there before make a new flag, so fixing a typo doesn't flag again.
- **Staff-only words.** Some words only matter when staff write them. "Text me" or "WhatsApp" is normal from a parent, but CLG's code of conduct says tutors don't contact students privately outside CLG. These are marked "staff writing only".
- **Urgent words.** Self-harm, abuse, grooming and sexual content words are urgent: the reviewer gets an email straight away, even in quiet hours (child safety can't wait). The email holds no names, words or details, only "open the app" (with two-step sign-in). Other flags show in the red Child safety number in the top bar.
- **Review.** On **Child safety > Flagged words** (`/safety/flags`) the reviewer sees each flag with the words that matched, where it was written, who wrote it, which student it's about, and a copy of the text. They record a decision: no concern (with a reason), following up, or raised as a child safety concern (with a link to the concern form, and 000 first if a child is in danger now).
- **The list.** 65 starting words in eight groups (self-harm, abuse or neglect, grooming signs, contact outside CLG, bullying, violence, sexual content, other). The officer, the deputy and the owner can add words, mark them urgent or staff-only, turn them off or remove them. Removing a word keeps the flags it already made.

## 4. How we'll know it works

- Every flag gets a decision, and new flags are reviewed within a day (urgent ones within 1 hr).
- The share of "no concern" decisions per word. A word that is almost always a false alarm gets reworded, made staff-only, or turned off. A word that leads to real concerns stays.
- In the pilot, the officer reviews the list each month for the first three months, then each term.

## 5. Privacy and child safety

- **Who sees flags.** Only the Child Safety Officer and the deputy, after two-step sign-in, and **never a flag on their own writing**. Words Carla writes go to Lauren only, and the other way round. Urgent emails go to the officer, or to the deputy when the officer wrote the text. This is in the database (row level security), with tests in `supabase/tests/safety_watch_words.test.sql`.
- **Who sees the list.** Only the officer, the deputy and the owner. Tutors, parents and students can't read it, so it can't be worked around.
- **No leaks elsewhere.** The activity log records the flag id and decision only, never the words. Emails hold no details.
- **Privacy Act, APP 1 and APP 5 (being open, and telling people).** People must be told their writing is checked for child safety. **To do:** add a sentence to the privacy policy, family terms and tutor contract (suggested wording: "To keep children safe, the app checks what is written in it for words that may point to a risk to a child. A match is seen only by CLG's Child Safety Officer or deputy, who decide whether any action is needed.").
- **APP 3 and APP 6 (collecting and using).** The flag copies text CLG already holds, for a related purpose (keeping children safe while CLG provides its service). Where it involves sensitive information, using it to lessen a serious threat to someone's life, health or safety is a permitted general situation (Privacy Act s 16A). Ask the lawyer to confirm.
- **Automated decisions (Privacy Act, APP 1.7 to 1.9, from 10 Dec 2026).** These new rules require the privacy policy to explain computer programs that make, or substantially help make, decisions that significantly affect people. The app makes no decision here (a person always decides), but the privacy policy should still describe the check, to be safe and open.
- **Children's Online Privacy Code (OAIC, in development).** Expected to require that children's information is handled in their best interests, with transparency. Checking for risks to children, with human review and no automatic consequences, is in their best interests. Explain it to students 16+ in plain words.
- **APP 11 (security and keeping records).** Flags hold a copy of the text so the record survives edits and deletions. Flags that become concerns are kept as child safety records (45+ years in the policy draft). **Open question:** flags marked "no concern" could have their text copy cleared after a set time (for example 1 year), since they're no longer needed. Not built yet; for Carla and the lawyer.
- **Staff monitoring.** South Australia has no general workplace surveillance law, but NSW (Workplace Surveillance Act 2005) and the ACT require written notice before computer surveillance of staff. Tell all staff in writing (tutor contract and code of conduct) that their writing in the app is checked, wherever they work.
- **UK and EU later.** UK: the ICO Children's Code allows profiling of children where there is a compelling reason in their best interests, such as safeguarding; a data protection impact assessment (DPIA) is needed. EU: GDPR Art. 35 DPIA; Art. 22 is not triggered because no decision is solely automated. The design (human review, restricted access, transparency) fits both.

## Open questions for Carla and the lawyer

1. Approve the privacy policy, family terms and tutor contract wording in section 5.
2. Should the deputy see all flags (as built, so nothing waits while Carla is away), or only flags on Carla's writing?
3. Clear the text copy on "no concern" flags after a set time? If so, how long?
4. When "Report a problem" (PR #115) and any future messaging are merged, add their text boxes to the check.
5. Review the starting word list together in the first month of the pilot.
