import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { extractArticle } from "../src/lib/extractor";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const DEFAULT_INPUT = path.join(ROOT, "_matter_history.csv");
const DEFAULT_OUTPUT = path.join(ROOT, "parser-audit");
const DEFAULT_DOMAIN_COUNT = 20;
const DEFAULT_SAMPLES_PER_DOMAIN = 3;
const DEFAULT_TIMEOUT_MS = 20_000;

type MatterRecord = {
  title: string;
  author: string;
  publisher: string;
  url: string;
  tags: string;
  wordCount: number | null;
  inQueue: boolean;
  favorited: boolean;
  read: boolean;
  highlightCount: number | null;
  lastInteractionDate: string;
  fileId: string;
};

type AuditOptions = {
  input: string;
  output: string;
  domainCount: number;
  samplesPerDomain: number;
  timeoutMs: number;
};

type ExtractedArticle = Awaited<ReturnType<typeof extractArticle>>;

type SampleResult = {
  domain: string;
  url: string;
  matterTitle: string;
  extractedTitle: string | null;
  matterWords: number | null;
  extractedWords: number;
  score: number;
  status: "pass" | "warn" | "fail";
  issues: string[];
  error: string | null;
  ttr: number | null;
  siteName: string | null;
};

type DomainResult = {
  domain: string;
  totalInHistory: number;
  sampled: number;
  averageScore: number;
  pass: number;
  warn: number;
  fail: number;
  commonIssues: Array<{ issue: string; count: number }>;
  samples: SampleResult[];
};

type AuditReport = {
  generatedAt: string;
  input: string;
  options: AuditOptions;
  summary: ReturnType<typeof summarizeRun>;
  domains: DomainResult[];
};

async function main() {
  const options = parseArgs(process.argv.slice(2));
  await fs.mkdir(options.output, { recursive: true });

  const csv = await fs.readFile(options.input, "utf8");
  const records = parseMatterCSV(csv).filter((record) => isArticleURL(record.url));
  const topDomains = topDomainsFrom(records, options.domainCount);

  const domainResults: DomainResult[] = [];
  for (const domain of topDomains) {
    const domainRecords = records.filter((record) => domainFromURL(record.url) === domain.domain);
    const samples = pickSamples(domainRecords, options.samplesPerDomain);
    const results: SampleResult[] = [];

    console.log(`\n${domain.domain} (${domain.count} in history)`);
    for (const sample of samples) {
      const result = await auditSample(domain.domain, sample, options.timeoutMs);
      results.push(result);
      console.log(`  ${result.status.toUpperCase().padEnd(4)} ${result.score.toString().padStart(3)} ${sample.url}`);
      if (result.issues.length) console.log(`       ${result.issues.join("; ")}`);
      if (result.error) console.log(`       ${result.error}`);
    }

    domainResults.push(summarizeDomain(domain.domain, domain.count, results));
  }

  const report: AuditReport = {
    generatedAt: new Date().toISOString(),
    input: path.relative(ROOT, options.input),
    options,
    summary: summarizeRun(domainResults),
    domains: domainResults,
  };

  const jsonPath = path.join(options.output, "parser-audit.json");
  const markdownPath = path.join(options.output, "parser-audit.md");
  await fs.writeFile(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  await fs.writeFile(markdownPath, renderMarkdown(report));

  console.log(`\nWrote ${path.relative(ROOT, jsonPath)}`);
  console.log(`Wrote ${path.relative(ROOT, markdownPath)}`);
}

async function auditSample(domain: string, record: MatterRecord, timeoutMs: number): Promise<SampleResult> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const extracted = await extractArticle(record.url, { signal: controller.signal });
    return evaluateExtraction(domain, record, extracted, null);
  } catch (error) {
    return evaluateExtraction(domain, record, null, error instanceof Error ? error.message : "Unknown extraction error");
  } finally {
    clearTimeout(timeout);
  }
}

