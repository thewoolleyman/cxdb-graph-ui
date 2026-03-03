/**
 * Status derivation algorithms (pure functions).
 * Implements the status map lifecycle, merging, error heuristic, and stale detection.
 */

import type { NodeStatus, NodeStatusValue, StatusMap, TurnItem } from "@/types/index";
import { numericTurnId } from "@/lib/utils";

// Turn type IDs
const STAGE_FINISHED = "com.kilroy.attractor.StageFinished";
const STAGE_FAILED = "com.kilroy.attractor.StageFailed";
const STAGE_STARTED = "com.kilroy.attractor.StageStarted";
const RUN_FAILED = "com.kilroy.attractor.RunFailed";
const TOOL_RESULT = "com.kilroy.attractor.ToolResult";

// Per-context status precedence
const CONTEXT_PRECEDENCE: Record<NodeStatusValue, number> = {
  error: 3,
  complete: 2,
  running: 1,
  pending: 0,
  stale: 0,
};

// Merge precedence (cross-context)
const MERGE_PRECEDENCE: Record<NodeStatusValue, number> = {
  error: 3,
  running: 2,
  complete: 1,
  pending: 0,
  stale: 0,
};

/**
 * Create a new NodeStatus with default values.
 */
export function createNodeStatus(): NodeStatus {
  return {
    status: "pending",
    lastTurnId: null,
    toolName: null,
    turnCount: 0,
    errorCount: 0,
    hasLifecycleResolution: false,
  };
}

/**
 * Process turns for a single context and update the per-context status map.
 * Returns the updated map and the new lastSeenTurnId.
 */
export function updateContextStatusMap(
  existingMap: StatusMap,
  dotNodeIds: Set<string>,
  turns: TurnItem[],
  lastSeenTurnId: string | null
): { map: StatusMap; newLastSeenTurnId: string | null } {
  // Prune entries for node IDs no longer in dotNodeIds
  for (const nodeId of existingMap.keys()) {
    if (!dotNodeIds.has(nodeId)) {
      existingMap.delete(nodeId);
    }
  }

  // Initialize entries for new node IDs
  for (const nodeId of dotNodeIds) {
    if (!existingMap.has(nodeId)) {
      existingMap.set(nodeId, createNodeStatus());
    }
  }

  // Compute new lastSeenTurnId as the max turn_id across the batch
  let newLastSeenTurnId = lastSeenTurnId;
  for (const turn of turns) {
    if (
      newLastSeenTurnId === null ||
      numericTurnId(turn.turn_id) > numericTurnId(newLastSeenTurnId)
    ) {
      newLastSeenTurnId = turn.turn_id;
    }
  }

  // Process turns (oldest-first from API, may have gap recovery prepended)
  for (const turn of turns) {
    // Skip already-processed turns
    if (
      lastSeenTurnId !== null &&
      numericTurnId(turn.turn_id) <= numericTurnId(lastSeenTurnId)
    ) {
      continue; // don't break — batch may not be strictly sorted at join point
    }

    const nodeId = turn.data.node_id;
    const typeId = turn.declared_type.type_id;

    if (!nodeId || !existingMap.has(nodeId)) {
      continue;
    }

    const nodeStatus = existingMap.get(nodeId)!;
    let newStatus: NodeStatusValue | null = null;
    let isLifecycle = false;

    if (typeId === STAGE_FINISHED) {
      nodeStatus.hasLifecycleResolution = true;
      isLifecycle = true;
      newStatus = turn.data.status === "fail" ? "error" : "complete";
    } else if (typeId === STAGE_FAILED) {
      if (turn.data.will_retry === true) {
        newStatus = "running";
        // Do NOT set hasLifecycleResolution — node is retrying
      } else {
        newStatus = "error";
        nodeStatus.hasLifecycleResolution = true;
        isLifecycle = true;
      }
    } else if (typeId === RUN_FAILED) {
      newStatus = "error";
      nodeStatus.hasLifecycleResolution = true;
      isLifecycle = true;
    } else if (typeId === STAGE_STARTED) {
      newStatus = "running";
    } else {
      newStatus = "running";
    }

    // Promote status
    if (isLifecycle) {
      // Lifecycle turns are authoritative — unconditionally override
      nodeStatus.status = newStatus!;
    } else if (
      !nodeStatus.hasLifecycleResolution &&
      newStatus !== null &&
      (newStatus === "error" ||
        CONTEXT_PRECEDENCE[newStatus] >
          CONTEXT_PRECEDENCE[nodeStatus.status])
    ) {
      nodeStatus.status = newStatus;
    }

    if (turn.data.is_error === true) {
      nodeStatus.errorCount++;
    }

    nodeStatus.turnCount++;

    if (nodeStatus.toolName === null && turn.data.tool_name) {
      nodeStatus.toolName = turn.data.tool_name;
    }

    // Update lastTurnId to the most recent turn for this node
    if (
      nodeStatus.lastTurnId === null ||
      numericTurnId(turn.turn_id) > numericTurnId(nodeStatus.lastTurnId)
    ) {
      nodeStatus.lastTurnId = turn.turn_id;
    }
  }

  return { map: existingMap, newLastSeenTurnId };
}

