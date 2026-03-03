/**
 * Pipeline discovery logic (pure functions).
 * Discovers which CXDB contexts belong to which pipelines by reading
 * the RunStarted turn.
 */

import type {
  ActiveContext,
  ContextInfo,
  ContextListResponse,
  CqlSearchResponse,
  KnownMapping,
  TurnItem,
  TurnResponse,
} from "@/types/index";
import { decodeFirstTurn as defaultDecodeFirstTurn } from "@/lib/msgpack";
import { numericTurnId } from "@/lib/utils";

export const NULL_TAG_BATCH_SIZE = 5;
export const MAX_PAGES = 50;
export const PAGE_SIZE = 100;

type FetchContextsFn = (
  index: number,
  limit?: number
) => Promise<ContextListResponse>;

type FetchCqlSearchFn = (
  index: number,
  query: string
) => Promise<CqlSearchResponse | null>;

type FetchTurnsFn = (
  index: number,
  contextId: string,
  options?: { limit?: number; beforeTurnId?: string; view?: "typed" | "raw" }
) => Promise<TurnResponse>;

type DecodeFirstTurnFn = (
  turn: TurnItem
) => Promise<{
  declared_type: { type_id: string; type_version: number };
  data: { graph_name: string | null; run_id: string | null } | null;
} | null>;

export interface DiscoveryDeps {
  fetchContexts: FetchContextsFn;
  fetchCqlSearch: FetchCqlSearchFn;
  fetchTurns: FetchTurnsFn;
  decodeFirstTurn?: DecodeFirstTurnFn;
}

// Cached context lists per CXDB instance (used for liveness checks)
export type CachedContextLists = Map<number, ContextInfo[]>;

/**
 * Fetch the first turn of a context, paginating backward from the head.
 * Uses view=raw to avoid type registry dependency.
 * Returns null if the context is empty, or if MAX_PAGES is exceeded.
 */
export async function fetchFirstTurn(
  deps: Pick<DiscoveryDeps, "fetchTurns">,
  cxdbIndex: number,
  contextId: string,
  headDepth: number
): Promise<TurnItem | null> {
  const { fetchTurns } = deps;

  // Fast path: headDepth == 0 means at most one turn
  if (headDepth === 0) {
    const resp = await fetchTurns(cxdbIndex, contextId, {
      limit: 1,
      view: "raw",
    });
    if (resp.turns.length === 0) {
      return null;
    }
    if (resp.turns[0].depth === 0) {
      return resp.turns[0];
    }
    // Fall through to pagination
  }

  // Paginate backward from head
  let cursor: string | null = null;

  for (let page = 1; page <= MAX_PAGES; page++) {
    const resp = await fetchTurns(cxdbIndex, contextId, {
      limit: PAGE_SIZE,
      beforeTurnId: cursor ?? undefined,
      view: "raw",
    });

    if (resp.turns.length === 0) {
      return null;
    }

    // turns are oldest-first; check if depth=0 is in this page
    if (resp.turns[0].depth === 0) {
      return resp.turns[0];
    }

    // Continue paginating backward
    cursor = resp.turns[0].turn_id;
  }

  // Exceeded MAX_PAGES without finding depth=0
  console.warn(
    `[discovery] context ${contextId} on instance ${cxdbIndex} exceeds MAX_PAGES pagination cap`
  );
  return null;
}

/**
 * Run pipeline discovery for one CXDB instance.
 * Updates knownMappings and returns the effective context list for caching.
 */
