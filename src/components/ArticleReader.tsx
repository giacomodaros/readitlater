"use client";

import { useEffect, useRef, useState } from "react";
import HighlightLayer from "./HighlightLayer";

interface ArticleReaderProps {
  articleId: string;
  content: string;
  title: string;
  author?: string | null;
  siteName?: string | null;
  publishedAt?: string | null;
  ttr?: number | null;
  fontSize?: "sm" | "md" | "lg";
}

const FONT_SIZE_CLASS = {
  sm: "prose-sm",
  md: "",
  lg: "prose-lg",
};

const FONT_FAMILY_CLASS = {
  serif: "font-serif-body",
  sans: "font-sans",
  mono: "font-mono",
};

export default function ArticleReader({
  articleId,
  content,
  title,
  author,
  siteName,
  publishedAt,
  ttr,
  fontSize = "md",
}: ArticleReaderProps) {
  const contentRef = useRef<HTMLDivElement>(null);
  const [fontFamily, setFontFamily] = useState<keyof typeof FONT_FAMILY_CLASS>("serif");

  useEffect(() => {
    function syncFont() {
      const stored = localStorage.getItem("reader-font-family");
      setFontFamily(stored === "sans" || stored === "mono" ? stored : "serif");
    }

    syncFont();
    window.addEventListener("reader-appearance-change", syncFont);
    return () => window.removeEventListener("reader-appearance-change", syncFont);
  }, []);

  const byline = [
    author ? `By ${author}` : null,
    siteName && author ? `on ${siteName}` : siteName,
    publishedAt
      ? new Date(publishedAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })
      : null,
    ttr ? `${ttr} min read` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <article className="mx-auto max-w-[68ch]">
      <header className="mb-10 border-b border-cream-dark pb-8">
        <h1 className="font-serif-display text-[2rem] font-normal leading-[1.2] text-neutral-900">
          {title}
        </h1>
        {byline && (
          <p className="mt-4 text-[12.5px] uppercase tracking-widest text-neutral-400">{byline}</p>
        )}
      </header>

      <div className="relative">
        <HighlightLayer articleId={articleId} contentRef={contentRef} originalHtml={content} />
        <div
          ref={contentRef}
          className={[
            "prose prose-neutral max-w-none",
            FONT_FAMILY_CLASS[fontFamily],
            "prose-headings:tracking-tight",
            "prose-p:leading-[1.85] prose-p:text-neutral-800",
            "prose-a:text-brand-purple prose-a:no-underline hover:prose-a:underline",
            "prose-img:rounded-xl prose-img:shadow-sm",
            "prose-blockquote:border-brand-purple/40 prose-blockquote:text-neutral-600 prose-blockquote:font-serif-body",
            "prose-code:text-brand-purple prose-code:font-normal",
            FONT_SIZE_CLASS[fontSize],
          ].join(" ")}
          dangerouslySetInnerHTML={{ __html: content }}
        />
      </div>
    </article>
  );
}
