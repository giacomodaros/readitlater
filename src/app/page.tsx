"use client";

import { useEffect, useState, useCallback, Fragment, useRef } from "react";
import { useSearchParams } from "next/navigation";
import AddArticleForm from "@/components/AddArticleForm";
import ArticleCard from "@/components/ArticleCard";
import LabelBadge from "@/components/LabelBadge";
import clsx from "clsx";

type Label = { id: string; name: string; color: string };
type Article = {
  id: string;
  title: string;
  author: string | null;
  description: string | null;
  siteName: string | null;
  image: string | null;
  favicon: string | null;
  publishedAt: string | null;
  archived: boolean;
  readAt: string | null;
  ttr: number | null;
  createdAt: string;
  labels: Label[];
  _count: { highlights: number };
};

const STRIPE_COLORS = ["bg-brand-purple", "bg-brand-green", "bg-brand-blue", "bg-brand-orange"];

function StripeDivider() {
  return (
    <div className="flex gap-[2px] px-3 py-[2px]">
      {STRIPE_COLORS.map((c) => (
        <div key={c} className={`h-[2px] flex-1 rounded-full ${c} opacity-25`} />
      ))}
    </div>
  );
}

export default function HomePage() {
  const searchParams = useSearchParams();
  const isArchiveView = searchParams.get("view") === "archive";

  const [articles, setArticles] = useState<Article[]>([]);
  const [labels, setLabels] = useState<Label[]>([]);
  const [filterLabel, setFilterLabel] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);

  const fetchArticles = useCallback(async (searchQuery?: string) => {
    const params = new URLSearchParams();
    params.set("archived", String(isArchiveView));
    if (filterLabel) params.set("labelId", filterLabel);
    const q = searchQuery ?? search;
    if (q.trim()) params.set("search", q.trim());
    const res = await fetch(`/api/articles?${params}`);
    setArticles(await res.json());
    setLoading(false);
  }, [isArchiveView, filterLabel, search]);

  const fetchLabels = useCallback(async () => {
    const res = await fetch("/api/labels");
    setLabels(await res.json());
  }, []);

  useEffect(() => {
    setLoading(true);
    setSearch("");
    setFilterLabel(null);
    fetchArticles("");
    fetchLabels();
  }, [isArchiveView]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    setLoading(true);
    fetchArticles();
  }, [filterLabel]); // eslint-disable-line react-hooks/exhaustive-deps

  function handleSearchChange(value: string) {
    setSearch(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      fetchArticles(value);
    }, 250);
  }

  async function handleArchiveToggle(id: string, archived: boolean) {
    await fetch(`/api/articles/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ archived }),
    });
    fetchArticles();
  }

  async function handleDelete(id: string) {
    if (!confirm("Delete this article?")) return;
    await fetch(`/api/articles/${id}`, { method: "DELETE" });
    fetchArticles();
  }

  const emptyMessage = search.trim()
    ? "No articles match your search."
    : isArchiveView
      ? "No archived articles."
      : "No articles yet. Paste a URL above to get started.";

  return (
    <div className="space-y-5">
      {!isArchiveView && <AddArticleForm onAdded={() => fetchArticles()} />}

      <div className="flex items-center justify-between gap-4">
        <h2 className="shrink-0 text-lg font-semibold text-neutral-800">
          {isArchiveView ? "Archive" : "To Read"}
        </h2>

        {/* Search */}
        <div className="relative max-w-xs flex-1">
          <svg
            className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-neutral-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z" />
          </svg>
          <input
            type="text"
            placeholder="Search by title or author..."
            value={search}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="w-full rounded-lg border-2 border-cream-dark bg-cream py-1.5 pl-9 pr-3 text-sm text-neutral-900 placeholder:text-neutral-400 focus:border-brand-purple focus:outline-none"
          />
        </div>
      </div>

      {/* Label filters — shown on both views when labels exist */}
      {labels.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <button
            onClick={() => setFilterLabel(null)}
            className={clsx(
              "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
              !filterLabel
                ? "border-brand-purple bg-brand-purple-light text-brand-purple"
                : "border-cream-dark text-neutral-500 hover:bg-cream-dark/50"
            )}
          >
            All
          </button>
          {labels.map((l) => (
            <button
              key={l.id}
              onClick={() => setFilterLabel(filterLabel === l.id ? null : l.id)}
            >
              <LabelBadge name={l.name} color={l.color} />
            </button>
          ))}
        </div>
      )}

      {loading ? (
        <div className="py-20 text-center text-neutral-400">Loading...</div>
      ) : articles.length === 0 ? (
        <div className="py-20 text-center text-neutral-400">{emptyMessage}</div>
      ) : (
        <div>
          {articles.map((a, i) => (
            <Fragment key={a.id}>
              {i > 0 && <StripeDivider />}
              <ArticleCard
                {...a}
                onArchiveToggle={handleArchiveToggle}
                onDelete={handleDelete}
              />
            </Fragment>
          ))}
        </div>
      )}
    </div>
  );
}
