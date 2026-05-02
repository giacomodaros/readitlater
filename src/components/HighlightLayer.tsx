"use client";

import { useEffect, useCallback, useState, useRef } from "react";
import { useTextSelection } from "@/hooks/useTextSelection";

type Highlight = {
  id: string;
  text: string;
  startOffset: number;
  endOffset: number;
  color: string;
  note: string | null;
};

interface HighlightLayerProps {
  articleId: string;
  contentRef: React.RefObject<HTMLElement | null>;
  originalHtml: string;
}

const COLORS = ["#7B6AEE", "#2DB87A", "#6CBAFC", "#E8883A"];

type ConfirmPopover = { x: number; y: number; highlightId: string; note: string | null };

export default function HighlightLayer({ articleId, contentRef, originalHtml }: HighlightLayerProps) {
  const [highlights, setHighlights] = useState<Highlight[]>([]);
  const [popover, setPopover] = useState<{ x: number; y: number } | null>(null);
  const [pendingSelection, setPendingSelection] = useState<{
    text: string;
    startOffset: number;
    endOffset: number;
  } | null>(null);
  const [pendingNote, setPendingNote] = useState("");
  const [confirmPopover, setConfirmPopover] = useState<ConfirmPopover | null>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const confirmPopoverRef = useRef<HTMLDivElement>(null);
  const { getSelection } = useTextSelection(contentRef);

  const fetchHighlights = useCallback(async () => {
    const res = await fetch(`/api/articles/${articleId}/highlights`);
    const data = await res.json();
    setHighlights(data);
  }, [articleId]);

  useEffect(() => {
    fetchHighlights();
  }, [fetchHighlights]);

  // Apply highlights to DOM
  useEffect(() => {
    const el = contentRef.current;
    if (!el) return;

    // Reset to original HTML
    el.innerHTML = originalHtml;

    if (highlights.length === 0) return;

    // Sort highlights by start offset
    const sorted = [...highlights].sort((a, b) => a.startOffset - b.startOffset);

    // Walk text nodes and apply highlights
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    const textNodes: { node: Text; start: number; end: number }[] = [];
    let offset = 0;
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const len = node.textContent?.length ?? 0;
      textNodes.push({ node: node as Text, start: offset, end: offset + len });
      offset += len;
    }

    // Process highlights in reverse order to maintain offsets
    for (let i = sorted.length - 1; i >= 0; i--) {
      const hl = sorted[i];
      const affectedNodes = textNodes.filter(
        (tn) => tn.start < hl.endOffset && tn.end > hl.startOffset
      );

      for (let j = affectedNodes.length - 1; j >= 0; j--) {
        const tn = affectedNodes[j];
        const textNode = tn.node;
        if (!textNode.parentNode) continue;

        const nodeStart = Math.max(0, hl.startOffset - tn.start);
        const nodeEnd = Math.min(textNode.length, hl.endOffset - tn.start);

        if (nodeStart >= nodeEnd) continue;

        const range = document.createRange();
        range.setStart(textNode, nodeStart);
        range.setEnd(textNode, nodeEnd);

        const mark = document.createElement("mark");
        mark.style.backgroundColor = hl.color + "66";
        mark.style.borderRadius = "2px";
        mark.style.cursor = "pointer";
        mark.dataset.highlightId = hl.id;
        if (hl.note) {
          mark.dataset.note = hl.note;
          mark.style.borderBottom = `2px solid ${hl.color}`;
        }

        range.surroundContents(mark);
      }
    }

    // Click handler — show inline confirm instead of confirm()
    function handleMarkClick(e: Event) {
      const target = e.target as HTMLElement;
      const mark = target.closest("mark") as HTMLElement | null;
      if (mark && mark.dataset.highlightId) {
        const rect = mark.getBoundingClientRect();
        const hl = highlights.find((h) => h.id === mark.dataset.highlightId);
        setConfirmPopover({
          x: rect.left + rect.width / 2,
          y: rect.top,
          highlightId: mark.dataset.highlightId,
          note: hl?.note ?? null,
        });
      }
    }
    el.addEventListener("click", handleMarkClick);
    return () => el.removeEventListener("click", handleMarkClick);
  }, [highlights, contentRef, originalHtml, articleId]);

  async function deleteHighlight(highlightId: string) {
    await fetch(`/api/articles/${articleId}/highlights/${highlightId}`, {
      method: "DELETE",
    });
    fetchHighlights();
  }

  // Listen for text selection
  useEffect(() => {
    function handleMouseUp(e: MouseEvent) {
      setTimeout(() => {
        const sel = getSelection();
        if (sel) {
          setPendingSelection(sel);
          setPendingNote("");

          // Get the actual selection bounds instead of mouse coordinates
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            const range = selection.getRangeAt(0);
            const rect = range.getBoundingClientRect();
            // Position popover above the selection, centered on it
            setPopover({
              x: rect.left + rect.width / 2,
              y: rect.top - 10
            });
          }
        } else {
          setPopover(null);
          setPendingSelection(null);
        }
      }, 10);
    }

    function handleMouseDown(e: MouseEvent) {
      if (popoverRef.current && !popoverRef.current.contains(e.target as Node)) {
        setPopover(null);
        setPendingSelection(null);
        setPendingNote("");
      }
      if (confirmPopoverRef.current && !confirmPopoverRef.current.contains(e.target as Node)) {
        setConfirmPopover(null);
      }
    }

    document.addEventListener("mouseup", handleMouseUp);
    document.addEventListener("mousedown", handleMouseDown);
    return () => {
      document.removeEventListener("mouseup", handleMouseUp);
      document.removeEventListener("mousedown", handleMouseDown);
    };
  }, [getSelection]);

  async function handleHighlight(color: string) {
    if (!pendingSelection) return;
    await fetch(`/api/articles/${articleId}/highlights`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...pendingSelection, color, note: pendingNote.trim() || null }),
    });
    window.getSelection()?.removeAllRanges();
    setPopover(null);
    setPendingSelection(null);
    setPendingNote("");
    fetchHighlights();
  }

  return (
    <>
      {popover && (
        <div
          ref={popoverRef}
          className="fixed z-50 flex flex-col gap-2 rounded-lg border border-cream-dark bg-cream p-2 shadow-lg"
          style={{ left: popover.x - 76, top: popover.y - 80 }}
        >
          <div className="flex gap-1.5">
            {COLORS.map((c) => (
              <button
                key={c}
                onClick={() => handleHighlight(c)}
                className="h-6 w-6 rounded-full border-2 border-white shadow transition-transform hover:scale-110"
                style={{ backgroundColor: c }}
                title={`Highlight`}
              />
            ))}
          </div>
          <input
            type="text"
            placeholder="Add a note… (optional)"
            value={pendingNote}
            onChange={(e) => setPendingNote(e.target.value)}
            onKeyDown={(e) => e.stopPropagation()}
            className="w-full rounded border border-cream-dark bg-white px-2 py-1 text-xs text-neutral-700 placeholder:text-neutral-400 focus:border-brand-purple focus:outline-none"
          />
        </div>
      )}
      {confirmPopover && (
        <div
          ref={confirmPopoverRef}
          className="fixed z-50 flex flex-col gap-2 rounded-lg border border-cream-dark bg-white px-3 py-2 shadow-lg"
          style={{ left: confirmPopover.x - 100, top: confirmPopover.y - (confirmPopover.note ? 72 : 44) }}
        >
          {confirmPopover.note && (
            <p className="max-w-[200px] text-xs text-neutral-600 italic">"{confirmPopover.note}"</p>
          )}
          <div className="flex items-center gap-2">
            <span className="text-xs text-neutral-500">Remove highlight?</span>
            <button
              onClick={() => { deleteHighlight(confirmPopover.highlightId); setConfirmPopover(null); }}
              className="rounded bg-brand-orange px-2 py-0.5 text-xs font-medium text-white hover:brightness-110"
            >
              Remove
            </button>
            <button
              onClick={() => setConfirmPopover(null)}
              className="text-xs text-neutral-400 hover:text-neutral-600"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </>
  );
}
