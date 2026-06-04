import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";

type Ctx = { params: Promise<{ id: string }> };

export async function PUT(req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id } = await ctx.params;
    const { labelIds } = await req.json();
    const parsedLabelIds = parseLabelIds(labelIds);

    if (!Array.isArray(labelIds)) {
      return NextResponse.json(
        { error: "labelIds must be an array" },
        { status: 400 }
      );
    }

    const [article, labels] = await Promise.all([
      prisma.article.findFirst({ where: { id, userId: user.id }, select: { id: true } }),
      prisma.label.findMany({
        where: { id: { in: parsedLabelIds }, userId: user.id },
        select: { id: true },
      }),
    ]);

    if (!article) return NextResponse.json({ error: "Not found" }, { status: 404 });
    if (labels.length !== parsedLabelIds.length) {
      return NextResponse.json({ error: "One or more labels were not found" }, { status: 400 });
    }

    const updated = await prisma.article.update({
      where: { id },
      data: {
        labels: { set: labels.map((l) => ({ id: l.id })) },
      },
      include: { labels: true },
    });

    return NextResponse.json(updated);
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}

function parseLabelIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const ids: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string") continue;
    const id = item.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}
