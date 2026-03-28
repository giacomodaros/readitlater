"use client";

import { useState } from "react";

type Status = "idle" | "fetching" | "parsing" | "saving" | "done";

const STATUS_LABELS: Record<Status, string> = {
  idle: "",
  fetching: "Fetching article…",
  parsing: "Extracting content…",
  saving: "Saving…",
  done: "Saved!",
};

export default function AddArticleForm({ onAdded }: { onAdded: () => void }) {
  const [url, setUrl] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);

  const loading = status !== "idle" && status !== "done";

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!url.trim()) return;
    setError(null);

    setStatus("fetching");
    await new Promise((r) => setTimeout(r, 600));
    setStatus("parsing");
    await new Promise((r) => setTimeout(r, 400));
    setStatus("saving");

    try {
      const res = await fetch("/api/articles", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: url.trim() }),
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || "Failed to save article");
      }
      setStatus("done");
      setUrl("");
      onAdded();
      setTimeout(() => setStatus("idle"), 1500);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong");
      setStatus("idle");
    }
  }

  return (
    <div>
      <form onSubmit={handleSubmit} className="flex gap-1.5">
        <input
          type="url"
          placeholder="Paste URL…"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          required
          disabled={loading}
          className="min-w-0 flex-1 rounded-md border border-cream-dark bg-cream px-3 py-1.5 text-xs text-neutral-900 placeholder:text-neutral-400 focus:border-brand-purple focus:outline-none disabled:opacity-60"
        />
        <button
          type="submit"
          disabled={loading}
          className="shrink-0 rounded-md bg-brand-purple px-3 py-1.5 text-xs font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {loading ? (
            <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24" fill="none">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
            </svg>
          ) : (
            "Save"
          )}
        </button>
      </form>
      {loading && (
        <p className="mt-1.5 text-[11px] text-neutral-400">{STATUS_LABELS[status]}</p>
      )}
      {status === "done" && (
        <p className="mt-1.5 text-[11px] text-brand-green">Saved!</p>
      )}
      {error && <p className="mt-1.5 text-[11px] text-brand-orange">{error}</p>}
    </div>
  );
}
