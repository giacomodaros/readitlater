import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { extractArticle, extractFromHtml } from "@/lib/extractor";

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = req.nextUrl;
    const archived = searchParams.get("archived");
    const labelId = searchParams.get("labelId");
    const search = searchParams.get("search");

    const sort = searchParams.get("sort") ?? "newest";
    const orderBy =
      sort === "oldest" ? { createdAt: "asc" as const } :
      sort === "ttr" ? { ttr: "asc" as const } :
      sort === "published" ? { publishedAt: "desc" as const } :
      { createdAt: "desc" as const };

    const articles = await prisma.article.findMany({
      where: {
        ...(archived !== null && { archived: archived === "true" }),
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
    const message = e instanceof Error ? e.message : "Database error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { url, html } = body;

    if (!url || typeof url !== "string") {
      return NextResponse.json({ error: "URL is required" }, { status: 400 });
    }

    const existing = await prisma.article.findUnique({ where: { url } });
    if (existing) {
      return NextResponse.json(existing);
    }

    const data = html && typeof html === "string"
      ? await extractFromHtml(url, html)
      : await extractArticle(url);

    const article = await prisma.article.create({
      data,
      include: { labels: true },
    });
    return NextResponse.json(article, { status: 201 });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Failed";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}
