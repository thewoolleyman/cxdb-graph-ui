/**
 * DetailPanel — right sidebar showing DOT attributes and CXDB turns for the
 * selected node.
 */
import React, { useMemo, useCallback } from "react";
import type { EdgeInfo, NodeAttrs, TurnItem } from "@/types/index";
import { TurnRow } from "./TurnRow";
import { numericTurnId } from "@/lib/utils";

type ContextKey = string;

const SHAPE_LABELS: Record<string, string> = {
  Mdiamond: "Start",
  circle: "Start",
  Msquare: "Exit",
  doublecircle: "Exit",
  box: "LLM Task",
  diamond: "Conditional",
  parallelogram: "Tool Gate",
  hexagon: "Human Gate",
  component: "Parallel",
  tripleoctagon: "Parallel Fan-in",
  house: "Stack Manager Loop",
};

function shapeLabel(shape: string | null): string {
  if (!shape) return "LLM Task";
  return SHAPE_LABELS[shape] ?? "LLM Task";
}

const MAX_TURNS_PER_CONTEXT = 20;

interface ContextSection {
  cxdbIndex: number;
  contextId: string;
  turns: TurnItem[];
  maxTurnId: number;
}

interface DetailPanelProps {
  nodeId: string | null;
  nodeAttrs: NodeAttrs | null;
  edges: EdgeInfo[];
  turnCache: Map<string, Map<ContextKey, TurnItem[]>>;
  graphId: string | null;
  onClose: () => void;
}

export function DetailPanel({
  nodeId,
  nodeAttrs,
  edges,
  turnCache,
  graphId,
  onClose,
}: DetailPanelProps): React.ReactElement | null {
  // All hooks must be called unconditionally — before any early returns
  const choices = useMemo(() => {
    if (nodeId === null) return [];
    return edges
      .filter((e) => e.source === nodeId && e.label !== null)
      .map((e) => e.label as string);
  }, [edges, nodeId]);

  const contextSections = useMemo((): ContextSection[] => {
    if (!graphId || nodeId === null) return [];
    const cache = turnCache.get(graphId);
    if (!cache) return [];

    const sections: ContextSection[] = [];
    for (const [key, turns] of cache.entries()) {
      const colonIdx = key.indexOf(":");
      if (colonIdx < 0) continue;
      const cxdbIndex = parseInt(key.slice(0, colonIdx), 10);
      const contextId = key.slice(colonIdx + 1);

      const nodeTurns = turns
        .filter((t) => t.data.node_id === nodeId)
        .sort((a, b) => numericTurnId(b.turn_id) - numericTurnId(a.turn_id))
        .slice(0, MAX_TURNS_PER_CONTEXT);

      if (nodeTurns.length === 0) continue;

      const maxTurnId =
        nodeTurns.length > 0 ? numericTurnId(nodeTurns[0].turn_id) : 0;

      sections.push({ cxdbIndex, contextId, turns: nodeTurns, maxTurnId });
    }

    // Sort: by cxdbIndex asc, then by maxTurnId desc
    sections.sort((a, b) => {
      if (a.cxdbIndex !== b.cxdbIndex) return a.cxdbIndex - b.cxdbIndex;
      return b.maxTurnId - a.maxTurnId;
    });

    return sections;
  }, [turnCache, graphId, nodeId]);

  const handleClose = useCallback(() => onClose(), [onClose]);

  // Early return AFTER all hooks
  if (nodeId === null) return null;

  return (
    <aside
      className="flex w-96 flex-col overflow-hidden border-l border-gray-200 bg-white"
      data-testid="detail-panel"
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-gray-200 px-4 py-3">
        <div className="flex items-center gap-2">
          <h2
            className="text-sm font-semibold text-gray-800"
            data-testid="detail-node-id"
          >
            {nodeId}
          </h2>
          {nodeAttrs?.goal_gate === "true" && (
            <span className="rounded bg-blue-100 px-1.5 py-0.5 text-xs text-blue-700">
              goal gate
            </span>
          )}
        </div>
        <button
          type="button"
          onClick={handleClose}
          className="text-gray-400 hover:text-gray-600"
          aria-label="Close detail panel"
          data-testid="detail-close"
        >
          ✕
        </button>
      </div>

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto">
        {/* DOT Attributes */}
        <section className="border-b border-gray-100 px-4 py-3">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">
            Node Attributes
          </h3>
          <dl className="space-y-1 text-xs">
            <div className="flex gap-2">
              <dt className="w-24 shrink-0 text-gray-500">Type</dt>
              <dd className="text-gray-800">
                {shapeLabel(nodeAttrs?.shape ?? null)}
              </dd>
            </div>
            {nodeAttrs?.class && (
              <div className="flex gap-2">
                <dt className="w-24 shrink-0 text-gray-500">Class</dt>
                <dd className="text-gray-800">{nodeAttrs.class}</dd>
              </div>
            )}
            {nodeAttrs?.prompt && (
              <div>
                <dt className="mb-0.5 text-gray-500">Prompt</dt>
                <dd>
                  <pre className="whitespace-pre-wrap break-words rounded bg-gray-50 p-2 text-xs text-gray-700">
                    {nodeAttrs.prompt}
                  </pre>
                </dd>
              </div>
            )}
            {nodeAttrs?.tool_command && (
              <div>
                <dt className="mb-0.5 text-gray-500">Tool Command</dt>
                <dd>
                  <pre className="whitespace-pre-wrap break-words rounded bg-gray-50 p-2 font-mono text-xs text-gray-700">
                    {nodeAttrs.tool_command}
                  </pre>
                </dd>
              </div>
            )}
            {nodeAttrs?.question && (
              <div>
                <dt className="mb-0.5 text-gray-500">Question</dt>
                <dd>
                  <pre className="whitespace-pre-wrap break-words rounded bg-gray-50 p-2 text-xs text-gray-700">
                    {nodeAttrs.question}
                  </pre>
                </dd>
              </div>
            )}
            {choices.length > 0 && (
              <div>
                <dt className="mb-0.5 text-gray-500">Choices</dt>
                <dd>
                  <ul className="list-inside list-disc space-y-0.5 text-xs text-gray-700">
                    {choices.map((c) => (
                      <li key={c}>{c}</li>
                    ))}
                  </ul>
                </dd>
              </div>
            )}
          </dl>
        </section>

        {/* CXDB Activity */}
        <section className="px-4 py-3">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">
            CXDB Activity
          </h3>
          {contextSections.length === 0 ? (
            <p className="text-xs text-gray-400">No recent CXDB activity</p>
          ) : (
            contextSections.map((section) => (
              <details
                key={`${section.cxdbIndex}:${section.contextId}`}
                open
                className="mb-3"
              >
                <summary className="cursor-pointer text-xs font-medium text-gray-600 hover:text-gray-800">
                  CXDB-{section.cxdbIndex} / Context {section.contextId}
                </summary>
                <table className="mt-1 w-full border-collapse">
                  <thead>
                    <tr className="text-left text-xs text-gray-400">
                      <th className="p-1">Type</th>
                      <th className="p-1">Tool</th>
                      <th className="p-1">Output</th>
                    </tr>
                  </thead>
                  <tbody>
                    {section.turns.map((turn) => (
                      <TurnRow key={turn.turn_id} turn={turn} />
                    ))}
                  </tbody>
                </table>
              </details>
            ))
          )}
        </section>
      </div>
    </aside>
  );
}
