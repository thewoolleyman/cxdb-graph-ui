# spec:critique-revise-loop

Automated loop that alternates `/spec:critique` and `/spec:revise` until the critique finds no remaining issues (or only minor ones).

## Architecture

The loop is driven by a **deterministic bash script** — not LLM loop control. This ensures the loop always completes the correct number of rounds regardless of LLM behavior after sub-skill invocations.

```
SKILL.md (thin wrapper — parses args, invokes loop.sh)
  └── scripts/loop.sh (deterministic loop driver)
        ├── claude -p "/spec:critique ..." (sub-skill)
        ├── scripts/check_exit.sh (exit condition check)
        ├── claude -p "/spec:revise ..." (sub-skill)
        └── scripts/round_summary.sh (parse acknowledgement)
```

- **Bash owns the loop**: round counting, exit conditions, state tracking
- **LLM owns the work**: critique analysis and spec revision (via `claude -p`)
- **No LLM involvement in loop control**: exit conditions are checked with `grep`/`awk`

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
┌──────────────────────────┐
│  Parse ARGUMENTS         │
│  Run scripts/loop.sh     │
└────────────┬─────────────┘
             │
┌────────────▼─────────────┐
│  [A] round++             │◄──────────────────────────┐
│      round > MAX?        │                           │
│      yes → FINAL REPORT  │                           │
└────────────┬─────────────┘                           │
         no  │                                         │
┌────────────▼─────────────┐                           │
│  [B] claude -p           │                           │
│      "/spec:critique"    │                           │
└────────────┬─────────────┘                           │
             │                                         │
┌────────────▼─────────────┐                           │
│  [C] Find critique file  │                           │
│      (ls diff)           │                           │
└────────────┬─────────────┘                           │
             │                                         │
┌────────────▼─────────────┐                           │
│  [D] check_exit.sh       │                           │
│      converged → REPORT  │                           │
│      stuck → REPORT      │                           │
└────────────┬─────────────┘                           │
         no  │                                         │
┌────────────▼─────────────┐                           │
│  [E] claude -p           │                           │
│      "/spec:revise"      │                           │
└────────────┬─────────────┘                           │
             │                                         │
┌────────────▼─────────────┐                           │
│  [F] round_summary.sh    │                           │
│      Parse ack files     │───────────────────────────┘
└──────────────────────────┘

FINAL REPORT (printed by loop.sh)
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
├── SKILL.md              # Thin wrapper (parse args → run loop.sh)
├── README.md             # This file
├── specification.md      # Detailed design spec
└── scripts/
    ├── loop.sh           # Main loop driver
    ├── check_exit.sh     # Exit condition checker (grep/awk)
    └── round_summary.sh  # Parse acknowledgement files
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
