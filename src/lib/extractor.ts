function computeReadingTime(html: string): number {
  const text = html.replace(/<[^>]*>/g, " ");
  const words = text.split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 238));
}

function firstValue(...values: Array<string | null | undefined>) {
  return values.find((value) => value?.trim())?.trim() ?? null;
}

function faviconUrl(url: string): string {
  try {
    const { origin } = new URL(url);
    return `${origin}/favicon.ico`;
  } catch {
    return "";
  }
}

function absoluteUrl(value: string | null, baseUrl: string) {
  if (!value) return null;
  try {
    return new URL(value, baseUrl).toString();
  } catch {
    return value;
  }
}

function meta(document: Document, ...selectors: string[]) {
  for (const selector of selectors) {
    const value = document.querySelector(selector)?.getAttribute("content");
    if (value?.trim()) return value.trim();
  }
  return null;
}

type JsonLdNode = Record<string, unknown>;

function parseJsonLd(document: Document): JsonLdNode | null {
  const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
  const nodes = scripts.flatMap((script) => {
    try {
      const parsed = JSON.parse(script.textContent ?? "");
      if (Array.isArray(parsed)) return parsed;
      if (Array.isArray(parsed?.["@graph"])) return parsed["@graph"];
      return parsed ? [parsed] : [];
    } catch {
      return [];
    }
  });

  return nodes.find((node): node is JsonLdNode => {
    const type = node?.["@type"];
    const types = Array.isArray(type) ? type : [type];
    return types.some((item) => typeof item === "string" && /Article|NewsArticle|BlogPosting/i.test(item));
  }) ?? null;
}

function normalizeDate(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function normalizeAuthor(value: unknown) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value
      .map((author) => {
        if (typeof author === "string") return author;
        if (author && typeof author === "object" && "name" in author && typeof author.name === "string") {
          return author.name;
        }
        return null;
      })
      .filter(Boolean)
      .join(", ") || null;
  }
  if (value && typeof value === "object" && "name" in value && typeof value.name === "string") {
    return value.name;
  }
  return null;
}

function jsonString(value: unknown) {
  return typeof value === "string" ? value : null;
}

function jsonImage(value: unknown) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return jsonImage(value[0]);
  if (value && typeof value === "object" && "url" in value && typeof value.url === "string") {
    return value.url;
  }
  return null;
}

/** Parse pre-fetched HTML from the browser or server. */
export async function extractFromHtml(url: string, html: string) {
  const { parseHTML } = await import("linkedom");
  const { Readability } = await import("@mozilla/readability");

  const { document } = parseHTML(html);
  const jsonLd = parseJsonLd(document);
  const canonicalUrl = document.querySelector('link[rel="canonical"]')?.getAttribute("href");
  const fallbackTitle = document.querySelector("title")?.textContent ?? null;
  // linkedom's document is compatible with Readability
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const article = new Readability(document as any, {
    keepClasses: false,
  }).parse();

  if (!article) throw new Error("Could not parse article content");

  const content = article.content ?? "";
  const image = absoluteUrl(
    firstValue(
      meta(document, 'meta[property="og:image"]', 'meta[name="twitter:image"]'),
      jsonImage(jsonLd?.image)
    ),
    url
  );

  return {
    url: absoluteUrl(canonicalUrl, url) ?? url,
    title: firstValue(
      article.title,
      meta(document, 'meta[property="og:title"]', 'meta[name="twitter:title"]'),
      jsonString(jsonLd?.headline),
      fallbackTitle
    ) ?? "Untitled",
    author: firstValue(article.byline, normalizeAuthor(jsonLd?.author), meta(document, 'meta[name="author"]')),
    description: firstValue(
      article.excerpt,
      meta(document, 'meta[name="description"]', 'meta[property="og:description"]', 'meta[name="twitter:description"]'),
      jsonString(jsonLd?.description)
    ),
    content,
    image,
    favicon: faviconUrl(url),
    siteName: firstValue(
      article.siteName,
      meta(document, 'meta[property="og:site_name"]', 'meta[name="application-name"]'),
      new URL(url).hostname.replace(/^www\./, "")
    ),
    publishedAt: normalizeDate(
      firstValue(
        article.publishedTime,
        jsonString(jsonLd?.datePublished),
        meta(document, 'meta[property="article:published_time"]', 'meta[name="pubdate"]', 'meta[name="date"]')
      )
    ),
    ttr: computeReadingTime(content),
  };
}

/** Fetch and extract via server-side HTTP (works for open, non-rate-limited sites). */
export async function extractArticle(url: string) {
  const res = await fetch(url, {
    headers: {
      "Accept": "text/html,application/xhtml+xml",
      "User-Agent": "ArticleFetcher/1.0",
    },
    redirect: "follow",
  });

  if (!res.ok) throw new Error(`Failed to fetch article (${res.status})`);

  const contentType = res.headers.get("content-type") ?? "";
  if (!contentType.includes("text/html") && !contentType.includes("application/xhtml+xml")) {
    throw new Error("URL did not return an HTML document");
  }

  return extractFromHtml(res.url || url, await res.text());
}