function evaluateExtraction(
  domain: string,
  record: MatterRecord,
  extracted: ExtractedArticle | null,
  error: string | null,
): SampleResult {
  const issues: string[] = [];
  const extractedWords = extracted ? wordCount(stripHTML(extracted.content)) : 0;
  const titleSimilarity = extracted ? similarity(normalizeComparable(record.title), normalizeComparable(extracted.title)) : 0;

  let score = 100;
  if (error) {
    score = 0;
    issues.push("extractor threw");
  }
  if (extracted && extractedWords < 120) {
    score -= 35;
    issues.push("very short content");
  }
  if (extracted && record.wordCount && record.wordCount >= 300) {
    const ratio = extractedWords / record.wordCount;
    if (ratio < 0.35) {
      score -= 30;
      issues.push(`word count too low (${Math.round(ratio * 100)}% of Matter)`);
    } else if (ratio < 0.65) {
      score -= 15;
      issues.push(`word count low (${Math.round(ratio * 100)}% of Matter)`);
    }
    if (ratio > 2.2) {
      score -= 20;
      issues.push(`word count too high (${Math.round(ratio * 100)}% of Matter)`);
    }
  }
  if (extracted && titleSimilarity < 0.35 && record.title.trim()) {
    score -= 18;
    issues.push("title mismatch");
  }
  if (extracted && hasBoilerplate(extracted.content)) {
    score -= 18;
    issues.push("boilerplate leaked");
  }
  if (extracted && looksLikePlaceholder(extracted.content)) {
    score -= 45;
    issues.push("placeholder-like content");
  }
  if (extracted && isPaywallShell(extracted.content)) {
    score -= 35;
    issues.push("paywall/login shell");
  }

  score = Math.max(0, Math.min(100, Math.round(score)));
  const status: SampleResult["status"] = score >= 78 ? "pass" : score >= 50 ? "warn" : "fail";

  return {
    domain,
    url: record.url,
    matterTitle: record.title,
    extractedTitle: extracted?.title ?? null,
    matterWords: record.wordCount,
    extractedWords,
    score,
    status,
    issues,
    error,
    ttr: extracted?.ttr ?? null,
    siteName: extracted?.siteName ?? null,
  };
}

function summarizeDomain(domain: string, totalInHistory: number, samples: SampleResult[]): DomainResult {
  const issueCounts = new Map<string, number>();
  for (const sample of samples) {
    for (const issue of sample.issues) {
      issueCounts.set(issue, (issueCounts.get(issue) ?? 0) + 1);
    }
  }

  return {
    domain,
    totalInHistory,
    sampled: samples.length,
    averageScore: samples.length ? Math.round(samples.reduce((sum, sample) => sum + sample.score, 0) / samples.length) : 0,
    pass: samples.filter((sample) => sample.status === "pass").length,
    warn: samples.filter((sample) => sample.status === "warn").length,
    fail: samples.filter((sample) => sample.status === "fail").length,
    commonIssues: Array.from(issueCounts.entries())
      .sort((a, b) => b[1] - a[1])
      .map(([issue, count]) => ({ issue, count })),
    samples,
  };
}

function summarizeRun(domains: DomainResult[]) {
  const samples = domains.flatMap((domain) => domain.samples);
  return {
    domains: domains.length,
    samples: samples.length,
    averageScore: samples.length ? Math.round(samples.reduce((sum, sample) => sum + sample.score, 0) / samples.length) : 0,
    pass: samples.filter((sample) => sample.status === "pass").length,
    warn: samples.filter((sample) => sample.status === "warn").length,
    fail: samples.filter((sample) => sample.status === "fail").length,
  };
}

