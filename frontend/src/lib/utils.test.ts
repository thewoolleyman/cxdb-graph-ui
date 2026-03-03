/**
 * Unit tests for utility functions.
 */

import { describe, it, expect } from "vitest";
import {
  cn,
  formatMilliseconds,
  compareTurnIds,
  numericTurnId,
  htmlEscape,
} from "./utils";

describe("cn", () => {
  it("joins truthy class names", () => {
    expect(cn("a", "b", "c")).toBe("a b c");
  });

  it("skips falsy values", () => {
    expect(cn("a", null, undefined, false, "b")).toBe("a b");
  });

  it("returns empty string for all falsy", () => {
    expect(cn(null, undefined, false)).toBe("");
  });
});

describe("formatMilliseconds", () => {
  it("formats whole seconds", () => {
    expect(formatMilliseconds(2000)).toBe("2s");
    expect(formatMilliseconds(60000)).toBe("60s");
  });

  it("formats fractional seconds", () => {
    expect(formatMilliseconds(1500)).toBe("1.5s");
    expect(formatMilliseconds(2500)).toBe("2.5s");
  });

  it("formats milliseconds", () => {
    expect(formatMilliseconds(250)).toBe("250ms");
    expect(formatMilliseconds(1)).toBe("1ms");
  });

  it("formats exactly 1000ms as 1s", () => {
    expect(formatMilliseconds(1000)).toBe("1s");
  });
});

describe("compareTurnIds", () => {
  it("returns negative when a < b", () => {
    expect(compareTurnIds("100", "200")).toBeLessThan(0);
  });

  it("returns positive when a > b", () => {
    expect(compareTurnIds("200", "100")).toBeGreaterThan(0);
  });

  it("returns 0 for equal IDs", () => {
    expect(compareTurnIds("100", "100")).toBe(0);
  });

  it("handles numeric ordering for different length strings", () => {
    // "999" < "1000" numerically
    expect(compareTurnIds("999", "1000")).toBeLessThan(0);
  });
});

describe("numericTurnId", () => {
  it("parses turn ID as integer", () => {
    expect(numericTurnId("6066")).toBe(6066);
    expect(numericTurnId("1")).toBe(1);
  });
});

describe("htmlEscape", () => {
  it("escapes ampersand", () => {
    expect(htmlEscape("a & b")).toBe("a &amp; b");
  });

  it("escapes less-than", () => {
    expect(htmlEscape("<script>")).toBe("&lt;script&gt;");
  });

  it("escapes double quotes", () => {
    expect(htmlEscape('"hello"')).toBe("&quot;hello&quot;");
  });

  it("leaves safe characters unchanged", () => {
    expect(htmlEscape("hello world")).toBe("hello world");
  });
});
