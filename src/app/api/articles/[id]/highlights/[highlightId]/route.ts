import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";

type Ctx = { params: Promise<{ id: string; highlightId: string }> };

export async function DELETE(_req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id, highlightId } = await ctx.params;
    const highlight = await prisma.highlight.findFirst({
      where: { id: highlightId, articleId: id, article: { userId: user.id } },
      select: { id: true },
    });
    if (!highlight) return NextResponse.json({ error: "Not found" }, { status: 404 });
    await prisma.highlight.delete({ where: { id: highlightId } });
    return NextResponse.json({ ok: true });
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}
