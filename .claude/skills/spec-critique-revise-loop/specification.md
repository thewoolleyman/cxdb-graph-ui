# spec:critique-revise-loop — Deterministic Bash Loop Specification

## Problem

The LLM-driven loop in `spec:critique-revise-loop` repeatedly fails to maintain loop control. After sub-skill invocations (`/spec:critique`, `/spec:revise`), the agent stops despite prompt engineering (step labels, post-skill reminders, sub-skill exit warnings). Natural language loop control is fundamentally unreliable.

## Solution

Move the loop into a deterministic bash script (`scripts/loop.sh`) that:
1. Invokes `claude -p` for each sub-skill (critique, revise)
2. Checks exit conditions with `grep`/`awk` (no LLM involvement)
3. Only delegates to the LLM for the critique and revise work itself

## Architecture

```
SKILL.md (thin wrapper — parses args, runs loop.sh)
  └── scripts/loop.sh (deterministic loop driver)
        ├── claude -p "/spec:critique ..." (sub-skill via CLI)
        ├── scripts/check_exit.sh (exit condition checker)
        ├── claude -p "/spec:revise ..." (sub-skill via CLI)
        └── scripts/round_summary.sh (parse acknowledgement)
```

The bash script owns the loop. The LLM owns critique and revise. The bash script checks exit conditions deterministically.

## Key Design Decisions

### Sub-skill invocation via `claude -p`

Each sub-skill runs as a **non-interactive one-shot** `claude -p` process:
- Output streams to stdout in real time
- Exit code indicates success/failure
- The skill's own `allowed-tools` header restricts tool access
- `--allowed-tools` on the CLI pre-authorizes tools to avoid interactive prompts

### Exit condition checking is pure bash

- **Issue counting**: `grep -c '## Issue #' critique_file` counts issues
- **Minor classification**: `awk` scans each issue section for minor/nitpick/cosmetic/trivial/optional keywords
- **Stuck detection**: `comm -23` compares sorted issue title lists between rounds

### State is bash variables

- `round` — current round number
- `prev_issues_file` — tempfile with sorted issue titles from last round
- `cumulative_*` — running totals across rounds
- `exit_reason` — converged / stuck / round_limit

### No `--dangerously-skip-permissions`

The `--allowed-tools` flag pre-authorizes exactly the tools each sub-skill declares in its YAML frontmatter. This maintains the permission model.

## File Inventory

| File | Purpose |
|------|---------|
| `SKILL.md` | Thin wrapper: parse `$ARGUMENTS`, invoke `scripts/loop.sh` |
| `scripts/loop.sh` | Main loop driver |
| `scripts/check_exit.sh` | Exit condition checker (grep/awk) |
| `scripts/round_summary.sh` | Parse acknowledgement files for summary |
| `specification.md` | This file |
| `README.md` | User-facing documentation |

## Exit Conditions

| Condition | How Detected | Exit Code |
|-----------|-------------|-----------|
| Converged (no issues) | `grep` finds zero `## Issue #` headings | `check_exit.sh` returns 1 |
| Converged (all minor) | `awk` finds all issues contain minor keywords | `check_exit.sh` returns 1 |
| Stuck | `comm -23` shows current issues are subset of previous | `check_exit.sh` returns 2 |
| Round limit | `round > max_rounds` in bash | Loop breaks in `loop.sh` |
