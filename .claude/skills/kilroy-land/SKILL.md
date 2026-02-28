---
name: kilroy:land
description: Land a completed Kilroy pipeline run — merge the worktree branch back into this repo, run smoke tests, and push.
user-invocable: true
---

Land a completed Kilroy pipeline run by merging the run branch into this repo, running smoke tests, and pushing.

## Step 1: Discover the run

Resolve this repo's absolute path, then scan all runs in `~/.local/state/kilroy/attractor/runs/` and read each `manifest.json` to find runs whose `repo_path` matches. From the matching runs, select the most recent one (highest run ID, which is a ULID and sorts chronologically).

If no matching runs are found, stop and tell the user. Suggest `/kilroy:run` to start a run.

If the user passed a specific run ID instead of using the default, use it directly.

## Step 2: Verify run completed successfully

Read `~/.local/state/kilroy/attractor/runs/<run_id>/final.json`. It must exist and contain `"status": "success"`. If the run did not succeed, stop and tell the user. Suggest `/kilroy:status` to inspect, or `/kilroy:run` to re-run.

## Step 3: Read run metadata

Read `~/.local/state/kilroy/attractor/runs/<run_id>/manifest.json` and extract:

- `base_sha` — the commit the run branched from
- `repo_path` — absolute path to this repo
- `run_branch` — the branch name (e.g. `attractor/run/<run_id>`)
- `run_id`

Report these to the user so they know what's about to happen.

## Step 4: Ensure the repo is clean

Check for uncommitted changes:

```bash
git status --porcelain
```

If there are uncommitted changes (output is non-empty), prompt the user:

> "The repo has uncommitted changes. These must be stashed before landing. Stash all changes now?"

If the user agrees, stash:

```bash
git stash push -m "kilroy-land: stash before landing run <run_id>"
```

If the user declines, stop.

## Step 5: Reset to the run's base SHA

Check what the current HEAD is:

```bash
git rev-parse HEAD
```

If HEAD does not match `base_sha`, reset to it:

```bash
git checkout <base_sha> --detach
```

Then re-attach to the original branch at that point. Determine the branch name first:

```bash
git branch --show-current
```

If on a named branch (e.g. `main`), reset it:

```bash
git checkout <branch_name> && git reset --hard <base_sha>
```

**Important:** Before resetting, confirm with the user if HEAD has moved forward from `base_sha`:

> "The repo HEAD (<current_sha>) has moved past the run's base commit (<base_sha>). Landing requires resetting to the base commit. Commits after <base_sha> will be lost. Proceed?"

If the user declines, stop.

## Step 6: Squash-merge the run branch

Squash-merge the run branch into the current branch. This collapses the entire pipeline run into a single commit, avoiding the clutter of empty per-node checkpoint commits on `main`:

```bash
git merge --squash <run_branch>
```

If the merge fails, something is wrong — the run branch should be a direct descendant of `base_sha`. Stop and report the error.

After the squash, build a summary of which pipeline nodes produced file changes. Inspect the run branch commits between `base_sha` and the tip of `<run_branch>`:

```bash
git log --oneline <base_sha>..<run_branch> --format="%h %s" --reverse
```

For each commit, check if it changed files:

```bash
git diff-tree --no-commit-id --name-only -r <commit_hash>
```

Collect the node names from commits that had actual file changes (non-empty diff-tree output). Then commit the squashed changes:

```bash
git commit -m "attractor(<run_id>): landed pipeline run

Squash-merged from <run_branch>

Nodes with file changes:
- <node_name_1>
- <node_name_2>
..."
```

If the squash results in no changes at all (every node was empty), skip the commit and warn the user that the pipeline run produced no file changes.

## Step 7: Run smoke tests

Run the smoke test suite:

```bash
script/smoke-test-suite-full
```

If the smoke tests fail, stop and report. Do NOT push. The user can inspect failures and decide what to do. The squashed changes are already committed on the local branch, so no work is lost.

## Step 8: Holdout scenario verification (optional)

Ask the user:

> "Would you like to run holdout scenario verification before pushing?"

If the user says yes, invoke the `verify:run-holdout-scenarios` skill, and report the result.

If there were failures, the report should contain a summary and also the path to the critique versioned file which was created by the spec:critique skill from the verification.

If the holdout scenario verification fails, stop and report. Do NOT push. The user can inspect failures and decide what to do. The squashed changes are already committed on the local branch, so no work is lost.

## Step 9: Push

Ask the user:

> "Smoke tests and holdout scenario verification passed. Push to origin?"

If holdout scenarios were skipped, adjust the prompt accordingly:

> "Smoke tests passed (holdout scenarios skipped). Push to origin?"

If the user agrees:

```bash
git push
```

## Step 10: Clean up

After a successful push, clean up the worktree and run branch:

```bash
git worktree remove ~/.local/state/kilroy/attractor/runs/<run_id>/worktree --force
git branch -D <run_branch>
```

Report that the run has been landed and cleaned up.

## Summary

At the end, report:
- Run ID that was landed
- The single squash commit hash
- How many pipeline nodes ran vs. how many produced file changes
- Smoke test result
- Holdout scenario verification result (or skipped)
- Whether changes were pushed
