import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { createSession, hashPassword, setSessionCookie } from "@/lib/auth";

export async function POST(req: NextRequest) {
  const { email, password, name } = await req.json();
  const normalizedEmail = typeof email === "string" ? email.trim().toLowerCase() : "";

  if (!normalizedEmail || !normalizedEmail.includes("@")) {
    return NextResponse.json({ error: "A valid email is required" }, { status: 400 });
  }
  if (typeof password !== "string" || password.length < 8) {
    return NextResponse.json({ error: "Password must be at least 8 characters" }, { status: 400 });
  }

  try {
    const existingRealUsers = await prisma.user.count({
      where: { id: { not: "local_user" } },
    });
    const user = await prisma.user.create({
      data: {
        email: normalizedEmail,
        passwordHash: hashPassword(password),
        ...(typeof name === "string" && name.trim() && { name: name.trim() }),
      },
      select: { id: true, email: true, name: true },
    });

    if (existingRealUsers === 0) {
      await prisma.article.updateMany({ where: { userId: "local_user" }, data: { userId: user.id } });
      await prisma.label.updateMany({ where: { userId: "local_user" }, data: { userId: user.id } });
      await prisma.user.delete({ where: { id: "local_user" } }).catch(() => undefined);
    }

    const { token, expiresAt } = await createSession(user.id);
    const res = NextResponse.json({ user, token }, { status: 201 });
    setSessionCookie(res, token, expiresAt);
    return res;
  } catch {
    return NextResponse.json({ error: "An account with that email already exists" }, { status: 409 });
  }
}
