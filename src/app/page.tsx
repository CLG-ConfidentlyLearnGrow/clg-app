// Summary: the app's front page, with sign-in and sign-up buttons.
//
import Image from "next/image"; // Shows images at the right size.
import Link from "next/link"; // Links between pages without a full reload.
import { TextLink } from "@/components/ui"; // The link style.

// Shows the front page.
export default function Home() {
  return ( // Shows:
    <main className="mx-auto flex w-full max-w-3xl flex-col items-center px-4 py-12 text-center sm:py-20">{/* a centred column: */}
      <Image // the logo:
        src="/brand/clg-logo-book.png" // its file,
        alt="CLG Tutoring" // its description for screen readers,
        width={453} // its width,
        height={256} // its height,
        priority // loaded first,
        className="h-auto w-72 sm:w-96" // sized for phones and bigger screens.
      />{/* (end of the logo) */}
      <p className="mt-4 text-lg text-zinc-600">Confidently Learn &amp; Grow</p>{/* The tagline, */}
      <p className="mt-6 max-w-xl text-zinc-700">{/* a short line: */}
        Tutoring, homework and learning support, all in one place for students, parents and tutors.{/* about what CLG offers. */}
      </p>{/* End of the line. */}
      <div className="mt-8 flex flex-wrap justify-center gap-3">{/* A row of buttons: */}
        <Link // a link:
          href="/login" // to sign in,
          className="rounded-full bg-teal-700 px-6 py-3 text-sm font-medium text-white shadow-sm transition hover:bg-teal-800" // styled as a filled button.
        >{/* (end of its settings) */}
          Sign in{/* "Sign in". */}
        </Link>{/* End of the link. */}
        <Link // A link:
          href="/signup" // to create an account,
          className="rounded-full border border-teal-700 bg-white px-6 py-3 text-sm font-medium text-teal-800 transition hover:bg-teal-50" // styled as an outlined button.
        >{/* (end of its settings) */}
          Create an account{/* "Create an account". */}
        </Link>{/* End of the link. */}
      </div>{/* End of the row. */}
      <p className="mt-8 text-sm">{/* A small line: */}
        <TextLink href="/install">Add CLG to your home screen</TextLink>{/* with a link to install the app. */}
      </p>{/* End of the line. */}
    </main> // End of the column.
  ); // End of what's shown.
} // End of Home.
