/**
 * ConnectionIndicator — shows CXDB instance reachability status.
 */
import React from "react";
import type { InstanceStatus } from "@/types/index";

interface ConnectionIndicatorProps {
  instanceStatuses: InstanceStatus[];
  cxdbUrls: string[];
  hasStaleNode: boolean;
}

export function ConnectionIndicator({
  instanceStatuses,
  cxdbUrls,
  hasStaleNode,
}: ConnectionIndicatorProps): React.ReactElement {
  const total = instanceStatuses.length;
  const reachable = instanceStatuses.filter((s) => s === "ok").length;
  const unknown = instanceStatuses.filter((s) => s === "unknown").length;

  if (total === 0 || unknown === total) {
    return (
      <div
        className="flex items-center gap-1.5 px-3 text-sm text-gray-400"
        data-testid="connection-indicator"
      >
        <span className="h-2 w-2 rounded-full bg-gray-400" />
        <span>CXDB connecting…</span>
      </div>
    );
  }

  if (reachable === total) {
    return (
      <div
        className="flex flex-col items-end px-3"
        data-testid="connection-indicator"
      >
        <div className="flex items-center gap-1.5 text-sm text-green-600">
          <span className="h-2 w-2 rounded-full bg-green-500" />
          <span>CXDB OK</span>
        </div>
        {hasStaleNode && (
          <div className="text-xs text-amber-600">
            Pipeline stalled — no active sessions.
          </div>
        )}
      </div>
    );
  }

  if (reachable === 0) {
    return (
      <div
        className="flex flex-col items-end px-3"
        data-testid="connection-indicator"
      >
        <div className="flex items-center gap-1.5 text-sm text-red-600">
          <span className="h-2 w-2 rounded-full bg-red-500" />
          <span>CXDB unreachable</span>
        </div>
        <div className="mt-0.5 text-xs text-red-400">
          {cxdbUrls.map((url) => (
            <div key={url}>{url}</div>
          ))}
        </div>
      </div>
    );
  }

  // Partial connectivity
  return (
    <div
      className="flex flex-col items-end px-3"
      title={cxdbUrls
        .map((url, i) => `${url}: ${instanceStatuses[i] ?? "unknown"}`)
        .join("\n")}
      data-testid="connection-indicator"
    >
      <div className="flex items-center gap-1.5 text-sm text-yellow-600">
        <span className="h-2 w-2 rounded-full bg-yellow-400" />
        <span>
          {reachable}/{total} CXDB
        </span>
      </div>
    </div>
  );
}
