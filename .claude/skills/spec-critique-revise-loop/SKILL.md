---
name: spec:critique-revise-loop
description: "Automated critique-revise loop for the CXDB Graph UI spec. Args: LOOP_EXIT_CRITERIA=no_issues_found|no_major_issues_found (default: no_major_issues_found), MAX_ROUNDS=N (default: 3), CRITIQUE_PROMPT=\"...\", REVISE_PROMPT=\"...\""
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(ls:*), Bash(pwd:*), Bash(date:*), Skill
---

You are running an automated critique-revise loop on the CXDB Graph UI specification.

## ARGUMENTS

Parse the following raw arguments string for named parameters. **Ignore any text that is not a named parameter.**

Raw arguments: `$ARGUMENTS`

Extract these named parameters (all optional):

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `LOOP_EXIT_CRITERIA` | `no_issues_found` or `no_major_issues_found` | `no_major_issues_found` | When to stop the loop |
| `MAX_ROUNDS` | Any positive integer | `3` | Maximum critique-revise cycles before forced exit |
| `CRITIQUE_PROMPT` | Quoted string | _(empty)_ | Additional instructions passed to `/spec:critique` |
| `REVISE_PROMPT` | Quoted string | _(empty)_ | Additional instructions passed to `/spec:revise` |

**Parsing rules:**
- Parameters use `KEY=VALUE` syntax (e.g., `MAX_ROUNDS=5`)
- String values may be quoted with double quotes (e.g., `CRITIQUE_PROMPT="focus on API design"`)
- Unrecognized keys are ignored
- Missing parameters use their defaults

After parsing, print exactly:

```
=== PARSED ARGUMENTS ===
LOOP_EXIT_CRITERIA = {value}
MAX_ROUNDS         = {value}
CRITIQUE_PROMPT    = {value or "(none)"}
REVISE_PROMPT      = {value or "(none)"}
========================
```

Store these as `exit_criteria`, `max_rounds`, `critique_prompt`, and `revise_prompt`.

## MANDATORY LOOP PROTOCOL

You MUST follow this protocol exactly. There is only ONE way to exit: the EXIT CONDITION defined below. **Do not stop until the exit condition is met.**

### Initialization

Set `round = 0`. Set `previous_issue_titles = []`.

### Loop Start

**You are now entering the loop. Execute the following steps IN ORDER, then return to Loop Start. Do NOT exit the loop unless the EXIT CONDITION is met.**

#### A. Increment Round

Set `round = round + 1`.

Print exactly: **`=== CRITIQUE-REVISE LOOP: STARTING ROUND {round} OF {max_rounds} ===`**

If `round > max_rounds`, go to **FORCED EXIT (round limit)**.

#### B. Run Critique

Invoke the `spec-critique` skill using the Skill tool. If `critique_prompt` is non-empty, pass it as the skill's arguments. Otherwise invoke with no arguments.

#### C. Read the Critique File

After the critique skill completes, read the **newly created** critique file in `specification/critiques/`. Extract all issue titles (headings matching `## Issue #N: {title}`). Store them as `current_issue_titles`. Also note which issues (if any) are explicitly described as "minor" in their body text.

#### D. Check EXIT CONDITION

The exit condition depends on `exit_criteria`:

- **If `exit_criteria` = `no_issues_found`:** Exit when the critique file contains ZERO issues matching `## Issue #N:`.
- **If `exit_criteria` = `no_major_issues_found`:** Exit when the critique file contains ZERO issues matching `## Issue #N:`, OR when ALL issues present are explicitly labeled as minor (the critique body uses words like "minor", "nitpick", "cosmetic", "trivial", or "optional" to describe every issue, with no issues described as significant, major, critical, or important).

Check now:
- If the exit condition is satisfied → go to **NORMAL EXIT (converged)**.
- Otherwise → continue to step E.

#### E. Check Stuck Detection

Compare `current_issue_titles` to `previous_issue_titles`. If EVERY title in `current_issue_titles` also appeared in `previous_issue_titles` (the critique is raising only issues it already raised last round), go to **FORCED EXIT (stuck)**.

Set `previous_issue_titles = current_issue_titles`.

#### F. Run Revise

Invoke the `spec-revise` skill using the Skill tool. If `revise_prompt` is non-empty, pass it as the skill's arguments. Otherwise invoke with no arguments.

#### G. Round Summary

After the revise skill completes, read the **newly created** acknowledgement file(s) in `specification/critiques/` for this round. Produce a round summary by printing:

```
=== ROUND {round} SUMMARY ===
```

Then for each issue from the critique, print its disposition from the acknowledgement:
- **Applied:** `  ✓ Issue #{n}: {title} — applied to spec`
- **Partially addressed:** `  ~ Issue #{n}: {title} — partially addressed: {brief reason}`
- **Not addressed:** `  ✗ Issue #{n}: {title} — not addressed: {brief reason}`

If `revise_prompt` is non-empty, also note any additional changes the revise skill made in response to the `REVISE_PROMPT` that went beyond the critique issues:
- `  + Additional (REVISE_PROMPT): {brief description of extra change}`

End the summary with:
- `  Issues raised: {count}`
- `  Applied: {count} | Partial: {count} | Skipped: {count}`

#### H. Continue Loop

Print exactly: **`=== ROUND {round} COMPLETE. LOOPING BACK. ===`**

**You are NOT done. Return to Loop Start NOW and execute the next round. Do NOT stop.**

---

## NORMAL EXIT (converged)

Print exactly: **`=== LOOP CONVERGED after {round} rounds ===`**

Then proceed to **Final Report**.

## FORCED EXIT (round limit)

Print exactly: **`=== LOOP HIT ROUND LIMIT ({max_rounds} rounds) without converging ===`**

Then proceed to **Final Report**.

## FORCED EXIT (stuck)

Print exactly: **`=== LOOP STUCK: consecutive critiques raised the same issues ===`**

Then proceed to **Final Report**.

## Final Report

This is the ONLY place where you may stop. Tell the user:

- **Rounds completed:** The value of `round`
- **Exit reason:** converged / round limit / stuck
- **Exit criteria used:** The value of `exit_criteria`
- **Cumulative summary:** Combine the per-round summaries into an overall view — total issues raised across all rounds, total applied/partial/skipped, and the most significant spec improvements
- **Files created:** List all critique and acknowledgement files generated during the loop (read `specification/critiques/` and list them)
