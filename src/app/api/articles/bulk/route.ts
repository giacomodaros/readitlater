import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";

const MAX_BULK_ARTICLES = 1000;

export async function POST(req: NextRequest) {
  try {
    const user = await requireUser();
    const body = await req.json();
    const ids = parseArticleIds(body.ids);
    const action = typeof body.action === "string" ? body.action : "";

    if (!ids.length) {
      return NextResponse.json({ count: 0 });
    }
    if (ids.length > MAX_BULK_ARTICLES) {
      return NextResponse.json({ error: `Select ${MAX_BULK_ARTICLES} articles or fewer at a time.` }, { status: 413 });
    }

    if (action === "delete") {
      const result = await prisma.article.deleteMany({
        where: { userId: user.id, id: { in: ids } },
      });
      return NextResponse.json({ count: result.count });
    }

    if (action === "archive") {
      if (typeof body.archived !== "boolean") {
        return NextResponse.json({ error: "archived must be a boolean." }, { status: 400 });
      }
      const result = await prisma.article.updateMany({
        where: { userId: user.id, id: { in: ids } },
        data: { archived: body.archived },
      });
      return NextResponse.json({ count: result.count });
    }

    if (action === "read") {
      if (typeof body.read !== "boolean") {
        return NextResponse.json({ error: "read must be a boolean." }, { status: 400 });
      }
      const result = await prisma.article.updateMany({
        where: { userId: user.id, id: { in: ids } },
        data: { readAt: body.read ? new Date() : null },
      });
      return NextResponse.json({ count: result.count });
    }

    return NextResponse.json({ error: "Unsupported bulk action." }, { status: 400 });
  } catch (error) {
    if (error instanceof Error && error.message === "UNAUTHENTICATED") return authErrorResponse();
    const message = error instanceof Error ? error.message : "Bulk action failed.";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}

function parseArticleIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string") continue;
    const id = item.trim();
    if (id) seen.add(id);
  }

  return Array.from(seen);
}
