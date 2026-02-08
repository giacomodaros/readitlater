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

export default function HighlightLayer({ articleId, contentRef, originalHtml }: HighlightLayerProps) {
  const [highlights, setHighlights] = useState<Highlight[]>([]);
  const [popover, setPopover] = useState<{ x: number; y: number } | null>(null);
  const [pendingSelection, setPendingSelection] = useState<{
    text: string;
    startOffset: number;
    endOffset: number;
  } | null>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
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

        range.surroundContents(mark);
      }
    }

    // Click handler for deleting highlights
    function handleMarkClick(e: Event) {
      const target = e.target as HTMLElement;
      if (target.tagName === "MARK" && target.dataset.highlightId) {
        if (confirm("Remove this highlight?")) {
          deleteHighlight(target.dataset.highlightId);
        }
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
      // Small delay to let selection finalize
      setTimeout(() => {
        const sel = getSelection();
        if (sel) {
          setPendingSelection(sel);
          setPopover({ x: e.clientX, y: e.clientY - 10 });
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
      body: JSON.stringify({ ...pendingSelection, color }),
    });
    window.getSelection()?.removeAllRanges();
    setPopover(null);
    setPendingSelection(null);
    fetchHighlights();
  }

  return (
    <>
      {popover && (
        <div
          ref={popoverRef}
          className="fixed z-50 flex gap-1.5 rounded-lg border border-cream-dark bg-cream p-2 shadow-lg"
          style={{ left: popover.x - 80, top: popover.y - 48 }}
        >
          {COLORS.map((c) => (
            <button
              key={c}
              onClick={() => handleHighlight(c)}
              className="h-6 w-6 rounded-full border-2 border-white shadow transition-transform hover:scale-110"
              style={{ backgroundColor: c }}
              title={`Highlight with ${c}`}
            />
          ))}
        </div>
      )}
    </>
  );
}
