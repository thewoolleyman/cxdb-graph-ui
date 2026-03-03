/**
 * Unit tests for status derivation algorithms.
 */

import { describe, it, expect } from "vitest";
import {
  createNodeStatus,
  updateContextStatusMap,
  mergeStatusMaps,
  applyErrorHeuristic,
  applyStaleDetection,
  initStatusMap,
} from "./status";
import type { StatusMap, TurnItem } from "@/types/index";

function makeTurn(
  turnId: string,
  nodeId: string,
  typeId: string,
  data: Record<string, unknown> = {}
): TurnItem {
  return {
    turn_id: turnId,
    parent_turn_id: null,
    depth: 1,
    declared_type: { type_id: typeId, type_version: 1 },
    data: { node_id: nodeId, ...data },
  };
}

const nodeIds = new Set(["implement", "check_fmt", "done"]);

describe("createNodeStatus", () => {
  it("creates a pending status with defaults", () => {
    const s = createNodeStatus();
    expect(s.status).toBe("pending");
    expect(s.turnCount).toBe(0);
    expect(s.errorCount).toBe(0);
    expect(s.hasLifecycleResolution).toBe(false);
  });
});

describe("initStatusMap", () => {
  it("initializes all nodes as pending", () => {
    const map = initStatusMap(nodeIds);
    for (const nodeId of nodeIds) {
      expect(map.get(nodeId)?.status).toBe("pending");
    }
  });
});

describe("updateContextStatusMap", () => {
  it("promotes pending -> running on StageStarted", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn(
        "1",
        "implement",
        "com.kilroy.attractor.StageStarted"
      ),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.status).toBe("running");
  });

  it("promotes running -> complete on StageFinished success", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("1", "implement", "com.kilroy.attractor.StageStarted"),
      makeTurn("2", "implement", "com.kilroy.attractor.StageFinished", {
        status: "success",
      }),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.status).toBe("complete");
  });

  it("sets error on StageFinished with status=fail", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("2", "implement", "com.kilroy.attractor.StageFinished", {
        status: "fail",
      }),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.status).toBe("error");
  });

  it("sets running (not error) on StageFailed with will_retry=true", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("2", "implement", "com.kilroy.attractor.StageFailed", {
        will_retry: true,
      }),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.status).toBe("running");
    expect(updated.get("implement")?.hasLifecycleResolution).toBe(false);
  });

  it("sets error on terminal StageFailed (will_retry=false)", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("2", "implement", "com.kilroy.attractor.StageFailed", {
        will_retry: false,
      }),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.status).toBe("error");
    expect(updated.get("implement")?.hasLifecycleResolution).toBe(true);
  });

  it("deduplicates turns using lastSeenTurnId", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns1 = [
      makeTurn("1", "implement", "com.kilroy.attractor.StageStarted"),
    ];
    const { newLastSeenTurnId: cursor1 } = updateContextStatusMap(
      map,
      nodeIds,
      turns1,
      null
    );
    expect(cursor1).toBe("1");

    // Same turn again — should not be re-processed
    const { map: updated2 } = updateContextStatusMap(
      map,
      nodeIds,
      turns1,
      cursor1
    );
    expect(updated2.get("implement")?.turnCount).toBe(1); // still 1
  });

  it("advances lastSeenTurnId to max turn_id in batch", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("3", "implement", "com.kilroy.attractor.StageStarted"),
      makeTurn("1", "implement", "com.kilroy.attractor.StageStarted"),
      makeTurn("5", "implement", "com.kilroy.attractor.StageStarted"),
    ];
    const { newLastSeenTurnId } = updateContextStatusMap(
      map,
      nodeIds,
      turns,
      null
    );
    expect(newLastSeenTurnId).toBe("5");
  });

  it("prunes nodes no longer in dotNodeIds", () => {
    const map: StatusMap = new Map();
    map.set("old_node", createNodeStatus());
    map.set("implement", createNodeStatus());

    const { map: updated } = updateContextStatusMap(map, nodeIds, [], null);
    expect(updated.has("old_node")).toBe(false);
    expect(updated.has("implement")).toBe(true);
  });

  it("lifecycle resolution prevents non-lifecycle demotion", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    // StageFinished sets complete + hasLifecycleResolution
    const turns1 = [
      makeTurn("2", "implement", "com.kilroy.attractor.StageFinished", {
        status: "success",
      }),
    ];
    const { newLastSeenTurnId: cursor } = updateContextStatusMap(
      map,
      nodeIds,
      turns1,
      null
    );
    expect(map.get("implement")?.hasLifecycleResolution).toBe(true);

    // StageStarted should NOT demote complete -> running
    const turns2 = [
      makeTurn("3", "implement", "com.kilroy.attractor.StageStarted"),
    ];
    const { map: updated } = updateContextStatusMap(
      map,
      nodeIds,
      turns2,
      cursor
    );
    expect(updated.get("implement")?.status).toBe("complete");
  });

  it("increments errorCount on is_error=true", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.errorCount).toBe(1);
  });

  it("skips turns with unknown node_id", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("1", "unknown_node", "com.kilroy.attractor.StageStarted"),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    // All nodes should remain pending
    for (const nodeId of nodeIds) {
      expect(updated.get(nodeId)?.status).toBe("pending");
    }
  });

  it("assigns toolName on first appearance", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolCall", {
        tool_name: "shell",
      }),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.toolName).toBe("shell");
  });

  it("RunFailed sets error with lifecycle resolution", () => {
    const map: StatusMap = initStatusMap(nodeIds);
    const turns = [
      makeTurn("2", "implement", "com.kilroy.attractor.RunFailed"),
    ];
    const { map: updated } = updateContextStatusMap(map, nodeIds, turns, null);
    expect(updated.get("implement")?.status).toBe("error");
    expect(updated.get("implement")?.hasLifecycleResolution).toBe(true);
  });
});

