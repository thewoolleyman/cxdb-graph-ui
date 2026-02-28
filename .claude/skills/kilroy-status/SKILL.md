---
name: kilroy:status
description: Check status of Kilroy runs, resume an interrupted run, or stop a running pipeline.
user-invocable: true
---

Manage Kilroy Attractor pipeline runs. This skill handles status checks, resuming interrupted runs, and stopping running pipelines.

This repo is the current working directory. The Kilroy binary is at `../kilroy/kilroy`.

## Find runs

List existing Kilroy run directories:

```bash
ls -la ~/.local/state/kilroy/attractor/runs/ 2>/dev/null
```

If no runs directory exists, report that no runs have been executed yet and suggest `/kilroy:run`.

## Determine action

Based on the user's input or the state of runs, decide what to do:

### If the user passed a run ID or path

Use it directly for status/resume/stop.

### If multiple runs exist

List them with their timestamps and ask the user which run to inspect.

### If one run exists

Use it automatically.

## Check status

**Note:** All `kilroy` commands must be wrapped with `direnv exec "$PWD"` so that `ANTHROPIC_API_KEY` and other `.env` variables are available (Claude Code's non-interactive shell does not auto-load direnv). Additionally, prefix with `env -u CLAUDECODE` to unset the nested-session guard variable, since Kilroy internally invokes `claude` and would otherwise fail with "cannot be launched inside another Claude Code session".

```bash
env -u CLAUDECODE direnv exec "$PWD" ../kilroy/kilroy attractor status --logs-root ~/.local/state/kilroy/attractor/runs/<run_id>
```

Also extract the git worktree path and branch name from the run's `worktree` directory:

```bash
# Worktree path (the worktree directory inside the run)
WORKTREE_PATH=~/.local/state/kilroy/attractor/runs/<run_id>/worktree

# Branch name
git -C "$WORKTREE_PATH" branch --show-current 2>/dev/null
```

Include both values in the status output table alongside the other fields (run_id, state, etc.).

Also include a convenient one-liner to cd into the worktree (it's already on the correct branch since Kilroy creates it via `git worktree add`):

```
cd ~/.local/state/kilroy/attractor/runs/<run_id>/worktree
```

Report the status and then ask the user what they want to do:

- **Resume** — if the run was interrupted or is paused:
  ```bash
  env -u CLAUDECODE direnv exec "$PWD" ../kilroy/kilroy attractor resume --logs-root ~/.local/state/kilroy/attractor/runs/<run_id>
  ```

- **Stop** — if the run is still active:
  ```bash
  env -u CLAUDECODE direnv exec "$PWD" ../kilroy/kilroy attractor stop --logs-root ~/.local/state/kilroy/attractor/runs/<run_id> --grace-ms 30000
  ```

- **View in CXDB** — remind the user they can open `http://localhost:9110` for the full UI

- **Nothing** — just report and exit

## Report

Show the run status and remind the user of next steps based on the outcome:
- If the run completed successfully: use `/kilroy:land` to merge and push
- If the run failed: consider revising the spec file and re-running with `/kilroy:run`
- If the run is in progress: wait or stop it
