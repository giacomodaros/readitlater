import { NextResponse } from "next/server";
import { authErrorResponse, getCurrentUser } from "@/lib/auth";

export async function GET() {
  const user = await getCurrentUser();
  if (!user) return authErrorResponse();
  return NextResponse.json({ user });
}
