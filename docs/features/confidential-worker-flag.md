# Confidential flag about a CLG worker

Requested by Carla, 12 Nov 2026. Rules confirmed by Carla, 15 Nov 2026. Draft for the lawyer's review with the Child Safe Policy.

## 1. What it's for

Sometimes the worry is about a person who works for CLG: a tutor, or a staff member. The person raising it must be able to say so safely, without that worker finding out. This builds on the child safety concern form (see `child-safety-concerns.md`). It doesn't replace that form.

Carla's rules (15 Nov 2026):

1. Anyone can raise one. That includes parents, students with their own login, tutors and staff flagging a colleague.
2. It's named, but hidden from the worker. The worker never sees the concern, its notes, or that they were named. The person raising it isn't promised that CLG won't contact them, because CLG may need to.
3. A concern about Lauren (deputy) goes to Carla (Child Safety Officer). A concern about Carla goes to Lauren. A concern naming both goes to both. Once CLG has a lawyer, concerns that name all the child safety contacts will go to the lawyer instead.
4. Lauren's emergency owner access doesn't open concerns. Lauren can choose to share one particular flag about Carla with Carla.
5. Concerns about teaching quality (service), and small "something felt off" worries, belong in the feedback feature. Only Carla sees feedback about a person. That's a separate module, still to come.
6. It's noted in the policy that Carla, as the database owner, could technically read the raw tables in Supabase. This stays until more people are involved and the keys can be held by someone else.

## 2. What the evidence and the rules say

- **National Principles for Child Safe Organisations.** Principle 5: people working with children are suitable and supported. Principle 6: processes to respond to complaints and concerns are child focused. Organisations need a known, safe way to raise a worry about a worker. They also need a named person to receive it, and a second route when the worry is about that person.
- **Royal Commission into Institutional Responses to Child Sexual Abuse (2017).** It found that complaints about staff were often handled by people close to the staff member, or by the person complained about. It recommends records kept at least 45 years.
- **Allegations against workers (Victorian Department of Education, "Child abuse including grooming"; Queensland Department of Education, "Allegations against workers in the area of child and student protection").** Both say the worker shouldn't be told until police or child protection agree, so an investigation isn't put at risk. The person handling the concern must not be the person it's about.
- **Low-level concerns (UK "Keeping Children Safe in Education" and ICMEC, "Developing and implementing a low-level concerns policy", 2023).** UK schools keep a confidential record of small worries about staff, such as boundary slips, favouritism or overly personal messages. Patterns get spotted early. Carla wants these handled in the feedback feature, not in this form (rule 5).
- **SA law.** Children and Young People (Safety) Act 2017 ss 30 and 31: tutors are mandated notifiers and must still report to CARL (13 14 78) themselves. Naming a worker in CLG's form doesn't replace that duty. As far as could be confirmed (15 Nov 2026), SA has no "reportable conduct" scheme yet. NSW, Victoria, ACT, WA and Queensland do, so the record is kept in a way that would meet one: who, when, what, what was done, and the outcome.
- **Fairness to the worker.** Before any disciplinary step, the worker has to be told the allegation and get the chance to respond (procedural fairness; Fair Work Act unfair dismissal rules). The app keeps the worker uninformed while CLG looks into it. Telling them later is a decision for the Child Safety Officer, in line with the Child Safe Policy ("only when CLG decides it is safe and fair").
- **Privacy.** A worker can ask what CLG holds about them (APP 12). Most records about employees are exempt (Privacy Act s 7B(3)). APP 12.3 also lets CLG refuse where access would put someone's safety at risk or prejudice an investigation. The lawyer should confirm. UK and EU rules (UK GDPR art 15, with exemptions) work the same way.
- **Education research.** EEF, AERO and Evidence for Learning have no studies on reporting concerns about staff. What they do support is safe, trusting relationships as a precondition for learning (AERO, "Creating safe and supportive learning environments"). This is a safeguarding duty, so the design follows the child safety sources above.

## 3. How the design follows this

- **Form.** The Child safety page has a new optional question: "Is this about someone who works for CLG?" with tick boxes. Staff see every staff member. Families see CLG's admins and any tutor who has ever taught their child. Nobody sees themselves.
- **Routing.** It's done by the database, whatever the person picked. Naming the officer sends it to the deputy. Naming the deputy sends it to the officer. Naming both sends it to both. If no deputy is named in the app, a concern about the officer is refused with a plain message to phone the child protection line, and the police if a crime may have happened. Carla must name Lauren as deputy on the Child safety page.
- **Hidden from the worker.** A database rule blocks anyone named in a concern from reading it, its notes, or the list of people named. The only exceptions are when they're one of the people handling it (it names both contacts, or it was shared on purpose). The worker's own screens don't change, and they get no to-do number.
- **Passing on and sharing.** The person handling a concern can still pass it to the other contact, but not to someone it names. Instead they can **share** it. Both of them can then read it, and the reason is kept as a note. That's how Lauren can choose to show Carla one flag about Carla.
- **Email.** The second reader gets their own alert email with no names or details. It goes straight away, even in quiet hours.
- **Activity log.** It holds ids only, never names or details.

## 4. How we'll know it works

- Every concern naming a worker has a recorded outcome (a note and "Closed").
- In the pilot test guide: a tutor named in a concern sees nothing new on any page.
- Time from raised to opened: target same day, as for all concerns.

## 5. Quiet steps (Carla chose "both, as separate buttons", 15 Nov 2026)

On a concern that names a tutor, the person handling it can take either step. Nothing happens unless they press the button.

- **Stop new students.** The tutor keeps their current students, but matching, offers and bookings won't pair them with anyone new.
- **End the match** with the child in the concern. The tutor's match ends today, so they can no longer open the child's records, and the pair can't be matched again.

Each step needs a reason, which is kept as a note on the concern, and each can be lifted later. Lifting an ended match allows matching again but doesn't restart the match by itself. Upcoming bookings for the pair are counted and shown, so the handler can change them in Sessions.

The tutor is never told why. Admins doing matching see only the usual "Can't be matched with this student". This follows the Victorian and Queensland guidance on not alerting a worker while a concern is looked into (section 2). Before any disciplinary step, the worker is still told and gets to respond.

This works through the shared pairing check (`private.blocked_pair`), which now also reads `safety_holds`.

## 6. Still to decide

- The lawyer route for concerns naming all child safety contacts, once a lawyer is appointed.
