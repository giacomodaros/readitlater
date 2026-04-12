"use client";

import { useEffect, useState, useCallback, useRef, Suspense } from "react";
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
  notionPageId: string | null;
  labels: Label[];
  highlights: Highlight[];
};

const SORT_OPTIONS = [
  { value: "newest", label: "Newest first" },
  { value: "oldest", label: "Oldest first" },
  { value: "ttr", label: "Shortest read" },
  { value: "published", label: "Published date" },
];

function HomePageContent() {
  const searchParams = useSearchParams();
  const isArchiveView = searchParams.get("view") === "archive";

  const [articles, setArticles] = useState<ArticleListItem[]>([]);
  const [labels, setLabels] = useState<Label[]>([]);
  const [filterLabel, setFilterLabel] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState("newest");
  const [loading, setLoading] = useState(true);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(null);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [fullArticle, setFullArticle] = useState<FullArticle | null>(null);
  const [articleLoading, setArticleLoading] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [notionSyncing, setNotionSyncing] = useState(false);
  const [fontSize, setFontSize] = useState<"sm" | "md" | "lg">(() => {
    if (typeof window !== "undefined") {
      return (localStorage.getItem("reader-font-size") as "sm" | "md" | "lg") || "md";
    }
    return "md";
  });

  // UI state
  const [showAddForm, setShowAddForm] = useState(false);
  const [showSortMenu, setShowSortMenu] = useState(false);
  const [overflowOpen, setOverflowOpen] = useState(false);

  const scrollPositions = useRef<Record<string, number>>({});
  const readerPaneRef = useRef<HTMLDivElement>(null);
  const sortMenuRef = useRef<HTMLDivElement>(null);
  const overflowMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    localStorage.setItem("reader-font-size", fontSize);
  }, [fontSize]);

  // Close menus on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (sortMenuRef.current && !sortMenuRef.current.contains(e.target as Node)) setShowSortMenu(false);
      if (overflowMenuRef.current && !overflowMenuRef.current.contains(e.target as Node)) setOverflowOpen(false);
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  // Re-fetch when sort changes
  useEffect(() => {
    setLoading(true);
    fetchArticles().then((data) => {
      if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
      else { setSelectedId(null); setFullArticle(null); }
    });
  }, [sort]); // eslint-disable-line react-hooks/exhaustive-deps

  const fetchArticles = useCallback(async (searchQuery?: string) => {
    const params = new URLSearchParams();
    params.set("archived", String(isArchiveView));
    if (filterLabel) params.set("labelId", filterLabel);
    const q = searchQuery ?? search;
    if (q.trim()) params.set("search", q.trim());
    params.set("sort", sort);
    const res = await fetch(`/api/articles?${params}`);
    const data: ArticleListItem[] = await res.json();
    setArticles(data);
    setLoading(false);
    return data;
  }, [isArchiveView, filterLabel, search, sort]);

  const fetchLabels = useCallback(async () => {
    const res = await fetch("/api/labels");
    setLabels(await res.json());
  }, []);

  const fetchFullArticle = useCallback(async (id: string) => {
    setArticleLoading(true);
    const res = await fetch(`/api/articles/${id}`);
    if (res.ok) setFullArticle(await res.json());
    setArticleLoading(false);
  }, []);

  useEffect(() => {
    setLoading(true);
    setSearch("");
    setFilterLabel(null);
    setSelectedId(null);
    setFullArticle(null);
    (async () => {
      const data = await fetchArticles("");
      fetchLabels();
      if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
    })();
  }, [isArchiveView]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    setLoading(true);
    (async () => {
      const data = await fetchArticles();
      if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
      else { setSelectedId(null); setFullArticle(null); }
    })();
  }, [filterLabel]); // eslint-disable-line react-hooks/exhaustive-deps

  function handleSearchChange(value: string) {
    setSearch(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(async () => {
      const data = await fetchArticles(value);
      if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
      else { setSelectedId(null); setFullArticle(null); }
    }, 250);
  }

  function handleSelectArticle(id: string) {
    if (selectedId && readerPaneRef.current) {
      scrollPositions.current[selectedId] = readerPaneRef.current.scrollTop;
    }
    setSelectedId(id);
    setConfirmDelete(false);
    setOverflowOpen(false);
    fetchFullArticle(id);
    setArticles((prev) =>
      prev.map((a) => (a.id === id && !a.readAt ? { ...a, readAt: new Date().toISOString() } : a))
    );
  }

  useEffect(() => {
    if (!fullArticle || !readerPaneRef.current) return;
    const saved = scrollPositions.current[fullArticle.id] ?? 0;
    readerPaneRef.current.scrollTop = saved;
  }, [fullArticle?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleNotionSync() {
    if (!fullArticle) return;
    setNotionSyncing(true);
    const res = await fetch(`/api/articles/${fullArticle.id}/notion`, { method: "POST" });
    if (res.ok) {
      const { notionPageId } = await res.json();
      setFullArticle((prev) => prev ? { ...prev, notionPageId } : prev);
    }
    setNotionSyncing(false);
  }

  // Keyboard navigation
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      const idx = articles.findIndex((a) => a.id === selectedId);
      if (e.key === "j" || e.key === "ArrowDown") {
        e.preventDefault();
        const next = articles[idx + 1];
        if (next) handleSelectArticle(next.id);
      } else if (e.key === "k" || e.key === "ArrowUp") {
        e.preventDefault();
        const prev = articles[idx - 1];
        if (prev) handleSelectArticle(prev.id);
      } else if (e.key === "e") {
        if (fullArticle) handleArchiveToggle();
      } else if (e.key === "o") {
        if (fullArticle) window.open(fullArticle.url, "_blank", "noopener,noreferrer");
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [articles, selectedId, fullArticle]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleArchiveToggle() {
    if (!fullArticle) return;
    await fetch(`/api/articles/${fullArticle.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ archived: !fullArticle.archived }),
    });
    const data = await fetchArticles();
    if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
    else { setSelectedId(null); setFullArticle(null); }
  }

  async function handleDelete() {
    if (!fullArticle) return;
    await fetch(`/api/articles/${fullArticle.id}`, { method: "DELETE" });
    setConfirmDelete(false);
    setOverflowOpen(false);
    const data = await fetchArticles();
    if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
    else { setSelectedId(null); setFullArticle(null); }
  }

  async function handleArticleAdded() {
    setShowAddForm(false);
    const data = await fetchArticles();
    if (data.length > 0) { setSelectedId(data[0].id); fetchFullArticle(data[0].id); }
  }

  const emptyMessage = search.trim()
    ? "No results for that search."
    : isArchiveView
      ? "No archived articles."
      : "No articles yet.";

  return (
    <div className="flex h-full">
      {/* ── Left pane ── */}
      <div className="flex w-[360px] shrink-0 flex-col border-r border-cream-dark">

        {/* Header */}
        <div className="border-b border-cream-dark px-4 pb-3 pt-4">

          {/* Row 1: title + sort + add */}
          <div className="flex items-center gap-2">
            <span className="flex-1 text-[11px] font-semibold uppercase tracking-widest text-neutral-400">
              {isArchiveView ? "Archive" : "To Read"}
              {!loading && articles.length > 0 && (
                <span className="ml-2 font-normal normal-case tracking-normal text-neutral-400">
                  {articles.length}
                </span>
              )}
            </span>

            {/* Sort */}
            <div className="relative" ref={sortMenuRef}>
              <button
                onClick={() => setShowSortMenu((v) => !v)}
                title="Sort"
                className={clsx(
                  "rounded p-1.5 transition-colors",
                  showSortMenu ? "bg-cream-dark text-neutral-700" : "text-neutral-400 hover:bg-cream-dark hover:text-neutral-600"
                )}
              >
                <svg className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M2 4.75A.75.75 0 0 1 2.75 4h14.5a.75.75 0 0 1 0 1.5H2.75A.75.75 0 0 1 2 4.75Zm0 5A.75.75 0 0 1 2.75 9h8.5a.75.75 0 0 1 0 1.5h-8.5A.75.75 0 0 1 2 9.75Zm0 5A.75.75 0 0 1 2.75 14h4.5a.75.75 0 0 1 0 1.5h-4.5A.75.75 0 0 1 2 14.75Z" />
                </svg>
              </button>
              {showSortMenu && (
                <div className="absolute right-0 top-full z-50 mt-1 w-44 overflow-hidden rounded-lg border border-cream-dark bg-white shadow-lg">
                  {SORT_OPTIONS.map((o) => (
                    <button
                      key={o.value}
                      onClick={() => { setSort(o.value); setShowSortMenu(false); }}
                      className={clsx(
                        "flex w-full items-center gap-2 px-3 py-2 text-left text-xs transition-colors",
                        sort === o.value ? "bg-cream text-neutral-900 font-medium" : "text-neutral-600 hover:bg-cream"
                      )}
                    >
                      {sort === o.value && (
                        <svg className="h-3 w-3 shrink-0 text-brand-purple" viewBox="0 0 20 20" fill="currentColor">
                          <path fillRule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clipRule="evenodd" />
                        </svg>
                      )}
                      {sort !== o.value && <span className="h-3 w-3 shrink-0" />}
                      {o.label}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Add article */}
            {!isArchiveView && (
              <button
                onClick={() => setShowAddForm((v) => !v)}
                title="Add article"
                className={clsx(
                  "rounded p-1.5 transition-colors",
                  showAddForm ? "bg-cream-dark text-neutral-700" : "text-neutral-400 hover:bg-cream-dark hover:text-neutral-600"
                )}
              >
                <svg className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M10.75 4.75a.75.75 0 0 0-1.5 0v4.5h-4.5a.75.75 0 0 0 0 1.5h4.5v4.5a.75.75 0 0 0 1.5 0v-4.5h4.5a.75.75 0 0 0 0-1.5h-4.5v-4.5Z" />
                </svg>
              </button>
            )}
          </div>

          {/* Add form — expands inline */}
          {showAddForm && !isArchiveView && (
            <div className="mt-3">
              <AddArticleForm onAdded={handleArticleAdded} />
            </div>
          )}

          {/* Search */}
          <div className="relative mt-3">
            <svg
              className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-neutral-300"
              fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}
            >
              <path strokeLinecap="round" strokeLinejoin="round" d="M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z" />
            </svg>
            <input
              type="text"
              placeholder="Search…"
              value={search}
              onChange={(e) => handleSearchChange(e.target.value)}
              className="w-full rounded-lg border-0 bg-cream-dark/60 py-1.5 pl-8 pr-7 text-xs text-neutral-800 placeholder:text-neutral-400 focus:bg-cream-dark focus:outline-none focus:ring-1 focus:ring-brand-purple/30"
            />
            {search && (
              <button
                onClick={() => handleSearchChange("")}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-neutral-400 hover:text-neutral-600"
              >
                <svg className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
                </svg>
              </button>
            )}
          </div>

          {/* Label filters */}
          {labels.length > 0 && (
            <div className="mt-2.5 flex items-center gap-1 overflow-x-auto [scrollbar-width:none]">
              <button
                onClick={() => setFilterLabel(null)}
                className={clsx(
                  "shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium transition-colors",
                  !filterLabel
                    ? "bg-brand-purple/10 text-brand-purple"
                    : "text-neutral-400 hover:bg-cream-dark hover:text-neutral-600"
                )}
              >
                All
              </button>
              {labels.map((l) => (
                <button
                  key={l.id}
                  onClick={() => setFilterLabel(filterLabel === l.id ? null : l.id)}
                  className={clsx(
                    "shrink-0 rounded-full transition-opacity",
                    filterLabel && filterLabel !== l.id ? "opacity-40" : "opacity-100"
                  )}
                >
                  <LabelBadge name={l.name} color={l.color} />
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Article list */}
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="py-16 text-center text-xs text-neutral-400">Loading…</div>
          ) : articles.length === 0 ? (
            <div className="px-6 py-16 text-center text-xs text-neutral-400">{emptyMessage}</div>
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

      {/* ── Right pane: reader ── */}
      <div ref={readerPaneRef} className="flex-1 overflow-y-auto">
        {articleLoading ? (
          <div className="py-20 text-center text-xs text-neutral-400">Loading…</div>
        ) : fullArticle ? (
          <div className="px-10 py-8">

            {/* Toolbar */}
            <div className="mb-8 flex items-center justify-between">
              {/* Left: label chips + picker */}
              <div className="flex flex-wrap items-center gap-1.5">
                {fullArticle.labels.map((l) => (
                  <LabelBadge key={l.id} name={l.name} color={l.color} />
                ))}
                <LabelPicker
                  articleId={fullArticle.id}
                  currentLabelIds={fullArticle.labels.map((l) => l.id)}
                  onLabelsChanged={() => { fetchFullArticle(fullArticle.id); fetchArticles(); }}
                  compact
                />
              </div>

              {/* Right: Archive + overflow */}
              <div className="flex items-center gap-1">
                <button
                  onClick={handleArchiveToggle}
                  className="rounded-md px-3 py-1.5 text-xs font-medium text-neutral-500 hover:bg-cream-dark hover:text-neutral-700 transition-colors"
                >
                  {fullArticle.archived ? "Unarchive" : "Archive"}
                </button>

                {/* ··· overflow menu */}
                <div className="relative" ref={overflowMenuRef}>
                  <button
                    onClick={() => setOverflowOpen((v) => !v)}
                    className={clsx(
                      "rounded-md px-2 py-1.5 text-sm font-medium transition-colors leading-none",
                      overflowOpen ? "bg-cream-dark text-neutral-700" : "text-neutral-400 hover:bg-cream-dark hover:text-neutral-600"
                    )}
                  >
                    ···
                  </button>

                  {overflowOpen && (
                    <div className="absolute right-0 top-full z-50 mt-1 w-52 overflow-hidden rounded-lg border border-cream-dark bg-white shadow-lg">

                      {/* Font size */}
                      <div className="flex items-center justify-between border-b border-cream-dark/60 px-3 py-2">
                        <span className="text-[11px] text-neutral-400">Font size</span>
                        <span className="flex items-center gap-0.5">
                          {([["sm", "10px"], ["md", "13px"], ["lg", "16px"]] as const).map(([s, size]) => (
                            <button
                              key={s}
                              onClick={() => setFontSize(s)}
                              style={{ fontSize: size }}
                              className={clsx(
                                "flex h-6 w-6 items-center justify-center rounded font-semibold leading-none transition-colors",
                                fontSize === s ? "bg-cream-dark text-neutral-800" : "text-neutral-400 hover:text-neutral-700"
                              )}
                            >
                              A
                            </button>
                          ))}
                        </span>
                      </div>

                      {/* Notion */}
                      {fullArticle.notionPageId ? (
                        <a
                          href={`https://notion.so/${fullArticle.notionPageId.replace(/-/g, "")}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          onClick={() => setOverflowOpen(false)}
                          className="flex items-center gap-2.5 px-3 py-2 text-xs text-neutral-600 transition-colors hover:bg-cream"
                        >
                          <svg className="h-3.5 w-3.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                            <path fillRule="evenodd" d="M4.25 5.5a.75.75 0 0 0-.75.75v8.5c0 .414.336.75.75.75h8.5a.75.75 0 0 0 .75-.75v-4a.75.75 0 0 1 1.5 0v4A2.25 2.25 0 0 1 12.75 17h-8.5A2.25 2.25 0 0 1 2 14.75v-8.5A2.25 2.25 0 0 1 4.25 4h5a.75.75 0 0 1 0 1.5h-5Zm6.5-3a.75.75 0 0 1 .75-.75h3.5a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0V3.56l-4.22 4.22a.75.75 0 0 1-1.06-1.06l4.22-4.22h-2.19a.75.75 0 0 1-.75-.75Z" clipRule="evenodd" />
                          </svg>
                          Open in Notion
                        </a>
                      ) : (
                        <button
                          onClick={() => { handleNotionSync(); setOverflowOpen(false); }}
                          disabled={notionSyncing}
                          className="flex w-full items-center gap-2.5 px-3 py-2 text-left text-xs text-neutral-600 transition-colors hover:bg-cream disabled:opacity-40"
                        >
                          <svg className="h-3.5 w-3.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                            <path fillRule="evenodd" d="M4.25 5.5a.75.75 0 0 0-.75.75v8.5c0 .414.336.75.75.75h8.5a.75.75 0 0 0 .75-.75v-4a.75.75 0 0 1 1.5 0v4A2.25 2.25 0 0 1 12.75 17h-8.5A2.25 2.25 0 0 1 2 14.75v-8.5A2.25 2.25 0 0 1 4.25 4h5a.75.75 0 0 1 0 1.5h-5Zm6.5-3a.75.75 0 0 1 .75-.75h3.5a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0V3.56l-4.22 4.22a.75.75 0 0 1-1.06-1.06l4.22-4.22h-2.19a.75.75 0 0 1-.75-.75Z" clipRule="evenodd" />
                          </svg>
                          {notionSyncing ? "Syncing…" : "Send to Notion"}
                        </button>
                      )}

                      {/* Original */}
                      <a
                        href={fullArticle.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        onClick={() => setOverflowOpen(false)}
                        className="flex items-center gap-2.5 px-3 py-2 text-xs text-neutral-600 transition-colors hover:bg-cream"
                      >
                        <svg className="h-3.5 w-3.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                          <path fillRule="evenodd" d="M4.25 5.5a.75.75 0 0 0-.75.75v8.5c0 .414.336.75.75.75h8.5a.75.75 0 0 0 .75-.75v-4a.75.75 0 0 1 1.5 0v4A2.25 2.25 0 0 1 12.75 17h-8.5A2.25 2.25 0 0 1 2 14.75v-8.5A2.25 2.25 0 0 1 4.25 4h5a.75.75 0 0 1 0 1.5h-5Zm6.5-3a.75.75 0 0 1 .75-.75h3.5a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0V3.56l-4.22 4.22a.75.75 0 0 1-1.06-1.06l4.22-4.22h-2.19a.75.75 0 0 1-.75-.75Z" clipRule="evenodd" />
                        </svg>
                        Open original
                      </a>

                      {/* Delete */}
                      <div className="border-t border-cream-dark/60">
                        {confirmDelete ? (
                          <div className="flex items-center gap-2 px-3 py-2">
                            <span className="flex-1 text-xs text-neutral-500">Sure?</span>
                            <button
                              onClick={handleDelete}
                              className="text-xs font-medium text-brand-orange hover:underline"
                            >
                              Delete
                            </button>
                            <button
                              onClick={() => setConfirmDelete(false)}
                              className="text-xs text-neutral-400 hover:text-neutral-600"
                            >
                              Cancel
                            </button>
                          </div>
                        ) : (
                          <button
                            onClick={() => setConfirmDelete(true)}
                            className="flex w-full items-center gap-2.5 px-3 py-2 text-left text-xs text-brand-orange transition-colors hover:bg-cream"
                          >
                            <svg className="h-3.5 w-3.5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                              <path fillRule="evenodd" d="M8.75 1A2.75 2.75 0 0 0 6 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 1 0 .23 1.482l.149-.022.841 10.518A2.75 2.75 0 0 0 7.596 19h4.807a2.75 2.75 0 0 0 2.742-2.53l.841-10.52.149.023a.75.75 0 0 0 .23-1.482A41.03 41.03 0 0 0 14 4.193V3.75A2.75 2.75 0 0 0 11.25 1h-2.5ZM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4ZM8.58 7.72a.75.75 0 0 0-1.5.06l.3 7.5a.75.75 0 1 0 1.5-.06l-.3-7.5Zm4.34.06a.75.75 0 1 0-1.5-.06l-.3 7.5a.75.75 0 1 0 1.5.06l.3-7.5Z" clipRule="evenodd" />
                            </svg>
                            Delete article
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
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
              fontSize={fontSize}
            />
          </div>
        ) : (
          <div className="flex h-full items-center justify-center">
            <p className="text-xs text-neutral-400">
              {articles.length === 0
                ? isArchiveView ? "Nothing archived yet." : "Add an article to get started."
                : "Select an article to read."}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

export default function HomePage() {
  return (
    <Suspense>
      <HomePageContent />
    </Suspense>
  );
}
