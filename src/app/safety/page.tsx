// Summary: the "Child safety" page, open to everyone signed in. In order:
// 1. call 000 if a child is in immediate danger (the biggest thing on the page),
// 2. phone the child protection line for the child's state (SA first),
// 3. tell CLG: the form sends the concern to the Child Safety Officer, or
//    to the deputy (for example when the concern is about the officer).
// Then support lines for young people, the documents, the concerns this
// person has raised, and (owner only) who receives concerns.
//
import Link from "next/link"; // Next.js link tag (moves between pages without reloading).
import { raiseConcern, setSafetyContacts } from "@/app/actions/child-safety"; // The server actions for raising a concern and naming the contacts.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Card, Empty, Field, Page, Select, TextArea } from "@/components/ui"; // The card, "nothing yet" note, text box, page frame, drop-down and multi-line box.
import { getAdminLevel, requireViewer } from "@/lib/auth"; // Makes sure someone is signed in, and reads their admin level.
import { CONTACT_ROLE_LABELS, LINES_CHECKED_ON, REPORTING_LINES, SAFETY_DOCUMENTS, STATUS_LABELS, SUPPORT_LINES, lineFor, telHref } from "@/lib/child-safety"; // The reporting lines, documents, labels and phone link maker.
import { plainDate } from "@/lib/privacy"; // Dates in words.
import { createClient } from "@/lib/supabase/server"; // Connects to the database as the signed-in person.

// A concern this person raised, as the database gives it.
type MyConcern = { id: string; child_name: string; sent_to: string; status: string; created_at: string }; // its id, child, who it went to, stage and date.

// A child safety contact, as the database gives it.
type Contact = { role: "officer" | "deputy"; account_id: string; full_name: string }; // the job, the account and the name.

// The style for a radio button or tick box, so they match the app's other fields.
const tick = "h-4 w-4 shrink-0 accent-teal-700"; // small, in CLG's teal.