function renderMarkdown(report: AuditReport) {
  const lines: string[] = [
    "# Parser Audit",
    "",
    `Generated: ${report.generatedAt}`,
    `Input: ${report.input}`,
    "",
    `Domains: ${report.summary.domains}`,
    `Samples: ${report.summary.samples}`,
    `Average score: ${report.summary.averageScore}`,
    `Pass / warn / fail: ${report.summary.pass} / ${report.summary.warn} / ${report.summary.fail}`,
    "",
    "## Domains",
    "",
  ];

  for (const domain of report.domains) {
    lines.push(
      `### ${domain.domain}`,
      "",
      `History rows: ${domain.totalInHistory}`,
      `Sampled: ${domain.sampled}`,
      `Average score: ${domain.averageScore}`,
      `Pass / warn / fail: ${domain.pass} / ${domain.warn} / ${domain.fail}`,
      "",
    );

    if (domain.commonIssues.length) {
      lines.push("Common issues:");
      for (const issue of domain.commonIssues) {
        lines.push(`- ${issue.issue}: ${issue.count}`);
      }
      lines.push("");
    }

    lines.push("| Status | Score | Matter words | Extracted words | URL | Issues |");
    lines.push("| --- | ---: | ---: | ---: | --- | --- |");
    for (const sample of domain.samples) {
      lines.push(
        `| ${sample.status} | ${sample.score} | ${sample.matterWords ?? ""} | ${sample.extractedWords} | ${markdownCell(sample.url)} | ${markdownCell(sample.error ?? sample.issues.join("; "))} |`,
      );
    }
    lines.push("");
  }

  return `${lines.join("\n")}\n`;
}

function parseArgs(args: string[]): AuditOptions {
  const options: AuditOptions = {
    input: DEFAULT_INPUT,
    output: DEFAULT_OUTPUT,
    domainCount: DEFAULT_DOMAIN_COUNT,
    samplesPerDomain: DEFAULT_SAMPLES_PER_DOMAIN,
    timeoutMs: DEFAULT_TIMEOUT_MS,
  };

  for (const arg of args) {
    const [key, rawValue] = arg.split("=");
    const value = rawValue ?? "";
    if (key === "--input" && value) options.input = path.resolve(value);
    if (key === "--output" && value) options.output = path.resolve(value);
    if (key === "--domains" && Number.isFinite(Number(value))) options.domainCount = Math.max(1, Number(value));
    if (key === "--samples" && Number.isFinite(Number(value))) options.samplesPerDomain = Math.max(1, Number(value));
    if (key === "--timeout-ms" && Number.isFinite(Number(value))) options.timeoutMs = Math.max(1000, Number(value));
  }

  return options;
}

