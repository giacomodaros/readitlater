import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const article = await prisma.article.findUnique({
    where: { id },
    include: { labels: true, highlights: true },
  });
  if (!article) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  if (!article.readAt) {
    await prisma.article.update({ where: { id }, data: { readAt: new Date() } });
  }
  return NextResponse.json(article);
}

export async function PATCH(req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const body = await req.json();
  const article = await prisma.article.update({
    where: { id },
    data: {
      ...(typeof body.archived === "boolean" && { archived: body.archived }),
      ...(typeof body.title === "string" && { title: body.title }),
    },
    include: { labels: true },
  });
  return NextResponse.json(article);
}

export async function DELETE(_req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  await prisma.article.delete({ where: { id } });
  return NextResponse.json({ ok: true });
}
