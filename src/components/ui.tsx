import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";
import type { FormState } from "@/lib/forms";

export function Page({ title, intro, children }: { title: string; intro?: ReactNode; children: ReactNode }) {
  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-8 sm:py-12">
      <PageTitle title={title} intro={intro} />
      <div className="space-y-6">{children}</div>
    </main>
  );
}

export function PageTitle({ title, intro }: { title: string; intro?: ReactNode }) {
  return (
    <div className="mb-8">
      <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">{title}</h1>
      <div className="mt-3 h-1 w-12 rounded-full bg-brand" aria-hidden />
      {intro && <p className="mt-4 max-w-2xl text-zinc-600">{intro}</p>}
    </div>
  );
}

// A white panel. The title and any description sit together at the top so
// the panel's contents read as belonging to it.
export function Card({
  title,
  description,
  children,
}: {
  title?: string;
  description?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-zinc-200/80 bg-white p-6 shadow-[0_1px_3px_rgba(65,64,66,0.06),0_8px_24px_-12px_rgba(65,64,66,0.12)]">
      {(title || description) && (
        <header className="mb-5 border-b border-zinc-100 pb-4">
          {title && <h2 className="text-lg font-semibold tracking-tight">{title}</h2>}
          {description && <p className="mt-1 text-sm text-zinc-600">{description}</p>}
        </header>
      )}
      {children}
    </section>
  );
}

// A heading inside a card, for a smaller part of it.
export function SubHeading({ children }: { children: ReactNode }) {
  return (
    <h3 className="mt-8 mb-3 flex items-center gap-2 text-sm font-semibold text-zinc-800 first:mt-0">
      <span className="h-4 w-1 rounded-full bg-brand" aria-hidden />
      {children}
    </h3>
  );
}

// Shown when a list or table has nothing in it yet.
export function Empty({ children }: { children: ReactNode }) {
  return <p className="rounded-xl bg-zinc-50 px-4 py-3 text-sm text-zinc-500">{children}</p>;
}

// A simple table: headings in a tinted band, rows separated by thin lines.
export function Table({ headings, children }: { headings: string[]; children: ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-zinc-200">
      <table className="w-full text-left text-sm">
        <thead className="bg-zinc-50 text-xs uppercase tracking-wide text-zinc-600">
          <tr>
            {headings.map((h) => (
              <th key={h} scope="col" className="px-4 py-2.5 font-semibold">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-100 [&_td]:px-4 [&_td]:py-2.5">{children}</tbody>
      </table>
    </div>
  );
}

export function Field({
  label,
  hint,
  ...input
}: { label: string; hint?: string } & ComponentProps<"input">) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      <input
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
        {...input}
      />
      {hint && <span className="block text-xs text-zinc-500">{hint}</span>}
    </label>
  );
}

export function TextArea({
  label,
  hint,
  ...input
}: { label: string; hint?: string } & ComponentProps<"textarea">) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      <textarea
        rows={3}
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
        {...input}
      />
      {hint && <span className="block text-xs text-zinc-500">{hint}</span>}
    </label>
  );
}

export function Select({
  label,
  children,
  ...select
}: { label: string } & ComponentProps<"select">) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-medium text-zinc-800">{label}</span>
      <select
        className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none"
        {...select}
      >
        {children}
      </select>
    </label>
  );
}

export function Button({ children, ...props }: ComponentProps<"button">) {
  return (
    <button
      className="shrink-0 rounded-full bg-teal-700 px-5 py-2.5 text-sm font-medium whitespace-nowrap text-white shadow-sm transition hover:bg-teal-800 hover:shadow disabled:opacity-50"
      {...props}
    >
      {children}
    </button>
  );
}

export function FormMessage({ state }: { state: FormState }) {
  if (state.error) {
    return (
      <p role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
        {state.error}
      </p>
    );
  }
  if (state.message) {
    return (
      <p role="status" className="rounded-xl border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900">
        {state.message}
      </p>
    );
  }
  return null;
}

export function TextLink(props: ComponentProps<typeof Link>) {
  return <Link className="font-medium text-teal-700 underline decoration-teal-300 underline-offset-4 transition hover:decoration-teal-700" {...props} />;
}
