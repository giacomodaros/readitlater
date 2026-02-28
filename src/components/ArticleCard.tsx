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

  if (days === 0) {
    return d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  }
  if (days < 7) {
    return d.toLocaleDateString("en-US", { weekday: "short" });
  }
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
  description,
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
        "block w-full cursor-pointer border-b border-cream-dark px-4 py-3 text-left transition-colors",
        selected
          ? "border-l-2 border-l-brand-purple bg-white"
          : "border-l-2 border-l-transparent hover:bg-cream-dark/30"
      )}
    >
      {/* Row 1: favicon + source + date */}
      <div className="flex items-center gap-2">
        <div className="flex h-5 w-5 shrink-0 items-center justify-center overflow-hidden rounded-full bg-cream-dark">
          {favicon ? (
            <img src={favicon} alt="" className="h-5 w-5 rounded-full object-cover" />
          ) : (
            <span className="text-[9px] font-bold text-neutral-400">
              {(source || title).charAt(0).toUpperCase()}
            </span>
          )}
        </div>
        <span
          className={clsx(
            "min-w-0 flex-1 truncate text-sm",
            isUnread ? "font-semibold text-neutral-900" : "font-medium text-neutral-600"
          )}
        >
          {source || "Unknown"}
        </span>
        {publishedAt && (
          <span className="shrink-0 text-xs text-neutral-400">
            {formatDate(publishedAt)}
          </span>
        )}
      </div>

      {/* Row 2: title */}
      <p
        className={clsx(
          "mt-1 truncate text-sm leading-snug",
          isUnread ? "font-semibold text-neutral-800" : "text-neutral-600"
        )}
      >
        {title}
      </p>

      {/* Row 3: description preview + labels + ttr */}
      <div className="mt-0.5 flex items-center gap-1.5">
        {labels.length > 0 && (
          <span className="flex shrink-0 gap-1">
            {labels.map((l) => (
              <LabelBadge key={l.id} name={l.name} color={l.color} />
            ))}
          </span>
        )}
        {description && (
          <span className="min-w-0 truncate text-xs text-neutral-400">
            {description}
          </span>
        )}
      </div>
    </button>
  );
}
