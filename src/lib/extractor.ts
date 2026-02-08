import { extract } from "@extractus/article-extractor";

export async function extractArticle(url: string) {
  const article = await extract(url);
  if (!article) throw new Error("Failed to extract article from URL");
  if (!article.content) throw new Error("No content found in article");
  return {
    url: article.url ?? url,
    title: article.title ?? "Untitled",
    author: article.author ?? null,
    description: article.description ?? null,
    content: article.content,
    image: article.image ?? null,
    favicon: article.favicon ?? null,
    siteName: article.source ?? null,
    publishedAt: article.published ? new Date(article.published) : null,
    ttr: article.ttr ?? null,
  };
}
