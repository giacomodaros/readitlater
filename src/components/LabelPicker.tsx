"use client";

import { useState, useEffect, useRef } from "react";

type Label = { id: string; name: string; color: string };

interface LabelPickerProps {
  articleId: string;
  currentLabelIds: string[];
  onLabelsChanged: () => void;
}

export default function LabelPicker({ articleId, currentLabelIds, onLabelsChanged }: LabelPickerProps) {
  const [open, setOpen] = useState(false);
  const [labels, setLabels] = useState<Label[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set(currentLabelIds));
  const [newName, setNewName] = useState("");
  const [newColor, setNewColor] = useState("#7B6AEE");
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
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
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

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="rounded-md border border-cream-dark px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-cream-dark/50"
      >
        Labels
      </button>
      {open && (
        <div className="absolute right-0 top-full z-40 mt-1 w-64 rounded-lg border border-cream-dark bg-white p-2 shadow-lg">
          {labels.length === 0 && (
            <p className="px-2 py-1 text-xs text-neutral-400">No labels yet</p>
          )}
          {labels.map((l) => (
            <label key={l.id} className="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 hover:bg-cream/60">
              <input
                type="checkbox"
                checked={selected.has(l.id)}
                onChange={() => toggle(l.id)}
                className="rounded"
              />
              <span
                className="h-3 w-3 rounded-full"
                style={{ backgroundColor: l.color }}
              />
              <span className="text-sm text-neutral-700">{l.name}</span>
            </label>
          ))}
          <form onSubmit={createLabel} className="mt-2 flex gap-1 border-t border-cream-dark/60 pt-2">
            <input
              type="color"
              value={newColor}
              onChange={(e) => setNewColor(e.target.value)}
              className="h-8 w-8 cursor-pointer rounded border-0 p-0"
            />
            <input
              type="text"
              placeholder="New label..."
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
