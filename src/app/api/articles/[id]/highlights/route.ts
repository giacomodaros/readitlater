import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { syncHighlightToNotion } from "@/lib/notion";
import { authErrorResponse, requireUser } from "@/lib/auth";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id } = await ctx.params;
    const article = await prisma.article.findFirst({ where: { id, userId: user.id }, select: { id: true } });
    if (!article) return NextResponse.json({ error: "Not found" }, { status: 404 });
    const highlights = await prisma.highlight.findMany({
      where: { articleId: id },
      orderBy: { startOffset: "asc" },
    });
    return NextResponse.json(highlights);
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}

export async function POST(req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id } = await ctx.params;
    const body = await req.json();
    const { text, startOffset, endOffset, color, note } = body;

    if (typeof text !== "string" || typeof startOffset !== "number" || typeof endOffset !== "number") {
      return NextResponse.json({ error: "Invalid highlight data" }, { status: 400 });
    }

    const article = await prisma.article.findUnique({
      where: { id },
      select: {
        userId: true,
        title: true,
        url: true,
        author: true,
        siteName: true,
        publishedAt: true,
        notionPageId: true,
        labels: { select: { name: true } },
      },
    });

    if (!article || article.userId !== user.id) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }

    const highlight = await prisma.highlight.create({
      data: {
        articleId: id,
        text,
        startOffset,
        endOffset,
        ...(color && { color }),
        ...(note && { note }),
      },
    });

    // Sync to Notion, creating the article page on first highlight if needed.
    try {
      const notionPageId = await syncHighlightToNotion({
        notionPageId: article.notionPageId,
        highlightText: text,
        articleTitle: article.title,
        articleUrl: article.url,
        author: article.author,
        siteName: article.siteName,
        publishedAt: article.publishedAt,
        labels: article.labels.map((l) => l.name),
      });
      if (notionPageId && notionPageId !== article.notionPageId) {
        await prisma.article.update({
          where: { id },
          data: { notionPageId },
        });
      }
    } catch (err) {
      console.error("[Notion] Failed to sync highlight:", err);
    }

    return NextResponse.json(highlight, { status: 201 });
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}