// Shows the Child safety page.
export default async function SafetyPage({ searchParams }: PageProps<"/safety">) { // The page itself (reads the address's settings).
  const viewer = await requireViewer(); // Makes sure someone is signed in, and gets who they are.
  const params = await searchParams; // The address's settings.
  const sent = typeof params.sent === "string"; // True straight after a concern was sent.
  const supabase = await createClient(); // Connects to the database.
  const level = await getAdminLevel(); // Their admin level (owner, etc.), if any.
  const [children, contacts, mine, choices] = await Promise.all([ // Reads four things at once:
    supabase.from("students").select("id, full_name").order("full_name"), // the children they can see (their own, their students, or all for admins),
    supabase.rpc("child_safety_contacts_list"), // who receives concerns,
    supabase.from("safety_concerns").select("id, child_name, sent_to, status, created_at").eq("raised_by", viewer.id).order("created_at", { ascending: false }).limit(20), // the concerns they raised (latest 20),
    level === "owner" ? supabase.rpc("child_safety_contact_choices") : Promise.resolve({ data: [] }), // and, for the owner, the staff to choose from.
  ]); // End of the reads.
  const childRows = (children.data ?? []) as { id: string; full_name: string }[]; // The children.
  const contactRows = (contacts.data ?? []) as Contact[]; // The contacts.
  const officer = contactRows.find((c) => c.role === "officer"); // The Child Safety Officer, if named.
  const deputy = contactRows.find((c) => c.role === "deputy"); // The deputy, if named.
  const myRows = (mine.data ?? []) as MyConcern[]; // The concerns they raised.
  const choiceRows = (choices.data ?? []) as { account_id: string; full_name: string }[]; // The staff the owner can choose from.
  const isContact = contactRows.some((c) => c.account_id === viewer.id); // True if they receive concerns themselves.
  const sa = lineFor("SA"); // South Australia's line (all students live in SA).

  return ( // Shows:
    <Page // a page:
      title="Child safety" // titled "Child safety",
      intro="If you are worried about a child or young person, follow these steps in order. You don't need proof: a reasonable worry is enough." // with a short explanation.
    >{/* (end of the page's settings) */}
      {isContact && ( // If they receive concerns:
        <p className="rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm">{/* a small box: */}
          You receive child safety concerns.{" "}{/* says so, */}
          <Link href="/safety/concerns" className="font-medium text-teal-800 underline underline-offset-4">{/* and links to them: */}
            Open concerns sent to you{/* the link's words. */}
          </Link>{/* End of the link. */}
          {" · "}{/* a separator, */}
          <Link href="/safety/flags" className="font-medium text-teal-800 underline underline-offset-4">{/* and links to the flagged words: */}
            Flagged words{/* the link's words. */}
          </Link>{/* End of the link. */}
        </p> // End of the box.
      )}{/* End of that part. */}
      {!isContact && level === "owner" && ( // If they're the owner but don't receive concerns:
        <p className="rounded-xl border border-zinc-200 bg-white px-4 py-3 text-sm">{/* a small box: */}
          <Link href="/safety/flags" className="font-medium text-teal-800 underline underline-offset-4">{/* a link to the word list: */}
            Words and phrases the app watches for{/* the link's words. */}
          </Link>{/* End of the link. */}
        </p> // End of the box.
      )}{/* End of that part. */}

      {sent && ( // Straight after sending:
        <div role="status" className="rounded-2xl border border-teal-300 bg-teal-50 p-5 text-sm text-teal-900">{/* a green confirmation box: */}
          <p className="font-semibold">Thank you. Your concern has been sent to CLG.</p>{/* the confirmation, */}
          <p className="mt-2">{/* what happens next: */}
            Only the person you sent it to can read it. They will contact you if they need more information. Please
            don&apos;t talk about it with the family or the person involved.{/* who can read it and what not to do, */}
          </p>{/* End of the paragraph. */}
          <p className="mt-2 font-medium">{/* a reminder: */}
            Telling CLG doesn&apos;t replace reporting to the child protection line. If you haven&apos;t phoned {sa.phones[0].number} yet and you should, please do it now.{/* that reporting to CLG isn't enough on its own. */}
          </p>{/* End of the paragraph. */}
        </div> // End of the box.
      )}{/* End of that part. */}

      {/* Step 1: emergency. Red, large and first, so nobody can miss it. */}
      <section aria-labelledby="step-000" className="rounded-2xl border-4 border-red-700 bg-red-50 p-6 text-red-950">{/* a thick red box: */}
        <h2 id="step-000" className="text-xl font-bold sm:text-2xl">{/* its heading: */}
          1. Is a child in immediate danger? Call 000 now.{/* the instruction, */}
        </h2>{/* End of the heading. */}
        <p className="mt-2 text-base">{/* the explanation: */}
          If a child is hurt, in danger right now, or about to be harmed, call Triple Zero (000) for police or
          ambulance <strong>before you do anything else</strong>. Stay with the child if it is safe to.{/* call 000 first, */}
        </p>{/* End of the paragraph. */}
        <a // the call button:
          href="tel:000" // dials 000 on a phone,
          className="mt-4 inline-flex items-center gap-2 rounded-full bg-red-700 px-8 py-4 text-2xl font-bold text-white shadow-md transition hover:bg-red-800" // big, red and round,
        >{/* (end of the link's settings) */}
          Call 000{/* its words. */}
        </a>{/* End of the button. */}
        <p className="mt-4 text-sm">{/* what to do after: */}
          When the child is safe, come back and do steps 2 and 3.{/* then the other steps. */}
        </p>{/* End of the paragraph. */}
      </section>{/* End of step 1. */}

      {/* Step 2: the state's child protection line. */}
      <Card title="2. Report to the child protection line" description="For concerns that are not an emergency, or after you have called 000.">{/* A card for the reporting line: */}
        <div className="rounded-xl bg-amber-50 p-4 text-amber-950">{/* a highlighted box for South Australia: */}
          <p className="text-sm font-semibold uppercase tracking-wide">South Australia (all CLG students)</p>{/* the state, */}
          <p className="mt-1 text-sm">{sa.service}</p>{/* the service's name, */}
          <a href={telHref(sa.phones[0].number)} className="mt-2 inline-block text-3xl font-bold underline-offset-4 hover:underline">{/* the number, as a link that dials it: */}
            {sa.phones[0].number}{/* 13 14 78, */}
          </a>{/* end of the number, */}
          <p className="text-sm">{sa.phones[0].label}</p>{/* when it's open, */}
          <p className="mt-3 text-sm">{sa.notes}</p>{/* when you must phone, */}
          {sa.online && ( // the online form, if there is one:
            <p className="mt-2 text-sm">{/* a line: */}
              Other non-urgent reports from mandated notifiers can use{" "}{/* when it can be used, */}
              <a href={sa.online.url} target="_blank" rel="noreferrer" className="font-medium underline underline-offset-4">{/* the link: */}
                e-CARL{/* its words, */}
              </a>{/* end of the link, */}
              .{/* (full stop) */}
            </p> // End of the line.
          )}{/* End of the online form. */}
        </div>{/* End of the SA box. */}

        <div className="mt-4 space-y-2 text-sm text-zinc-700">{/* Who must report: */}
          <p>{/* the law: */}
            <strong>Who must report in South Australia.</strong> CLG tutors and staff who work directly with
            children are mandated notifiers. If you suspect on reasonable grounds that a child is, or may be, at
            risk of harm, you must report it to the Child Abuse Report Line as soon as is reasonably practicable
            (Children and Young People (Safety) Act 2017, sections 30 and 31).{/* who and when, */}
          </p>{/* End of the paragraph. */}
          <p>{/* CLG's own rule: */}
            <strong>CLG&apos;s rule:</strong> everyone who works for CLG reports, wherever they live, and then tells
            CLG in step 3. Parents and students can phone the line too.{/* everyone reports, */}
          </p>{/* End of the paragraph. */}
          <p>{/* what not to do: */}
            Don&apos;t investigate, question the child in detail, or confront the person you are worried about.
            Write down what you saw or heard, in the child&apos;s own words where you can.{/* don't investigate, */}
          </p>{/* End of the paragraph. */}
        </div>{/* End of who must report. */}

        <details className="mt-4 rounded-xl border border-zinc-200 p-4">{/* An open-and-close list of the other states: */}
          <summary className="cursor-pointer text-sm font-medium text-teal-800">Child lives in another state or territory?</summary>{/* its title, */}
          <ul className="mt-3 space-y-3 text-sm">{/* the list: */}
            {REPORTING_LINES.filter((l) => l.state !== "SA").map((l) => ( // for each state except SA:
              <li key={l.state}>{/* a list item: */}
                <p className="font-semibold">{l.stateName}: <span className="font-normal">{l.service}</span></p>{/* the state and service, */}
                <ul className="ml-4 list-disc">{/* its numbers: */}
                  {l.phones.map((p) => ( // for each number:
                    <li key={p.number}>{/* a line: */}
                      <a href={telHref(p.number)} className="font-medium underline-offset-4 hover:underline">{p.number}</a> ({p.label}){/* the number (dials on a phone) and when. */}
                    </li> // End of the line.
                  ))}{/* End of the loop. */}
                </ul>{/* End of the numbers. */}
              </li> // End of the item.
            ))}{/* End of the loop. */}
          </ul>{/* End of the list. */}
          <p className="mt-3 text-xs text-zinc-500">Numbers checked {LINES_CHECKED_ON}.</p>{/* When the numbers were checked. */}
        </details>{/* End of the other states. */}
      </Card>{/* End of step 2. */}

      {/* Step 3: tell CLG. */}
      <Card title="3. Tell CLG" description="Your concern goes to one person only and is kept confidential. The person you are worried about is never told who raised it.">{/* A card with the form: */}
        {!officer ? ( // If no officer has been named yet:
          <Empty>CLG hasn&apos;t named its Child Safety Officer in the app yet. Please phone CLG directly.</Empty> // says to phone.
        ) : ( // Otherwise:
          <ActionForm action={raiseConcern} submitLabel="Send to CLG">{/* the form that sends the concern: */}
            <fieldset className="space-y-2">{/* the "who to send to" choice: */}
              <legend className="text-sm font-medium text-zinc-800">Who should get this?</legend>{/* its question, */}
              <label className="flex items-start gap-2 text-sm">{/* the officer option: */}
                <input type="radio" name="send_to" value="officer" defaultChecked className={`${tick} mt-0.5`} />{/* its radio button (chosen at the start), */}
                <span>{/* its words: */}
                  <strong>{officer.full_name}</strong>, {CONTACT_ROLE_LABELS.officer} (usual choice){/* the officer's name and job, */}
                </span>{/* end of the words. */}
              </label>{/* End of the option. */}
              {deputy && ( // If a deputy is named:
                <label className="flex items-start gap-2 text-sm">{/* the deputy option: */}
                  <input type="radio" name="send_to" value="deputy" className={`${tick} mt-0.5`} />{/* its radio button, */}
                  <span>{/* its words: */}
                    <strong>{deputy.full_name}</strong>, {CONTACT_ROLE_LABELS.deputy}. Choose this if the concern is about{" "}
                    {officer.full_name}, or you can&apos;t reach them.{/* the deputy's name, job and when to choose them. */}
                  </span>{/* end of the words. */}
                </label> // End of the option.
              )}{/* End of the deputy option. */}
            </fieldset>{/* End of the choice. */}

            <fieldset className="space-y-2">{/* the danger question: */}
              <legend className="text-sm font-medium text-zinc-800">Is a child in immediate danger right now?</legend>{/* its question, */}
              <label className="flex items-center gap-2 text-sm">{/* the "yes" option: */}
                <input type="radio" name="immediate_danger" value="yes" required className={tick} />{/* its radio button, */}
                Yes{/* its words, */}
              </label>{/* end of the option. */}
              <label className="flex items-center gap-2 text-sm">{/* the "no" option: */}
                <input type="radio" name="immediate_danger" value="no" required className={tick} />{/* its radio button, */}
                No{/* its words, */}
              </label>{/* end of the option. */}
              <p className="rounded-lg bg-red-50 px-3 py-2 text-sm font-medium text-red-900">{/* a red reminder: */}
                If yes, stop and call 000 first. Come back to this form afterwards.{/* call 000 first. */}
              </p>{/* End of the reminder. */}
              <label className="flex items-center gap-2 text-sm">{/* the "I called 000" tick box: */}
                <input type="checkbox" name="called_000" className={tick} />{/* its box, */}
                I have called 000 about this{/* its words. */}
              </label>{/* End of the tick box. */}
            </fieldset>{/* End of the danger question. */}

            <Select label="Which child is it about?" name="child" required defaultValue="">{/* a drop-down of children: */}
              <option value="" disabled>{/* a blank first option that can't be picked: */}
                Choose one{/* "Choose one", */}
              </option>{/* (end of the option) */}
              {childRows.map((c) => ( // for each child they can see:
                <option key={c.id} value={c.id}>{/* an option: */}
                  {c.full_name}{/* their name. */}
                </option> // (end of the option)
              ))}{/* End of the loop. */}
              <option value="other">Someone not listed</option>{/* and "someone not listed". */}
            </Select>{/* End of the drop-down. */}
            <div className="grid gap-4 rounded-xl bg-zinc-50 p-4 sm:grid-cols-2">{/* the extra fields for a child not listed: */}
              <p className="text-xs text-zinc-600 sm:col-span-2">Only if you chose &quot;Someone not listed&quot;:</p>{/* when to fill them in, */}
              <Field label="Child's name (or a description)" name="child_name" maxLength={200} />{/* the name box, */}
              <Select label="State the child lives in" name="child_state" defaultValue="">{/* the state drop-down: */}
                <option value="">Choose a state</option>{/* a blank first option, */}
                {REPORTING_LINES.map((l) => ( // for each state:
                  <option key={l.state} value={l.state}>{/* an option: */}
                    {l.stateName}{/* its name. */}
                  </option> // (end of the option)
                ))}{/* End of the loop. */}
              </Select>{/* End of the drop-down. */}
            </div>{/* End of the extra fields. */}

            <TextArea // the main box:
              label="What happened?" // its label,
              name="what_happened" // its name,
              required // must be filled in,
              minLength={10} // at least a sentence,
              maxLength={8000} // at most 8,000 letters,
              rows={6} // six lines tall,
              hint="What you saw, heard or were told, and when. Use the child's own words where you can. Facts only: please don't guess or investigate." // and what to write.
            />{/* End of the box. */}
            <Field label="When did it happen or when did you notice? (optional)" name="happened_on" type="date" />{/* the date box. */}

            <fieldset className="space-y-2">{/* the reporting-line question: */}
              <legend className="text-sm font-medium text-zinc-800">Have you reported this to the child protection line (step 2)?</legend>{/* its question, */}
              <label className="flex items-center gap-2 text-sm">{/* the "yes" option: */}
                <input type="radio" name="reported_to_line" value="yes" required className={tick} />{/* its radio button, */}
                Yes{/* its words, */}
              </label>{/* end of the option. */}
              <label className="flex items-center gap-2 text-sm">{/* the "not yet" option: */}
                <input type="radio" name="reported_to_line" value="no" required className={tick} />{/* its radio button, */}
                Not yet{/* its words, */}
              </label>{/* end of the option. */}
              <label className="flex items-center gap-2 text-sm">{/* the "not sure" option: */}
                <input type="radio" name="reported_to_line" value="not_sure" required className={tick} />{/* its radio button, */}
                Not sure whether it needs reporting{/* its words. */}
              </label>{/* end of the option. */}
            </fieldset>{/* End of the question. */}
            <Field label="Reference number from the line (if you have one)" name="line_reference" maxLength={100} />{/* the reference box. */}
          </ActionForm> // End of the form.
        )}{/* End of the officer check. */}
      </Card>{/* End of step 3. */}

      {/* For children and young people using the app themselves. */}
      <Card title="If you are a young person and don't feel safe">{/* A card for young people: */}
        <p className="text-sm text-zinc-700">{/* what to do: */}
          If you are in danger now, call 000. You can also talk to someone any time, for free:{/* call 000 or a helpline: */}
        </p>{/* End of the paragraph. */}
        <ul className="mt-2 space-y-1 text-sm">{/* the helplines: */}
          {SUPPORT_LINES.map((s) => ( // for each helpline:
            <li key={s.number}>{/* a line: */}
              <a href={telHref(s.number)} className="font-semibold underline-offset-4 hover:underline">{s.number}</a> {s.label}{/* the number (dials on a phone) and its name. */}
            </li> // End of the line.
          ))}{/* End of the loop. */}
        </ul>{/* End of the helplines. */}
        <p className="mt-2 text-sm text-zinc-700">Or tell an adult you trust, or use the form above.</p>{/* other ways. */}
      </Card>{/* End of the card. */}

      {/* The documents behind all of this. */}
      <Card title="Policies and the law" description="The documents that set out these steps.">{/* A card of documents: */}
        <ul className="space-y-2 text-sm">{/* the list: */}
          {SAFETY_DOCUMENTS.map((d) => ( // for each document:
            <li key={d.url}>{/* a line: */}
              <a href={d.url} target="_blank" rel="noreferrer" className="font-medium text-teal-800 underline underline-offset-4">{/* the link (opens in a new tab): */}
                {d.label}{/* its name, */}
              </a>{/* end of the link, */}
              <span className="block text-zinc-600">{d.note}</span>{/* and what it's for. */}
            </li> // End of the line.
          ))}{/* End of the loop. */}
        </ul>{/* End of the list. */}
      </Card>{/* End of the card. */}

      {/* The concerns this person raised. */}
      <Card title="Concerns you've raised" description="Only you and the person you sent each one to can see these." collapsible defaultOpen={myRows.length > 0}>{/* A card of their concerns: */}
        {myRows.length === 0 ? ( // if none:
          <Empty>None.</Empty> // says so.
        ) : ( // Otherwise:
          <ul className="space-y-2 text-sm">{/* the list: */}
            {myRows.map((c) => ( // for each concern:
              <li key={c.id} className="border-b border-zinc-100 pb-2 last:border-0">{/* a line: */}
                <strong>{c.child_name}</strong>, sent {plainDate(c.created_at)} to the {CONTACT_ROLE_LABELS[c.sent_to] ?? c.sent_to}: {STATUS_LABELS[c.status] ?? c.status}{/* the child, when, to whom, and where it's up to. */}
              </li> // End of the line.
            ))}{/* End of the loop. */}
          </ul> // End of the list.
        )}{/* End of the choice. */}
      </Card>{/* End of the card. */}

      {level === "owner" && ( // Only for the owner:
        <Card title="Who receives concerns (owner only)" description="New concerns go to these people. Concerns already raised stay with the person they were sent to." collapsible defaultOpen={!deputy}>{/* A card for naming the contacts: */}
          <ActionForm action={setSafetyContacts} submitLabel="Save">{/* the form: */}
            <Select label={CONTACT_ROLE_LABELS.officer} name="officer" required defaultValue={officer?.account_id ?? ""}>{/* the officer drop-down: */}
              <option value="" disabled>Choose someone</option>{/* a blank first option, */}
              {choiceRows.map((c) => ( // for each staff member:
                <option key={c.account_id} value={c.account_id}>{c.full_name}</option> // an option with their name.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
            <Select label={`${CONTACT_ROLE_LABELS.deputy} (handles concerns about the officer)`} name="deputy" defaultValue={deputy?.account_id ?? ""}>{/* the deputy drop-down: */}
              <option value="">Nobody</option>{/* "nobody" first, */}
              {choiceRows.map((c) => ( // for each staff member:
                <option key={c.account_id} value={c.account_id}>{c.full_name}</option> // an option with their name.
              ))}{/* End of the loop. */}
            </Select>{/* End of the drop-down. */}
          </ActionForm>{/* End of the form. */}
        </Card> // End of the card.
      )}{/* End of the owner part. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of SafetyPage.
