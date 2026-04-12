"use client";

import { useState, useEffect, useRef } from "react";

type Label = { id: string; name: string; color: string };

interface LabelPickerProps {
  articleId: string;
  currentLabelIds: string[];
  onLabelsChanged: () => void;
  compact?: boolean;
}

export default function LabelPicker({ articleId, currentLabelIds, onLabelsChanged, compact }: LabelPickerProps) {
  const [open, setOpen] = useState(false);
  const [labels, setLabels] = useState<Label[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set(currentLabelIds));
  const [newName, setNewName] = useState("");
  const [newColor, setNewColor] = useState("#7B6AEE");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editColor, setEditColor] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setSelected(new Set(currentLabelIds));
  }, [currentLabelIds]);

  useEffect(() => {
    if (open) {
      fetch("/api/labels")
        .then((r) => r.json())
        .then(setLabels);
    }
  }, [open]);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
        setEditingId(null);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  async function toggle(labelId: string) {
    const next = new Set(selected);
    if (next.has(labelId)) next.delete(labelId);
    else next.add(labelId);
    setSelected(next);
    await fetch(`/api/articles/${articleId}/labels`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ labelIds: [...next] }),
    });
    onLabelsChanged();
  }

  async function createLabel(e: React.FormEvent) {
    e.preventDefault();
    if (!newName.trim()) return;
    const res = await fetch("/api/labels", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: newName.trim(), color: newColor }),
    });
    const label = await res.json();
    setLabels([...labels, label]);
    setNewName("");
    await toggle(label.id);
  }

  function startEdit(label: Label) {
    setEditingId(label.id);
    setEditName(label.name);
    setEditColor(label.color);
  }

  async function saveEdit(labelId: string) {
    if (!editName.trim()) return;
    const res = await fetch(`/api/labels/${labelId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: editName.trim(), color: editColor }),
    });
    const updated = await res.json();
    setLabels(labels.map((l) => (l.id === labelId ? updated : l)));
    setEditingId(null);
    onLabelsChanged();
  }

  async function deleteLabel(labelId: string) {
    await fetch(`/api/labels/${labelId}`, { method: "DELETE" });
    setLabels(labels.filter((l) => l.id !== labelId));
    const next = new Set(selected);
    if (next.has(labelId)) {
      next.delete(labelId);
      setSelected(next);
    }
    onLabelsChanged();
  }

  return (
    <div ref={ref} className="relative">
      {compact ? (
        <button
          onClick={() => setOpen(!open)}
          title="Edit labels"
          className="flex h-5 w-5 items-center justify-center rounded text-neutral-300 transition-colors hover:bg-cream-dark hover:text-neutral-500"
        >
          <svg className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M4.5 2A2.5 2.5 0 0 0 2 4.5v3.879a2.5 2.5 0 0 0 .732 1.767l7.5 7.5a2.5 2.5 0 0 0 3.536 0l3.879-3.879a2.5 2.5 0 0 0 0-3.536l-7.5-7.5A2.5 2.5 0 0 0 8.379 2H4.5ZM5 6a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clipRule="evenodd" />
          </svg>
        </button>
      ) : (
        <button
          onClick={() => setOpen(!open)}
          className="flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-neutral-400 transition-colors hover:bg-cream-dark hover:text-neutral-600"
        >
          Labels
          <svg className={`h-3 w-3 transition-transform ${open ? "rotate-180" : ""}`} viewBox="0 0 20 20" fill="currentColor">
            <path fillRule="evenodd" d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z" clipRule="evenodd" />
          </svg>
        </button>
      )}

      {open && (
        <div className="absolute left-0 top-full z-40 mt-1 w-64 rounded-lg border border-cream-dark bg-white p-2 shadow-lg">
          {labels.length === 0 && (
            <p className="px-2 py-1 text-xs text-neutral-400">No labels yet</p>
          )}
          {labels.map((l) =>
            editingId === l.id ? (
              <div key={l.id} className="flex items-center gap-1 rounded px-2 py-1">
                <input
                  type="color"
                  value={editColor}
                  onChange={(e) => setEditColor(e.target.value)}
                  className="h-7 w-7 shrink-0 cursor-pointer rounded border-0 p-0"
                />
                <input
                  type="text"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") saveEdit(l.id);
                    if (e.key === "Escape") setEditingId(null);
                  }}
                  autoFocus
                  className="min-w-0 flex-1 rounded border border-cream-dark px-1.5 py-0.5 text-sm focus:border-brand-purple focus:outline-none"
                />
                <button
                  onClick={() => saveEdit(l.id)}
                  className="shrink-0 rounded bg-brand-purple px-1.5 py-0.5 text-[10px] font-medium text-white hover:brightness-110"
                >
                  Save
                </button>
                <button
                  onClick={() => deleteLabel(l.id)}
                  className="shrink-0 text-[10px] text-brand-orange hover:underline"
                >
                  Delete
                </button>
                <button
                  onClick={() => setEditingId(null)}
                  className="shrink-0 text-[10px] text-neutral-400 hover:text-neutral-600"
                >
                  ✕
                </button>
              </div>
            ) : (
              <div key={l.id} className="group flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 hover:bg-cream/60">
                <label className="flex flex-1 cursor-pointer items-center gap-2">
                  <input
                    type="checkbox"
                    checked={selected.has(l.id)}
                    onChange={() => toggle(l.id)}
                    className="rounded"
                  />
                  <span className="h-3 w-3 shrink-0 rounded-full" style={{ backgroundColor: l.color }} />
                  <span className="text-sm text-neutral-700">{l.name}</span>
                </label>
                <button
                  onClick={(e) => { e.stopPropagation(); startEdit(l); }}
                  title="Edit label"
                  className="invisible text-neutral-300 transition-colors hover:text-neutral-600 group-hover:visible"
                >
                  <svg className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                    <path d="M2.695 14.763l-1.262 3.154a.5.5 0 0 0 .65.65l3.155-1.262a4 4 0 0 0 1.343-.885L17.5 5.5a2.121 2.121 0 0 0-3-3L3.58 13.42a4 4 0 0 0-.885 1.343Z" />
                  </svg>
                </button>
              </div>
            )
          )}
          <form onSubmit={createLabel} className="mt-2 flex gap-1 border-t border-cream-dark/60 pt-2">
            <input
              type="color"
              value={newColor}
              onChange={(e) => setNewColor(e.target.value)}
              className="h-8 w-8 cursor-pointer rounded border-0 p-0"
            />
            <input
              type="text"
              placeholder="New label…"
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              className="flex-1 rounded border border-cream-dark px-2 py-1 text-sm focus:border-brand-purple focus:outline-none"
            />
            <button type="submit" className="rounded bg-brand-purple px-2 py-1 text-xs font-medium text-white hover:brightness-110">
              Add
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
