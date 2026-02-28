"use client";

import { useState } from "react";

export default function AddArticleForm({ onAdded }: { onAdded: () => void }) {
  const [url, setUrl] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!url.trim()) return;
    setLoading(true);
    setError(null);

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
      setUrl("");
      onAdded();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <form onSubmit={handleSubmit} className="flex gap-1.5">
        <input
          type="url"
          placeholder="Paste URL..."
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          required
          className="min-w-0 flex-1 rounded-md border border-cream-dark bg-cream px-3 py-1.5 text-xs text-neutral-900 placeholder:text-neutral-400 focus:border-brand-purple focus:outline-none"
        />
        <button
          type="submit"
          disabled={loading}
          className="shrink-0 rounded-md bg-brand-purple px-3 py-1.5 text-xs font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {loading ? "..." : "Save"}
        </button>
      </form>
      {error && <p className="mt-2 text-sm text-brand-orange">{error}</p>}
    </div>
  );
}
