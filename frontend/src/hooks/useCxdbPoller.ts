/**
 * useCxdbPoller — polls all CXDB instances every 3 seconds and maintains
 * per-context status maps, turn caches, and the connection indicator state.
 */
import { useState, useEffect, useRef, useCallback } from "react";
import type {
  ActiveContext,
  InstanceStatus,
  NodeStatus,
  Pipeline,
  StatusMap,
  TurnItem,
} from "@/types/index";
import { fetchContextList, fetchCqlSearch, fetchTurns } from "@/lib/api";
import {
  discoverForInstance,
  determineActiveRuns,
  checkPipelineLiveness,
  makeContextKey,
  type CachedContextLists,
} from "@/lib/discovery";
import {
  updateContextStatusMap,
  mergeStatusMaps,
  applyErrorHeuristic,
  applyStaleDetection,
} from "@/lib/status";
import type { KnownMapping } from "@/types/index";

type ContextKey = string; // `${cxdbIndex}:${contextId}`

export interface CxdbPollerState {
  /** Per-pipeline merged status maps (keyed by graph ID) */
  pipelineStatusMaps: Map<string, StatusMap>;
  /** Per-pipeline turn cache (keyed by pipeline graphId, then context key) */
  pipelineTurnCache: Map<string, Map<ContextKey, TurnItem[]>>;
  /** Per-instance reachability */
  instanceStatuses: InstanceStatus[];
  /** Active contexts per pipeline */
  activeContextsByPipeline: Map<string, ActiveContext[]>;
}

interface PollerRefs {
  knownMappings: Map<ContextKey, KnownMapping | null>;
  cachedContextLists: CachedContextLists;
  perContextStatusMaps: Map<ContextKey, StatusMap>;
  lastSeenTurnIds: Map<ContextKey, string | null>;
  previousActiveRunIds: Map<string, string | null>;
  pipelineTurnCache: Map<string, Map<ContextKey, TurnItem[]>>;
  cqlSupported: Map<number, boolean | undefined>;
  instanceReachable: Map<number, boolean>;
}

