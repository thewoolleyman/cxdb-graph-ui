# spec:critique-revise-loop — Design Specification

## Problem

Running `claude -p` as a subprocess from within the Claude Code Bash tool produces no visible output. This is a known TTY dependency issue (GitHub issue #9026) — `claude -p` requires terminal presence even in pipe mode. When spawned as a background or foreground process inside the Bash tool, all stdout is lost, including echo statements before and after the `claude -p` call.

The original architecture used bash scripts (`round.sh`, `loop.sh`) that invoked `claude -p` for critique and revise work. While the scripts executed correctly (files were created, exit codes were correct), no output was visible to the user.

## Solution

Use **Task subagents** for all LLM work instead of `claude -p`. The SKILL.md agent drives each round directly:

1. **Critics** launch as parallel Task subagents — Claude critics use native skill invocation, external critics (opencode) use Bash within the subagent
2. **Revise** launches as a Task subagent running `/spec:revise`
3. **Deterministic work** (exit checks, file detection, summaries) runs via Bash — these scripts don't invoke `claude -p` so they work fine

This eliminates `claude -p` entirely from the main flow. The Task tool handles all inter-process communication natively.

## Architecture

```
SKILL.md (loop driver)
  ├── [parallel] Task subagent: /spec:critique (Claude, model from config)
  ├── [parallel] Task subagent: opencode (external, via Bash in subagent)
  ├── Bash: check_exit.sh (deterministic exit condition check)
  ├── Task subagent: /spec:revise
  ├── Bash: round_summary.sh (parse acknowledgement files)
  └── Bash: report.sh (final report from state dir)
```

### Why Task subagents instead of `claude -p`?

| Approach | Output visible? | Parallel? | TTY issues? |
|----------|----------------|-----------|-------------|
| `claude -p` in Bash tool | No (all lost) | Yes (background `&`) | Yes (known bug) |
| Task subagents | Yes (returned by Task tool) | Yes (multiple calls in one message) | No |

### Multi-critic config

Critic commands are in `config/critic-commands.conf`:

```conf
skill:opus /spec:critique {CRITIQUE_PROMPT}
bash opencode run --agent build --model ... "..."
```

Format:
- `skill:<model> <prompt>` — Task subagent with specified model
- `bash <command>` — Command run via Task subagent's Bash tool
- `{CRITIQUE_PROMPT}` — substituted with the full critique prompt

### Convergence rule

ALL critics must find only minor/no issues to stop. Decision per round:
- All `check_exit.sh` return 1 → converged
- Any returns 0 → continue to revise
- Any returns 2, none return 0 → stuck

### State management

State persists between rounds via a temporary directory (`mktemp -d`):

| File | Contents |
|------|----------|
| `prev_issues` | Sorted issue titles from previous round (union across all critics) |
| `cumulative` | `"issues applied partial skipped"` count string |
| `critique_files` | Newline-separated list of critique files created |
| `ack_files` | Newline-separated list of acknowledgement files created |

## Exit Conditions (pure bash)

| Condition | Detection | Script |
|-----------|-----------|--------|
| No issues | `grep` finds zero `## Issue #` headings | `check_exit.sh` → exit 1 |
| All minor | `awk` finds all issues contain minor keywords | `check_exit.sh` → exit 1 |
| Stuck | `comm -23` shows current ⊆ previous | `check_exit.sh` → exit 2 |
| Round limit | Loop counter in SKILL.md | N/A |

## File Inventory

| File | Purpose |
|------|---------|
| `SKILL.md` | Loop driver: parse args, run rounds via Task subagents |
| `config/critic-commands.conf` | Critic commands (type + command per line) |
| `scripts/check_exit.sh` | Exit condition checker (grep/awk/comm) |
| `scripts/round_summary.sh` | Parse acknowledgement files for summary |
| `scripts/report.sh` | Final report generator (reads state dir) |
| `scripts/round.sh` | Single-round executor (used by unit tests, uses `claude -p`) |
| `scripts/loop.sh` | Full loop driver (used by unit tests, uses `claude -p`) |
| `specification.md` | This file |
| `README.md` | User-facing documentation |
