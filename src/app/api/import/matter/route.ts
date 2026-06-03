import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { authErrorResponse, requireUser } from "@/lib/auth";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const CHUNK_SIZE = 75;
const WORDS_PER_MINUTE = 238;

type MatterRecord = {
  url: string;
  title: string | null;
  author: string | null;
  publisher: string | null;
  wordCount: number | null;
  inQueue: boolean;
  read: boolean;
  lastInteractionDate: Date | null;
};

type ParsedMatterCSV = {
  totalRows: number;
  skipped: number;
  records: MatterRecord[];
};

export async function POST(req: NextRequest) {
  try {
    const user = await requireUser();
    const csv = await readCSVBody(req);
    const parsed = parseMatterCSV(csv);

    let skipped = parsed.skipped;
    const byURL = new Map<string, MatterRecord>();
    for (const record of parsed.records) {
      const url = normalizeURL(record.url);
      if (!url) {
        skipped += 1;
        continue;
      }
      if (byURL.has(url)) skipped += 1;
      byURL.set(url, { ...record, url });
    }

    const records = Array.from(byURL.values());
    let queued = 0;
    let archived = 0;
    let failed = 0;
    let lastError: string | null = null;

    for (let index = 0; index < records.length; index += CHUNK_SIZE) {
      const chunk = records.slice(index, index + CHUNK_SIZE);
      try {
        await upsertMatterChunk(user.id, chunk);
        for (const record of chunk) {
          if (record.inQueue) queued += 1;
          else archived += 1;
        }
      } catch (error) {
        for (const record of chunk) {
          try {
            await upsertMatterChunk(user.id, [record]);
            if (record.inQueue) queued += 1;
            else archived += 1;
          } catch (singleError) {
            failed += 1;
            lastError = singleError instanceof Error ? singleError.message : "Import failed.";
          }
        }
        if (!lastError) {
          lastError = error instanceof Error ? error.message : "Import failed.";
        }
      }
    }

    return NextResponse.json({
      totalRows: parsed.totalRows,
      queued,
      archived,
      skipped,
      failed,
      lastError,
    });
  } catch (error) {
    if (error instanceof Error && error.message === "UNAUTHENTICATED") return authErrorResponse();
    const message = error instanceof Error ? error.message : "Matter import failed.";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}

async function readCSVBody(req: NextRequest) {
  const contentType = req.headers.get("content-type")?.toLowerCase() ?? "";
  if (contentType.includes("application/json")) {
    const body = await req.json();
    const csv = typeof body.csv === "string" ? body.csv : "";
    if (!csv.trim()) throw new Error("CSV is empty.");
    return csv;
  }

  const csv = await req.text();
  if (!csv.trim()) throw new Error("CSV is empty.");
  return csv;
}

async function upsertMatterChunk(userId: string, records: MatterRecord[]) {
  await prisma.$transaction(
    records.map((record) => {
      const data = articleData(userId, record);
      return prisma.article.upsert({
        where: { userId_url: { userId, url: record.url } },
        create: data,
        update: {
          title: data.title,
          author: data.author,
          favicon: data.favicon,
          siteName: data.siteName,
          ttr: data.ttr,
          archived: data.archived,
          readAt: data.readAt,
        },
      });
    }),
  );
}

function articleData(userId: string, record: MatterRecord) {
  const parsed = new URL(record.url);
  const hostname = parsed.hostname.replace(/^www\./, "");
  const title = cleanText(record.title) ?? hostname;
  const author = cleanText(record.author);
  const siteName = cleanText(record.publisher) ?? hostname;
  const readAt = record.read ? record.lastInteractionDate ?? new Date() : null;
  const ttr = record.wordCount && record.wordCount > 0
    ? Math.max(1, Math.round(record.wordCount / WORDS_PER_MINUTE))
    : 1;

  return {
    userId,
    url: record.url,
    title,
    author,
    description: null,
    content: placeholderContent(title, siteName, record.url),
    image: null,
    favicon: `${parsed.origin}/favicon.ico`,
    siteName,
    publishedAt: null,
    ttr,
    archived: !record.inQueue,
    readAt,
    createdAt: record.lastInteractionDate ?? undefined,
  };
}

function placeholderContent(title: string, siteName: string, url: string) {
  return [
    `<p>${escapeHtml(title)}</p>`,
    `<p>Imported from Matter${siteName ? ` (${escapeHtml(siteName)})` : ""}.</p>`,
    `<p><a href="${escapeHtml(url)}">${escapeHtml(url)}</a></p>`,
  ].join("");
}

function parseMatterCSV(csv: string): ParsedMatterCSV {
  const rows = parseCSVRows(csv.replace(/^\uFEFF/, ""));
  const firstNonEmpty = rows.findIndex((row) => row.some((cell) => cell.trim()));
  if (firstNonEmpty === -1) throw new Error("CSV is empty.");

  const header = rows[firstNonEmpty].map(normalizeHeader);
  const urlIndex = columnIndex(header, ["url", "article url", "original url"]);
  if (urlIndex === -1) throw new Error("Matter CSV is missing the URL column.");

  const titleIndex = columnIndex(header, ["title"]);
  const authorIndex = columnIndex(header, ["author"]);
  const publisherIndex = columnIndex(header, ["publisher", "publication", "site", "site name"]);
  const wordCountIndex = columnIndex(header, ["word count", "words", "wordcount"]);
  const inQueueIndex = columnIndex(header, ["in queue", "queue", "queued"]);
  const readIndex = columnIndex(header, ["read"]);
  const lastInteractionIndex = columnIndex(header, [
    "last interaction date",
    "last interacted at",
    "date",
    "saved date",
  ]);

  let skipped = 0;
  const records: MatterRecord[] = [];

  for (const row of rows.slice(firstNonEmpty + 1)) {
    if (!row.some((cell) => cell.trim())) continue;
    const url = cell(row, urlIndex);
    if (!url) {
      skipped += 1;
      continue;
    }
    records.push({
      url,
      title: cleanText(cell(row, titleIndex)),
      author: cleanText(cell(row, authorIndex)),
      publisher: cleanText(cell(row, publisherIndex)),
      wordCount: parseInteger(cell(row, wordCountIndex)),
      inQueue: inQueueIndex === -1 ? false : parseBoolean(cell(row, inQueueIndex)),
      read: readIndex !== -1 && parseBoolean(cell(row, readIndex)),
      lastInteractionDate: parseMatterDate(cell(row, lastInteractionIndex)),
    });
  }

  return { totalRows: records.length + skipped, skipped, records };
}

function parseCSVRows(text: string) {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (inQuotes) {
      if (char === "\"" && next === "\"") {
        field += "\"";
        index += 1;
      } else if (char === "\"") {
        inQuotes = false;
      } else {
        field += char;
      }
      continue;
    }

    if (char === "\"") {
      inQuotes = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (char !== "\r") {
      field += char;
    }
  }

  row.push(field);
  rows.push(row);
  return rows;
}

function normalizeURL(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const normalized = /^[a-z][a-z\d+\-.]*:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    const url = new URL(normalized);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function cell(row: string[], index: number) {
  return index >= 0 && index < row.length ? decodeMatterText(row[index]).trim() : "";
}

function columnIndex(header: string[], aliases: string[]) {
  return header.findIndex((value) => aliases.includes(value));
}

function normalizeHeader(value: string) {
  return value.replace(/^\uFEFF/, "").trim().toLowerCase();
}

function parseBoolean(value: string) {
  const normalized = value.trim().toLowerCase();
  return normalized === "true" || normalized === "yes" || normalized === "1" || normalized === "y";
}

function parseInteger(value: string) {
  const parsed = Number.parseInt(value.replace(/[^\d-]/g, ""), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function parseMatterDate(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?/);
  if (match) {
    const [, year, month, day, hour = "0", minute = "0", second = "0"] = match;
    return new Date(
      Number(year),
      Number(month) - 1,
      Number(day),
      Number(hour),
      Number(minute),
      Number(second),
    );
  }
  const date = new Date(trimmed);
  return Number.isNaN(date.getTime()) ? null : date;
}

function cleanText(value: string | null | undefined) {
  const cleaned = decodeMatterText(value ?? "").replace(/\s+/g, " ").trim();
  return cleaned || null;
}

function decodeMatterText(value: string) {
  return value.replace(/=\?utf-8\?q\?([^?]+)\?=/gi, (_, encoded: string) => {
    const bytes = encoded.replace(/_/g, " ").replace(/=([0-9a-f]{2})/gi, "%$1");
    try {
      return decodeURIComponent(bytes);
    } catch {
      return encoded;
    }
  });
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
