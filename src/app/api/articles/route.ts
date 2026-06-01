import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { extractArticle, extractFromHtml } from "@/lib/extractor";
import { authErrorResponse, requireUser } from "@/lib/auth";

export async function GET(req: NextRequest) {
  try {
    const user = await requireUser();
    const { searchParams } = req.nextUrl;
    const archived = searchParams.get("archived");
    const mode = searchParams.get("mode");
    const labelId = searchParams.get("labelId");
    const search = searchParams.get("search");
    const since = searchParams.get("since");
    const sinceDate = since ? new Date(since) : null;

    const sort = searchParams.get("sort") ?? "newest";
    const orderBy =
      sort === "oldest" ? { createdAt: "asc" as const } :
      sort === "ttr" ? { ttr: "asc" as const } :
      sort === "published" ? { publishedAt: "desc" as const } :
      { createdAt: "desc" as const };

    const visibilityWhere =
      mode === "inbox"
        ? { archived: false }
        : mode === "archive"
          ? { archived: true }
          : archived !== null
            ? { archived: archived === "true" }
            : {};

    const articles = await prisma.article.findMany({
      where: {
        userId: user.id,
        ...visibilityWhere,
        ...(sinceDate && !Number.isNaN(sinceDate.getTime()) && { updatedAt: { gt: sinceDate } }),
        ...(labelId && { labels: { some: { id: labelId } } }),
        ...(search && {
          OR: [
            { title: { contains: search } },
            { author: { contains: search } },
            { description: { contains: search } },
            { siteName: { contains: search } },
          ],
        }),
      },
      include: { labels: true, _count: { select: { highlights: true } } },
      orderBy,
    });

    return NextResponse.json(articles);
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    const message = e instanceof Error ? e.message : "Database error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const user = await requireUser();
    const body = await req.json();
    const { url, html } = body;

    if (!url || typeof url !== "string") {
      return NextResponse.json({ error: "URL is required" }, { status: 400 });
    }

    const existing = await prisma.article.findUnique({
      where: { userId_url: { userId: user.id, url } },
      include: { labels: true },
    });
    const archived = typeof body.archived === "boolean" ? body.archived : undefined;
    const readAt = body.readAt === true ? new Date() : body.readAt === false || body.readAt === null ? null : undefined;

    if (existing) {
      if (archived !== undefined || readAt !== undefined) {
        await prisma.article.updateMany({
          where: { id: existing.id, userId: user.id },
          data: {
            ...(archived !== undefined && { archived }),
            ...(readAt !== undefined && { readAt }),
          },
        });
        const updated = await prisma.article.findUnique({
          where: { id: existing.id },
          include: { labels: true },
        });
        return NextResponse.json(updated);
      }
      return NextResponse.json(existing);
    }

    const metadataOnly = body.metadataOnly === true || body.source === "matter";
    const data = metadataOnly
      ? metadataArticleData(url, body)
      : html && typeof html === "string"
        ? await extractFromHtml(url, html)
        : await extractArticle(url);

    const article = await prisma.article.create({
      data: {
        ...data,
        userId: user.id,
        ...(archived !== undefined && { archived }),
        ...(readAt !== undefined && { readAt }),
      },
      include: { labels: true },
    });
    return NextResponse.json(article, { status: 201 });
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    const message = e instanceof Error ? e.message : "Failed";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}

function metadataArticleData(url: string, body: Record<string, unknown>) {
  const parsed = new URL(url);
  const title = stringValue(body.title) || parsed.hostname.replace(/^www\./, "");
  const author = stringValue(body.author);
  const siteName = stringValue(body.siteName) || stringValue(body.publisher) || parsed.hostname.replace(/^www\./, "");
  const description = stringValue(body.description);
  const content = stringValue(body.content) || `<p>${escapeHtml(description || "Imported from Matter.")}</p>`;
  const words = Number(body.wordCount);

  return {
    url,
    title,
    author,
    description: description || null,
    content,
    image: null,
    favicon: `${parsed.origin}/favicon.ico`,
    siteName,
    publishedAt: null,
    ttr: Number.isFinite(words) && words > 0 ? Math.max(1, Math.round(words / 238)) : 1,
  };
}

function stringValue(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
