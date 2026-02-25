---
name: spec:critique-revise-loop
description: "Automated critique-revise loop for the CXDB Graph UI spec. Args: LOOP_EXIT_CRITERIA=no_issues_found|no_major_issues_found (default: no_major_issues_found), MAX_ROUNDS=N (default: 3), ROUND_TIMEOUT_MINUTES=N (default: 45), CRITIQUE_PROMPT=\"...\", REVISE_PROMPT=\"...\""
user-invocable: true
allowed-tools: Bash(bash:*), Bash(ls:*), Bash(cat:*), Bash(comm:*), Bash(sort:*), Bash(mktemp:*), Bash(rm:*), Bash(mkdir:*), Bash(wc:*), Bash(echo:*), Task, Read, Glob
---

Parse `$ARGUMENTS` for named `KEY=VALUE` parameters. Ignore non-parameter text.

| Parameter | Values | Default |
|-----------|--------|---------|
| `LOOP_EXIT_CRITERIA` | `no_issues_found` \| `no_major_issues_found` | `no_major_issues_found` |
| `MAX_ROUNDS` | Positive integer | `3` |
| `ROUND_TIMEOUT_MINUTES` | Positive integer | `45` |
| `CRITIQUE_PROMPT` | Quoted string | _(empty)_ |
| `REVISE_PROMPT` | Quoted string | _(empty)_ |

The loop timeout is derived automatically: `LOOP_TIMEOUT_MINUTES = ROUND_TIMEOUT_MINUTES * MAX_ROUNDS`.

Print the parsed arguments.

## Execution

You drive the loop directly. LLM work (critique, revise) is done via **Task subagents**. Deterministic work (file detection, exit checks, summaries) is done via **Bash**. This avoids the known `claude -p` TTY issue where the Bash tool cannot capture output from nested Claude invocations.

### Step 1: Initialize

```bash
STATE_DIR=$(mktemp -d -t critique-revise-loop.XXXXXX)
echo "State dir: $STATE_DIR"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/prev_issues"
echo "0 0 0 0" > "$STATE_DIR/cumulative"
date +%s > "$STATE_DIR/loop_start"
echo "Loop started at $(date)"
```

Compute `LOOP_TIMEOUT_MINUTES = ROUND_TIMEOUT_MINUTES * MAX_ROUNDS` and store both values for later use.

### Step 2: Print header

Print the loop configuration to the user.

### Step 3: Read critic config

Read `.claude/skills/spec-critique-revise-loop/config/critic-commands.conf`. Parse it into a list of critics, skipping comments and blank lines. Each line has format:
- `skill:<model> <prompt>` — Task subagent critic
- `bash <command>` — Bash command critic

Substitute `{CRITIQUE_PROMPT}` in each line. The expansion differs by critic type:

- **`skill:<model>` critics**: `{CRITIQUE_PROMPT}` → `/spec:critique {CRITIQUE_PROMPT_ARG}` (or just `/spec:critique` if no extra prompt was given). The subagent will invoke the spec:critique skill with the extra instructions as `$ARGUMENTS`.
- **`bash` critics**: `{CRITIQUE_PROMPT}` → `. Additional instructions: {CRITIQUE_PROMPT_ARG}` (or empty string `""` if no extra prompt was given). This appends the extra instructions inline into the command string.

Print the number of critics found.

### Step 4: Process unacknowledged critiques

Before starting the loop, check for critique files in `specification/critiques/` that have no corresponding `*-acknowledgement.md` file. These are critiques from a previous interrupted run that were never processed.

```bash
ls specification/critiques/ 2>/dev/null | sort
```

For each `v*-*.md` file (excluding `*acknowledgement*`) that has no matching `*-acknowledgement.md`:
- Collect it as an unacknowledged critique.

If any unacknowledged critiques are found:
1. Print the count and filenames.
2. Launch a single Task subagent to revise:

```
Task tool:
  subagent_type: "general-purpose"
  prompt: "/spec:revise {REVISE_PROMPT_ARG}"  (or just "/spec:revise" if no extra prompt)
  description: "Pre-loop revise: process unacknowledged critiques"
  max_turns: 40
```

Wait for the subagent to complete. Print a summary of the result.

If no unacknowledged critiques are found, print a message and proceed.

### Step 5: Run rounds

For each round from 1 to `{MAX_ROUNDS}`:

When printing each substep header, include round info and elapsed time. Before each header, get the elapsed time:

```bash
LOOP_START=$(cat "$STATE_DIR/loop_start")
ELAPSED=$(bash .claude/skills/spec-critique-revise-loop/scripts/elapsed_time.sh "$LOOP_START")
```

Then print the header in **bold** with this format: `*Step 5x (round N/MAX_ROUNDS, elapsed MM:SS): Description*`

Example: `*Step 5c (round 2/10, elapsed 15:30): Launch ALL critics in parallel*`

#### Step 5a: Check timeouts before starting round

Before each round, check both the loop timeout and record the round start time:

