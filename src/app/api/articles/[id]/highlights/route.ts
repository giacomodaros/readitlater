import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { syncHighlightToNotion } from "@/lib/notion";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const highlights = await prisma.highlight.findMany({
    where: { articleId: id },
    orderBy: { startOffset: "asc" },
  });
  return NextResponse.json(highlights);
}

export async function POST(req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const body = await req.json();
  const { text, startOffset, endOffset, color, note } = body;

  if (typeof text !== "string" || typeof startOffset !== "number" || typeof endOffset !== "number") {
    return NextResponse.json({ error: "Invalid highlight data" }, { status: 400 });
  }

  const [highlight, article] = await Promise.all([
    prisma.highlight.create({
      data: {
        articleId: id,
        text,
        startOffset,
        endOffset,
        ...(color && { color }),
        ...(note && { note }),
      },
    }),
    prisma.article.findUnique({
      where: { id },
      select: {
        title: true,
        url: true,
        author: true,
        siteName: true,
        publishedAt: true,
        notionPageId: true,
        labels: { select: { name: true } },
      },
    }),
  ]);

  // Sync to Notion — create article page on first highlight, then append
  if (article) {
    syncHighlightToNotion({
      notionPageId: article.notionPageId,
      highlightText: text,
      articleTitle: article.title,
      articleUrl: article.url,
      author: article.author,
      siteName: article.siteName,
      publishedAt: article.publishedAt,
      labels: article.labels.map((l) => l.name),
    })
      .then((notionPageId) => {
        // Persist the Notion page ID if it was just created
        if (notionPageId && notionPageId !== article.notionPageId) {
          return prisma.article.update({
            where: { id },
            data: { notionPageId },
          });
        }
      })
      .catch((err) => console.error("[Notion] Failed to sync highlight:", err));
  }

  return NextResponse.json(highlight, { status: 201 });
}
