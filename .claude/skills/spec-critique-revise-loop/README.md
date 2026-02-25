# spec:critique-revise-loop

Automated loop that alternates `/spec:critique` and `/spec:revise` until the critique finds no remaining issues (or only minor ones).

## Architecture

The loop uses a **per-round driver** architecture. Each round is a separate Bash tool call so that output is visible between rounds (the Claude Code Bash tool buffers output until a command completes). The SKILL.md agent drives a trivial loop that just checks integer exit codes — all real logic is in bash scripts.

```
SKILL.md (per-round driver — parses args, calls round.sh in a loop)
  └── scripts/round.sh (single-round executor)
        ├── claude -p "/spec:critique ..." (sub-skill)
        ├── scripts/check_exit.sh (exit condition check)
        ├── claude -p "/spec:revise ..." (sub-skill)
        └── scripts/round_summary.sh (parse acknowledgement)
  └── scripts/report.sh (final report from state dir)
```

- **Bash owns each round**: critique, exit checking, revision, summary
- **LLM owns the work**: critique analysis and spec revision (via `claude -p`)
- **Exit conditions are pure bash**: `grep`/`awk`/`comm` — no LLM involvement
- **Per-round execution**: output appears every ~10 minutes instead of buffering for the entire run

## Usage

```
/spec:critique-revise-loop
/spec:critique-revise-loop MAX_ROUNDS=5
/spec:critique-revise-loop LOOP_EXIT_CRITERIA=no_issues_found MAX_ROUNDS=10
/spec:critique-revise-loop CRITIQUE_PROMPT="focus on API completeness" REVISE_PROMPT="preserve backward compatibility"
```

## Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `LOOP_EXIT_CRITERIA` | `no_issues_found` \| `no_major_issues_found` | `no_major_issues_found` | When to stop |
| `MAX_ROUNDS` | Positive integer | `3` | Max critique-revise cycles |
| `CRITIQUE_PROMPT` | Quoted string | _(none)_ | Extra instructions for `/spec:critique` |
| `REVISE_PROMPT` | Quoted string | _(none)_ | Extra instructions for `/spec:revise` |

### LOOP_EXIT_CRITERIA

- **`no_major_issues_found`** (default) — Stops when zero issues remain, or all issues are minor/cosmetic.
- **`no_issues_found`** — Stops only when zero `## Issue #N:` headings exist. Stricter.

## How It Works

### Loop Flow

```
SKILL.md agent:
  1. Create state dir (mktemp -d)
  2. Print header
  3. For round = 1 to MAX_ROUNDS:
  │   └── bash round.sh --round N --state-dir $DIR ...
  │       │   [A] Print round header
  │       │   [B] claude -p "/spec:critique"
  │       │   [C] Find new critique file (ls diff)
  │       │   [D] check_exit.sh → converged? stuck?
  │       │   [E] claude -p "/spec:revise"
  │       │   [F] round_summary.sh → parse acknowledgement
  │       └── Exit code: 0=continue, 1=converged, 2=stuck
  │
  │   Check exit code → break if non-zero
  4. bash report.sh --state-dir $DIR ...
  5. Clean up state dir
```

### Exit Conditions (all checked in bash, not LLM)

| Exit | Trigger | Detection |
|------|---------|-----------|
| **Converged** | No issues, or all minor | `grep` + `awk` on critique file |
| **Round limit** | `round > MAX_ROUNDS` | Bash integer comparison |
| **Stuck** | Same issues as last round | `comm -23` on sorted title lists |

### Sub-skill Invocation

Each sub-skill runs as a non-interactive `claude -p` process:
- `claude -p "/spec:critique ..." --allowed-tools "Read Write Glob ..."`
- `claude -p "/spec:revise ..." --allowed-tools "Read Write Edit Glob ..."`

Output streams to stdout in real time. The `--allowed-tools` flag pre-authorizes tool access without `--dangerously-skip-permissions`.

## File Structure

```
spec-critique-revise-loop/
├── SKILL.md              # Per-round driver (parse args, call round.sh in loop)
├── README.md             # This file
├── specification.md      # Detailed design spec
└── scripts/
    ├── round.sh          # Single-round executor (critique → check → revise → summary)
    ├── report.sh         # Final report generator (reads state dir)
    ├── loop.sh           # Full loop driver (used by tests, runs all rounds in one process)
    ├── check_exit.sh     # Exit condition checker (grep/awk)
    ├── round_summary.sh  # Parse acknowledgement files
    └── tests/
        ├── test_round.sh          # Per-round integration test (21 assertions)
        ├── test_loop.sh           # Full loop integration test (18 assertions)
        ├── test_check_exit.sh     # Exit condition unit tests (17 assertions)
        ├── test_round_summary.sh  # Summary parser tests (11 assertions)
        └── test_io_streaming.sh   # I/O streaming proof (19 assertions)
```

## Round Summary Output

After each revise, the loop prints:

```
[STEP F] (round 1 of 3) Round summary
  ✓ Issue #1: Missing error codes — applied to specification
  ~ Issue #2: Incomplete auth flow — partially addressed
  ✗ Issue #3: Naming inconsistency — not addressed
  Issues: 3 | Applied: 1 | Partial: 1 | Skipped: 1
=== ROUND 1 of 3 COMPLETE ===
```

## Related Skills

- `/spec:critique` — Single critique pass
- `/spec:revise` — Single revision pass