export function useCxdbPoller(
  pipelines: Pipeline[],
  cxdbInstances: string[],
  dotNodeIds: Map<string, Set<string>>
): CxdbPollerState {
  const [state, setState] = useState<CxdbPollerState>({
    pipelineStatusMaps: new Map(),
    pipelineTurnCache: new Map(),
    instanceStatuses: [],
    activeContextsByPipeline: new Map(),
  });

  const refs = useRef<PollerRefs>({
    knownMappings: new Map(),
    cachedContextLists: new Map(),
    perContextStatusMaps: new Map(),
    lastSeenTurnIds: new Map(),
    previousActiveRunIds: new Map(),
    pipelineTurnCache: new Map(),
    cqlSupported: new Map(),
    instanceReachable: new Map(),
  });

  const dotNodeIdsRef = useRef(dotNodeIds);
  dotNodeIdsRef.current = dotNodeIds;

  const pipelinesRef = useRef(pipelines);
  pipelinesRef.current = pipelines;

  const cxdbInstancesRef = useRef(cxdbInstances);
  cxdbInstancesRef.current = cxdbInstances;

  const poll = useCallback(async () => {
    const r = refs.current;
    const currentPipelines = pipelinesRef.current;
    const instances = cxdbInstancesRef.current;
    const currentDotNodeIds = dotNodeIdsRef.current;

    const newInstanceStatuses: InstanceStatus[] = new Array<InstanceStatus>(
      instances.length
    ).fill("unknown");

    // Step 1 & 2: fetch contexts and run discovery for each instance
    for (let i = 0; i < instances.length; i++) {
      const wasReachable = r.instanceReachable.get(i) ?? true;
      try {
        const discoveryDeps = {
          fetchContexts: async (idx: number, limit?: number) =>
            fetchContextList(idx, limit),
          fetchCqlSearch: async (idx: number, query: string) =>
            fetchCqlSearch(idx, query),
          fetchTurns: async (
            idx: number,
            contextId: string,
            opts?: { limit?: number; beforeTurnId?: string; view?: "typed" | "raw" }
          ) => fetchTurns(idx, contextId, opts ?? {}),
        };

        if (!wasReachable) {
          // Instance reconnected — reset CQL state
          r.cqlSupported.set(i, undefined);
        }

        const effectiveContexts = await discoverForInstance(
          discoveryDeps,
          i,
          r.knownMappings,
          r.cqlSupported
        );

        r.cachedContextLists.set(i, effectiveContexts);
        r.instanceReachable.set(i, true);
        newInstanceStatuses[i] = "ok";
      } catch {
        r.instanceReachable.set(i, false);
        newInstanceStatuses[i] = "unreachable";
        // Retain cached context list from last successful poll
      }
    }

    // Step 3: determine active runs
    const validPipelines = currentPipelines.filter(
      (p): p is Pipeline & { graphId: string } => p.graphId !== null
    );

    const prevRunIds = r.previousActiveRunIds;
    const activeContextsByPipeline = determineActiveRuns(
      validPipelines,
      r.knownMappings,
      prevRunIds
    );

    // Detect run changes and reset state
    for (const [graphId, activeCtxs] of activeContextsByPipeline.entries()) {
      const activeRunId =
        activeCtxs.length > 0 ? activeCtxs[0].runId : null;
      const prevRunId = prevRunIds.get(graphId);
      if (
        prevRunId !== undefined &&
        prevRunId !== null &&
        prevRunId !== activeRunId &&
        activeRunId !== null
      ) {
        // Run changed — reset per-context state for this pipeline
        for (const [key, mapping] of r.knownMappings.entries()) {
          if (mapping?.graphName === graphId) {
            r.perContextStatusMaps.delete(key);
            r.lastSeenTurnIds.set(key, null);
          }
        }
        r.pipelineTurnCache.delete(graphId);
      }
    }

    // Step 4 & 5: fetch turns for active contexts
    for (const [graphId, activeCtxs] of activeContextsByPipeline.entries()) {
      let pipelineCache = r.pipelineTurnCache.get(graphId);
      if (!pipelineCache) {
        pipelineCache = new Map();
        r.pipelineTurnCache.set(graphId, pipelineCache);
      }

      for (const ctx of activeCtxs) {
        const key = makeContextKey(ctx.cxdbIndex, ctx.contextId);
        if (!(r.instanceReachable.get(ctx.cxdbIndex) ?? true)) continue;

        try {
          const resp = await fetchTurns(ctx.cxdbIndex, ctx.contextId, {
            limit: 100,
            view: "typed",
          });
          let turns = resp.turns;

          // Gap recovery
          const lastSeen = r.lastSeenTurnIds.get(key) ?? null;
          const MAX_GAP_PAGES = 10;
          if (
            turns.length > 0 &&
            lastSeen !== null &&
            resp.next_before_turn_id !== null
          ) {
            const oldestFetched = parseInt(turns[0].turn_id, 10);
            const lastSeenNum = parseInt(lastSeen, 10);
            if (oldestFetched > lastSeenNum) {
              const recovered: TurnItem[] = [];
              let cursor: string | null = resp.next_before_turn_id;
              let pagesFetched = 0;
              while (cursor !== null && pagesFetched < MAX_GAP_PAGES) {
                const gapResp = await fetchTurns(
                  ctx.cxdbIndex,
                  ctx.contextId,
                  { limit: 100, beforeTurnId: cursor, view: "typed" }
                );
                pagesFetched++;
                if (gapResp.turns.length === 0) break;
                recovered.unshift(...gapResp.turns);
                const oldest = parseInt(gapResp.turns[0].turn_id, 10);
                if (oldest <= lastSeenNum) break;
                cursor = gapResp.next_before_turn_id;
              }
              if (
                pagesFetched >= MAX_GAP_PAGES &&
                cursor !== null &&
                recovered.length > 0
              ) {
                r.lastSeenTurnIds.set(key, recovered[0].turn_id);
              }
              turns = [...recovered, ...turns];
            }
          }

          pipelineCache.set(key, turns);

          // Update per-context status map
          const nodeIds = currentDotNodeIds.get(graphId) ?? new Set<string>();
          let contextMap = r.perContextStatusMaps.get(key);
          if (!contextMap) {
            contextMap = new Map();
            r.perContextStatusMaps.set(key, contextMap);
          }
          const { newLastSeenTurnId } = updateContextStatusMap(
            contextMap,
            nodeIds,
            turns,
            lastSeen
          );
          r.lastSeenTurnIds.set(key, newLastSeenTurnId);
        } catch {
          // Retain cached data on error
        }
      }
    }

    // Step 6: merge status maps per pipeline
    const pipelineStatusMaps = new Map<string, StatusMap>();
    for (const pipeline of validPipelines) {
      const graphId = pipeline.graphId;
      const activeCtxs = activeContextsByPipeline.get(graphId) ?? [];
      const nodeIds = currentDotNodeIds.get(graphId) ?? new Set<string>();
      const pipelineCache = r.pipelineTurnCache.get(graphId) ?? new Map();

      const perContextMaps: Map<string, NodeStatus>[] = [];
      for (const ctx of activeCtxs) {
        const key = makeContextKey(ctx.cxdbIndex, ctx.contextId);
        const m = r.perContextStatusMaps.get(key);
        if (m) perContextMaps.push(m);
      }

      let merged = mergeStatusMaps(nodeIds, perContextMaps);

      // Apply error heuristic
      const cacheArrays = Array.from(pipelineCache.values());
      merged = applyErrorHeuristic(merged, nodeIds, cacheArrays);

      // Apply stale detection
      const isLive = checkPipelineLiveness(activeCtxs, r.cachedContextLists);
      merged = applyStaleDetection(merged, nodeIds, isLive);

      pipelineStatusMaps.set(graphId, merged);
    }

    // Build ActiveContext[] typed result
    const typedActiveContextsByPipeline = new Map<string, ActiveContext[]>();
    for (const [graphId, ctxs] of activeContextsByPipeline.entries()) {
      typedActiveContextsByPipeline.set(graphId, ctxs);
    }

    setState({
      pipelineStatusMaps,
      pipelineTurnCache: new Map(r.pipelineTurnCache),
      instanceStatuses: newInstanceStatuses,
      activeContextsByPipeline: typedActiveContextsByPipeline,
    });
  }, []);

  useEffect(() => {
    if (cxdbInstances.length === 0) return;

    let timeoutId: ReturnType<typeof setTimeout>;
    let cancelled = false;

    const runPoll = async () => {
      if (cancelled) return;
      await poll();
      if (!cancelled) {
        timeoutId = setTimeout(() => void runPoll(), 3000);
      }
    };

    void runPoll();

    return () => {
      cancelled = true;
      clearTimeout(timeoutId);
    };
  }, [cxdbInstances, poll]);

  return state;
}
