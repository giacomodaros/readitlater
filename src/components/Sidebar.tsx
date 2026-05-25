"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import clsx from "clsx";
import AppearanceControls from "@/components/AppearanceControls";

const NAV_ITEMS = [
  { label: "To Read", href: "/", icon: BookIcon },
  { label: "Archive", href: "/?view=archive", icon: ArchiveIcon },
];

function BookIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 20 20" fill="currentColor">
      <path d="M6 4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H6Zm0 1.5h8a.5.5 0 0 1 .5.5v10a.5.5 0 0 1-.5.5H6a.5.5 0 0 1-.5-.5V6a.5.5 0 0 1 .5-.5Z" />
      <path d="M8 7.5a.5.5 0 0 1 .5-.5h3a.5.5 0 0 1 0 1h-3a.5.5 0 0 1-.5-.5ZM8 10a.5.5 0 0 1 .5-.5h3a.5.5 0 0 1 0 1h-3A.5.5 0 0 1 8 10Z" />
    </svg>
  );
}

function ArchiveIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 20 20" fill="currentColor">
      <path d="M3 5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v1a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5Zm1.5-.5a.5.5 0 0 0-.5.5v.5h12V5a.5.5 0 0 0-.5-.5h-11Z" />
      <path d="M4 8h12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8Zm4 2a.5.5 0 0 0 0 1h4a.5.5 0 0 0 0-1H8Z" />
    </svg>
  );
}

export default function Sidebar() {
  const pathname = usePathname();
  const router = useRouter();
  const searchParams = useSearchParams();
  const currentView = searchParams.get("view");
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/auth/me")
      .then((res) => res.ok ? res.json() : null)
      .then((data) => setEmail(data?.user?.email ?? null))
      .catch(() => setEmail(null));
  }, []);

  async function handleSignOut() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  }

  function isActive(href: string) {
    if (href === "/") return pathname === "/" && !currentView;
    if (href === "/?view=archive") return pathname === "/" && currentView === "archive";
    return false;
  }

  return (
    <aside className="flex w-52 shrink-0 flex-col border-r border-cream-dark">
      <div className="px-5 pb-4 pt-5">
        <Link href="/" className="text-[13px] font-semibold uppercase tracking-widest text-neutral-500">
          Library
        </Link>
      </div>

      <nav className="flex flex-col gap-0.5 px-2">
        {NAV_ITEMS.map((item) => {
          const active = isActive(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={clsx(
                "flex items-center gap-2.5 rounded-md px-3 py-2 text-[13px] font-medium transition-colors",
                active
                  ? "bg-brand-purple/8 text-brand-purple"
                  : "text-neutral-500 hover:bg-cream-dark/60 hover:text-neutral-700"
              )}
            >
              <item.icon className="h-4 w-4 shrink-0" />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="mt-5 px-5">
        <AppearanceControls />
      </div>

      <div className="mt-auto border-t border-cream-dark px-5 py-4">
        {email && (
          <p className="mb-2 truncate text-[11px] text-neutral-400" title={email}>
            {email}
          </p>
        )}
        <button
          onClick={handleSignOut}
          className="text-xs font-medium text-neutral-500 hover:text-brand-purple"
        >
          Sign out
        </button>
      </div>
    </aside>
  );
}
