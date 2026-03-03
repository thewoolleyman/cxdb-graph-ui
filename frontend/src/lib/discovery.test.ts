/**
 * Unit tests for pipeline discovery logic.
 */

import { describe, it, expect, vi, type Mock } from "vitest";
import {
  fetchFirstTurn,
  discoverForInstance,
  makeContextKey,
  determineActiveRuns,
  checkPipelineLiveness,
  recoverGap,
  NULL_TAG_BATCH_SIZE,
} from "./discovery";
import type {
  ContextInfo,
  ContextListResponse,
  CqlSearchResponse,
  KnownMapping,
  TurnItem,
  TurnResponse,
} from "@/types/index";

function makeContext(
  contextId: string,
  opts: Partial<ContextInfo> = {}
): ContextInfo {
  return {
    context_id: contextId,
    head_depth: 5,
    head_turn_id: "100",
    created_at_unix_ms: 1000000,
    is_live: false,
    client_tag: `kilroy/run-${contextId}`,
    ...opts,
  };
}

function makeRunStartedTurn(
  graphName: string,
  runId: string,
  turnId = "1"
): TurnItem {
  return {
    turn_id: turnId,
    parent_turn_id: null,
    depth: 0,
    declared_type: {
      type_id: "com.kilroy.attractor.RunStarted",
      type_version: 1,
    },
    data: { graph_name: graphName, run_id: runId },
    bytes_b64: btoa(JSON.stringify({ "1": runId, "8": graphName })),
  };
}

function makeTurnResponse(
  turns: TurnItem[],
  nextBeforeTurnId: string | null = null
): TurnResponse {
  return {
    meta: {
      context_id: "1",
      head_depth: turns.length,
      head_turn_id: turns[turns.length - 1]?.turn_id ?? "0",
      registry_bundle_id: "kilroy-attractor-v1",
    },
    turns,
    next_before_turn_id: nextBeforeTurnId,
  };
}

describe("makeContextKey", () => {
  it("formats the key correctly", () => {
    expect(makeContextKey(0, "33")).toBe("0:33");
    expect(makeContextKey(1, "100")).toBe("1:100");
  });
});

describe("fetchFirstTurn", () => {
  it("returns turn for headDepth=0 context", async () => {
    const turn = makeRunStartedTurn("alpha", "run1");
    const fetchTurns = vi.fn().mockResolvedValue(makeTurnResponse([turn]));
    const result = await fetchFirstTurn(
      { fetchTurns },
      0,
      "1",
      0
    );
    expect(result?.turn_id).toBe("1");
  });

  it("returns null for empty context (headDepth=0)", async () => {
    const fetchTurns = vi.fn().mockResolvedValue(makeTurnResponse([]));
    const result = await fetchFirstTurn({ fetchTurns }, 0, "1", 0);
    expect(result).toBeNull();
  });

  it("paginates to find depth=0 turn", async () => {
    const turn0 = { ...makeRunStartedTurn("alpha", "run1", "1"), depth: 0 };
    const turn1 = { ...makeRunStartedTurn("alpha", "run1", "2"), depth: 1 };

    const fetchTurns = vi.fn().mockImplementation(
      (_idx: number, _ctxId: string, opts?: { beforeTurnId?: string }) => {
        if (!opts?.beforeTurnId) {
          // First page — return turn1 at head
          return Promise.resolve(makeTurnResponse([turn1], null));
        }
        // Paginated page — return turn0
        return Promise.resolve(makeTurnResponse([turn0], null));
      }
    );

    const result = await fetchFirstTurn({ fetchTurns }, 0, "1", 5);
    expect(result?.depth).toBe(0);
    expect(result?.turn_id).toBe("1");
  });

  it("returns null when MAX_PAGES exceeded", async () => {
    // Always return a non-depth-0 turn
    const turn = {
      ...makeRunStartedTurn("alpha", "run1", "100"),
      depth: 1000,
    };
    const fetchTurns = vi
      .fn()
      .mockResolvedValue(makeTurnResponse([turn], "99"));

    const result = await fetchFirstTurn({ fetchTurns }, 0, "1", 5000);
    expect(result).toBeNull();
    // Should have made MAX_PAGES=50 requests
    expect((fetchTurns as Mock).mock.calls.length).toBe(50);
  });
});

function makeDecodeFirstTurnMock(graphName: string, runId: string) {
  return vi.fn().mockImplementation(async (turn: TurnItem) => {
    if (
      turn.declared_type.type_id === "com.kilroy.attractor.RunStarted"
    ) {
      return {
        declared_type: turn.declared_type,
        data: { graph_name: graphName, run_id: runId },
      };
    }
    return { declared_type: turn.declared_type, data: null };
  });
}

