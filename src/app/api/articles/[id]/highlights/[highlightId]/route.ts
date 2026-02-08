import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

type Ctx = { params: Promise<{ id: string; highlightId: string }> };

export async function DELETE(_req: NextRequest, ctx: Ctx) {
  const { highlightId } = await ctx.params;
  await prisma.highlight.delete({ where: { id: highlightId } });
  return NextResponse.json({ ok: true });
}
