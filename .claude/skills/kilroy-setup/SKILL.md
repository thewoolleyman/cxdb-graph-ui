---
name: kilroy:setup
description: Build the Kilroy binary, start CXDB, and verify all prerequisites for running Kilroy pipelines.
user-invocable: true
---

Set up the Kilroy software factory environment. Run all checks and report results. Stop on the first fatal error.

This repo is the current working directory. The Kilroy source repo is at `../kilroy`.

## Step 1: Check prerequisites

Verify the following are installed and report each result:

- `go` — required to build Kilroy
- `docker` — required for CXDB
- `ruby` — required for pipeline generation scripts
- `claude` — the Claude CLI, required by Kilroy to run agents
- `ANTHROPIC_API_KEY` environment variable is set (do NOT print the value)

**Note:** The `.env` file is loaded via `direnv`. Claude Code's non-interactive shell does not trigger direnv hooks automatically, so use `direnv exec "$PWD"` to wrap any command that needs to check or use environment variables from `.env`. Additionally, prefix with `env -u CLAUDECODE` to unset the nested-session guard variable, since Kilroy internally invokes `claude` and would otherwise fail with "cannot be launched inside another Claude Code session". For example:

```bash
env -u CLAUDECODE direnv exec "$PWD" sh -c '[ -n "$ANTHROPIC_API_KEY" ] && echo "set" || echo "NOT set"'
```

If any are missing, report which ones and stop. Do not proceed to build.

## Step 2: Build Kilroy

```bash
cd ../kilroy && go build -o kilroy ./cmd/kilroy
```

Verify the binary was produced: `../kilroy/kilroy --version`

If the build fails, report the error and stop.

## Step 3: Start CXDB

```bash
./script/start-cxdb.sh
```

This script is idempotent — it reuses a healthy container. CXDB runs on `:9009` (binary protocol) and `:9010` (HTTP UI).

After the script completes, verify CXDB is responding:

```bash
curl -sf http://localhost:9010/healthz > /dev/null
```

If the curl fails, report that CXDB did not start and suggest checking Docker.

## Step 4: Report

Summarize: prerequisites status, Kilroy version, CXDB status. Remind the user the next step is `/kilroy:generate-pipeline`.