export async function discoverForInstance(
  deps: DiscoveryDeps,
  cxdbIndex: number,
  knownMappings: Map<string, KnownMapping | null>,
  cqlSupported: Map<number, boolean | undefined>
): Promise<ContextInfo[]> {
  const { fetchContexts, fetchCqlSearch, fetchTurns } = deps;
  const decodeFn = deps.decodeFirstTurn ?? defaultDecodeFirstTurn;

  let contexts: ContextInfo[] = [];
  const supplementalNullTagCandidates: ContextInfo[] = [];

  const isSupported = cqlSupported.get(cxdbIndex);

  if (isSupported !== false) {
    // Try CQL search first
    try {
      const searchResp = await fetchCqlSearch(cxdbIndex, 'tag ^= "kilroy/"');
      if (searchResp === null) {
        // 404 — CQL not supported
        cqlSupported.set(cxdbIndex, false);
        const listResp = await fetchContexts(cxdbIndex, 10000);
        contexts = listResp.contexts;
      } else {
        cqlSupported.set(cxdbIndex, true);
        contexts = searchResp.contexts;

        // Always run supplemental fetch (three roles — see spec Section 5.2)
        const supplemental = await fetchContexts(cxdbIndex, 10000);
        const cqlContextIds = new Set(contexts.map((c) => c.context_id));

        for (const ctx of supplemental.contexts) {
          if (
            ctx.client_tag !== null &&
            ctx.client_tag !== undefined &&
            ctx.client_tag.startsWith("kilroy/")
          ) {
            if (!cqlContextIds.has(ctx.context_id)) {
              contexts.push(ctx);
              cqlContextIds.add(ctx.context_id);
            }
          } else if (ctx.client_tag === null || ctx.client_tag === undefined) {
            supplementalNullTagCandidates.push(ctx);
          }
        }
      }
    } catch (e) {
      // Check if this is a 400 error (CQL supported but query rejected)
      const errorMsg = e instanceof Error ? e.message : String(e);
      if (errorMsg.includes("400")) {
        console.warn(
          `[discovery] CQL query error on instance ${cxdbIndex}: ${errorMsg}`
        );
        // Don't set cqlSupported to false — CQL works, query failed
        return [];
      }
      // Other errors (502, network) — instance unreachable
      return [];
    }
  } else {
    // CQL not supported — use fallback
    try {
      const listResp = await fetchContexts(cxdbIndex, 10000);
      contexts = listResp.contexts;
    } catch {
      return [];
    }
  }

  // Build null-tag candidates from fallback path (CQL not supported)
  const nullTagCandidates: ContextInfo[] = [...supplementalNullTagCandidates];

  // Process contexts for Phase 2 discovery
  for (const context of contexts) {
    const key = makeContextKey(cxdbIndex, context.context_id);
    if (knownMappings.has(key)) {
      continue; // already discovered
    }

    const isSupp = cqlSupported.get(cxdbIndex);
    if (isSupp === false) {
      // Client-side prefix filter for fallback path
      if (
        context.client_tag !== null &&
        context.client_tag !== undefined &&
        !context.client_tag.startsWith("kilroy/")
      ) {
        knownMappings.set(key, null); // confirmed non-Kilroy
        continue;
      } else if (
        context.client_tag === null ||
        context.client_tag === undefined
      ) {
        nullTagCandidates.push(context);
        continue;
      }
    }

    // Phase 2: fetch first turn
    try {
      const firstTurn = await fetchFirstTurn(
        { fetchTurns },
        cxdbIndex,
        context.context_id,
        context.head_depth
      );

      if (firstTurn === null) {
        // Empty context — don't cache, retry next poll
        continue;
      }

      const decoded = await decodeFn(firstTurn);
      if (!decoded) {
        continue; // decode error — retry
      }

      if (
        decoded.declared_type.type_id === "com.kilroy.attractor.RunStarted"
      ) {
        const graphName = decoded.data?.graph_name;
        const runId = decoded.data?.run_id;
        if (!graphName) {
          knownMappings.set(key, null);
          continue;
        }
        knownMappings.set(key, { graphName, runId: runId ?? "" });
      } else if (firstTurn.depth === 0) {
        // Has a first turn but it's not RunStarted
        knownMappings.set(key, null);
      }
      // else: no first turn found (null returned from fetchFirstTurn)
    } catch {
      // Transient failure — don't cache, retry next poll
      continue;
    }
  }

  // Null-tag batch: attempt fetchFirstTurn for the newest N null-tag contexts
  const sortedNullTag = [...nullTagCandidates].sort(
    (a, b) => parseInt(b.context_id, 10) - parseInt(a.context_id, 10)
  );

  let nullTagProcessed = 0;
  for (const context of sortedNullTag) {
    if (nullTagProcessed >= NULL_TAG_BATCH_SIZE) {
      break;
    }
    const key = makeContextKey(cxdbIndex, context.context_id);
    if (knownMappings.has(key)) {
      continue; // skip (does NOT count toward batch limit)
    }

    nullTagProcessed++;
    try {
      const firstTurn = await fetchFirstTurn(
        { fetchTurns },
        cxdbIndex,
        context.context_id,
        context.head_depth
      );

      if (firstTurn === null) {
        continue; // empty context — retry next poll
      }

      const decoded = await decodeFn(firstTurn);
      if (!decoded) {
        continue;
      }

      if (
        decoded.declared_type.type_id === "com.kilroy.attractor.RunStarted"
      ) {
        const graphName = decoded.data?.graph_name;
        const runId = decoded.data?.run_id;
        if (!graphName) {
          knownMappings.set(key, null);
          continue;
        }
        knownMappings.set(key, { graphName, runId: runId ?? "" });
      } else {
        knownMappings.set(key, null); // confirmed non-Kilroy
      }
    } catch {
      // Transient failure — don't cache
      continue;
    }
  }

  return contexts;
}

/**
 * Make the key for the knownMappings map.
 */
