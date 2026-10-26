import { continueEmailLink } from "@/app/actions/auth";
import { Button, Card, Page } from "@/components/ui";
import { isEmailLinkType } from "@/lib/email-links";
import { safeNextPath } from "@/lib/forms";
import { redirect } from "next/navigation";

// Email links land here and wait for a button press. Email security scanners
// open links automatically; without this step they would use the link up
// before the person clicks it.
export default async function ContinuePage({ searchParams }: PageProps<"/auth/continue">) {
  const { token_hash, type, next } = await searchParams;
  if (typeof token_hash !== "string" || !isEmailLinkType(type)) redirect("/login?link=expired");

  const label = type === "recovery" ? "Reset my password" : type === "invite" ? "Accept invitation" : "Continue";
  return (
    <Page title="One more step">
      <Card>
        <p className="mb-4 text-sm">Press the button to carry on.</p>
        <form action={continueEmailLink}>
          <input type="hidden" name="token_hash" value={token_hash} />
          <input type="hidden" name="type" value={type} />
          <input type="hidden" name="next" value={safeNextPath(typeof next === "string" ? next : null)} />
          <Button type="submit">{label}</Button>
        </form>
      </Card>
    </Page>
  );
}
