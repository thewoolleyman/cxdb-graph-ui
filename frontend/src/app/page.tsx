/**
 * App — main dashboard layout.
 * Manages pipeline tabs, graph rendering, CXDB polling, and detail panel state.
 */
import React, { useState, useEffect, useCallback, useRef } from "react";
import type { EdgeInfo, NodeAttrs, Pipeline } from "@/types/index";
import {
  fetchDotList,
  fetchCxdbInstances,
  fetchDotSource,
  fetchNodes,
  fetchEdges,
} from "@/lib/api";
import { extractGraphId } from "@/lib/dot-parser";
import { useGraphviz } from "@/hooks/useGraphviz";
import { useCxdbPoller } from "@/hooks/useCxdbPoller";
import {
  TabBar,
  GraphViewer,
  DetailPanel,
  ConnectionIndicator,
} from "@/components/index";

type ContextKey = string;

export default function App(): React.ReactElement {
  // Pipeline list
  const [pipelines, setPipelines] = useState<Pipeline[]>([]);
  const [activePipelineFilename, setActivePipelineFilename] = useState<
    string | null
  >(null);

  // CXDB instances
  const [cxdbInstances, setCxdbInstances] = useState<string[]>([]);

  // DOT source per pipeline filename
  const [dotSources, setDotSources] = useState<Map<string, string>>(new Map());

  // Parsed node attributes per pipeline filename
  const [nodeAttrsByFilename, setNodeAttrsByFilename] = useState<
    Map<string, Record<string, NodeAttrs>>
  >(new Map());

  // Parsed edges per pipeline filename
  const [edgesByFilename, setEdgesByFilename] = useState<
    Map<string, EdgeInfo[]>
  >(new Map());

  // dotNodeIds per graphId (for polling)
  const [dotNodeIds, setDotNodeIds] = useState<Map<string, Set<string>>>(
    new Map()
  );

  // Currently rendered SVG
  const [svgContent, setSvgContent] = useState<string | null>(null);
  const [svgError, setSvgError] = useState<string | null>(null);

  // Detail panel
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);

  // Error state for initialization
  const [initError, setInitError] = useState<string | null>(null);

  // Graphviz WASM
  const { ready: gvReady, error: gvError, renderDot } = useGraphviz();

  // Track which graphId each filename maps to
  const pipelinesRef = useRef(pipelines);
  pipelinesRef.current = pipelines;

  // CXDB polling
  const pollerState = useCxdbPoller(pipelines, cxdbInstances, dotNodeIds);

  // Active pipeline's graphId
  const activePipeline = pipelines.find(
    (p) => p.filename === activePipelineFilename
  );
  const activeGraphId = activePipeline?.graphId ?? null;

  // Active status map
  const activeStatusMap = activeGraphId
    ? (pollerState.pipelineStatusMaps.get(activeGraphId) ?? null)
    : null;

  // Has stale node in active pipeline
  const hasStaleNode =
    activeStatusMap !== null &&
    Array.from(activeStatusMap.values()).some((ns) => ns.status === "stale");

  // Initialize: fetch DOT list and CXDB instances in parallel
  useEffect(() => {
    let cancelled = false;

    const init = async () => {
      try {
        const [dotFilenames, cxdbUrls] = await Promise.all([
          fetchDotList(),
          fetchCxdbInstances(),
        ]);

        if (cancelled) return;

        setCxdbInstances(cxdbUrls);

        const initialPipelines: Pipeline[] = dotFilenames.map((fn) => ({
          filename: fn,
          graphId: null,
        }));
        setPipelines(initialPipelines);

        if (dotFilenames.length > 0) {
          setActivePipelineFilename(dotFilenames[0]);
        }

        // Prefetch nodes and edges for all pipelines
        const nodesFetches = dotFilenames.map(async (fn) => {
          try {
            const nodes = await fetchNodes(fn);
            return { fn, nodes };
          } catch {
            console.warn(`Failed to prefetch nodes for ${fn}`);
            return { fn, nodes: {} as Record<string, NodeAttrs> };
          }
        });

        const edgesFetches = dotFilenames.map(async (fn) => {
          try {
            const edges = await fetchEdges(fn);
            return { fn, edges };
          } catch {
            console.warn(`Failed to prefetch edges for ${fn}`);
            return { fn, edges: [] as EdgeInfo[] };
          }
        });

        const [nodeResults, edgeResults] = await Promise.all([
          Promise.all(nodesFetches),
          Promise.all(edgesFetches),
        ]);

        if (cancelled) return;

        const newNodeAttrs = new Map<string, Record<string, NodeAttrs>>();
        for (const { fn, nodes } of nodeResults) {
          newNodeAttrs.set(fn, nodes);
        }
        setNodeAttrsByFilename(newNodeAttrs);

        const newEdges = new Map<string, EdgeInfo[]>();
        for (const { fn, edges } of edgeResults) {
          newEdges.set(fn, edges);
        }
        setEdgesByFilename(newEdges);

        // Fetch DOT source for first pipeline and extract graph IDs for all
        const dotSourceFetches = dotFilenames.map(async (fn) => {
          try {
            const source = await fetchDotSource(fn);
            return { fn, source };
          } catch {
            console.warn(`Failed to fetch DOT source for ${fn}`);
            return { fn, source: null };
          }
        });

        const dotSourceResults = await Promise.all(dotSourceFetches);
        if (cancelled) return;

        const newDotSources = new Map<string, string>();
        const newPipelines: Pipeline[] = [...initialPipelines];
        const newDotNodeIds = new Map<string, Set<string>>();

        for (const { fn, source } of dotSourceResults) {
          if (source !== null) {
            newDotSources.set(fn, source);
            const graphId = extractGraphId(source);
            const idx = newPipelines.findIndex((p) => p.filename === fn);
            if (idx >= 0) {
              newPipelines[idx] = { filename: fn, graphId };
            }
          }
        }

        // Build dotNodeIds from prefetched nodes
        for (const { fn, nodes } of nodeResults) {
          const pipeline = newPipelines.find((p) => p.filename === fn);
          const graphId = pipeline?.graphId;
          if (graphId) {
            newDotNodeIds.set(graphId, new Set(Object.keys(nodes)));
          }
        }

        setDotSources(newDotSources);
        setPipelines(newPipelines);
        setDotNodeIds(newDotNodeIds);
      } catch (err) {
        if (!cancelled) {
          setInitError(
            err instanceof Error ? err.message : "Initialization failed"
          );
        }
      }
    };

    void init();

    return () => {
      cancelled = true;
    };
  }, []);

  // Render SVG when Graphviz is ready and active pipeline changes
  useEffect(() => {
    if (!gvReady || !activePipelineFilename) return;
    const dotSource = dotSources.get(activePipelineFilename);
    if (!dotSource) return;

    const svg = renderDot(dotSource);
    if (svg) {
      setSvgContent(svg);
      setSvgError(null);
    } else {
      setSvgError("Failed to render DOT file");
    }
  }, [gvReady, activePipelineFilename, dotSources, renderDot]);

  // Handle tab switch
  const handleSelectPipeline = useCallback(
    async (filename: string) => {
      setActivePipelineFilename(filename);
      setSelectedNodeId(null);

      // Refresh nodes and edges on tab switch
      try {
        const [nodes, edges] = await Promise.all([
          fetchNodes(filename),
          fetchEdges(filename),
        ]);
        setNodeAttrsByFilename((prev) => {
          const next = new Map(prev);
          next.set(filename, nodes);
          return next;
        });
        setEdgesByFilename((prev) => {
          const next = new Map(prev);
          next.set(filename, edges);
          return next;
        });

        // Update dotNodeIds
        const pipeline = pipelinesRef.current.find(
          (p) => p.filename === filename
        );
        const graphId = pipeline?.graphId;
        if (graphId) {
          setDotNodeIds((prev) => {
            const next = new Map(prev);
            next.set(graphId, new Set(Object.keys(nodes)));
            return next;
          });
        }

        // Refresh DOT source
        const source = await fetchDotSource(filename);
        setDotSources((prev) => {
          const next = new Map(prev);
          next.set(filename, source);
          return next;
        });
      } catch {
        console.warn(`Failed to refresh data for ${filename}`);
      }
    },
    []
  );

  const handleNodeClick = useCallback((nodeId: string) => {
    setSelectedNodeId(nodeId);
  }, []);

  const handleCloseDetail = useCallback(() => {
    setSelectedNodeId(null);
  }, []);

  // Get active edges
  const activeEdges = activePipelineFilename
    ? (edgesByFilename.get(activePipelineFilename) ?? [])
    : [];

  // Get selected node attrs
  const activeNodeAttrs = activePipelineFilename
    ? (nodeAttrsByFilename.get(activePipelineFilename) ?? {})
    : {};
  const selectedNodeAttrs =
    selectedNodeId !== null ? (activeNodeAttrs[selectedNodeId] ?? null) : null;

  if (initError) {
    return (
      <div className="flex h-screen items-center justify-center bg-gray-50 text-red-600">
        <div className="text-center">
          <div className="text-lg font-semibold">Initialization Error</div>
          <div className="mt-2 text-sm">{initError}</div>
        </div>
      </div>
    );
  }

  // Build turn cache for active pipeline (keyed by graphId)
  const activeGraphTurnCache = new Map<string, Map<ContextKey, unknown[]>>();
  if (activeGraphId) {
    const pipelineCache = pollerState.pipelineTurnCache.get(activeGraphId);
    if (pipelineCache) {
      activeGraphTurnCache.set(activeGraphId, pipelineCache);
    }
  }

  return (
    <div className="flex h-screen flex-col bg-gray-50">
      {/* Top bar */}
      <TabBar
        pipelines={pipelines}
        activePipeline={activePipelineFilename}
        onSelectPipeline={(fn) => void handleSelectPipeline(fn)}
      >
        <ConnectionIndicator
          instanceStatuses={pollerState.instanceStatuses}
          cxdbUrls={cxdbInstances}
          hasStaleNode={hasStaleNode}
        />
      </TabBar>

      {/* Main content */}
      <div className="flex flex-1 overflow-hidden">
        <GraphViewer
          svgContent={svgContent}
          loading={!gvReady && gvError === null}
          error={gvError ?? svgError}
          statusMap={activeStatusMap}
          onNodeClick={handleNodeClick}
        />
        {selectedNodeId !== null && (
          <DetailPanel
            nodeId={selectedNodeId}
            nodeAttrs={selectedNodeAttrs}
            edges={activeEdges}
            turnCache={pollerState.pipelineTurnCache}
            graphId={activeGraphId}
            onClose={handleCloseDetail}
          />
        )}
      </div>
    </div>
  );
}
