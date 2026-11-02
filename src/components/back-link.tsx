"use client";

import { useRouter } from "next/navigation";

// "Back" that returns to the page the person came from (for example the
// sign-up or agree form, with what they typed still there), or to the home
// page when the page was opened on its own.
export function BackLink({ label = "Back" }: { label?: string }) {
  const router = useRouter();
  return (
    <button
      type="button"
      onClick={() => (window.history.length > 1 ? router.back() : router.push("/"))}
      className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 transition hover:decoration-teal-700"
    >
      {label}
    </button>
  );
}
