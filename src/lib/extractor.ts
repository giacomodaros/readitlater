function computeReadingTime(html: string): number {
  const text = html.replace(/<[^>]*>/g, " ");
  const words = text.split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 238));
}

function faviconUrl(url: string): string {
  try {
    const { origin } = new URL(url);
    return `${origin}/favicon.ico`;
  } catch {
    return "";
  }
}

/** Parse pre-fetched HTML from the browser (bypasses rate limits / paywalls). */
export async function extractFromHtml(url: string, html: string) {
  const { parseHTML } = await import("linkedom");
  const { Readability } = await import("@mozilla/readability");

  const { document } = parseHTML(html);
  // linkedom's document is compatible with Readability
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const article = new Readability(document as any).parse();

  if (!article) throw new Error("Could not parse article content");

  const content = article.content ?? "";
  const siteNameMeta =
    document
      .querySelector('meta[property="og:site_name"]')
      ?.getAttribute("content") ?? null;

  return {
    url,
    title: article.title ?? "Untitled",
    author: article.byline ?? null,
    description: article.excerpt ?? null,
    content,
    image:
      document
        .querySelector('meta[property="og:image"]')
        ?.getAttribute("content") ?? null,
    favicon: faviconUrl(url),
    siteName: siteNameMeta ?? new URL(url).hostname.replace(/^www\./, ""),
    publishedAt: null,
    ttr: computeReadingTime(content),
  };
}

/** Fetch and extract via server-side HTTP (works for open, non-rate-limited sites). */
export async function extractArticle(url: string) {
  const { extract } = await import("@extractus/article-extractor");
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
    ttr: computeReadingTime(article.content),
  };
}
