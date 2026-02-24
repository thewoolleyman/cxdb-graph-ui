---
name: spec:critique-revise-loop
description: "Automated critique-revise loop for the CXDB Graph UI spec. Args: LOOP_EXIT_CRITERIA=no_issues_found|no_major_issues_found (default: no_major_issues_found), MAX_ROUNDS=N (default: 3), CRITIQUE_PROMPT=\"...\", REVISE_PROMPT=\"...\""
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(ls:*), Bash(pwd:*), Bash(date:*), Skill
---

## ARGUMENTS

Parse `$ARGUMENTS` for named `KEY=VALUE` parameters. Ignore non-parameter text.

| Parameter | Values | Default |
|-----------|--------|---------|
| `LOOP_EXIT_CRITERIA` | `no_issues_found` \| `no_major_issues_found` | `no_major_issues_found` |
| `MAX_ROUNDS` | Positive integer | `3` |
| `CRITIQUE_PROMPT` | Quoted string | _(empty)_ |
| `REVISE_PROMPT` | Quoted string | _(empty)_ |

Print:

```
=== PARSED ARGUMENTS ===
LOOP_EXIT_CRITERIA = {value}
MAX_ROUNDS         = {value}
CRITIQUE_PROMPT    = {value or "(none)"}
REVISE_PROMPT      = {value or "(none)"}
========================
```

---

## LOOP

Set `round = 0`. Set `previous_issue_titles = []`.

Execute steps A through H in order. After H, return to A. The ONLY exits are in step A (round limit) and step D (converged or stuck).

### A. Increment round

Print: **`[STEP A] round = {round + 1} of {max_rounds}`**

Set `round = round + 1`. If `round > max_rounds` → go to EXIT: ROUND LIMIT.

### B. Run critique

Print: **`[STEP B] Running /spec:critique...`**

Invoke `spec-critique` via the Skill tool. Pass `critique_prompt` as arguments if non-empty.

**After the skill returns, you are still inside the loop. Your next step is C.**

### C. Read critique file

Print: **`[STEP C] Reading critique file...`**

Read the newly created file in `specification/critiques/`. Extract issue titles matching `## Issue #N: {title}`. Store as `current_issue_titles`. Note which issues are described as "minor" in their body.

### D. Check exit condition

Print: **`[STEP D] Checking exit condition...`**

**`no_issues_found`:** Exit if `current_issue_titles` is empty.

**`no_major_issues_found`:** Exit if `current_issue_titles` is empty OR every issue is explicitly minor/nitpick/cosmetic/trivial/optional.

If exit condition met → go to EXIT: CONVERGED.

If `current_issue_titles` is a subset of `previous_issue_titles` (every current title appeared last round) → go to EXIT: STUCK.

Set `previous_issue_titles = current_issue_titles`. Continue to E.

### E. Run revise

Print: **`[STEP E] Running /spec:revise...`**

Invoke `spec-revise` via the Skill tool. Pass `revise_prompt` as arguments if non-empty.

**After the skill returns, you are still inside the loop. Your next step is F.**

### F. Round summary

Print: **`[STEP F] Round {round} summary`**

Read the new acknowledgement file(s). For each critique issue, print:
- `  ✓ Issue #{n}: {title} — applied`
- `  ~ Issue #{n}: {title} — partial: {reason}`
- `  ✗ Issue #{n}: {title} — skipped: {reason}`

If `revise_prompt` produced extra changes: `  + REVISE_PROMPT: {description}`

Print totals: `  Issues: {n} | Applied: {n} | Partial: {n} | Skipped: {n}`

### G. Loop continuation check

Print: **`=== ROUND {round} COMPLETE ===`**

**You are NOT done. Proceed to step H now.**

### H. Return to A

Print: **`[STEP H] Returning to step A`**

Go to step A.

---

## EXIT: CONVERGED

Print: **`=== LOOP CONVERGED after {round} round(s) ===`**

Go to FINAL REPORT.

## EXIT: ROUND LIMIT

Print: **`=== LOOP HIT ROUND LIMIT ({max_rounds}) ===`**

Go to FINAL REPORT.

## EXIT: STUCK

Print: **`=== LOOP STUCK — same issues as previous round ===`**

Go to FINAL REPORT.

## FINAL REPORT

This is the ONLY place you may stop. Print:

- **Rounds:** `{round}`
- **Exit reason:** converged / round limit / stuck
- **Exit criteria:** `{exit_criteria}`
- **Cumulative totals:** issues raised, applied, partial, skipped across all rounds
- **Key improvements:** most significant spec changes
- **Files created:** list all critique and acknowledgement files from `specification/critiques/`
