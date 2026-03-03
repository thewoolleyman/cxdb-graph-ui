/**
 * useGraphviz — loads @hpcc-js/wasm-graphviz and exposes a render function.
 */
import { useState, useEffect, useCallback } from "react";

interface GraphvizInstance {
  layout: (dot: string, outputFormat: string, layoutEngine: string) => string;
}

interface UseGraphvizResult {
  ready: boolean;
  error: string | null;
  renderDot: (dot: string) => string | null;
}

export function useGraphviz(): UseGraphvizResult {
  const [gv, setGv] = useState<GraphvizInstance | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    import("@hpcc-js/wasm-graphviz")
      .then((mod) => mod.Graphviz.load())
      .then((instance) => {
        if (!cancelled) setGv(instance as unknown as GraphvizInstance);
      })
      .catch((err: unknown) => {
        if (!cancelled)
          setError(
            err instanceof Error ? err.message : "Failed to load Graphviz"
          );
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const renderDot = useCallback(
    (dot: string): string | null => {
      if (!gv) return null;
      try {
        return gv.layout(dot, "svg", "dot");
      } catch (err) {
        return null;
      }
    },
    [gv]
  );

  return { ready: gv !== null, error, renderDot };
}