```bash
LOOP_START=$(cat "$STATE_DIR/loop_start")
bash .claude/skills/spec-critique-revise-loop/scripts/check_timeout.sh "$LOOP_START" {LOOP_TIMEOUT_MINUTES} "loop"
```

If exit code is 1 → set `EXIT_REASON=loop_timeout`. Skip to Step 6.

```bash
date +%s > "$STATE_DIR/round_start"
```

#### Step 5b: Snapshot critiques directory

```bash
ls specification/critiques/ 2>/dev/null | sort
```

Save this listing for comparison after critics run.

#### Step 5c: Launch ALL critics in parallel

For each critic from the config, launch a Task subagent. **Launch ALL critics concurrently in a single message with multiple Task tool calls.**

For `skill:<model>` critics:
```
Task tool:
  subagent_type: "general-purpose"
  model: "<model>"  (e.g., "opus")
  prompt: "<the substituted prompt>"
  description: "Critic <N>: critique spec"
  max_turns: 30
```

For `bash` critics:
```
Task tool:
  subagent_type: "general-purpose"
  prompt: "Run this command from the project root and report the output: <command>"
  description: "Critic <N>: external critic"
  max_turns: 15
```

Each Task subagent will return when done (or when `max_turns` is reached). Wait for all to complete.

Print a brief summary of each critic's result.

#### Step 5d: Find new critique files

```bash
ls specification/critiques/ 2>/dev/null | sort
```

Compare with the snapshot from Step 5b using `comm -13` to find new files. Filter out `*acknowledgement*` files — those are from revise, not critique.

If no new critique files found, this is an error. Stop.

Print the new critique files found.

#### Step 5e: Check exit conditions

For each new critique file, run:

```bash
bash .claude/skills/spec-critique-revise-loop/scripts/check_exit.sh \
  "specification/critiques/<file>" \
  "{LOOP_EXIT_CRITERIA}" \
  "$STATE_DIR/prev_issues"
```

**Decision logic (all critics must converge):**
- If ALL return exit code 1 → **converged**. Set `EXIT_REASON=converged`. Stop looping.
- If ANY return exit code 0 → **continue** to revise.
- If ANY return exit code 2 and NONE return 0 → **stuck**. Set `EXIT_REASON=stuck`. Stop looping.

Note: `check_exit.sh` updates `$STATE_DIR/prev_issues` as a side effect. When checking multiple files, use a temporary copy per critic and merge after (sort -u) to avoid cross-contamination.

#### Step 5f: Check round timeout, then run revise

Before launching revise, check the round timeout:

```bash
ROUND_START=$(cat "$STATE_DIR/round_start")
bash .claude/skills/spec-critique-revise-loop/scripts/check_timeout.sh "$ROUND_START" {ROUND_TIMEOUT_MINUTES} "round"
```

If exit code is 1 → set `EXIT_REASON=round_timeout`. Skip to Step 6.

Also check the loop timeout:

```bash
LOOP_START=$(cat "$STATE_DIR/loop_start")
bash .claude/skills/spec-critique-revise-loop/scripts/check_timeout.sh "$LOOP_START" {LOOP_TIMEOUT_MINUTES} "loop"
```

If exit code is 1 → set `EXIT_REASON=loop_timeout`. Skip to Step 6.

Extract the version identifier(s) from the new critique files (e.g., `v45` from `v45-opus.md`) and include them in the Step 5f header: `*Step 5f (round N/MAX_ROUNDS, elapsed MM:SS): Run revise for v45*`. When multiple critics produce different versions, join them with commas (e.g., `v45, v46`).

If continuing, launch a single Task subagent to revise:

```
Task tool:
  subagent_type: "general-purpose"
  prompt: "/spec:revise {REVISE_PROMPT_ARG}"  (or just "/spec:revise" if no extra prompt)
  description: "Revise spec from critiques"
  max_turns: 40
```

Wait for the revise subagent to complete. Print a summary of the result.

#### Step 5g: Round summary

Find new acknowledgement files (compare critiques dir before/after revise, filter for `*acknowledgement*`).

If acknowledgement files exist, run:

```bash
bash .claude/skills/spec-critique-revise-loop/scripts/round_summary.sh <ack_files...>
```

Track any new critique and acknowledgement filenames by appending to `$STATE_DIR/critique_files` and `$STATE_DIR/ack_files`.

Update cumulative counts in `$STATE_DIR/cumulative`.

Print: `=== ROUND {N} of {MAX_ROUNDS} COMPLETE ===`

---

If all rounds complete without converging or getting stuck, set `EXIT_REASON=round_limit`.

### Step 6: Print final report

```bash
bash .claude/skills/spec-critique-revise-loop/scripts/report.sh \
  --state-dir "$STATE_DIR" \
  --rounds-completed {ROUNDS_COMPLETED} \
  --exit-reason "{EXIT_REASON}" \
  --exit-criteria "{LOOP_EXIT_CRITERIA}"
```

### Step 7: Clean up

```bash
rm -rf "$STATE_DIR"
```

Print the exit reason and you are done. Do NOT add any extra logic, analysis, or loop control beyond what is described above.
