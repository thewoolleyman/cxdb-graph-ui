/**
 * GraphViewer — renders a DOT file as an SVG using Graphviz WASM.
 * Applies status CSS classes to SVG nodes on status map changes.
 */
import React, { useEffect, useRef, useCallback } from "react";
import type { StatusMap } from "@/types/index";

const STATUS_CLASSES = [
  "node-pending",
  "node-running",
  "node-complete",
  "node-error",
  "node-stale",
] as const;

interface GraphViewerProps {
  svgContent: string | null;
  loading: boolean;
  error: string | null;
  statusMap: StatusMap | null;
  onNodeClick: (nodeId: string) => void;
}

export function GraphViewer({
  svgContent,
  loading,
  error,
  statusMap,
  onNodeClick,
}: GraphViewerProps): React.ReactElement {
  const containerRef = useRef<HTMLDivElement>(null);

  // Apply status classes whenever statusMap or svgContent changes
  useEffect(() => {
    const container = containerRef.current;
    if (!container || !statusMap) return;

    const svgEl = container.querySelector("svg");
    if (!svgEl) return;

    const nodeGroups = svgEl.querySelectorAll<SVGGElement>("g.node");
    for (const g of nodeGroups) {
      const titleEl = g.querySelector("title");
      if (!titleEl) continue;
      const nodeId = titleEl.textContent?.trim() ?? "";
      const ns = statusMap.get(nodeId);
      const status = ns?.status ?? "pending";

      g.setAttribute("data-status", status);
      g.classList.remove(...STATUS_CLASSES);
      g.classList.add(`node-${status}`);
    }
  }, [statusMap, svgContent]);

  // Attach click handler to SVG nodes after SVG is rendered
  const handleSvgClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      const target = e.target as Element;
      const g = target.closest("g.node");
      if (!g) return;
      const titleEl = g.querySelector("title");
      if (!titleEl) return;
      const nodeId = titleEl.textContent?.trim() ?? "";
      if (nodeId) onNodeClick(nodeId);
    },
    [onNodeClick]
  );

  if (loading) {
    return (
      <div
        className="flex flex-1 items-center justify-center text-gray-500"
        data-testid="graph-loading"
      >
        Loading Graphviz...
      </div>
    );
  }

  if (error) {
    return (
      <div
        className="flex flex-1 items-center justify-center text-red-500"
        data-testid="graph-error"
      >
        {error}
      </div>
    );
  }

  if (!svgContent) {
    return (
      <div
        className="flex flex-1 items-center justify-center text-gray-400"
        data-testid="graph-empty"
      >
        No pipeline loaded
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className="flex-1 overflow-auto p-4"
      onClick={handleSvgClick}
      data-testid="graph-container"
      dangerouslySetInnerHTML={{ __html: svgContent }}
    />
  );
}
