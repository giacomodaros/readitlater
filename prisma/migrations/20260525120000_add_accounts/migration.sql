-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "name" TEXT,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "Session" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" DATETIME NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "Session_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- Existing single-user data is moved under this local account.
INSERT INTO "User" ("id", "email", "passwordHash", "name")
VALUES ('local_user', '__local_migration__@reader.local', 'migrated-login-disabled', 'Local Library');

-- AlterTable
ALTER TABLE "Article" ADD COLUMN "userId" TEXT NOT NULL DEFAULT 'local_user';
ALTER TABLE "Label" ADD COLUMN "userId" TEXT NOT NULL DEFAULT 'local_user';

-- Replace global uniqueness with per-account uniqueness.
DROP INDEX IF EXISTS "Article_url_key";
DROP INDEX IF EXISTS "Label_name_key";
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");
CREATE UNIQUE INDEX "Session_tokenHash_key" ON "Session"("tokenHash");
CREATE INDEX "Session_userId_idx" ON "Session"("userId");
CREATE INDEX "Session_expiresAt_idx" ON "Session"("expiresAt");
CREATE UNIQUE INDEX "Article_userId_url_key" ON "Article"("userId", "url");
CREATE INDEX "Article_userId_createdAt_idx" ON "Article"("userId", "createdAt");
CREATE UNIQUE INDEX "Label_userId_name_key" ON "Label"("userId", "name");
CREATE INDEX "Label_userId_name_idx" ON "Label"("userId", "name");
