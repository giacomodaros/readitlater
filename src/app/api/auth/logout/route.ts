import { NextRequest, NextResponse } from "next/server";
import { clearSessionCookie, destroyCurrentSession } from "@/lib/auth";

export async function POST(req: NextRequest) {
  await destroyCurrentSession(req);
  const res = NextResponse.json({ ok: true });
  clearSessionCookie(res);
  return res;
}
