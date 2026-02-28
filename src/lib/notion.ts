import { Client } from "@notionhq/client";

const notion = new Client({ auth: process.env.NOTION_TOKEN });

const DATABASE_ID = "6665244f-95cd-4197-8207-221ab2764b3b";

async function createArticlePage(params: {
  articleTitle: string;
  articleUrl: string;
  author: string | null;
  siteName: string | null;
  publishedAt: Date | null;
  labels: string[];
}): Promise<string> {
  const page = await notion.pages.create({
    parent: { database_id: DATABASE_ID },
    properties: {
      Name: {
        title: [{ text: { content: params.articleTitle } }],
      },
      Link: { url: params.articleUrl },
      ...(params.author && {
        Author: { rich_text: [{ text: { content: params.author } }] },
      }),
      ...(params.siteName && {
        Publisher: { rich_text: [{ text: { content: params.siteName } }] },
      }),
      ...(params.publishedAt && {
        "Publication Date": {
          date: { start: params.publishedAt.toISOString().split("T")[0] },
        },
      }),
      "Creation Date": {
        date: { start: new Date().toISOString().split("T")[0] },
      },
      ...(params.labels.length > 0 && {
        Labels: {
          multi_select: params.labels.map((name) => ({ name })),
        },
      }),
    },
  });
  return page.id;
}

async function updatePageLabels(notionPageId: string, labels: string[]): Promise<void> {
  await notion.pages.update({
    page_id: notionPageId,
    properties: {
      Labels: {
        multi_select: labels.map((name) => ({ name })),
      },
    },
  });
}

async function appendHighlight(notionPageId: string, text: string): Promise<void> {
  await notion.blocks.children.append({
    block_id: notionPageId,
    children: [
      {
        type: "quote",
        quote: {
          rich_text: [{ type: "text", text: { content: text.slice(0, 2000) } }],
        },
      },
    ],
  });
}

export async function syncHighlightToNotion(params: {
  notionPageId: string | null;
  highlightText: string;
  articleTitle: string;
  articleUrl: string;
  author: string | null;
  siteName: string | null;
  publishedAt: Date | null;
  labels: string[];
}): Promise<string> {
  if (!process.env.NOTION_TOKEN) return params.notionPageId ?? "";

  let pageId = params.notionPageId;

  if (!pageId) {
    pageId = await createArticlePage({
      articleTitle: params.articleTitle,
      articleUrl: params.articleUrl,
      author: params.author,
      siteName: params.siteName,
      publishedAt: params.publishedAt,
      labels: params.labels,
    });
  } else if (params.labels.length > 0) {
    // Keep labels in sync on existing pages
    await updatePageLabels(pageId, params.labels);
  }

  await appendHighlight(pageId, params.highlightText);
  return pageId;
}
