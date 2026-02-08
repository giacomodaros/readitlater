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
      <form onSubmit={handleSubmit} className="flex gap-2">
        <input
          type="url"
          placeholder="Paste an article URL..."
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          required
          className="flex-1 rounded-lg border-2 border-cream-dark bg-cream px-4 py-2.5 text-sm text-neutral-900 placeholder:text-neutral-400 focus:border-brand-purple focus:outline-none"
        />
        <button
          type="submit"
          disabled={loading}
          className="rounded-lg bg-brand-purple px-5 py-2.5 text-sm font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {loading ? "Saving..." : "Save"}
        </button>
      </form>
      {error && <p className="mt-2 text-sm text-brand-orange">{error}</p>}
    </div>
  );
}
