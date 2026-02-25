# spec:critique-revise-loop

Automated loop that alternates `/spec:critique` and `/spec:revise` until the critique finds no remaining issues (or only minor ones).

## Architecture

The loop uses a **Task subagent** architecture. The SKILL.md agent drives each round directly:
- **Critics** run as parallel Task subagents (Claude via native skill invocation, external tools via Bash)
- **Revise** runs as a Task subagent
- **Deterministic checks** (exit conditions, summaries, file detection) run as Bash commands

This avoids a known limitation where `claude -p` invoked inside the Bash tool produces no visible output (TTY dependency issue).

```
SKILL.md (loop driver — parses args, runs rounds)
  ├── Task subagent: /spec:critique (Claude critic)
  ├── Task subagent: opencode (external critic, via Bash)
  ├── scripts/check_exit.sh (exit condition check)
  ├── Task subagent: /spec:revise
  ├── scripts/round_summary.sh (parse acknowledgement)
  └── scripts/report.sh (final report from state dir)
```

- **Task tool owns LLM work**: critics and revise run as parallel subagents with streaming output
- **Bash owns deterministic work**: exit checking, file detection, summaries
- **Exit conditions are pure bash**: `grep`/`awk`/`comm` — no LLM involvement
- **Multi-critic**: multiple critics run in parallel, all must converge to stop

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
  3. Read config/critic-commands.conf
  4. For round = 1 to MAX_ROUNDS:
  │   [A] Snapshot critiques directory
  │   [B] Launch ALL critics as parallel Task subagents
  │   [C] Find new critique files (ls diff)
  │   [D] check_exit.sh per file → converged? stuck?
  │   [E] Launch revise as Task subagent
  │   [F] round_summary.sh → parse acknowledgement
  │   Check decision → break if converged or stuck
  5. bash report.sh --state-dir $DIR ...
  6. Clean up state dir
```

### Exit Conditions (all checked in bash, not LLM)

| Exit | Trigger | Detection |
|------|---------|-----------|
| **Converged** | ALL critics find no issues or only minor ones | `grep` + `awk` on each critique file |
| **Round limit** | `round > MAX_ROUNDS` | Loop counter in SKILL.md |
| **Stuck** | No new issues from any critic | `comm -23` on sorted title lists |

### Multi-Critic Support

Critic commands are configured in `config/critic-commands.conf`. Two types:

- `skill:<model> <prompt>` — Runs as a Claude Code Task subagent with the specified model
- `bash <command>` — Runs the command via a Task subagent's Bash tool

All critics launch **in parallel** via multiple Task tool calls in a single message.

**Convergence rule**: ALL critics must agree there are no major issues. If any single critic finds major issues, the loop continues to revise.

**Failure tolerance**: If some critics fail but at least one produces a critique file, the round continues. If ALL critics fail, the round aborts.

### Sub-skill Invocation

The default critics are:
- `skill:opus /spec:critique` — Claude Opus via native Task subagent
- `bash opencode run --agent build --model gitlab/duo-chat-gpt-5-2-codex --variant high "..."` — Codex via external tool

## File Structure

```
spec-critique-revise-loop/
├── SKILL.md              # Loop driver (parses args, runs rounds via Task subagents)
├── README.md             # This file
├── specification.md      # Detailed design spec
├── config/
│   └── critic-commands.conf  # Critic commands (one per line, run in parallel)
└── scripts/
    ├── round.sh          # Single-round executor (used by unit tests)
    ├── report.sh         # Final report generator (reads state dir)
    ├── loop.sh           # Full loop driver (used by unit tests)
    ├── check_exit.sh     # Exit condition checker (grep/awk)
    ├── round_summary.sh  # Parse acknowledgement files
    └── tests/
        ├── test_multi_critic.sh   # Multi-critic parallel execution test
        ├── test_round.sh          # Per-round integration test
        ├── test_loop.sh           # Full loop integration test
        ├── test_check_exit.sh     # Exit condition unit tests
        ├── test_round_summary.sh  # Summary parser tests
        └── test_io_streaming.sh   # I/O streaming proof
```

## Round Summary Output

After each revise, the loop prints:

```
  ✓ Issue #1: Missing error codes — applied to specification
  ~ Issue #2: Incomplete auth flow — partially addressed
  ✗ Issue #3: Naming inconsistency — not addressed
  Issues: 3 | Applied: 1 | Partial: 1 | Skipped: 1
=== ROUND 1 of 3 COMPLETE ===
```

## Related Skills

- `/spec:critique` — Single critique pass
- `/spec:revise` — Single revision pass