/**
 * Merge per-context status maps into a single display map.
 * Uses merge precedence: error > running > complete > pending.
 */
export function mergeStatusMaps(
  dotNodeIds: Set<string>,
  perContextMaps: StatusMap[]
): StatusMap {
  const merged: StatusMap = new Map();

  for (const nodeId of dotNodeIds) {
    const mergedStatus: NodeStatus = {
      status: "pending",
      lastTurnId: null,
      toolName: null,
      turnCount: 0,
      errorCount: 0,
      hasLifecycleResolution: false,
    };

    let allContextsHaveLifecycleResolution = true;
    let anyContextHasNode = false;

    for (const contextMap of perContextMaps) {
      const contextStatus = contextMap.get(nodeId);
      if (!contextStatus) continue;

      if (
        MERGE_PRECEDENCE[contextStatus.status] >
        MERGE_PRECEDENCE[mergedStatus.status]
      ) {
        mergedStatus.status = contextStatus.status;
        mergedStatus.toolName = contextStatus.toolName;
        mergedStatus.lastTurnId = contextStatus.lastTurnId;
      }

      mergedStatus.turnCount += contextStatus.turnCount;
      mergedStatus.errorCount += contextStatus.errorCount;

      if (contextStatus.status !== "pending") {
        anyContextHasNode = true;
        if (!contextStatus.hasLifecycleResolution) {
          allContextsHaveLifecycleResolution = false;
        }
      }
    }

    // AND semantics: hasLifecycleResolution only when all active contexts have it
    mergedStatus.hasLifecycleResolution =
      anyContextHasNode && allContextsHaveLifecycleResolution;

    merged.set(nodeId, mergedStatus);
  }

  return merged;
}

/**
 * Apply error loop heuristic to the merged status map.
 * For nodes that are "running" without lifecycle resolution,
 * check if any context has 3 consecutive recent ToolResult errors.
 */
export function applyErrorHeuristic(
  mergedMap: StatusMap,
  dotNodeIds: Set<string>,
  perContextCaches: TurnItem[][]
): StatusMap {
  for (const nodeId of dotNodeIds) {
    const nodeStatus = mergedMap.get(nodeId);
    if (!nodeStatus) continue;

    if (
      nodeStatus.status === "running" &&
      !nodeStatus.hasLifecycleResolution
    ) {
      for (const contextTurns of perContextCaches) {
        const recentErrors = getMostRecentToolResultsForNodeInContext(
          contextTurns,
          nodeId,
          3
        );
        if (
          recentErrors.length >= 3 &&
          recentErrors.every((t) => t.data.is_error === true)
        ) {
          nodeStatus.status = "error";
          break;
        }
      }
    }
  }

  return mergedMap;
}

/**
 * Get the most recent N ToolResult turns for a node in a context.
 * Returns turns sorted newest-first.
 */
function getMostRecentToolResultsForNodeInContext(
  contextTurns: TurnItem[],
  nodeId: string,
  count: number
): TurnItem[] {
  const toolResults = contextTurns.filter(
    (t) =>
      t.declared_type.type_id === TOOL_RESULT && t.data.node_id === nodeId
  );

  // Sort newest-first (safe within a single context)
  toolResults.sort(
    (a, b) => numericTurnId(b.turn_id) - numericTurnId(a.turn_id)
  );

  return toolResults.slice(0, count);
}

/**
 * Apply stale detection to the merged status map.
 * Nodes that are "running" without lifecycle resolution become "stale"
 * when the pipeline has no active sessions.
 */
export function applyStaleDetection(
  mergedMap: StatusMap,
  dotNodeIds: Set<string>,
  pipelineIsLive: boolean
): StatusMap {
  if (pipelineIsLive) {
    return mergedMap; // at least one session is active
  }

  for (const nodeId of dotNodeIds) {
    const nodeStatus = mergedMap.get(nodeId);
    if (!nodeStatus) continue;

    if (
      nodeStatus.status === "running" &&
      !nodeStatus.hasLifecycleResolution
    ) {
      nodeStatus.status = "stale";
    }
  }

  return mergedMap;
}

/**
 * Initialize a status map for a set of node IDs.
 */
export function initStatusMap(dotNodeIds: Set<string>): StatusMap {
  const map: StatusMap = new Map();
  for (const nodeId of dotNodeIds) {
    map.set(nodeId, createNodeStatus());
  }
  return map;
}
