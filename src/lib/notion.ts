import { Client } from "@notionhq/client";

const notion = new Client({ auth: process.env.NOTION_TOKEN });

// Matter Library database ID
const DATABASE_ID = "6665244f-95cd-4197-8207-221ab2764b3b";

export async function sendHighlightToNotion(params: {
  highlightText: string;
  articleTitle: string;
  articleUrl: string;
  author: string | null;
  siteName: string | null;
  publishedAt: Date | null;
}) {
  if (!process.env.NOTION_TOKEN) return; // silently skip if not configured

  await notion.pages.create({
    parent: { database_id: DATABASE_ID },
    properties: {
      Name: {
        title: [{ text: { content: params.highlightText.slice(0, 2000) } }],
      },
      Title: {
        rich_text: [{ text: { content: params.articleTitle } }],
      },
      Link: {
        url: params.articleUrl,
      },
      ...(params.author && {
        Author: {
          rich_text: [{ text: { content: params.author } }],
        },
      }),
      ...(params.siteName && {
        Publisher: {
          rich_text: [{ text: { content: params.siteName } }],
        },
      }),
      ...(params.publishedAt && {
        "Publication Date": {
          date: { start: params.publishedAt.toISOString().split("T")[0] },
        },
      }),
      "Creation Date": {
        date: { start: new Date().toISOString().split("T")[0] },
      },
    },
  });
}
