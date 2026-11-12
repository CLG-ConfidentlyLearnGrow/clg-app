// Summary: the guide for adding CLG to a home screen.
//
import { Card, Page, TextLink } from "@/components/ui"; // The card, page frame and link style.

// Step-by-step guide for adding CLG to a phone or computer home screen.
export default function InstallPage() {
  return ( // Shows:
    <Page title="Add CLG to your home screen">{/* a page titled "Add CLG to your home screen": */}
      <p className="text-sm">{/* an opening note: */}
        CLG works in your web browser, and you can add it to your home screen so it opens like any other app. It takes
        about a minute and you only do it once.{/* that it works in the browser and takes a minute. */}
      </p>{/* End of the note. */}

      <Card title="iPhone or iPad">{/* A card for iPhone or iPad: */}
        <ol className="list-decimal space-y-2 pl-5 text-sm">{/* a numbered list: */}
          <li>{/* step: */}
            Open this website in <strong>Safari</strong> (the blue compass icon).{/* open in Safari. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Tap the <strong>Share</strong> button: the square with an arrow pointing up. It&apos;s at the bottom of the
            screen on iPhone, or the top on iPad.{/* tap Share. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Scroll down and tap <strong>Add to Home Screen</strong>.{/* tap Add to Home Screen. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Tap <strong>Add</strong> in the top corner. The CLG icon appears on your home screen.{/* tap Add. */}
          </li>{/* (end of step) */}
        </ol>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Android phone or tablet">{/* A card for Android: */}
        <ol className="list-decimal space-y-2 pl-5 text-sm">{/* a numbered list: */}
          <li>{/* step: */}
            Open this website in <strong>Chrome</strong>.{/* open in Chrome. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Tap the <strong>three dots</strong> in the top-right corner.{/* tap the three dots. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Tap <strong>Add to home screen</strong> (it may say <strong>Install</strong> and{" "}{/* tap Add to home screen or Install, */}
            <strong>Create shortcut</strong>: choose <strong>Install</strong>).{/* choosing Install if asked. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Tap <strong>Install</strong> or <strong>Add</strong>. The CLG icon appears on your home screen.{/* tap Install or Add. */}
          </li>{/* (end of step) */}
        </ol>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <Card title="Windows or Mac computer">{/* A card for computers: */}
        <ol className="list-decimal space-y-2 pl-5 text-sm">{/* a numbered list: */}
          <li>{/* step: */}
            Open this website in <strong>Chrome</strong> or <strong>Microsoft Edge</strong>.{/* open in Chrome or Edge. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Click the <strong>install icon</strong> at the right end of the address bar (a screen with a down arrow),
            or open the browser menu and choose <strong>Install CLG</strong>.{/* click the install icon or menu item. */}
          </li>{/* (end of step) */}
          <li>{/* Step: */}
            Click <strong>Install</strong>. CLG opens in its own window, and you can pin it to your taskbar or dock.{/* click Install. */}
          </li>{/* (end of step) */}
        </ol>{/* End of the list. */}
      </Card>{/* End of the card. */}

      <p className="text-sm">{/* A closing line: */}
        Stuck? Contact CLG and we&apos;ll walk you through it. <TextLink href="/">Back to CLG</TextLink>{/* offering help, with a link back. */}
      </p>{/* End of the line. */}
    </Page> // End of the page.
  ); // End of what's shown.
} // End of InstallPage.
