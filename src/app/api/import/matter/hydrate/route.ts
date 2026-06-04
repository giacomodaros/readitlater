import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";
import { extractArticle } from "@/lib/extractor";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const MAX_URLS_PER_REQUEST = 6;
const DEFAULT_PENDING_LIMIT = 4;

export async function POST(req: NextRequest) {
  try {
    const user = await requireUser();
    const body = await req.json();
    const requestedURLs = parseRequestedURLs(body.urls);
    const pendingLimit = clampLimit(body.limit);
    const urls = requestedURLs.length ? requestedURLs : await pendingPlaceholderURLs(user.id, pendingLimit);

    if (!urls.length) {
      return NextResponse.json({ hydrated: 0, skipped: 0, failed: 0, remaining: 0, lastError: null });
    }

    let hydrated = 0;
    let skipped = 0;
    let failed = 0;
    let lastError: string | null = null;

    for (const url of urls.slice(0, MAX_URLS_PER_REQUEST)) {
      const article = await prisma.article.findUnique({
        where: { userId_url: { userId: user.id, url } },
      });

      if (!article) {
        skipped += 1;
        continue;
      }

      if (!isMatterPlaceholder(article.content)) {
        skipped += 1;
        continue;
      }

      try {
        const extracted = await extractArticle(url);
        await prisma.article.update({
          where: { id: article.id },
          data: {
            title: extracted.title,
            author: extracted.author,
            description: extracted.description,
            content: extracted.content,
            image: extracted.image,
            favicon: extracted.favicon,
            siteName: extracted.siteName,
            publishedAt: extracted.publishedAt,
            ttr: extracted.ttr,
          },
        });
        hydrated += 1;
      } catch (error) {
        failed += 1;
        lastError = error instanceof Error ? `${url}: ${error.message}` : `${url}: fetch failed`;
        await prisma.article.update({
          where: { id: article.id },
          data: { updatedAt: new Date() },
        });
      }
    }

    const remaining = await countMatterPlaceholders(user.id);
    return NextResponse.json({ hydrated, skipped, failed, remaining, lastError });
  } catch (error) {
    if (error instanceof Error && error.message === "UNAUTHENTICATED") return authErrorResponse();
    const message = error instanceof Error ? error.message : "Matter hydration failed.";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}

async function pendingPlaceholderURLs(userId: string, limit: number) {
  const articles = await prisma.article.findMany({
    where: matterPlaceholderWhere(userId),
    select: { url: true },
    orderBy: { updatedAt: "asc" },
    take: limit,
  });
  return articles.map((article) => article.url);
}

async function countMatterPlaceholders(userId: string) {
  return prisma.article.count({ where: matterPlaceholderWhere(userId) });
}

function matterPlaceholderWhere(userId: string) {
  return {
    userId,
    OR: [
      { content: { contains: "Imported from Matter" } },
      { content: { contains: "Matter export does not always include" } },
      { content: { contains: "saved library history export" } },
    ],
  };
}

function clampLimit(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return DEFAULT_PENDING_LIMIT;
  return Math.max(1, Math.min(MAX_URLS_PER_REQUEST, Math.floor(parsed)));
}

function parseRequestedURLs(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const urls: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    const normalized = normalizeURL(String(item));
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    urls.push(normalized);
  }

  return urls;
}

function normalizeURL(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const normalized = /^[a-z][a-z\d+\-.]*:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    const url = new URL(normalized);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function isMatterPlaceholder(content: string | null | undefined) {
  const normalized = (content ?? "").trim().toLowerCase();
  if (!normalized) return true;
  return normalized.includes("imported from matter")
    || normalized.includes("matter export does not always include")
    || normalized.includes("saved library history export");
}
