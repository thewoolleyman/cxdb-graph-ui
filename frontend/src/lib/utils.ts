/**
 * Utility functions.
 */

/**
 * Conditionally join class names together.
 */
export function cn(...classes: (string | undefined | null | false)[]): string {
  return classes.filter(Boolean).join(" ");
}

/**
 * Format milliseconds to a human-readable duration.
 * - >= 1000ms: "{n}s" (one decimal if not whole, no decimal if whole)
 * - < 1000ms: "{n}ms"
 */
export function formatMilliseconds(ms: number): string {
  if (ms >= 1000) {
    const seconds = ms / 1000;
    const formatted = Number.isInteger(seconds)
      ? `${seconds}s`
      : `${seconds.toFixed(1)}s`;
    return formatted;
  }
  return `${ms}ms`;
}

/**
 * Compare two turn IDs numerically.
 * CXDB turn IDs are numeric strings (e.g. "6066").
 * Returns negative if a < b, 0 if equal, positive if a > b.
 */
export function compareTurnIds(a: string, b: string): number {
  return parseInt(a, 10) - parseInt(b, 10);
}

/**
 * Parse a turn ID as a number for numeric comparison.
 */
export function numericTurnId(id: string): number {
  return parseInt(id, 10);
}

/**
 * HTML-escape a string for safe DOM insertion.
 */
export function htmlEscape(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
