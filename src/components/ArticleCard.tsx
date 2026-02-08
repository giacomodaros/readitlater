"use client";

import Link from "next/link";
import clsx from "clsx";
import LabelBadge from "./LabelBadge";

type Label = { id: string; name: string; color: string };

interface ArticleCardProps {
  id: string;
  title: string;
  author?: string | null;
  siteName?: string | null;
  favicon?: string | null;
  publishedAt?: string | null;
  archived: boolean;
  readAt?: string | null;
  ttr?: number | null;
  createdAt: string;
  labels: Label[];
  _count: { highlights: number };
  onArchiveToggle: (id: string, archived: boolean) => void;
  onDelete: (id: string) => void;
}

function formatDate(dateStr: string) {
  const d = new Date(dateStr);
  const now = new Date();
  const sameYear = d.getFullYear() === now.getFullYear();
  return d.toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    ...(sameYear ? {} : { year: "numeric" }),
  });
}

export default function ArticleCard({
  id,
  title,
  author,
  siteName,
  favicon,
  publishedAt,
  archived,
  readAt,
  ttr,
  labels,
  _count,
  onArchiveToggle,
  onDelete,
}: ArticleCardProps) {
  const isUnread = !readAt;
  const meta = [author, siteName, publishedAt ? formatDate(publishedAt) : null].filter(Boolean);

  return (
    <div
      className={clsx(
        "group flex items-center gap-4 rounded-lg px-3 py-3.5 transition-colors hover:bg-cream-dark/40",
        archived && "opacity-50"
      )}
    >
      {/* Favicon */}
      <div className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-cream-dark">
        {favicon ? (
          <img src={favicon} alt="" className="h-10 w-10 rounded-full object-cover" />
        ) : (
          <span className="text-sm font-medium text-neutral-400">
            {(siteName || title).charAt(0).toUpperCase()}
          </span>
        )}
      </div>

      {/* Title + meta */}
      <div className="min-w-0 flex-1">
        <Link
          href={`/articles/${id}`}
          className={clsx(
            "block truncate leading-snug hover:text-brand-purple",
            isUnread ? "font-semibold text-neutral-900" : "font-medium text-neutral-600"
          )}
        >
          {title}
        </Link>
        <div className="mt-0.5 flex items-center gap-1 truncate text-sm text-neutral-500">
          {meta.length > 0 && (
            <span className="truncate">{meta.join(" \u00b7 ")}</span>
          )}
          {labels.length > 0 && (
            <>
              {meta.length > 0 && <span className="mx-1 text-neutral-300">{"\u00b7"}</span>}
              <span className="flex gap-1">
                {labels.map((l) => (
                  <LabelBadge key={l.id} name={l.name} color={l.color} />
                ))}
              </span>
            </>
          )}
        </div>
      </div>

      {/* Right side: reading time + status */}
      <div className="hidden shrink-0 items-center gap-3 text-sm text-neutral-400 sm:flex">
        {ttr && <span>{ttr} min</span>}
        {isUnread && (
          <span className="rounded-full bg-brand-purple-light px-2 py-0.5 text-xs font-medium text-brand-purple">
            Unread
          </span>
        )}
        {_count.highlights > 0 && (
          <span className="text-xs text-brand-orange">
            {_count.highlights} highlight{_count.highlights !== 1 ? "s" : ""}
          </span>
        )}
      </div>

      {/* Hover actions */}
      <div className="flex shrink-0 gap-1 opacity-0 transition-opacity group-hover:opacity-100">
        <button
          onClick={() => onArchiveToggle(id, !archived)}
          className="rounded-md px-2 py-1 text-xs font-medium text-neutral-500 hover:bg-cream-dark"
          title={archived ? "Unarchive" : "Archive"}
        >
          {archived ? "Unarchive" : "Archive"}
        </button>
        <button
          onClick={() => onDelete(id)}
          className="rounded-md px-2 py-1 text-xs font-medium text-brand-orange hover:bg-brand-orange-light"
        >
          Delete
        </button>
      </div>
    </div>
  );
}
