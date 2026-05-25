"use client";

import { useEffect, useState } from "react";
import clsx from "clsx";

const THEMES = [
  { value: "offwhite", label: "Off white" },
  { value: "black", label: "Black" },
] as const;

const FONTS = [
  { value: "serif", label: "Serif" },
  { value: "sans", label: "Sans" },
  { value: "mono", label: "Mono" },
] as const;

type Theme = (typeof THEMES)[number]["value"];
type Font = (typeof FONTS)[number]["value"];

function applyAppearance(theme: Theme, font: Font) {
  document.documentElement.dataset.theme = theme;
  document.documentElement.dataset.readerFont = font;
  localStorage.setItem("reader-theme", theme);
  localStorage.setItem("reader-font-family", font);
  window.dispatchEvent(new CustomEvent("reader-appearance-change", { detail: { theme, font } }));
}

export default function AppearanceControls() {
  const [theme, setTheme] = useState<Theme>("offwhite");
  const [font, setFont] = useState<Font>("serif");

  useEffect(() => {
    const storedTheme = localStorage.getItem("reader-theme") === "black" ? "black" : "offwhite";
    const storedFont = FONTS.some((item) => item.value === localStorage.getItem("reader-font-family"))
      ? localStorage.getItem("reader-font-family") as Font
      : "serif";

    setTheme(storedTheme);
    setFont(storedFont);
    applyAppearance(storedTheme, storedFont);
  }, []);

  function updateTheme(value: Theme) {
    setTheme(value);
    applyAppearance(value, font);
  }

  function updateFont(value: Font) {
    setFont(value);
    applyAppearance(theme, value);
  }

  return (
    <div className="space-y-4">
      <div>
        <p className="mb-2 text-[10px] font-medium uppercase tracking-widest text-neutral-400">Theme</p>
        <div className="grid grid-cols-2 gap-1 rounded-md bg-cream-dark/60 p-1">
          {THEMES.map((item) => (
            <button
              key={item.value}
              onClick={() => updateTheme(item.value)}
              className={clsx(
                "rounded px-2 py-1.5 text-[11px] font-medium transition-colors",
                theme === item.value ? "bg-white text-neutral-950 shadow-sm" : "text-neutral-500 hover:text-neutral-800"
              )}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>

      <div>
        <p className="mb-2 text-[10px] font-medium uppercase tracking-widest text-neutral-400">Article Font</p>
        <div className="grid grid-cols-3 gap-1 rounded-md bg-cream-dark/60 p-1">
          {FONTS.map((item) => (
            <button
              key={item.value}
              onClick={() => updateFont(item.value)}
              className={clsx(
                "rounded px-2 py-1.5 text-[11px] font-medium transition-colors",
                theme === "black" && font === item.value
                  ? "bg-neutral-800 text-white"
                  : font === item.value
                    ? "bg-white text-neutral-950 shadow-sm"
                    : "text-neutral-500 hover:text-neutral-800"
              )}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
