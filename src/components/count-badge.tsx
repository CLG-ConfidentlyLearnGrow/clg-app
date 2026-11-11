// A small number in a circle, for menus and tabs where something needs doing
// (e.g. "Matching 4"). Shows nothing when there's nothing to do. Screen
// readers hear "4 to do".
export function CountBadge({ n, className = "bg-zinc-700 text-white" }: { n: number | undefined; className?: string }) {
  if (!n) return null;
  return (
    <span className={`inline-flex min-w-5 items-center justify-center rounded-full px-1.5 text-xs leading-5 ${className}`}>
      {n}
      <span className="sr-only"> to do</span>
    </span>
  );
}
