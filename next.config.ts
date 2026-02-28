import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Exclude native modules from serverless bundling.
  // On Vercel we always use libsql; better-sqlite3 is dev-only.
  serverExternalPackages: [
    "better-sqlite3",
    "@prisma/adapter-better-sqlite3",
  ],
};

export default nextConfig;