describe("discoverForInstance", () => {
  it("discovers pipeline via CQL search", async () => {
    const ctx = makeContext("33");
    const firstTurn = makeRunStartedTurn("alpha_pipeline", "run123");

    const fetchCqlSearch = vi.fn().mockResolvedValue({
      contexts: [ctx],
      total_count: 1,
      elapsed_ms: 1,
      query: 'tag ^= "kilroy/"',
    } as CqlSearchResponse);

    const fetchContexts = vi.fn().mockResolvedValue({
      contexts: [ctx],
      count: 1,
    } as ContextListResponse);

    const fetchTurns = vi.fn().mockResolvedValue(
      makeTurnResponse([{ ...firstTurn, depth: 0 }])
    );

    const decodeFirstTurnMock = makeDecodeFirstTurnMock(
      "alpha_pipeline",
      "run123"
    );

    const knownMappings = new Map<string, KnownMapping | null>();
    const cqlSupported = new Map<number, boolean | undefined>();

    await discoverForInstance(
      {
        fetchContexts,
        fetchCqlSearch,
        fetchTurns,
        decodeFirstTurn: decodeFirstTurnMock,
      },
      0,
      knownMappings,
      cqlSupported
    );

    const key = makeContextKey(0, "33");
    expect(knownMappings.get(key)).toMatchObject({
      graphName: "alpha_pipeline",
    });
    expect(cqlSupported.get(0)).toBe(true);
  });

  it("falls back to context list when CQL returns 404", async () => {
    const ctx = makeContext("33");
    const firstTurn = makeRunStartedTurn("alpha_pipeline", "run123");

    const fetchCqlSearch = vi.fn().mockResolvedValue(null); // 404
    const fetchContexts = vi.fn().mockResolvedValue({
      contexts: [ctx],
      count: 1,
    } as ContextListResponse);

    const fetchTurns = vi.fn().mockResolvedValue(
      makeTurnResponse([{ ...firstTurn, depth: 0 }])
    );

    const decodeFirstTurnMock = makeDecodeFirstTurnMock(
      "alpha_pipeline",
      "run123"
    );

    const knownMappings = new Map<string, KnownMapping | null>();
    const cqlSupported = new Map<number, boolean | undefined>();

    await discoverForInstance(
      {
        fetchContexts,
        fetchCqlSearch,
        fetchTurns,
        decodeFirstTurn: decodeFirstTurnMock,
      },
      0,
      knownMappings,
      cqlSupported
    );

    expect(cqlSupported.get(0)).toBe(false);
    const key = makeContextKey(0, "33");
    expect(knownMappings.get(key)).toMatchObject({
      graphName: "alpha_pipeline",
    });
  });

  it("caches null for confirmed non-Kilroy contexts (CQL fallback)", async () => {
    const ctx = makeContext("33", { client_tag: "other/tag" });

    const fetchCqlSearch = vi.fn().mockResolvedValue(null);
    const fetchContexts = vi.fn().mockResolvedValue({
      contexts: [ctx],
    } as ContextListResponse);

    const fetchTurns = vi.fn();
    const knownMappings = new Map<string, KnownMapping | null>();
    const cqlSupported = new Map<number, boolean | undefined>();

    await discoverForInstance(
      { fetchContexts, fetchCqlSearch, fetchTurns },
      0,
      knownMappings,
      cqlSupported
    );

    const key = makeContextKey(0, "33");
    expect(knownMappings.get(key)).toBeNull();
    expect((fetchTurns as Mock).mock.calls.length).toBe(0);
  });

  it("skips already-known contexts", async () => {
    const ctx = makeContext("33");
    const fetchCqlSearch = vi.fn().mockResolvedValue(null);
    const fetchContexts = vi.fn().mockResolvedValue({
      contexts: [ctx],
    } as ContextListResponse);

    const fetchTurns = vi.fn();

    const key = makeContextKey(0, "33");
    const knownMappings = new Map<string, KnownMapping | null>();
    knownMappings.set(key, { graphName: "alpha", runId: "run1" });
    const cqlSupported = new Map<number, boolean | undefined>();

    await discoverForInstance(
      { fetchContexts, fetchCqlSearch, fetchTurns },
      0,
      knownMappings,
      cqlSupported
    );

    // fetchTurns should not be called for already-known contexts
    expect((fetchTurns as Mock).mock.calls.length).toBe(0);
  });

  it("processes null-tag candidates with batch limit", async () => {
    // Create NULL_TAG_BATCH_SIZE + 2 null-tag contexts
    const nullTagContexts = Array.from(
      { length: NULL_TAG_BATCH_SIZE + 2 },
      (_, i) => makeContext(String(i + 1), { client_tag: null })
    );

    const fetchCqlSearch = vi.fn().mockResolvedValue(null);
    const fetchContexts = vi.fn().mockResolvedValue({
      contexts: nullTagContexts,
    } as ContextListResponse);

    const decodeFirstTurnMock = makeDecodeFirstTurnMock("alpha", "run1");
    const fetchTurns = vi.fn().mockResolvedValue(
      makeTurnResponse([
        {
          ...makeRunStartedTurn("alpha", "run1"),
          depth: 0,
        },
      ])
    );

    const knownMappings = new Map<string, KnownMapping | null>();
    const cqlSupported = new Map<number, boolean | undefined>();

    await discoverForInstance(
      {
        fetchContexts,
        fetchCqlSearch,
        fetchTurns,
        decodeFirstTurn: decodeFirstTurnMock,
      },
      0,
      knownMappings,
      cqlSupported
    );

    // Should only process NULL_TAG_BATCH_SIZE contexts
    expect((fetchTurns as Mock).mock.calls.length).toBeLessThanOrEqual(
      NULL_TAG_BATCH_SIZE
    );
  });
});

