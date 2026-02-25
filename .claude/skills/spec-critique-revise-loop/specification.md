# spec:critique-revise-loop — Deterministic Bash Loop Specification

## Problem

The LLM-driven loop in `spec:critique-revise-loop` repeatedly fails to maintain loop control. After sub-skill invocations (`/spec:critique`, `/spec:revise`), the agent stops despite prompt engineering (step labels, post-skill reminders, sub-skill exit warnings). Natural language loop control is fundamentally unreliable.

## Solution

Split execution into per-round bash scripts called individually by the SKILL.md agent:
1. Each round runs as a separate Bash tool call (~10 minutes)
2. Output is visible between rounds (not buffered for the entire 40-minute run)
3. The agent's loop is trivial: just check integer exit codes (0=continue, 1=converged, 2=stuck)
4. All real logic (critique, exit checking, revision, summary) is in bash scripts

## Architecture

```
SKILL.md (per-round driver — parses args, calls round.sh in a loop)
  └── scripts/round.sh (single-round executor)
        ├── claude -p "/spec:critique ..." (sub-skill via CLI)
        ├── scripts/check_exit.sh (exit condition checker)
        ├── claude -p "/spec:revise ..." (sub-skill via CLI)
        └── scripts/round_summary.sh (parse acknowledgement)
  └── scripts/report.sh (final report from state dir)
```

The bash scripts own each round. The LLM owns critique and revise work. Exit conditions are checked deterministically. The SKILL.md agent's only job is to call round.sh repeatedly and check its exit code.

### Why per-round execution?

The Claude Code Bash tool captures all stdout/stderr and only returns it when the command completes. Running `loop.sh` (all rounds in one process) means 40+ minutes of "Running..." with zero visible output. By splitting into per-round calls, output appears every ~10 minutes.

State persists between rounds via a temporary state directory (`mktemp -d`).

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
| `SKILL.md` | Per-round driver: parse `$ARGUMENTS`, call `round.sh` in a loop |
| `scripts/round.sh` | Single-round executor (critique → check → revise → summary) |
| `scripts/report.sh` | Final report generator (reads state dir) |
| `scripts/loop.sh` | Full loop driver (used by tests, runs all rounds in one process) |
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
