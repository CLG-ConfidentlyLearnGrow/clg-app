"use client";

import { useActionState, useState, useTransition, type FormEvent } from "react";
import { addMaterials } from "@/app/actions/materials";
import { Button, FormMessage, Select, TextArea } from "@/components/ui";
import { initialFormState, type FormState } from "@/lib/forms";
import {
  MATERIAL_KINDS,
  MATERIAL_KIND_NAMES,
  MAX_SOURCE_BYTES,
  MAX_VIEW_BYTES,
  SOURCE_TYPES,
  titleFromFileName,
} from "@/lib/materials";
import { SUBJECT_SUGGESTIONS, YEAR_LEVELS } from "@/lib/students";
import { createBrowserSupabase } from "@/lib/supabase/browser";

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2.5 text-sm shadow-sm transition focus:border-brand focus:ring-2 focus:ring-teal-100 focus:outline-none";

type Row = { file: File; title: string; source: File | null };

function viewExt(file: File): "pdf" | "jpg" | "png" | null {
  const name = file.name.toLowerCase();
  if (file.type === "application/pdf" || name.endsWith(".pdf")) return "pdf";
  if (file.type === "image/jpeg" || /\.jpe?g$/.test(name)) return "jpg";
  if (file.type === "image/png" || name.endsWith(".png")) return "png";
  return null;
}

// Add one or many materials at once. The files go straight from this
// browser to CLG's private file store; then the server checks each one and
// saves it as a draft. Everything chosen here (kind, subject, years) applies
// to every file; each can be changed afterwards.
export function UploadMaterialsForm() {
  const [state, formAction, saving] = useActionState(addMaterials, initialFormState);
  const [rows, setRows] = useState<Row[]>([]);
  const [local, setLocal] = useState<FormState>({});
  const [uploading, startUpload] = useTransition();
  const busy = saving || uploading;

  function choose(list: FileList | null) {
    const files = [...(list ?? [])];
    const bad = files.filter((f) => !viewExt(f));
    const big = files.filter((f) => viewExt(f) && f.size > MAX_VIEW_BYTES);
    setLocal(
      bad.length || big.length
        ? {
            error: [
              bad.length ? `Not added (not a PDF, JPG or PNG): ${bad.map((f) => f.name).join(", ")}. Save Word or PowerPoint files as PDF first; you can attach the original as the editable copy.` : "",
              big.length ? `Not added (over 4 MB): ${big.map((f) => f.name).join(", ")}. Save a smaller PDF and try again.` : "",
            ]
              .filter(Boolean)
              .join(" "),
          }
        : {},
    );
    setRows(
      files
        .filter((f) => viewExt(f) && f.size <= MAX_VIEW_BYTES)
        .slice(0, 20)
        .map((file) => ({ file, title: titleFromFileName(file.name), source: null })),
    );
  }

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    if (rows.length === 0) {
      setLocal({ error: "Choose at least one file." });
      return;
    }
    setLocal({});
    startUpload(async () => {
      const supabase = createBrowserSupabase();
      const store = supabase.storage.from("materials");
      const sent: { viewPath: string; fileName: string; title: string; sourcePath?: string; sourceName?: string }[] = [];
      for (const r of rows) {
        const ext = viewExt(r.file)!;
        const viewPath = `view/${crypto.randomUUID()}.${ext}`;
        const up = await store.upload(viewPath, r.file, { contentType: r.file.type || undefined, upsert: false });
        if (up.error) {
          setLocal({ error: `Couldn't upload ${r.file.name}. Check your connection and try again.` });
          await store.remove(sent.flatMap((s) => [s.viewPath, ...(s.sourcePath ? [s.sourcePath] : [])]));
          return;
        }
        const item: (typeof sent)[number] = { viewPath, fileName: r.file.name, title: r.title };
        if (r.source) {
          const sExt = r.source.name.toLowerCase().split(".").pop() ?? "";
          const sourcePath = `source/${crypto.randomUUID()}.${sExt}`;
          const sUp = await store.upload(sourcePath, r.source, { contentType: SOURCE_TYPES[sExt], upsert: false });
          if (!sUp.error) {
            item.sourcePath = sourcePath;
            item.sourceName = r.source.name;
          }
        }
        sent.push(item);
      }
      form.set("files_json", JSON.stringify(sent));
      formAction(form);
      setRows([]);
      (e.target as HTMLFormElement).reset();
    });
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <FormMessage state={local.error ? local : state} />

      <label className="block space-y-1">
        <span className="text-sm font-medium text-zinc-800">Files tutors will open</span>
        <input
          type="file"
          multiple
          accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
          onChange={(e) => choose(e.target.files)}
          className={inputClass}
        />
        <span className="block text-xs text-zinc-500">
          PDF, JPG or PNG, under 4 MB each, up to 20 at a time. Tutors get a copy with their name on every page.
        </span>
      </label>

      {rows.length > 0 && (
        <ul className="space-y-3 rounded-xl bg-zinc-50 p-3">
          {rows.map((r, i) => (
            <li key={`${r.file.name}-${i}`} className="space-y-2 rounded-lg bg-white p-3 shadow-sm">
              <label className="block space-y-1">
                <span className="text-xs text-zinc-500">Title for {r.file.name}</span>
                <input
                  value={r.title}
                  maxLength={200}
                  onChange={(e) => setRows((prev) => prev.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))}
                  className={inputClass}
                />
              </label>
              <label className="block space-y-1">
                <span className="text-xs text-zinc-500">Editable original (optional, admins only): Word, PowerPoint, Excel</span>
                <input
                  type="file"
                  accept=".docx,.pptx,.xlsx,.doc,.ppt,.xls,.pdf"
                  onChange={(e) => {
                    const f = e.target.files?.[0] ?? null;
                    if (f && f.size > MAX_SOURCE_BYTES) {
                      setLocal({ error: `${f.name} is over 50 MB, so it wasn't added.` });
                      return;
                    }
                    setRows((prev) => prev.map((x, j) => (j === i ? { ...x, source: f } : x)));
                  }}
                  className="text-xs"
                />
              </label>
            </li>
          ))}
        </ul>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <Select label="Kind" name="kind" defaultValue="worksheet">
          {MATERIAL_KINDS.map((k) => (
            <option key={k} value={k}>
              {MATERIAL_KIND_NAMES[k]}
            </option>
          ))}
        </Select>
        <label className="block space-y-1">
          <span className="text-sm font-medium text-zinc-800">Subject</span>
          <input name="subject" list="material-subjects" required className={inputClass} placeholder="For example General Maths" />
          <datalist id="material-subjects">
            {SUBJECT_SUGGESTIONS.map((s) => (
              <option key={s} value={s} />
            ))}
          </datalist>
          <span className="block text-xs text-zinc-500">Use the same name tutors use in &ldquo;What you teach&rdquo;.</span>
        </label>
        <Select label="Suits from" name="from_level" defaultValue="Year 5">
          {YEAR_LEVELS.map((y) => (
            <option key={y}>{y}</option>
          ))}
        </Select>
        <Select label="Suits up to" name="to_level" defaultValue="Year 5">
          {YEAR_LEVELS.map((y) => (
            <option key={y}>{y}</option>
          ))}
        </Select>
      </div>
      <TextArea
        label="Note for tutors (optional)"
        name="description"
        maxLength={1000}
        hint="What it is and how to use it, for example: 20 minutes, use after introducing equivalent fractions."
      />
      <Button type="submit" disabled={busy}>
        {uploading ? "Uploading…" : saving ? "Checking files…" : "Upload and save as drafts"}
      </Button>
    </form>
  );
}
