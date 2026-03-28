"use client";

import clsx from "clsx";
import LabelBadge from "./LabelBadge";

type Label = { id: string; name: string; color: string };

interface ArticleCardProps {
  id: string;
  title: string;
  author?: string | null;
  description?: string | null;
  siteName?: string | null;
  favicon?: string | null;
  publishedAt?: string | null;
  readAt?: string | null;
  ttr?: number | null;
  labels: Label[];
  selected?: boolean;
  onClick?: () => void;
}

function formatDate(dateStr: string) {
  const d = new Date(dateStr);
  const now = new Date();
  const diff = now.getTime() - d.getTime();
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  if (days === 0) return d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  if (days < 7) return d.toLocaleDateString("en-US", { weekday: "short" });
  const sameYear = d.getFullYear() === now.getFullYear();
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    ...(sameYear ? {} : { year: "numeric" }),
  });
}

export default function ArticleCard({
  title,
  author,
  siteName,
  favicon,
  publishedAt,
  readAt,
  ttr,
  labels,
  selected,
  onClick,
}: ArticleCardProps) {
  const isUnread = !readAt;
  const source = siteName || author;

  return (
    <button
      onClick={onClick}
      className={clsx(
        "group block w-full cursor-pointer border-b border-cream-dark px-4 py-3.5 text-left transition-colors",
        selected
          ? "border-l-2 border-l-brand-purple bg-white"
          : "border-l-2 border-l-transparent hover:bg-white/70"
      )}
    >
      {/* Title — dominant element */}
      <p
        className={clsx(
          "text-sm leading-snug",
          isUnread ? "font-semibold text-neutral-900" : "font-medium text-neutral-600"
        )}
      >
        {title}
      </p>

      {/* Source + date */}
      <div className="mt-1 flex items-center gap-1.5">
        {favicon ? (
          <img src={favicon} alt="" className="h-3.5 w-3.5 rounded-full object-cover opacity-70" />
        ) : null}
        <span className="min-w-0 truncate text-[11px] text-neutral-400">
          {source || "Unknown"}
        </span>
        {publishedAt && (
          <>
            <span className="text-neutral-300">·</span>
            <span className="shrink-0 text-[11px] text-neutral-400">{formatDate(publishedAt)}</span>
          </>
        )}
      </div>

      {/* Bottom row: labels + TTR */}
      {(labels.length > 0 || ttr) && (
        <div className="mt-2 flex items-center gap-1.5">
          {labels.length > 0 && (
            <span className="flex gap-1">
              {labels.map((l) => (
                <LabelBadge key={l.id} name={l.name} color={l.color} />
              ))}
            </span>
          )}
          {ttr && (
            <span className="ml-auto shrink-0 text-[10px] text-neutral-300">
              {ttr}m
            </span>
          )}
        </div>
      )}
    </button>
  );
}
