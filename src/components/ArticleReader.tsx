"use client";

import { useRef } from "react";
import HighlightLayer from "./HighlightLayer";

interface ArticleReaderProps {
  articleId: string;
  content: string;
  title: string;
  author?: string | null;
  siteName?: string | null;
  publishedAt?: string | null;
  ttr?: number | null;
}

export default function ArticleReader({
  articleId,
  content,
  title,
  author,
  siteName,
  publishedAt,
  ttr,
}: ArticleReaderProps) {
  const contentRef = useRef<HTMLDivElement>(null);

  return (
    <article className="mx-auto max-w-2xl">
      <header className="mb-8 border-b border-cream-dark pb-6">
        <h1 className="text-3xl font-bold leading-tight text-neutral-900">{title}</h1>
        <div className="mt-3 flex flex-wrap items-center gap-2 text-sm text-neutral-500">
          {author && <span>By {author}</span>}
          {siteName && <span>{author ? "on" : ""} {siteName}</span>}
          {publishedAt && (
            <span>
              {new Date(publishedAt).toLocaleDateString("en-US", {
                year: "numeric",
                month: "long",
                day: "numeric",
              })}
            </span>
          )}
          {ttr && <span>{ttr} min read</span>}
        </div>
      </header>

      <div className="relative">
        <HighlightLayer
          articleId={articleId}
          contentRef={contentRef}
          originalHtml={content}
        />
        <div
          ref={contentRef}
          className="prose prose-neutral max-w-none prose-headings:font-semibold prose-a:text-brand-purple prose-img:rounded-lg"
          dangerouslySetInnerHTML={{ __html: content }}
        />
      </div>
    </article>
  );
}