export function makeContextKey(
  cxdbIndex: number,
  contextId: string
): string {
  return `${cxdbIndex}:${contextId}`;
}

/**
 * Determine the active run for each pipeline.
 * Returns a map from graphId to the active run's contexts.
 */
export function determineActiveRuns(
  pipelines: Array<{ graphId: string }>,
  knownMappings: Map<string, KnownMapping | null>,
  previousActiveRunIds: Map<string, string | null>
): Map<
  string,
  Array<{ cxdbIndex: number; contextId: string; runId: string }>
> {
  const activeContextsByPipeline = new Map<
    string,
    Array<{ cxdbIndex: number; contextId: string; runId: string }>
  >();

  for (const pipeline of pipelines) {
    const candidates: Array<{
      cxdbIndex: number;
      contextId: string;
      runId: string;
    }> = [];

    for (const [key, mapping] of knownMappings.entries()) {
      if (mapping !== null && mapping.graphName === pipeline.graphId) {
        const [indexStr, contextId] = parseContextKey(key);
        candidates.push({
          cxdbIndex: indexStr,
          contextId,
          runId: mapping.runId,
        });
      }
    }

    if (candidates.length === 0) {
      activeContextsByPipeline.set(pipeline.graphId, []);
      continue;
    }

    // Group by runId, pick the lexicographically greatest run_id (ULID order)
    const runGroups = new Map<
      string,
      Array<{ cxdbIndex: number; contextId: string; runId: string }>
    >();
    for (const c of candidates) {
      const group = runGroups.get(c.runId) ?? [];
      group.push(c);
      runGroups.set(c.runId, group);
    }

    let activeRunId: string | null = null;
    for (const runId of runGroups.keys()) {
      if (activeRunId === null || runId > activeRunId) {
        activeRunId = runId;
      }
    }

    const prev = previousActiveRunIds.get(pipeline.graphId);
    if (prev !== null && prev !== undefined && prev !== activeRunId) {
      // Run changed — caller should reset pipeline state
      previousActiveRunIds.set(pipeline.graphId, activeRunId);
    } else {
      previousActiveRunIds.set(pipeline.graphId, activeRunId);
    }

    activeContextsByPipeline.set(
      pipeline.graphId,
      activeRunId ? (runGroups.get(activeRunId) ?? []) : []
    );
  }

  return activeContextsByPipeline;
}

function parseContextKey(key: string): [number, string] {
  const colonIdx = key.indexOf(":");
  if (colonIdx < 0) {
    return [0, key];
  }
  return [parseInt(key.slice(0, colonIdx), 10), key.slice(colonIdx + 1)];
}

/**
 * Check whether a pipeline's active run has any live sessions.
 */
export function checkPipelineLiveness(
  activeContexts: ActiveContext[],
  cachedContextLists: CachedContextLists
): boolean {
  for (const ctx of activeContexts) {
    const list = cachedContextLists.get(ctx.cxdbIndex);
    if (!list) continue;
    const info = list.find((c) => c.context_id === ctx.contextId);
    if (info?.is_live) {
      return true;
    }
  }
  return false;
}

/**
 * Gap recovery: fetch turns between lastSeenTurnId and the current batch.
 * Returns the recovered turns (oldest-first) to prepend to the main batch.
 */
export async function recoverGap(
  deps: Pick<DiscoveryDeps, "fetchTurns">,
  cxdbIndex: number,
  contextId: string,
  lastSeenTurnId: string,
  firstBatchOldestTurnId: string,
  nextBeforeTurnId: string | null
): Promise<TurnItem[]> {
  const MAX_GAP_PAGES = 10;
  const recoveredTurns: TurnItem[] = [];

  // Only run gap recovery if needed
  if (
    numericTurnId(firstBatchOldestTurnId) <=
    numericTurnId(lastSeenTurnId)
  ) {
    return recoveredTurns;
  }
  if (!nextBeforeTurnId) {
    return recoveredTurns;
  }

  let cursor: string | null = nextBeforeTurnId;
  let pagesFetched = 0;

  while (cursor && pagesFetched < MAX_GAP_PAGES) {
    const gapResp = await deps.fetchTurns(cxdbIndex, contextId, {
      limit: 100,
      beforeTurnId: cursor,
    });
    pagesFetched++;

    if (gapResp.turns.length === 0) {
      break;
    }

    // Prepend to maintain oldest-first
    recoveredTurns.unshift(...gapResp.turns);

    const oldestInGap = gapResp.turns[0].turn_id;
    if (numericTurnId(oldestInGap) <= numericTurnId(lastSeenTurnId)) {
      break;
    }

    cursor = gapResp.next_before_turn_id;
  }

  return recoveredTurns;
}
