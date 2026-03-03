/**
 * Client-side DOT file parser (for graph ID extraction only).
 * Full node/edge parsing is done server-side.
 */

/**
 * Extract the graph ID from a DOT source string.
 * Matches: optional "strict", "digraph" or "graph", then the ID.
 * Returns the normalized (unquoted, unescaped) graph ID, or null if not found.
 */
export function extractGraphId(dotSource: string): string | null {
  // Regex: optional strict, optional di, "graph", then quoted or unquoted name
  const re =
    /^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/im;
  const match = re.exec(dotSource);
  if (!match) {
    return null;
  }
  const rawName = match[3];
  if (!rawName) {
    return null;
  }
  return normalizeId(rawName);
}

/**
 * Normalize a DOT identifier:
 * - Quoted IDs: strip outer quotes, unescape \" -> ", \\ -> \, \n -> newline
 * - Unquoted IDs: trim whitespace
 */
export function normalizeId(raw: string): string {
  const s = raw.trim();
  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
    const inner = s.slice(1, -1);
    return unescapeDotString(inner);
  }
  return s;
}

function unescapeDotString(s: string): string {
  let result = "";
  let i = 0;
  while (i < s.length) {
    if (s[i] === "\\" && i + 1 < s.length) {
      const next = s[i + 1];
      if (next === '"') {
        result += '"';
        i += 2;
      } else if (next === "n") {
        result += "\n";
        i += 2;
      } else if (next === "\\") {
        result += "\\";
        i += 2;
      } else {
        result += "\\" + next;
        i += 2;
      }
    } else {
      result += s[i];
      i++;
    }
  }
  return result;
}