describe("mergeStatusMaps", () => {
  it("returns pending for all nodes with no context maps", () => {
    const merged = mergeStatusMaps(nodeIds, []);
    for (const nodeId of nodeIds) {
      expect(merged.get(nodeId)?.status).toBe("pending");
    }
  });

  it("uses merge precedence: running > complete", () => {
    const map1: StatusMap = initStatusMap(nodeIds);
    map1.get("implement")!.status = "running";

    const map2: StatusMap = initStatusMap(nodeIds);
    map2.get("implement")!.status = "complete";

    const merged = mergeStatusMaps(nodeIds, [map1, map2]);
    expect(merged.get("implement")?.status).toBe("running");
  });

  it("uses merge precedence: error > running", () => {
    const map1: StatusMap = initStatusMap(nodeIds);
    map1.get("implement")!.status = "running";

    const map2: StatusMap = initStatusMap(nodeIds);
    map2.get("implement")!.status = "error";

    const merged = mergeStatusMaps(nodeIds, [map1, map2]);
    expect(merged.get("implement")?.status).toBe("error");
  });

  it("AND semantics for hasLifecycleResolution", () => {
    const map1: StatusMap = initStatusMap(nodeIds);
    map1.get("implement")!.status = "complete";
    map1.get("implement")!.hasLifecycleResolution = true;

    const map2: StatusMap = initStatusMap(nodeIds);
    map2.get("implement")!.status = "running";
    map2.get("implement")!.hasLifecycleResolution = false;

    const merged = mergeStatusMaps(nodeIds, [map1, map2]);
    // running > complete, hasLifecycleResolution = true AND false = false
    expect(merged.get("implement")?.status).toBe("running");
    expect(merged.get("implement")?.hasLifecycleResolution).toBe(false);
  });

  it("sums turnCount and errorCount across contexts", () => {
    const map1: StatusMap = initStatusMap(nodeIds);
    map1.get("implement")!.turnCount = 3;
    map1.get("implement")!.errorCount = 1;
    map1.get("implement")!.status = "running";

    const map2: StatusMap = initStatusMap(nodeIds);
    map2.get("implement")!.turnCount = 5;
    map2.get("implement")!.errorCount = 2;
    map2.get("implement")!.status = "running";

    const merged = mergeStatusMaps(nodeIds, [map1, map2]);
    expect(merged.get("implement")?.turnCount).toBe(8);
    expect(merged.get("implement")?.errorCount).toBe(3);
  });
});

describe("applyErrorHeuristic", () => {
  it("promotes running to error on 3 consecutive ToolResult errors", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";
    mergedMap.get("implement")!.hasLifecycleResolution = false;

    const contextTurns: TurnItem[] = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("2", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("3", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
    ];

    const result = applyErrorHeuristic(mergedMap, nodeIds, [contextTurns]);
    expect(result.get("implement")?.status).toBe("error");
  });

  it("does not fire with fewer than 3 consecutive errors", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";
    mergedMap.get("implement")!.hasLifecycleResolution = false;

    const contextTurns: TurnItem[] = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("2", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
    ];

    const result = applyErrorHeuristic(mergedMap, nodeIds, [contextTurns]);
    expect(result.get("implement")?.status).toBe("running");
  });

  it("does not fire if node has lifecycle resolution", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";
    mergedMap.get("implement")!.hasLifecycleResolution = true;

    const contextTurns: TurnItem[] = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("2", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("3", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
    ];

    const result = applyErrorHeuristic(mergedMap, nodeIds, [contextTurns]);
    expect(result.get("implement")?.status).toBe("running");
  });

  it("does not fire if node is not running", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "complete";

    const contextTurns: TurnItem[] = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("2", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("3", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
    ];

    const result = applyErrorHeuristic(mergedMap, nodeIds, [contextTurns]);
    expect(result.get("implement")?.status).toBe("complete");
  });

  it("only fires on ToolResult turns (not other types)", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";
    mergedMap.get("implement")!.hasLifecycleResolution = false;

    // Mix of ToolResult and non-ToolResult turns
    const contextTurns: TurnItem[] = [
      makeTurn("1", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
      makeTurn("2", "implement", "com.kilroy.attractor.ToolCall"),
      makeTurn("3", "implement", "com.kilroy.attractor.ToolResult", {
        is_error: true,
      }),
    ];

    // Only 2 ToolResult errors — should not fire
    const result = applyErrorHeuristic(mergedMap, nodeIds, [contextTurns]);
    expect(result.get("implement")?.status).toBe("running");
  });
});

describe("applyStaleDetection", () => {
  it("sets running -> stale when pipeline is not live", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";
    mergedMap.get("implement")!.hasLifecycleResolution = false;

    const result = applyStaleDetection(mergedMap, nodeIds, false);
    expect(result.get("implement")?.status).toBe("stale");
  });

  it("does not affect running nodes when pipeline is live", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";

    const result = applyStaleDetection(mergedMap, nodeIds, true);
    expect(result.get("implement")?.status).toBe("running");
  });

  it("does not affect nodes with lifecycle resolution", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "running";
    mergedMap.get("implement")!.hasLifecycleResolution = true;

    const result = applyStaleDetection(mergedMap, nodeIds, false);
    expect(result.get("implement")?.status).toBe("running");
  });

  it("does not affect non-running nodes", () => {
    const mergedMap: StatusMap = initStatusMap(nodeIds);
    mergedMap.get("implement")!.status = "complete";

    const result = applyStaleDetection(mergedMap, nodeIds, false);
    expect(result.get("implement")?.status).toBe("complete");
  });
});
