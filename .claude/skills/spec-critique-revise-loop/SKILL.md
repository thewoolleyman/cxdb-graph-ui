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

Print the parsed arguments, then run the deterministic bash loop.

**IMPORTANT:** This loop takes approximately 10-15 minutes per round. You MUST set the Bash tool timeout to 600000 (10 minutes per round, maximum 600000ms). Example for 3 rounds:

```bash
bash .claude/skills/spec-critique-revise-loop/scripts/loop.sh \
  --exit-criteria "{LOOP_EXIT_CRITERIA}" \
  --max-rounds "{MAX_ROUNDS}" \
  --critique-prompt "{CRITIQUE_PROMPT}" \
  --revise-prompt "{REVISE_PROMPT}"
```

Omit `--critique-prompt` and `--revise-prompt` flags entirely if their values are empty.

**Progress monitoring:** The script writes real-time progress to `specification/critiques/.loop-progress.log`. Tell the user they can monitor progress in another terminal with: `tail -f specification/critiques/.loop-progress.log`

The bash script handles everything: invoking sub-skills via `claude -p`, checking exit conditions, tracking state, and printing the final report. Do NOT add any loop logic here — just parse args and run the script.

After the script completes, print its exit status and you are done.
