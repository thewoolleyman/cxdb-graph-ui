---
name: land-the-plane
description: Run smoke tests, then commit and push all changes.
user-invocable: true
---

Run smoke tests, then commit and push changes. Follow these steps in order, stopping if any step fails.

## Step 0: Check for changes

Run `git status` in this repo (current working directory).

If there are no uncommitted changes (no untracked files, no modified files, no staged changes), report that there are no changes to land and stop. Do not run any smoke tests or pushes.

## Step 1: Run smoke tests

Run the smoke test suite:

```bash
script/smoke-test-suite-fast
```

If the script does not exist, skip this step. Fix any failures before continuing.

## Step 2: Commit and push

If there are changes:
1. Stage relevant files (not build artifacts)
2. Write a descriptive commit message
3. Push to origin

## Step 3: Report

Summarize what was checked, what passed, and what was pushed.
