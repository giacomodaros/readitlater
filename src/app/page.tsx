"use client";

import { useEffect, useState, useCallback, Fragment } from "react";
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
  const [articles, setArticles] = useState<Article[]>([]);
  const [labels, setLabels] = useState<Label[]>([]);
  const [filterLabel, setFilterLabel] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [loading, setLoading] = useState(true);

  const fetchArticles = useCallback(async () => {
    const params = new URLSearchParams();
    params.set("archived", String(showArchived));
    if (filterLabel) params.set("labelId", filterLabel);
    const res = await fetch(`/api/articles?${params}`);
    setArticles(await res.json());
    setLoading(false);
  }, [showArchived, filterLabel]);

  const fetchLabels = useCallback(async () => {
    const res = await fetch("/api/labels");
    setLabels(await res.json());
  }, []);

  useEffect(() => {
    fetchArticles();
    fetchLabels();
  }, [fetchArticles, fetchLabels]);

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

  return (
    <div className="space-y-6">
      <AddArticleForm onAdded={fetchArticles} />

      <div className="flex flex-wrap items-center gap-2">
        <button
          onClick={() => setShowArchived(!showArchived)}
          className={clsx(
            "rounded-full border px-3 py-1 text-xs font-medium transition-colors",
            showArchived
              ? "border-brand-purple bg-brand-purple-light text-brand-purple"
              : "border-cream-dark text-neutral-500 hover:bg-cream-dark/50"
          )}
        >
          {showArchived ? "Showing archived" : "Show archived"}
        </button>
        <span className="text-xs text-cream-dark">|</span>
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
          <button key={l.id} onClick={() => setFilterLabel(l.id)}>
            <LabelBadge name={l.name} color={l.color} />
          </button>
        ))}
      </div>

      {loading ? (
        <div className="py-20 text-center text-neutral-400">Loading...</div>
      ) : articles.length === 0 ? (
        <div className="py-20 text-center text-neutral-400">
          No articles yet. Paste a URL above to get started.
        </div>
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
