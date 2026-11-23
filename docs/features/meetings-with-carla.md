# Booking a meeting with Carla

Carla, 22 Nov 2026, from the How We Do Things guide: anyone who needs a meeting with Carla says what it is **About**, the **Context** and their **Goal**, and the request is handled like a help desk request. Carla agreed that the person asking suggests 2 or 3 times and how urgent it is, and Carla confirms one.

## What it is for

Meetings booked by text or in passing are easy to forget, and Carla often walks in without the background. A short written request means Carla can prepare, sometimes answer straight away without a meeting, and see every request in one place. It also supports the How We Do Things promise that Carla replies within 1 business day.

## What the evidence says

- **Structured conversations** (AERO and the EEF guidance on effective professional development and coaching): conversations with a clear purpose and agreed goal lead to more action than open-ended ones. About, Context and Goal give each meeting that purpose.
- **Supervision and support for staff** (Evidence for Learning on implementation, and the National Principles for Child Safe Organisations, Principle 7 on staff support): staff need an easy, reliable way to reach the person in charge, especially for urgent concerns.
- **Respecting time** (EEF on teacher workload): offering times up front avoids long back-and-forth messages.

## How the design follows it

- Every tutor and admin has **Meet with Carla** in their side menu. Carla sees it as **Meeting requests**.
- The request form asks for About, Context, Goal, how urgent (urgent, this week, no rush), how long (15, 30, 45 or 60 minutes), how to meet (online, phone, in person) and 2 or 3 times, all in Adelaide time. "If you are not sure whether it is urgent, choose urgent", as in the guide.
- Carla gets an app notice for each request; urgent ones say so in the title. Her list shows urgent requests first, then the oldest.
- Carla can confirm one of their times, offer a different time (the person accepts it or cancels), or answer without a meeting when a short answer is enough. Either person can cancel. After the meeting Carla marks it **Held**.
- The menu number shows Carla the requests waiting, and shows staff any different time waiting for their answer.
- A quick question is pointed to Help chat instead.

## How we will know it works

- share of requests answered within 1 business day
- share answered without needing a meeting
- urgent requests and how quickly they were answered

## Privacy, child safety and legal notes

- **Privacy Act 1988 (APPs 3, 6 and 11) and the Children's Online Privacy Code**: requests are staff information. Only the person who asked and CLG's owner can see a request (other admins cannot); access rules are in the database. The form asks staff to use first names or initials only for students.
- **Child safety**: this is not the way to report a concern about a child. Child safety concerns go through **Child safety** (in red on every page), which is unchanged.
- **UK and EU (GDPR)**: the same minimal fields and owner-only access apply; legitimate interest is the basis.

## Technical

- Migration `20261124711600_meeting_requests.sql` (module: staff). It adds the table `public.meeting_requests` and the functions `meeting_request_send`, `meeting_request_cancel`, `meeting_request_accept_time`, `meeting_request_confirm`, `meeting_request_answer`, `meeting_request_held` and `meeting_requests_to_do`. Times are typed as Adelaide clock times and saved as true moments. Safe to run more than once.
- Page: `/meetings`. Actions: `src/app/actions/meetings.ts`.
- Tests: `supabase/tests/meetings_book_with_carla.test.sql`.
- Later: add confirmed meetings to Carla's calendar automatically.
