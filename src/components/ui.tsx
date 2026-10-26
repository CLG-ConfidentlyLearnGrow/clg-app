import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";
import type { FormState } from "@/lib/forms";

export function Page({ title, children }: { title: string; children: ReactNode }) {
  return (
    <main className="mx-auto w-full max-w-3xl px-4 py-10">
      <h1 className="mb-6 text-2xl font-semibold">{title}</h1>
      <div className="space-y-6">{children}</div>
    </main>
  );
}

export function Card({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section className="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
      {title && <h2 className="mb-3 text-lg font-semibold">{title}</h2>}
      {children}
    </section>
  );
}

export function Field({
  label,
  hint,
  ...input
}: { label: string; hint?: string } & ComponentProps<"input">) {
  return (
    <label className="block space-y-1">
      <span className="text-sm font-medium">{label}</span>
      <input
        className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm"
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
      <span className="text-sm font-medium">{label}</span>
      <textarea
        rows={3}
        className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm"
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
      <span className="text-sm font-medium">{label}</span>
      <select
        className="w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm"
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
      className="rounded-md bg-teal-700 px-4 py-2 text-sm font-medium text-white hover:bg-teal-800 disabled:opacity-50"
      {...props}
    >
      {children}
    </button>
  );
}

export function FormMessage({ state }: { state: FormState }) {
  if (state.error) {
    return (
      <p role="alert" className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-800">
        {state.error}
      </p>
    );
  }
  if (state.message) {
    return (
      <p role="status" className="rounded-md bg-teal-50 px-3 py-2 text-sm text-teal-900">
        {state.message}
      </p>
    );
  }
  return null;
}

export function TextLink(props: ComponentProps<typeof Link>) {
  return <Link className="text-teal-700 underline" {...props} />;
}
