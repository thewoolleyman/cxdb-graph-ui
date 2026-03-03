/**
 * API fetch wrappers for the CXDB Graph UI server API.
 */

import type {
  ContextListResponse,
  CqlSearchResponse,
  EdgeInfo,
  NodeAttrs,
  TurnResponse,
} from "@/types/index";

const BASE_URL = "";

/**
 * Fetch the list of available DOT filenames.
 */
export async function fetchDotList(): Promise<string[]> {
  const resp = await fetch(`${BASE_URL}/api/dots`);
  if (!resp.ok) {
    throw new Error(`Failed to fetch dot list: ${resp.status}`);
  }
  const data = (await resp.json()) as { dots: string[] };
  return data.dots;
}

/**
 * Fetch the list of configured CXDB instance URLs.
 */
export async function fetchCxdbInstances(): Promise<string[]> {
  const resp = await fetch(`${BASE_URL}/api/cxdb/instances`);
  if (!resp.ok) {
    throw new Error(`Failed to fetch CXDB instances: ${resp.status}`);
  }
  const data = (await resp.json()) as { instances: string[] };
  return data.instances;
}

/**
 * Fetch the raw DOT source for a named pipeline.
 */
export async function fetchDotSource(name: string): Promise<string> {
  const resp = await fetch(`${BASE_URL}/dots/${encodeURIComponent(name)}`);
  if (!resp.ok) {
    throw new Error(`Failed to fetch DOT source for '${name}': ${resp.status}`);
  }
  return resp.text();
}

/**
 * Fetch parsed node attributes for a named pipeline.
 * Returns a map from nodeId to NodeAttrs.
 */
export async function fetchNodes(
  name: string
): Promise<Record<string, NodeAttrs>> {
  const resp = await fetch(
    `${BASE_URL}/dots/${encodeURIComponent(name)}/nodes`
  );
  if (!resp.ok) {
    throw new Error(`Failed to fetch nodes for '${name}': ${resp.status}`);
  }
  return resp.json() as Promise<Record<string, NodeAttrs>>;
}

/**
 * Fetch parsed edges for a named pipeline.
 */
export async function fetchEdges(name: string): Promise<EdgeInfo[]> {
  const resp = await fetch(
    `${BASE_URL}/dots/${encodeURIComponent(name)}/edges`
  );
  if (!resp.ok) {
    throw new Error(`Failed to fetch edges for '${name}': ${resp.status}`);
  }
  return resp.json() as Promise<EdgeInfo[]>;
}

/**
 * Fetch CXDB contexts using CQL search (primary discovery).
 * Returns null if the endpoint returns 404 (CQL not supported).
 * Throws for other error status codes.
 */
export async function fetchCqlSearch(
  cxdbIndex: number,
  query: string
): Promise<CqlSearchResponse | null> {
  const url = `${BASE_URL}/api/cxdb/${cxdbIndex}/v1/contexts/search?q=${encodeURIComponent(query)}`;
  const resp = await fetch(url);
  if (resp.status === 404) {
    return null;
  }
  if (!resp.ok) {
    throw new Error(`CQL search failed: ${resp.status} ${await resp.text()}`);
  }
  return resp.json() as Promise<CqlSearchResponse>;
}

/**
 * Fetch the full context list from a CXDB instance.
 */
export async function fetchContextList(
  cxdbIndex: number,
  limit = 10000
): Promise<ContextListResponse> {
  const url = `${BASE_URL}/api/cxdb/${cxdbIndex}/v1/contexts?limit=${limit}`;
  const resp = await fetch(url);
  if (!resp.ok) {
    throw new Error(
      `Failed to fetch contexts from instance ${cxdbIndex}: ${resp.status}`
    );
  }
  return resp.json() as Promise<ContextListResponse>;
}

/**
 * Fetch turns for a context.
 */
export async function fetchTurns(
  cxdbIndex: number,
  contextId: string,
  options: {
    limit?: number;
    beforeTurnId?: string;
    view?: "typed" | "raw";
  } = {}
): Promise<TurnResponse> {
  const { limit = 100, beforeTurnId, view = "typed" } = options;
  let url = `${BASE_URL}/api/cxdb/${cxdbIndex}/v1/contexts/${encodeURIComponent(contextId)}/turns?limit=${limit}&view=${view}`;
  if (beforeTurnId && beforeTurnId !== "0") {
    url += `&before_turn_id=${encodeURIComponent(beforeTurnId)}`;
  }
  const resp = await fetch(url);
  if (!resp.ok) {
    throw new Error(
      `Failed to fetch turns for context ${contextId}: ${resp.status}`
    );
  }
  return resp.json() as Promise<TurnResponse>;
}