describe("determineActiveRuns", () => {
  it("selects the run with the lexicographically greatest run_id", () => {
    const knownMappings = new Map<string, KnownMapping | null>();
    knownMappings.set("0:1", {
      graphName: "alpha",
      runId: "01AAAAAA",
    });
    knownMappings.set("0:2", {
      graphName: "alpha",
      runId: "01ZZZZZZ",
    });

    const previous = new Map<string, string | null>();
    const result = determineActiveRuns(
      [{ graphId: "alpha" }],
      knownMappings,
      previous
    );

    const activeContexts = result.get("alpha") ?? [];
    expect(activeContexts.every((c) => c.runId === "01ZZZZZZ")).toBe(true);
  });

  it("returns empty array when no contexts match pipeline", () => {
    const knownMappings = new Map<string, KnownMapping | null>();
    const previous = new Map<string, string | null>();
    const result = determineActiveRuns(
      [{ graphId: "alpha" }],
      knownMappings,
      previous
    );
    expect(result.get("alpha")).toEqual([]);
  });
});

describe("checkPipelineLiveness", () => {
  it("returns true when any context is live", () => {
    const cachedContextLists = new Map<number, ContextInfo[]>();
    cachedContextLists.set(0, [makeContext("1", { is_live: true })]);
    expect(
      checkPipelineLiveness(
        [{ cxdbIndex: 0, contextId: "1", runId: "r1" }],
        cachedContextLists
      )
    ).toBe(true);
  });

  it("returns false when no contexts are live", () => {
    const cachedContextLists = new Map<number, ContextInfo[]>();
    cachedContextLists.set(0, [makeContext("1", { is_live: false })]);
    expect(
      checkPipelineLiveness(
        [{ cxdbIndex: 0, contextId: "1", runId: "r1" }],
        cachedContextLists
      )
    ).toBe(false);
  });
});

describe("recoverGap", () => {
  it("returns empty when no gap", async () => {
    const fetchTurns = vi.fn();
    const result = await recoverGap(
      { fetchTurns },
      0,
      "1",
      "100", // lastSeenTurnId
      "99", // firstBatchOldestTurnId <= lastSeenTurnId — no gap
      "98"
    );
    expect(result).toEqual([]);
    expect((fetchTurns as Mock).mock.calls.length).toBe(0);
  });

  it("stops gap recovery when empty response received", async () => {
    const fetchTurns = vi.fn().mockResolvedValue(
      makeTurnResponse([], null) // empty turns
    );

    const result = await recoverGap(
      { fetchTurns },
      0,
      "1",
      "30",
      "80",
      "79"
    );

    expect(result).toEqual([]);
    expect((fetchTurns as Mock).mock.calls.length).toBe(1);
  });

  it("stops gap recovery when lastSeenTurnId is reached in gap page", async () => {
    const gapTurn: TurnItem = {
      turn_id: "35",
      parent_turn_id: null,
      depth: 1,
      declared_type: {
        type_id: "com.kilroy.attractor.StageStarted",
        type_version: 1,
      },
      data: { node_id: "implement" },
    };

    const fetchTurns = vi.fn().mockResolvedValue(
      makeTurnResponse([gapTurn], "34")
    );

    // lastSeenTurnId=30, firstBatchOldestTurnId=80 (gap), nextBeforeTurnId=79
    // gap page returns turn_id=35, which is > lastSeenTurnId=30 but <= next
    const result = await recoverGap(
      { fetchTurns },
      0,
      "1",
      "30",
      "80",
      "79"
    );

    // Should include the recovered turn
    expect(result.length).toBeGreaterThan(0);
  });

  it("stops gap recovery when lastSeenTurnId is reached in gap page", async () => {
    const gapTurn: TurnItem = {
      turn_id: "50",
      parent_turn_id: null,
      depth: 1,
      declared_type: {
        type_id: "com.kilroy.attractor.StageStarted",
        type_version: 1,
      },
      data: { node_id: "implement" },
    };

    const fetchTurns = vi.fn().mockResolvedValue(
      makeTurnResponse([gapTurn], null)
    );

    const result = await recoverGap(
      { fetchTurns },
      0,
      "1",
      "30", // lastSeenTurnId
      "80", // firstBatchOldestTurnId > lastSeenTurnId — gap!
      "79" // nextBeforeTurnId
    );

    expect(result.length).toBeGreaterThan(0);
    expect((fetchTurns as Mock).mock.calls.length).toBeGreaterThan(0);
  });
});

