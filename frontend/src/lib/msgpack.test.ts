/**
 * Unit tests for msgpack decoding.
 */

import { describe, it, expect, vi } from "vitest";
import { decodeFirstTurn } from "./msgpack";
import type { TurnItem } from "@/types/index";

const RUN_STARTED_TYPE_ID = "com.kilroy.attractor.RunStarted";

function makeTurn(typeId: string, opts: Partial<TurnItem> = {}): TurnItem {
  return {
    turn_id: "1",
    parent_turn_id: null,
    depth: 0,
    declared_type: { type_id: typeId, type_version: 1 },
    data: {},
    ...opts,
  };
}

// Mock the @msgpack/msgpack module
vi.mock("@msgpack/msgpack", () => ({
  decode: vi.fn().mockImplementation((bytes: Uint8Array) => {
    // Decode our test payload: { "1": runId, "8": graphName }
    const text = new TextDecoder().decode(bytes);
    return JSON.parse(text);
  }),
}));

describe("decodeFirstTurn", () => {
  it("returns non-RunStarted with null data for non-RunStarted turns", async () => {
    const turn = makeTurn("com.kilroy.attractor.StageStarted");
    const result = await decodeFirstTurn(turn);
    expect(result?.declared_type.type_id).toBe(
      "com.kilroy.attractor.StageStarted"
    );
    expect(result?.data).toBeNull();
  });

  it("returns null when no bytes_b64 for RunStarted", async () => {
    const turn = makeTurn(RUN_STARTED_TYPE_ID);
    const result = await decodeFirstTurn(turn);
    expect(result).toBeNull();
  });

  it("decodes RunStarted bytes_b64 to extract graph_name and run_id", async () => {
    // Create base64-encoded JSON payload with string keys (Go format)
    const payload = { "1": "my-run-id", "8": "my-graph-name" };
    const bytes = new TextEncoder().encode(JSON.stringify(payload));
    const b64 = btoa(String.fromCharCode(...bytes));

    const turn = makeTurn(RUN_STARTED_TYPE_ID, { bytes_b64: b64 });
    const result = await decodeFirstTurn(turn);

    expect(result?.data?.run_id).toBe("my-run-id");
    expect(result?.data?.graph_name).toBe("my-graph-name");
  });

  it("handles integer keys (fallback for non-Go encoders)", async () => {
    // Payload with integer keys (not Go format)
    const payload = { 1: "my-run-id", 8: "my-graph-name" };
    const bytes = new TextEncoder().encode(JSON.stringify(payload));
    const b64 = btoa(String.fromCharCode(...bytes));

    const turn = makeTurn(RUN_STARTED_TYPE_ID, { bytes_b64: b64 });
    const result = await decodeFirstTurn(turn);

    // Should still extract via integer key fallback
    expect(result?.data?.run_id).toBe("my-run-id");
    expect(result?.data?.graph_name).toBe("my-graph-name");
  });

  it("returns null on decode error", async () => {
    // Pass invalid base64 to trigger an error
    const turn = makeTurn(RUN_STARTED_TYPE_ID, { bytes_b64: "not-valid-b64!!!" });
    const result = await decodeFirstTurn(turn);
    // Should return null on error (graceful degradation)
    expect(result).toBeNull();
  });
});
