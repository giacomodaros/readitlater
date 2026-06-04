import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";
import { extractArticle } from "@/lib/extractor";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const MAX_URLS_PER_REQUEST = 10;
const DEFAULT_PENDING_LIMIT = 10;

type HydrateURLResult = {
  hydrated: number;
  skipped: number;
  failed: number;
  lastError: string | null;
};

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

    const results = await Promise.all(urls.slice(0, MAX_URLS_PER_REQUEST).map((url) => hydrateURL(user.id, url)));
    const hydrated = results.reduce((sum, result) => sum + result.hydrated, 0);
    const skipped = results.reduce((sum, result) => sum + result.skipped, 0);
    const failed = results.reduce((sum, result) => sum + result.failed, 0);
    const lastError = results.find((result) => result.lastError)?.lastError ?? null;

    const remaining = await countMatterPlaceholders(user.id);
    return NextResponse.json({ hydrated, skipped, failed, remaining, lastError });
  } catch (error) {
    if (error instanceof Error && error.message === "UNAUTHENTICATED") return authErrorResponse();
    const message = error instanceof Error ? error.message : "Matter hydration failed.";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}

async function hydrateURL(userId: string, url: string): Promise<HydrateURLResult> {
  const article = await prisma.article.findUnique({
    where: { userId_url: { userId, url } },
  });

  if (!article) {
    return { hydrated: 0, skipped: 1, failed: 0, lastError: null };
  }

  if (!isMatterPlaceholder(article.content)) {
    return { hydrated: 0, skipped: 1, failed: 0, lastError: null };
  }

  try {
    const extracted = await extractArticle(url);
    await prisma.article.update({
      where: { id: article.id },
      data: {
        title: article.title,
        author: extracted.author ?? article.author,
        description: extracted.description ?? article.description,
        content: extracted.content,
        image: extracted.image ?? article.image,
        favicon: extracted.favicon || article.favicon,
        siteName: extracted.siteName ?? article.siteName,
        publishedAt: extracted.publishedAt ?? article.publishedAt,
        ttr: extracted.ttr,
      },
    });
    return { hydrated: 1, skipped: 0, failed: 0, lastError: null };
  } catch (error) {
    const lastError = error instanceof Error ? `${url}: ${error.message}` : `${url}: fetch failed`;
    await prisma.article.update({
      where: { id: article.id },
      data: { updatedAt: new Date() },
    });
    return { hydrated: 0, skipped: 0, failed: 1, lastError };
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
