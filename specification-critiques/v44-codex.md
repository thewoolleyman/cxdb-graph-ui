# CXDB Graph UI Spec — Critique v44 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v43 acknowledgements applied numeric turn_id comparisons across all pseudocode, added StageFinished notes/suggested_next_ids and StageRetrying delay rendering, and documented unmatched-route 404 behavior. Two proposed holdouts were recorded (StageFailed retry intermediate state and DOT comment stripping with unterminated constructs), but remain unincorporated into the main holdout list.

---

## Issue #1: Holdout scenarios do not cover anonymous graph rejection at server startup

### The problem
Section 3.2 requires the server to reject DOT files that omit a graph identifier (for example, `digraph { ... }`), because discovery relies on `RunStarted.data.graph_name` matching a normalized graph ID. This is a hard startup failure with a specific error path, but none of the Server holdout scenarios exercise it. The closest coverage is duplicate graph IDs and duplicate basenames, which do not test the anonymous-graph rejection or the error message path.

Without a holdout, an implementation could silently accept anonymous graphs and fall back to filenames in the browser, which would break discovery (RunStarted graph_name would never match). This is a correctness requirement rather than a cosmetic preference.

### Suggestion
Add a server holdout scenario:

```
### Scenario: Anonymous graph rejected
Given a DOT file contains "digraph {" with no graph identifier
When the user runs: go run ui/main.go --dot /path/to/anonymous.dot
Then the server exits with a non-zero code
  And prints an error stating that named graphs are required for discovery
```

This ensures the startup validation behavior is implemented and prevents silent discovery failures.

## Issue #2: Holdout scenarios do not test DOT attribute concatenation or multiline quoted strings

### The problem
Section 3.2 requires the DOT parser to support the `+` concatenation operator for quoted attribute values and to handle multi-line quoted strings. The existing holdouts only cover long prompt text with escaped newlines and quotes (Scenario: DOT file with long prompt text) and basic edge parsing. Those tests do not exercise:

- `prompt="part1" + "part2"` concatenation semantics.
- A literal newline inside a quoted string (not an escaped `\n`).

An implementer could build a line-by-line parser that passes current scenarios but fails on these two required parsing rules, leading to truncated prompts or parse errors for valid DOT files.

### Suggestion
Add a DOT parsing holdout scenario that uses both constructs:

```
### Scenario: DOT attribute concatenation and multiline quoted values
Given a DOT node attribute uses concatenation: prompt="first " + "second"
  And a DOT node attribute contains a literal newline inside quotes
When the browser fetches /dots/{name}/nodes
Then the parsed prompt value is "first second" (concatenated with no separator)
  And the multiline prompt preserves the newline in the returned attribute value
```

This makes the parser requirements testable and aligns coverage with the spec’s detailed parsing rules.
