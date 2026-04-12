import type { Metadata } from "next";
import { Geist, Geist_Mono, DM_Serif_Display, Source_Serif_4 } from "next/font/google";
import { Suspense } from "react";
import "./globals.css";
import Sidebar from "@/components/Sidebar";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const dmSerifDisplay = DM_Serif_Display({
  variable: "--font-dm-serif-display",
  weight: "400",
  subsets: ["latin"],
  display: "swap",
});

const sourceSerif4 = Source_Serif_4({
  variable: "--font-source-serif",
  subsets: ["latin"],
  weight: ["400", "600"],
  style: ["normal", "italic"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Reader",
  description: "Read-it-later by Artifacts",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} ${dmSerifDisplay.variable} ${sourceSerif4.variable} antialiased bg-cream text-neutral-900`}
      >
        {/* Paper grain overlay */}
        <div
          aria-hidden="true"
          className="pointer-events-none fixed inset-0 z-[9999]"
          style={{
            opacity: 0.038,
            backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='256' height='256'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='256' height='256' filter='url(%23n)'/%3E%3C/svg%3E")`,
            backgroundSize: "256px 256px",
          }}
        />
        <div className="flex h-screen overflow-hidden">
          <Suspense>
            <Sidebar />
          </Suspense>
          <main className="flex-1 overflow-hidden">
            {children}
          </main>
        </div>
      </body>
    </html>
  );
}
