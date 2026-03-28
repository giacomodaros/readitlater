import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { Client } from "@notionhq/client";

type Ctx = { params: Promise<{ id: string }> };

const DATABASE_ID = "6665244f-95cd-4197-8207-221ab2764b3b";

export async function POST(_req: NextRequest, ctx: Ctx) {
  const { id } = await ctx.params;

  if (!process.env.NOTION_TOKEN) {
    return NextResponse.json({ error: "Notion not configured" }, { status: 400 });
  }

  const article = await prisma.article.findUnique({
    where: { id },
    include: { labels: true },
  });
  if (!article) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  // If already synced, return existing page URL
  if (article.notionPageId) {
    return NextResponse.json({ notionPageId: article.notionPageId });
  }

  const notion = new Client({ auth: process.env.NOTION_TOKEN });

  const page = await notion.pages.create({
    parent: { database_id: DATABASE_ID },
    properties: {
      Name: { title: [{ text: { content: article.title } }] },
      Link: { url: article.url },
      ...(article.author && {
        Author: { rich_text: [{ text: { content: article.author } }] },
      }),
      ...(article.siteName && {
        Publisher: { rich_text: [{ text: { content: article.siteName } }] },
      }),
      ...(article.publishedAt && {
        "Publication Date": {
          date: { start: article.publishedAt.toISOString().split("T")[0] },
        },
      }),
      "Creation Date": {
        date: { start: new Date().toISOString().split("T")[0] },
      },
      ...(article.labels.length > 0 && {
        Labels: {
          multi_select: article.labels.map((l) => ({ name: l.name })),
        },
      }),
    },
  });

  await prisma.article.update({
    where: { id },
    data: { notionPageId: page.id },
  });

  return NextResponse.json({ notionPageId: page.id });
}
