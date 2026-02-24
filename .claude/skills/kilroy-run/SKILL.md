---
name: kilroy:run
description: Run a Kilroy pipeline for this repo.
user-invocable: true
---

Run the Kilroy Attractor pipeline for this repo.

This repo is the current working directory. The Kilroy binary is at `../kilroy/kilroy`.

The pipeline file is `pipeline.dot` and the run config is `run.yaml`, both at the repo root.

## Pre-flight checks

Verify all of these before running. Stop and report if any fail:

1. `../kilroy/kilroy` binary exists (suggest `/kilroy:setup`)
2. CXDB is running: `curl -sf http://localhost:9010/healthz > /dev/null` (suggest `/kilroy:setup`)
3. The pipeline DOT file `pipeline.dot` exists (suggest `/kilroy:generate-pipeline`)
4. The run config `run.yaml` exists
5. `ANTHROPIC_API_KEY` is set (use `direnv exec "$PWD" sh -c '[ -n "$ANTHROPIC_API_KEY" ]'` to check — Claude Code's shell does not auto-load `.env` via direnv)
6. The pipeline DOT file only uses `anthropic` as `llm_provider`. Grep for `llm_provider:` in the DOT file — if any provider other than `anthropic` is found (e.g. `openrouter`), stop and tell the user to re-run `/kilroy:generate-pipeline`. Only `anthropic` is configured in the run config.

## Confirm with user

Before running, show:
- Pipeline file: `pipeline.dot`
- Config file: `run.yaml`
- Ask: "Ready to start the Kilroy pipeline run? This will create an isolated worktree and execute the full pipeline. Proceed?"

## Run the pipeline

```bash
env -u CLAUDECODE direnv exec "$PWD" ../kilroy/kilroy attractor run \
  --graph pipeline.dot \
  --config run.yaml
```

The `direnv exec "$PWD"` prefix ensures `ANTHROPIC_API_KEY` (and any other `.env` variables) are loaded into the Kilroy process. The `env -u CLAUDECODE` prefix unsets the nested-session guard variable, since Kilroy internally invokes `claude` and would otherwise fail with "cannot be launched inside another Claude Code session".

This is a long-running process. It will:
1. Create an isolated git worktree
2. Run setup commands
3. Execute each pipeline node with commits
4. Loop through postmortem if validation fails

The command runs interactively with output to stdout/stderr.

## When setup fails

If the pipeline fails during setup (e.g. "WaitDelay expired", timeout, or setup command error):

1. **NEVER increase the timeout or blindly retry.** Timeout failures are almost always caused by a hanging or failing command, not an insufficient timeout. Increasing the timeout is never the correct first response and wastes the user's time and money.
2. Read the `setup.commands` list from `run.yaml`.
3. Run each setup command individually (not via Kilroy) to observe its output and identify which specific command hangs or fails and why.
4. Report the specific failing command and its output to the user, then propose a fix.
5. If you cannot identify the root cause after running the commands individually, **stop and ask the user for help**. Do not guess, retry, or experiment further without their input.

## After completion

Report the outcome and the run ID. Remind the user:
- To check run history: `/kilroy:status`
- To land completed work: `/kilroy:land`
- If the pipeline looped on the same failure, consider revising the spec file and re-running
