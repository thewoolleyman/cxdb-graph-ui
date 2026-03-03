/**
 * Msgpack decoding for RunStarted turn discovery.
 * Uses @msgpack/msgpack (bundled via Vite).
 */

import type { TurnItem } from "@/types/index";

interface RunStartedData {
  graph_name: string | null;
  run_id: string | null;
}

interface DecodedFirstTurn {
  declared_type: { type_id: string; type_version: number };
  data: RunStartedData | null;
}

const RUN_STARTED_TYPE_ID = "com.kilroy.attractor.RunStarted";

/**
 * Decode a raw turn's bytes_b64 payload to extract RunStarted fields.
 * Uses @msgpack/msgpack loaded lazily to avoid blocking the main thread.
 * Returns null if the turn is not a RunStarted or if decoding fails.
 */
export async function decodeFirstTurn(
  rawTurn: TurnItem
): Promise<DecodedFirstTurn | null> {
  const typeId = rawTurn.declared_type.type_id;

  if (typeId !== RUN_STARTED_TYPE_ID) {
    return {
      declared_type: rawTurn.declared_type,
      data: null,
    };
  }

  const bytesB64 = rawTurn.bytes_b64;
  if (!bytesB64) {
    return null;
  }

  try {
    // Lazy import of msgpack to avoid blocking startup
    const { decode } = await import("@msgpack/msgpack");

    const bytes = base64ToBytes(bytesB64);
    // decode() returns the decoded value; for RunStarted it's an object with
    // integer keys (Go's msgpack encoder produces string-encoded integer keys)
    const payload = decode(bytes) as Record<string | number, unknown>;

    // RunStarted field tags (kilroy-attractor-v1 bundle, version 1):
    //   Tag 1: run_id (string)
    //   Tag 8: graph_name (string, optional)
    // Go's msgpack encoder produces string keys (e.g., "1" not 1).
    // Access both forms defensively.
    const graphName = (payload["8"] ?? payload[8]) as string | null | undefined;
    const runId = (payload["1"] ?? payload[1]) as string | null | undefined;

    return {
      declared_type: rawTurn.declared_type,
      data: {
        graph_name: graphName ?? null,
        run_id: runId ?? null,
      },
    };
  } catch (_e) {
    // If msgpack decode fails, return null so discovery retries on next poll
    return null;
  }
}

/**
 * Decode a base64 string to a Uint8Array.
 */
function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
