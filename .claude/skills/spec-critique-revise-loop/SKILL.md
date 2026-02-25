---
name: spec:critique-revise-loop
description: "Automated critique-revise loop for the CXDB Graph UI spec. Args: LOOP_EXIT_CRITERIA=no_issues_found|no_major_issues_found (default: no_major_issues_found), MAX_ROUNDS=N (default: 3), CRITIQUE_PROMPT=\"...\", REVISE_PROMPT=\"...\""
user-invocable: true
allowed-tools: Bash(bash:*)
---

Parse `$ARGUMENTS` for named `KEY=VALUE` parameters. Ignore non-parameter text.

| Parameter | Values | Default |
|-----------|--------|---------|
| `LOOP_EXIT_CRITERIA` | `no_issues_found` \| `no_major_issues_found` | `no_major_issues_found` |
| `MAX_ROUNDS` | Positive integer | `3` |
| `CRITIQUE_PROMPT` | Quoted string | _(empty)_ |
| `REVISE_PROMPT` | Quoted string | _(empty)_ |

Print the parsed arguments.

**IMPORTANT:** Each round takes approximately 10-15 minutes. You MUST set the Bash tool timeout to 600000 (the maximum) for EVERY Bash call below.

## Execution

Execute the following steps. The loop is driven by YOU calling one round at a time. This is intentional — it ensures output is visible between rounds instead of buffered for the entire run.

### Step 1: Initialize

```bash
STATE_DIR=$(mktemp -d -t critique-revise-loop.XXXXXX)
echo "State dir: $STATE_DIR"
```

### Step 2: Print header

```bash
echo ""
echo "============================================"
echo "  CRITIQUE-REVISE LOOP (per-round driver)"
echo "============================================"
echo "Exit criteria:   {LOOP_EXIT_CRITERIA}"
echo "Max rounds:      {MAX_ROUNDS}"
echo "Critique prompt: {CRITIQUE_PROMPT or '(none)'}"
echo "Revise prompt:   {REVISE_PROMPT or '(none)'}"
echo "============================================"
```

### Step 3: Run rounds

For each round from 1 to `{MAX_ROUNDS}`, run:

```bash
bash .claude/skills/spec-critique-revise-loop/scripts/round.sh \
  --round {ROUND} \
  --max-rounds {MAX_ROUNDS} \
  --exit-criteria "{LOOP_EXIT_CRITERIA}" \
  --state-dir "$STATE_DIR" \
  --critique-prompt "{CRITIQUE_PROMPT}" \
  --revise-prompt "{REVISE_PROMPT}"
```

Omit `--critique-prompt` and `--revise-prompt` flags entirely if their values are empty.

Check the exit code after each round:
- **Exit 0** → continue to the next round
- **Exit 1** → converged. Set `EXIT_REASON=converged`. Stop looping.
- **Exit 2** → stuck. Set `EXIT_REASON=stuck`. Stop looping.
- **Exit 10** → error. Print the error output. Stop looping.

If all rounds complete without converging or getting stuck, set `EXIT_REASON=round_limit`.

### Step 4: Print final report

```bash
bash .claude/skills/spec-critique-revise-loop/scripts/report.sh \
  --state-dir "$STATE_DIR" \
  --rounds-completed {ROUNDS_COMPLETED} \
  --exit-reason "{EXIT_REASON}" \
  --exit-criteria "{LOOP_EXIT_CRITERIA}"
```

### Step 5: Clean up

```bash
rm -rf "$STATE_DIR"
```

Print the exit reason and you are done. Do NOT add any extra logic, analysis, or loop control beyond checking exit codes as described above.
