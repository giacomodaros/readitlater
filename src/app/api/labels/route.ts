import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";

export async function GET() {
  const labels = await prisma.label.findMany({
    orderBy: { name: "asc" },
    include: { _count: { select: { articles: true } } },
  });
  return NextResponse.json(labels);
}

export async function POST(req: NextRequest) {
  const { name, color } = await req.json();

  if (!name || typeof name !== "string") {
    return NextResponse.json({ error: "Name is required" }, { status: 400 });
  }

  const label = await prisma.label.create({
    data: { name, color: color || "#6366f1" },
  });

  return NextResponse.json(label, { status: 201 });
}
