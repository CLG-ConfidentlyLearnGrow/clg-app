"use client";

import { useFormStatus } from "react-dom";
import { Button } from "@/components/ui";

// A submit button that can only be pressed once while the form is working.
// Email links work only once: a second press would use the link up and show
// "expired" even though the first press worked.
export function SubmitOnce({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending} aria-busy={pending}>
      {pending ? "One moment…" : label}
    </Button>
  );
}
