/**
 * One-time script to recompute ttr (minutes) for all existing articles.
 * Old values were in seconds from the extractor; new values are word-count based.
 *
 * Run with: npx tsx scripts/fix-ttr.ts
 */
import Database from "better-sqlite3";
import path from "path";

const dbPath = path.resolve(__dirname, "../dev.db");
const db = new Database(dbPath);

function computeReadingTime(html: string): number {
  const text = html.replace(/<[^>]*>/g, " ");
  const words = text.split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 238));
}

const articles = db.prepare("SELECT id, title, content, ttr FROM Article").all() as {
  id: string;
  title: string;
  content: string;
  ttr: number | null;
}[];

console.log(`Found ${articles.length} articles to update.`);

const update = db.prepare("UPDATE Article SET ttr = ? WHERE id = ?");

for (const a of articles) {
  const newTtr = computeReadingTime(a.content);
  if (a.ttr !== newTtr) {
    update.run(newTtr, a.id);
    console.log(`  "${a.title}": ${a.ttr} → ${newTtr} min`);
  } else {
    console.log(`  "${a.title}": already correct (${newTtr} min)`);
  }
}

console.log("Done.");
db.close();
