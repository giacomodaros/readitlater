import { NextResponse } from "next/server";

import { requireUser } from "@/lib/auth";
import { prisma } from "@/lib/db";

function csvCell(value: unknown) {
  if (value === null || value === undefined) return "";
  const text = value instanceof Date ? value.toISOString() : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

export async function GET() {
  const user = await requireUser();

  const highlights = await prisma.highlight.findMany({
    where: { article: { userId: user.id } },
    include: {
      article: {
        select: {
          title: true,
          url: true,
          siteName: true,
        },
      },
    },
    orderBy: { createdAt: "desc" },
  });

  const rows = [
    ["article_title", "article_url", "site_name", "highlight", "note", "color", "created_at"],
    ...highlights.map((highlight) => [
      highlight.article.title,
      highlight.article.url,
      highlight.article.siteName,
      highlight.text,
      highlight.note,
      highlight.color,
      highlight.createdAt,
    ]),
  ];

  const csv = rows.map((row) => row.map(csvCell).join(",")).join("\n");

  return new NextResponse(csv, {
    headers: {
      "Content-Disposition": 'attachment; filename="library-highlights.csv"',
      "Content-Type": "text/csv; charset=utf-8",
    },
  });
}
