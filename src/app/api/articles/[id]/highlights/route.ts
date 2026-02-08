import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const highlights = await prisma.highlight.findMany({
    where: { articleId: id },
    orderBy: { startOffset: "asc" },
  });
  return NextResponse.json(highlights);
}

export async function POST(req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const body = await req.json();
  const { text, startOffset, endOffset, color, note } = body;

  if (typeof text !== "string" || typeof startOffset !== "number" || typeof endOffset !== "number") {
    return NextResponse.json({ error: "Invalid highlight data" }, { status: 400 });
  }

  const highlight = await prisma.highlight.create({
    data: {
      articleId: id,
      text,
      startOffset,
      endOffset,
      ...(color && { color }),
      ...(note && { note }),
    },
  });

  return NextResponse.json(highlight, { status: 201 });
}
