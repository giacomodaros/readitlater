"use client";

import { useCallback } from "react";

interface SelectionOffset {
  text: string;
  startOffset: number;
  endOffset: number;
}

function getTextOffset(container: Node, targetNode: Node, targetOffset: number): number {
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
  let offset = 0;
  let node: Node | null;
  while ((node = walker.nextNode())) {
    if (node === targetNode) {
      return offset + targetOffset;
    }
    offset += (node.textContent?.length ?? 0);
  }
  return offset;
}

export function useTextSelection(containerRef: React.RefObject<HTMLElement | null>) {
  const getSelection = useCallback((): SelectionOffset | null => {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !containerRef.current) return null;

    const range = sel.getRangeAt(0);
    if (!containerRef.current.contains(range.commonAncestorContainer)) return null;

    const text = sel.toString().trim();
    if (!text) return null;

    const startOffset = getTextOffset(containerRef.current, range.startContainer, range.startOffset);
    const endOffset = getTextOffset(containerRef.current, range.endContainer, range.endOffset);

    return { text, startOffset, endOffset };
  }, [containerRef]);

  return { getSelection };
}
