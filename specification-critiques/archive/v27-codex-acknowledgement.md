# CXDB Graph UI Spec — Critique v27 (codex) Acknowledgement

All three issues from v27-codex have been applied to the specification. The changes define graph ID extraction behavior for `strict` and anonymous graphs (with server-side rejection of anonymous graphs), require whitespace-preserving rendering for all verbatim content, and specify a deterministic truncation/expansion policy for the detail panel.

## Issue #1: Graph ID extraction does not define behavior for `strict` or anonymous graphs

**Status: Applied to specification**

Updated the graph ID regex in both Section 3.2 (server) and Section 4.4 (browser) from `/(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/` to `/^\s*(strict\s+)?(di)?graph\s+("(?:[^"\\]|\\.)*"|\w+)/m`, adding support for the optional `strict` prefix. For anonymous graphs (where the regex does not match because no identifier follows the keyword), the server now rejects the DOT file at startup with a non-zero exit code and an error message stating that named graphs are required for pipeline discovery. The browser retains its filename fallback for defensive robustness but notes that in normal operation the regex always matches because the server has already validated. This ensures server and browser always agree on the graph ID and eliminates the silent discovery failure for `strict digraph` files.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated graph ID regex and added `strict` handling in Section 3.2 (server-side graph ID uniqueness check); updated graph ID regex, added `strict` handling, and clarified anonymous graph rejection in Section 4.4 (browser-side graph ID extraction).

## Issue #2: Whitespace preservation for prompts/outputs is undefined

**Status: Applied to specification**

Added explicit `white-space: pre-wrap` requirements to: (1) Section 7.1's DOT attribute table for Prompt, Tool Command, and Question fields, (2) Section 7.2's Output column description for CXDB turns, and (3) Invariant 15, which now reads "Content is displayed verbatim with whitespace preserved" and references `white-space: pre-wrap`. This ensures newlines, indentation, and runs of whitespace are preserved in all verbatim content, preventing HTML's default whitespace collapsing from making multiline prompts and tool output unreadable.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Updated Section 7.1 DOT attribute table (Prompt, Tool Command, Question rows); updated Section 7.2 Output column description; updated Invariant 15.

## Issue #3: Detail panel truncation/expansion behavior is unspecified

**Status: Applied to specification**

Added a "Truncation and expansion" paragraph after the per-type rendering table in Section 7.2. The policy is: truncate to the first 500 characters or 8 lines (whichever comes first), applied after HTML-escaping and before `white-space: pre-wrap` rendering. Truncated rows display a "Show more" toggle that expands inline to the full content; expanded rows show "Show less" to re-collapse. Each turn row has independent expand/collapse state. Fixed-label outputs (lifecycle turns, unknown types) are never truncated. This provides a deterministic, testable policy that preserves whitespace in the visible excerpt.

Changes:
- `specification/cxdb-graph-ui-spec.md`: Added "Truncation and expansion" paragraph in Section 7.2 after the per-type rendering mapping table.

## Not Addressed (Out of Scope)

- None. All three issues were applied.
