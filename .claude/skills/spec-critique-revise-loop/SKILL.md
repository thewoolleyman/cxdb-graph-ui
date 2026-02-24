---
name: spec:critique-revise-loop
description: Automatically critique and revise the CXDB Graph UI spec in a loop until no issues remain
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(ls:*), Bash(pwd:*), Bash(date:*), Skill
---

You are running an automated critique-revise loop on the CXDB Graph UI specification.

## Overview

This skill repeatedly invokes `/spec:critique` and `/spec:revise` in alternating rounds until the critique finds no major issues, at which point the loop terminates.

## Additional Direction from User

$ARGUMENTS

## Procedure

### Step 1: Run Critique

Invoke the `spec-critique` skill using the Skill tool. Pass through any `$ARGUMENTS` the user provided.

### Step 2: Check Critique Results

After the critique completes, read the newly created critique file in `specification/critiques/`. Determine whether it contains **any numbered issues** (sections matching `## Issue #N:`).

- If **no issues were found** (the critique explicitly states there are no major issues), proceed to **Step 5** (terminate the loop).
- If **issues were found**, proceed to **Step 3**.

### Step 3: Run Revise

Invoke the `spec-revise` skill using the Skill tool to address the critique.

### Step 4: Loop

Return to **Step 1** to run another critique round.

### Safety Limits

- **Maximum rounds:** 10 critique-revise cycles. If the loop reaches 10 rounds without converging, stop and report to the user.
- **Stuck detection:** If two consecutive critiques raise the same issues (by title), stop and report that the loop is not converging.

### Step 5: Report

When the loop terminates, tell the user:

- **Rounds completed:** How many critique-revise cycles ran
- **Final state:** Whether the spec converged (no issues) or hit a limit
- **Summary of changes:** A brief list of the most significant spec improvements across all rounds
- **Critique files created:** List all critique and acknowledgement files generated during the loop
