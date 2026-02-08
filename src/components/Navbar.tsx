"use client";

import Link from "next/link";

export default function Navbar() {
  return (
    <nav className="sticky top-0 z-50 bg-cream">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 pb-3 pt-4">
        <Link href="/" className="text-lg font-semibold tracking-tight text-neutral-900">
          ReadLater
        </Link>
        <span className="text-xs font-medium tracking-wide text-neutral-400">by Artifacts</span>
      </div>
      {/* Signature brand stripes */}
      <div className="flex flex-col gap-[3px] px-0">
        <div className="h-[3px] bg-brand-purple" />
        <div className="h-[3px] bg-brand-green" />
        <div className="h-[3px] bg-brand-blue" />
        <div className="h-[3px] bg-brand-orange" />
      </div>
    </nav>
  );
}
