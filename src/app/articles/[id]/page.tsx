"use client";

import { useEffect, useState, use, useCallback } from "react";
import { useRouter } from "next/navigation";
import ArticleReader from "@/components/ArticleReader";
import LabelPicker from "@/components/LabelPicker";
import LabelBadge from "@/components/LabelBadge";
import Link from "next/link";

type Label = { id: string; name: string; color: string };
type Highlight = {
  id: string;
  text: string;
  startOffset: number;
  endOffset: number;
  color: string;
  note: string | null;
};
type Article = {
  id: string;
  url: string;
  title: string;
  author: string | null;
  description: string | null;
  content: string;
  image: string | null;
  siteName: string | null;
  publishedAt: string | null;
  ttr: number | null;
  archived: boolean;
  labels: Label[];
  highlights: Highlight[];
};

export default function ArticlePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const [article, setArticle] = useState<Article | null>(null);
  const [error, setError] = useState<string | null>(null);

  const fetchArticle = useCallback(async () => {
    const res = await fetch(`/api/articles/${id}`);
    if (!res.ok) {
      setError("Article not found");
      return;
    }
    setArticle(await res.json());
  }, [id]);

  useEffect(() => {
    fetchArticle();
  }, [fetchArticle]);

  async function handleDelete() {
    if (!confirm("Delete this article?")) return;
    await fetch(`/api/articles/${id}`, { method: "DELETE" });
    router.push("/");
  }

  if (error) {
    return (
      <div className="py-20 text-center">
        <p className="text-neutral-500">{error}</p>
        <Link href="/" className="mt-4 inline-block text-sm text-brand-purple hover:underline">
          Back to library
        </Link>
      </div>
    );
  }

  if (!article) {
    return <div className="py-20 text-center text-neutral-400">Loading article...</div>;
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <Link href="/" className="text-sm text-neutral-500 hover:text-brand-purple">
          &larr; Back to library
        </Link>
        <div className="flex items-center gap-2">
          <div className="flex flex-wrap gap-1">
            {article.labels.map((l) => (
              <LabelBadge key={l.id} name={l.name} color={l.color} />
            ))}
          </div>
          <LabelPicker
            articleId={article.id}
            currentLabelIds={article.labels.map((l) => l.id)}
            onLabelsChanged={fetchArticle}
          />
          <a
            href={article.url}
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
        articleId={article.id}
        content={article.content}
        title={article.title}
        author={article.author}
        siteName={article.siteName}
        publishedAt={article.publishedAt}
        ttr={article.ttr}
      />
    </div>
  );
}
