import Image from "next/image";
import Link from "next/link";
import { TextLink } from "@/components/ui";

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col items-center px-4 py-12 text-center sm:py-20">
      <Image
        src="/brand/clg-logo-transparent.png"
        alt="CLG Tutoring"
        width={477}
        height={280}
        priority
        className="h-auto w-72 sm:w-96"
      />
      <p className="mt-4 text-lg text-zinc-600">Confidently Learn &amp; Grow</p>
      <p className="mt-6 max-w-xl text-zinc-700">
        Tutoring, homework and learning support, all in one place for students, parents and tutors.
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Link
          href="/login"
          className="rounded-full bg-teal-700 px-6 py-3 text-sm font-medium text-white shadow-sm transition hover:bg-teal-800"
        >
          Sign in
        </Link>
        <Link
          href="/signup"
          className="rounded-full border border-teal-700 bg-white px-6 py-3 text-sm font-medium text-teal-800 transition hover:bg-teal-50"
        >
          Create an account
        </Link>
      </div>
      <p className="mt-8 text-sm">
        <TextLink href="/install">Add CLG to your home screen</TextLink>
      </p>
    </main>
  );
}
