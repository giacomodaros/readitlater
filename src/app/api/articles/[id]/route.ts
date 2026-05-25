import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id } = await ctx.params;
    const article = await prisma.article.findFirst({
      where: { id, userId: user.id },
      include: { labels: true, highlights: true },
    });
    if (!article) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    if (!article.readAt) {
      await prisma.article.update({ where: { id }, data: { readAt: new Date() } });
    }
    return NextResponse.json(article);
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}

export async function PATCH(req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id } = await ctx.params;
    const body = await req.json();
    const article = await prisma.article.updateMany({
      where: { id, userId: user.id },
      data: {
        ...(typeof body.archived === "boolean" && { archived: body.archived }),
        ...(typeof body.title === "string" && { title: body.title }),
      },
    });
    if (article.count === 0) return NextResponse.json({ error: "Not found" }, { status: 404 });
    const updated = await prisma.article.findFirst({
      where: { id, userId: user.id },
      include: { labels: true },
    });
    return NextResponse.json(updated);
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}

export async function DELETE(_req: NextRequest, ctx: Ctx) {
  try {
    const user = await requireUser();
    const { id } = await ctx.params;
    const result = await prisma.article.deleteMany({ where: { id, userId: user.id } });
    if (result.count === 0) return NextResponse.json({ error: "Not found" }, { status: 404 });
    return NextResponse.json({ ok: true });
  } catch (e) {
    if (e instanceof Error && e.message === "UNAUTHENTICATED") return authErrorResponse();
    throw e;
  }
}
