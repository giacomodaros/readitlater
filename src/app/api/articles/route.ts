import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { extractArticle } from "@/lib/extractor";

export async function GET(req: NextRequest) {
  const { searchParams } = req.nextUrl;
  const archived = searchParams.get("archived");
  const labelId = searchParams.get("labelId");
  const search = searchParams.get("search");

  const articles = await prisma.article.findMany({
    where: {
      ...(archived !== null && { archived: archived === "true" }),
      ...(labelId && { labels: { some: { id: labelId } } }),
      ...(search && {
        OR: [
          { title: { contains: search } },
          { description: { contains: search } },
          { siteName: { contains: search } },
        ],
      }),
    },
    include: { labels: true, _count: { select: { highlights: true } } },
    orderBy: { createdAt: "desc" },
  });

  return NextResponse.json(articles);
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { url } = body;

  if (!url || typeof url !== "string") {
    return NextResponse.json({ error: "URL is required" }, { status: 400 });
  }

  const existing = await prisma.article.findUnique({ where: { url } });
  if (existing) {
    return NextResponse.json(existing);
  }

  try {
    const data = await extractArticle(url);
    const article = await prisma.article.create({
      data,
      include: { labels: true },
    });
    return NextResponse.json(article, { status: 201 });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Extraction failed";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}
