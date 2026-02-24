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

**CRITICAL: Always run Kilroy in the background with a monitoring loop.** Kilroy runs are long-running (30min–2hrs). Running them as a blocking Bash call will leave you unable to report status or detect problems. You MUST follow both steps below.

### Step 1: Launch in background

```bash
env -u CLAUDECODE direnv exec "$PWD" ../kilroy/kilroy attractor run \
  --graph pipeline.dot \
  --config run.yaml
```

Run this command with `run_in_background: true` on the Bash tool. The `direnv exec "$PWD"` prefix ensures `ANTHROPIC_API_KEY` (and any other `.env` variables) are loaded into the Kilroy process. The `env -u CLAUDECODE` prefix unsets the nested-session guard variable, since Kilroy internally invokes `claude` and would otherwise fail with "cannot be launched inside another Claude Code session".

### Step 2: Start monitoring loop

After launching, wait 10 seconds for the run to initialize, then find the run directory and begin monitoring. **You MUST do this — do not wait for the user to ask.**

**Find the active run directory:**
```bash
LOGS_ROOT=$(ls -dt ~/.local/state/kilroy/attractor/runs/*/  | head -1)
```

**Monitoring loop:** Poll every 90 seconds until the Kilroy process exits. On each poll iteration, report ALL of the following to the user:

1. **Current node** — read `live.json` from the run directory:
   ```bash
   cat "${LOGS_ROOT}/live.json" 2>/dev/null
   ```

2. **Recent progress events** — tail the last 5 entries from `progress.ndjson`:
   ```bash
   tail -5 "${LOGS_ROOT}/progress.ndjson" | python3 -c "import sys,json; [print(f'{e[\"event\"]:30s} node={e.get(\"node_id\",\"—\"):30s} status={e.get(\"status\",\"—\")}  attempt={e.get(\"attempt\",\"—\")}/{e.get(\"max\",\"—\")}') for e in (json.loads(l) for l in sys.stdin)]"
   ```

3. **Completed nodes** — count commits in the run worktree:
   ```bash
   cd "${LOGS_ROOT}/worktree" 2>/dev/null && git log --oneline | head -20
   ```

4. **Process alive check:**
   ```bash
   kill -0 $(cat "${LOGS_ROOT}/run.pid" 2>/dev/null) 2>/dev/null && echo "Kilroy running" || echo "Kilroy EXITED"
   ```

**Report format:** After each poll, output a concise status update to the user, e.g.:
```
Pipeline status (2m elapsed): node=implement_orchestrator, attempt 1/4, 3 nodes completed
```

### Anomaly detection during monitoring

While monitoring, watch for these patterns and **alert the user immediately** — do not wait for the run to finish:

- **Repeated identical failures:** If `progress.ndjson` shows 2+ consecutive `stage_attempt_end` events for the same `node_id` with the same `failure_reason`, flag it:
  ```
  ⚠ Node "verify_hangar_complete" has failed 2 times with identical reason: "tool_command timed out after 2m0s" — this looks deterministic and will not self-heal by retrying.
  ```

- **Postmortem loop on same node:** If you see the same node being re-entered after postmortem with the same failure pattern, flag it as a likely configuration issue.

- **No progress for 10+ minutes:** If `live.json` timestamp hasn't advanced in 10 minutes and the process is still alive, alert the user that the run may be stuck.

- **Process exited unexpectedly:** If the PID is gone but no completion event appeared in `progress.ndjson`, report the crash and check the background task output file for errors.

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
