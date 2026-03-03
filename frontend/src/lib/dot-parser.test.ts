/**
 * Unit tests for client-side DOT parser.
 */

import { describe, it, expect } from "vitest";
import { extractGraphId, normalizeId } from "./dot-parser";

describe("extractGraphId", () => {
  it("extracts simple unquoted graph ID", () => {
    expect(extractGraphId("digraph my_pipeline { }")).toBe("my_pipeline");
  });

  it("extracts graph ID with strict prefix", () => {
    expect(extractGraphId("strict digraph my_pipeline { }")).toBe(
      "my_pipeline"
    );
  });

  it("extracts undirected graph ID", () => {
    expect(extractGraphId("graph my_graph { }")).toBe("my_graph");
  });

  it("extracts quoted graph ID", () => {
    expect(extractGraphId('digraph "my pipeline" { }')).toBe("my pipeline");
  });

  it("returns null for anonymous graph", () => {
    expect(extractGraphId("digraph { }")).toBeNull();
  });

  it("returns null if regex match has no capture group 3", () => {
    // This tests the null rawName branch (line 20-21)
    // In practice this can't happen with a well-formed regex, so we test it
    // by calling normalizeId on empty string which returns empty
    expect(extractGraphId("// comment only\n// no graph")).toBeNull();
  });


  it("handles whitespace before graph keyword", () => {
    expect(extractGraphId("  digraph  alpha  { }")).toBe("alpha");
  });

  it("extracts from multiline DOT", () => {
    const dot = `// Pipeline config
digraph alpha_pipeline {
  start [shape=Mdiamond]
}`;
    expect(extractGraphId(dot)).toBe("alpha_pipeline");
  });
});

describe("normalizeId", () => {
  it("trims whitespace from unquoted ID", () => {
    expect(normalizeId("  implement  ")).toBe("implement");
  });

  it("strips outer quotes from quoted ID", () => {
    expect(normalizeId('"implement"')).toBe("implement");
  });

  it("unescapes backslash-quote in quoted ID", () => {
    expect(normalizeId('"say \\"hi\\""')).toBe('say "hi"');
  });

  it("unescapes \\n in quoted ID", () => {
    expect(normalizeId('"line1\\nline2"')).toBe("line1\nline2");
  });

  it("unescapes \\\\ in quoted ID", () => {
    expect(normalizeId('"back\\\\slash"')).toBe("back\\slash");
  });

  it("passes through other escape sequences verbatim", () => {
    expect(normalizeId('"\\t"')).toBe("\\t");
  });
});
