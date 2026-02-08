import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

type Ctx = { params: Promise<{ id: string }> };

export async function PUT(req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const { labelIds } = await req.json();

  if (!Array.isArray(labelIds)) {
    return NextResponse.json(
      { error: "labelIds must be an array" },
      { status: 400 }
    );
  }

  const article = await prisma.article.update({
    where: { id },
    data: {
      labels: { set: labelIds.map((lid: string) => ({ id: lid })) },
    },
    include: { labels: true },
  });

  return NextResponse.json(article);
}
