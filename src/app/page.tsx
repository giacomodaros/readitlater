"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { useSearchParams } from "next/navigation";
import AddArticleForm from "@/components/AddArticleForm";
import ArticleCard from "@/components/ArticleCard";
import ArticleReader from "@/components/ArticleReader";
import LabelPicker from "@/components/LabelPicker";
import LabelBadge from "@/components/LabelBadge";
import clsx from "clsx";

type Label = { id: string; name: string; color: string };
type Highlight = {
  id: string;
  text: string;
  startOffset: number;
  endOffset: number;
  color: string;
  note: string | null;
};
type ArticleListItem = {
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
type FullArticle = {
  id: string;
  url: string;
  title: string;
  author: string | null;
  description: string | null;
  content: string;
  siteName: string | null;
  publishedAt: string | null;
  ttr: number | null;
  archived: boolean;
  labels: Label[];
  highlights: Highlight[];
};

export default function HomePage() {
  const searchParams = useSearchParams();
  const isArchiveView = searchParams.get("view") === "archive";

  const [articles, setArticles] = useState<ArticleListItem[]>([]);
  const [labels, setLabels] = useState<Label[]>([]);
  const [filterLabel, setFilterLabel] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [fullArticle, setFullArticle] = useState<FullArticle | null>(null);
  const [articleLoading, setArticleLoading] = useState(false);

  const fetchArticles = useCallback(async (searchQuery?: string) => {
    const params = new URLSearchParams();
    params.set("archived", String(isArchiveView));
    if (filterLabel) params.set("labelId", filterLabel);
    const q = searchQuery ?? search;
    if (q.trim()) params.set("search", q.trim());
    const res = await fetch(`/api/articles?${params}`);
    const data: ArticleListItem[] = await res.json();
    setArticles(data);
    setLoading(false);
    return data;
  }, [isArchiveView, filterLabel, search]);

  const fetchLabels = useCallback(async () => {
    const res = await fetch("/api/labels");
    setLabels(await res.json());
  }, []);

  const fetchFullArticle = useCallback(async (id: string) => {
    setArticleLoading(true);
    const res = await fetch(`/api/articles/${id}`);
    if (res.ok) {
      setFullArticle(await res.json());
    }
    setArticleLoading(false);
  }, []);

  // On view change, reset and auto-select first article
  useEffect(() => {
    setLoading(true);
    setSearch("");
    setFilterLabel(null);
    setSelectedId(null);
    setFullArticle(null);
    (async () => {
      const data = await fetchArticles("");
      fetchLabels();
      if (data.length > 0) {
        setSelectedId(data[0].id);
        fetchFullArticle(data[0].id);
      }
    })();
  }, [isArchiveView]); // eslint-disable-line react-hooks/exhaustive-deps

  // On filter change, re-fetch and auto-select first
  useEffect(() => {
    setLoading(true);
    (async () => {
      const data = await fetchArticles();
      if (data.length > 0) {
        setSelectedId(data[0].id);
        fetchFullArticle(data[0].id);
      } else {
        setSelectedId(null);
        setFullArticle(null);
      }
    })();
  }, [filterLabel]); // eslint-disable-line react-hooks/exhaustive-deps

  function handleSearchChange(value: string) {
    setSearch(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(async () => {
      const data = await fetchArticles(value);
      if (data.length > 0) {
        setSelectedId(data[0].id);
        fetchFullArticle(data[0].id);
      } else {
        setSelectedId(null);
        setFullArticle(null);
      }
    }, 250);
  }

  function handleSelectArticle(id: string) {
    setSelectedId(id);
    fetchFullArticle(id);
    // Also mark the article as read in the list
    setArticles((prev) =>
      prev.map((a) => (a.id === id && !a.readAt ? { ...a, readAt: new Date().toISOString() } : a))
    );
  }

  async function handleArchiveToggle() {
    if (!fullArticle) return;
    await fetch(`/api/articles/${fullArticle.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ archived: !fullArticle.archived }),
    });
    const data = await fetchArticles();
    if (data.length > 0) {
      setSelectedId(data[0].id);
      fetchFullArticle(data[0].id);
    } else {
      setSelectedId(null);
      setFullArticle(null);
    }
  }

  async function handleDelete() {
    if (!fullArticle || !confirm("Delete this article?")) return;
    await fetch(`/api/articles/${fullArticle.id}`, { method: "DELETE" });
    const data = await fetchArticles();
    if (data.length > 0) {
      setSelectedId(data[0].id);
      fetchFullArticle(data[0].id);
    } else {
      setSelectedId(null);
      setFullArticle(null);
    }
  }

  async function handleArticleAdded() {
    const data = await fetchArticles();
    if (data.length > 0) {
      setSelectedId(data[0].id);
      fetchFullArticle(data[0].id);
    }
  }

  const emptyMessage = search.trim()
    ? "No articles match your search."
    : isArchiveView
      ? "No archived articles."
      : "No articles yet. Paste a URL above to get started.";

  return (
    <div className="flex h-full">
      {/* Left pane: article list */}
      <div className="flex w-[380px] shrink-0 flex-col border-r border-cream-dark">
        {/* Header with search and add form */}
        <div className="border-b border-cream-dark p-3">
          <div className="flex items-center gap-2">
            <h2 className="shrink-0 text-sm font-semibold text-neutral-700">
              {isArchiveView ? "Archive" : "To Read"}
            </h2>
            <div className="relative flex-1">
              <svg
                className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-neutral-400"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth={2}
              >
                <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z" />
              </svg>
              <input
                type="text"
                placeholder="Search..."
                value={search}
                onChange={(e) => handleSearchChange(e.target.value)}
                className="w-full rounded-md border border-cream-dark bg-cream py-1.5 pl-8 pr-3 text-xs text-neutral-900 placeholder:text-neutral-400 focus:border-brand-purple focus:outline-none"
              />
            </div>
          </div>

          {/* Label filters */}
          {labels.length > 0 && (
            <div className="mt-2 flex flex-wrap items-center gap-1.5">
              <button
                onClick={() => setFilterLabel(null)}
                className={clsx(
                  "rounded-full border px-2 py-0.5 text-[10px] font-medium transition-colors",
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

          {/* Add article form (only on To Read view) */}
          {!isArchiveView && (
            <div className="mt-2">
              <AddArticleForm onAdded={handleArticleAdded} />
            </div>
          )}
        </div>

        {/* Article list */}
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="py-12 text-center text-sm text-neutral-400">Loading...</div>
          ) : articles.length === 0 ? (
            <div className="px-4 py-12 text-center text-sm text-neutral-400">{emptyMessage}</div>
          ) : (
            articles.map((a) => (
              <ArticleCard
                key={a.id}
                {...a}
                selected={a.id === selectedId}
                onClick={() => handleSelectArticle(a.id)}
              />
            ))
          )}
        </div>
      </div>

      {/* Right pane: article reader */}
      <div className="flex-1 overflow-y-auto">
        {articleLoading ? (
          <div className="py-20 text-center text-sm text-neutral-400">Loading article...</div>
        ) : fullArticle ? (
          <div className="px-8 py-6">
            {/* Toolbar */}
            <div className="mb-6 flex items-center justify-between">
              <div className="flex flex-wrap items-center gap-2">
                {fullArticle.labels.map((l) => (
                  <LabelBadge key={l.id} name={l.name} color={l.color} />
                ))}
                <LabelPicker
                  articleId={fullArticle.id}
                  currentLabelIds={fullArticle.labels.map((l) => l.id)}
                  onLabelsChanged={() => {
                    fetchFullArticle(fullArticle.id);
                    fetchArticles();
                  }}
                />
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={handleArchiveToggle}
                  className="rounded-md border border-cream-dark px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-cream-dark/50"
                >
                  {fullArticle.archived ? "Unarchive" : "Archive"}
                </button>
                <a
                  href={fullArticle.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded-md border border-cream-dark px-3 py-1.5 text-xs font-medium text-neutral-600 hover:bg-cream-dark/50"
                >
                  Original
                </a>
                <button
                  onClick={handleDelete}
                  className="rounded-md border border-brand-orange/30 px-3 py-1.5 text-xs font-medium text-brand-orange hover:bg-brand-orange-light"
                >
                  Delete
                </button>
              </div>
            </div>

            <ArticleReader
              articleId={fullArticle.id}
              content={fullArticle.content}
              title={fullArticle.title}
              author={fullArticle.author}
              siteName={fullArticle.siteName}
              publishedAt={fullArticle.publishedAt}
              ttr={fullArticle.ttr}
            />
          </div>
        ) : (
          <div className="flex h-full items-center justify-center">
            <p className="text-sm text-neutral-400">
              {articles.length === 0
                ? isArchiveView
                  ? "No archived articles yet."
                  : "Add an article to get started."
                : "Select an article to read."}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