function parseMatterCSV(csv: string): MatterRecord[] {
  const rows = parseCSVRows(csv.replace(/^\uFEFF/, ""));
  const firstNonEmpty = rows.findIndex((row) => row.some((cell) => cell.trim()));
  if (firstNonEmpty === -1) return [];

  const header = rows[firstNonEmpty].map(normalizeHeader);
  const indexes = {
    title: columnIndex(header, ["title"]),
    author: columnIndex(header, ["author"]),
    publisher: columnIndex(header, ["publisher", "publication", "site", "site name"]),
    url: columnIndex(header, ["url", "article url", "original url"]),
    tags: columnIndex(header, ["tags"]),
    wordCount: columnIndex(header, ["word count", "words", "wordcount"]),
    inQueue: columnIndex(header, ["in queue", "queue", "queued"]),
    favorited: columnIndex(header, ["favorited", "favorite", "favourite"]),
    read: columnIndex(header, ["read"]),
    highlightCount: columnIndex(header, ["highlight count", "highlights"]),
    lastInteractionDate: columnIndex(header, ["last interaction date", "last interacted at", "date", "saved date"]),
    fileId: columnIndex(header, ["file id", "fileid"]),
  };

  if (indexes.url === -1) throw new Error("Matter CSV is missing a URL column.");

  return rows.slice(firstNonEmpty + 1).flatMap((row) => {
    if (!row.some((cellValue) => cellValue.trim())) return [];
    const url = normalizeURL(cell(row, indexes.url));
    if (!url) return [];

    return [{
      title: cleanText(cell(row, indexes.title)) || siteNameFromURL(url),
      author: cleanText(cell(row, indexes.author)) || "",
      publisher: cleanText(cell(row, indexes.publisher)) || "",
      url,
      tags: cleanText(cell(row, indexes.tags)) || "",
      wordCount: parseInteger(cell(row, indexes.wordCount)),
      inQueue: parseBoolean(cell(row, indexes.inQueue)),
      favorited: parseBoolean(cell(row, indexes.favorited)),
      read: parseBoolean(cell(row, indexes.read)),
      highlightCount: parseInteger(cell(row, indexes.highlightCount)),
      lastInteractionDate: cell(row, indexes.lastInteractionDate),
      fileId: cell(row, indexes.fileId),
    }];
  });
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

function topDomainsFrom(records: MatterRecord[], count: number) {
  const counts = new Map<string, number>();
  for (const record of records) {
    const domain = domainFromURL(record.url);
    if (!domain) continue;
    counts.set(domain, (counts.get(domain) ?? 0) + 1);
  }
  return Array.from(counts.entries())
    .map(([domain, total]) => ({ domain, count: total }))
    .sort((a, b) => b.count - a.count || a.domain.localeCompare(b.domain))
    .slice(0, count);
}

function pickSamples(records: MatterRecord[], count: number) {
  const sorted = records
    .slice()
    .sort((a, b) => (b.wordCount ?? 0) - (a.wordCount ?? 0));
  const samples: MatterRecord[] = [];
  for (const index of [0, Math.floor(sorted.length / 2), sorted.length - 1]) {
    const record = sorted[index];
    if (record && !samples.some((sample) => sample.url === record.url)) samples.push(record);
    if (samples.length >= count) return samples;
  }
  for (const record of sorted) {
    if (!samples.some((sample) => sample.url === record.url)) samples.push(record);
    if (samples.length >= count) break;
  }
  return samples;
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

function isArticleURL(value: string) {
  try {
    const url = new URL(value);
    return !/\.(pdf|jpg|jpeg|png|gif|webp|mp3|mp4|mov|zip)$/i.test(url.pathname);
  } catch {
    return false;
  }
}

function domainFromURL(value: string) {
  try {
    return new URL(value).hostname.replace(/^www\./, "").toLowerCase();
  } catch {
    return "";
  }
}

function siteNameFromURL(value: string) {
  return domainFromURL(value) || "Untitled";
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

function stripHTML(html: string) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function wordCount(text: string) {
  return text.split(/\s+/).filter(Boolean).length;
}

function hasBoilerplate(html: string) {
  const text = stripHTML(html).toLowerCase();
  return [
    "story continues below advertisement",
    "advertisement advertisement",
    "subscribe to continue reading",
    "accept cookies",
    "sign in subscribe",
  ].some((phrase) => text.includes(phrase));
}

function looksLikePlaceholder(html: string) {
  const text = stripHTML(html).toLowerCase();
  return text.includes("imported from matter") || text.includes("no readable text was saved");
}

function isPaywallShell(html: string) {
  const text = stripHTML(html).toLowerCase();
  const words = wordCount(text);
  return words < 250 && /subscribe|sign in|log in|register/.test(text);
}

function normalizeComparable(value: string) {
  return value
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function similarity(a: string, b: string) {
  if (!a || !b) return 0;
  if (a === b) return 1;
  const aTokens = new Set(a.split(" ").filter(Boolean));
  const bTokens = new Set(b.split(" ").filter(Boolean));
  const intersection = Array.from(aTokens).filter((token) => bTokens.has(token)).length;
  const union = new Set([...aTokens, ...bTokens]).size;
  return union ? intersection / union : 0;
}

function markdownCell(value: string) {
  return value.replace(/\|/g, "\\|").replace(/\n/g, " ");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
