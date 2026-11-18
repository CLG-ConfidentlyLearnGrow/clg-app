// Summary: the staff member's forms for their employment contract: signing
// it (typed full name, agreeing to the terms, and agreeing to sign
// electronically), then acknowledging each linked document with their typed
// name. See docs/features/employment-contracts.md.
//
"use client"; // Runs in the browser, so the forms can show their result straight away.

import { acknowledgeContractDocument, signContract } from "@/app/actions/employment-contracts"; // The server actions for signing and acknowledging.
import { ActionForm } from "@/components/action-form"; // The form that sends to a server action and shows its reply.
import { Field } from "@/components/ui"; // A text box.

// The signing form.
export function SignForm({ id, hash, fullName }: { id: string; hash: string; fullName: string }) {
  return ( // Shows:
    <ActionForm action={signContract} submitLabel="Sign and accept">{/* a form that signs it: */}
      <input type="hidden" name="id" value={id} />{/* the contract's id, hidden, */}
      <input type="hidden" name="body_sha256" value={hash} />{/* the fingerprint of the wording shown, hidden, */}
      <input type="hidden" name="pay_notice" value="shown" />{/* a note that the pay notice was on the page, hidden, */}
      <div className="rounded-xl border border-brand/40 bg-brand/5 p-4 text-sm">{/* the pay notice: */}
        <p className="font-semibold">Accepting pay</p>{/* its heading, */}
        <p className="mt-1">As the contract says, if you accept pay from CLG for work under this contract, that is also your acceptance of its terms, in addition to your signature here.</p>{/* and its words. */}
      </div>{/* End of the notice. */}
      <label className="flex items-start gap-2 text-sm">{/* the agreement tick: */}
        <input type="checkbox" name="agree" className="mt-1" />{/* a tick box, */}
        <span>I have read this contract in full and I agree to its terms.</span>{/* and its words. */}
      </label>{/* End of the line. */}
      <label className="flex items-start gap-2 text-sm">{/* the electronic signature tick: */}
        <input type="checkbox" name="consent" className="mt-1" />{/* a tick box, */}
        <span>I agree to sign this contract electronically. Typing my full name below and pressing Sign and accept is my signature.</span>{/* and its words. */}
      </label>{/* End of the line. */}
      <Field label={`Type your full name: ${fullName}`} name="typed_name" required maxLength={200} autoComplete="off" hint="Exactly as it shows here. Capital letters do not matter." />{/* the typed name. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of SignForm.

// The form to acknowledge one document.
export function AcknowledgeForm({ id, statement, title, href, fullName }: { id: string; statement: string; title: string; href: string; fullName: string }) {
  return ( // Shows:
    <ActionForm action={acknowledgeContractDocument} submitLabel={`Acknowledge the ${title}`}>{/* a form that acknowledges it: */}
      <input type="hidden" name="id" value={id} />{/* the contract's id, hidden, */}
      <input type="hidden" name="statement" value={statement} />{/* which document, hidden, */}
      <p className="text-sm"><a href={href} target="_blank" rel="noreferrer" className="inline-flex items-center rounded-lg border border-brand bg-brand px-3 py-1.5 font-medium text-white hover:opacity-90">Open the {title}</a> <span className="text-zinc-600">(opens in a new tab)</span></p>{/* a button to the document (a new tab, so this page stays open), */}
      <label className="flex items-start gap-2 text-sm">{/* the tick: */}
        <input type="checkbox" name="read" className="mt-1" />{/* a tick box, */}
        <span>I have opened and read the {title}, and I understand it.</span>{/* and its words. */}
      </label>{/* End of the line. */}
      <Field label={`Type your full name: ${fullName}`} name="typed_name" required maxLength={200} autoComplete="off" />{/* the typed name. */}
    </ActionForm> // End of the form.
  ); // End of what's shown.
} // End of AcknowledgeForm.
