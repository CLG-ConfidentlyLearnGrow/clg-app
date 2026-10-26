import { Card, Page, TextLink } from "@/components/ui";

// Step-by-step guide for adding CLG to a phone or computer home screen.
export default function InstallPage() {
  return (
    <Page title="Add CLG to your home screen">
      <p className="text-sm">
        CLG works in your web browser, and you can add it to your home screen so it opens like any other app. It takes
        about a minute and you only do it once.
      </p>

      <Card title="iPhone or iPad">
        <ol className="list-decimal space-y-2 pl-5 text-sm">
          <li>
            Open this website in <strong>Safari</strong> (the blue compass icon).
          </li>
          <li>
            Tap the <strong>Share</strong> button: the square with an arrow pointing up. It&apos;s at the bottom of the
            screen on iPhone, or the top on iPad.
          </li>
          <li>
            Scroll down and tap <strong>Add to Home Screen</strong>.
          </li>
          <li>
            Tap <strong>Add</strong> in the top corner. The CLG icon appears on your home screen.
          </li>
        </ol>
      </Card>

      <Card title="Android phone or tablet">
        <ol className="list-decimal space-y-2 pl-5 text-sm">
          <li>
            Open this website in <strong>Chrome</strong>.
          </li>
          <li>
            Tap the <strong>three dots</strong> in the top-right corner.
          </li>
          <li>
            Tap <strong>Add to home screen</strong> (it may say <strong>Install app</strong>).
          </li>
          <li>
            Tap <strong>Install</strong> or <strong>Add</strong>. The CLG icon appears on your home screen.
          </li>
        </ol>
      </Card>

      <Card title="Windows or Mac computer">
        <ol className="list-decimal space-y-2 pl-5 text-sm">
          <li>
            Open this website in <strong>Chrome</strong> or <strong>Microsoft Edge</strong>.
          </li>
          <li>
            Click the <strong>install icon</strong> at the right end of the address bar (a screen with a down arrow),
            or open the browser menu and choose <strong>Install CLG</strong>.
          </li>
          <li>
            Click <strong>Install</strong>. CLG opens in its own window, and you can pin it to your taskbar or dock.
          </li>
        </ol>
      </Card>

      <p className="text-sm">
        Stuck? Contact CLG and we&apos;ll walk you through it. <TextLink href="/">Back to CLG</TextLink>
      </p>
    </Page>
  );
}
