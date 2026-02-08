import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

type Ctx = { params: Promise<{ id: string }> };

export async function PATCH(req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  const body = await req.json();
  const label = await prisma.label.update({
    where: { id },
    data: {
      ...(typeof body.name === "string" && { name: body.name }),
      ...(typeof body.color === "string" && { color: body.color }),
    },
  });
  return NextResponse.json(label);
}

export async function DELETE(_req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;
  await prisma.label.delete({ where: { id } });
  return NextResponse.json({ ok: true });
}
