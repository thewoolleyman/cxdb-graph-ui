# Software Factory: CXDB Graph UI with Kilroy

Running the StrongDM Software Factory method on the CXDB Graph UI using [Kilroy](https://github.com/danshapiro/kilroy). This guide is specific to our project structure and curated specification.

## Architecture: Attractor and Kilroy

### What is Attractor?

Attractor is a **Natural Language Specification (NLSpec)** — a formal description of a software factory architecture, created by strongDM. It has no code of its own. It defines three layers:

| Spec | What it defines |
|------|----------------|
| `attractor-spec.md` | Pipeline orchestration using Graphviz DOT. Node types (LLM tasks, human review, conditionals, parallel), state management, validation, model stylesheets, condition expressions. |
| `coding-agent-loop-spec.md` | Autonomous coding agent: agentic loop (LLM call → tool exec → repeat), provider-aligned toolsets, execution environments, subagent spawning, loop detection. |
| `unified-llm-spec.md` | Provider-agnostic LLM SDK. Single interface across all providers, streaming-first, middleware pattern, structured outputs. |

**Architecture stack:** Unified LLM Client (bottom) → Coding Agent Loop (middle) → Pipeline Orchestration (top).

### What is Kilroy?

**Kilroy is the Go implementation of the Attractor spec.** There is no separate "Attractor" binary — Kilroy *is* the code. The CLI is `kilroy attractor <subcommand>` because "attractor" is the pipeline orchestration layer.

Key source directories in the Kilroy repo (`../kilroy`):

| Path | What it implements |
|------|-------------------|
| `internal/attractor/` | Pipeline engine: DOT parsing, execution, validation, checkpointing, model stylesheets |
| `internal/agent/` | Coding agent loop: turn-based LLM + tool execution, loop detection |
| `internal/llm/` | Unified LLM client: provider-agnostic interface |
| `internal/cxdb/` | CXDB integration: event streaming, run history |

### What Parts of Kilroy We Actually Use

With pipeline generation now deterministic, Kilroy's role has narrowed to **execution only**.

**Actively used:**

| Component | Command | What it does |
|-----------|---------|-------------|
| Pipeline execution | `kilroy attractor run` | Creates worktrees, executes each pipeline node with checkpoint commits, runs the agentic loop, handles postmortem/retry |
| Structural validation | `kilroy attractor validate` | Final check on DOT file structure after deterministic compilation |
| Run management | `kilroy attractor status/resume/stop` | Inspect, resume, or stop pipeline runs |
| CXDB integration | (automatic during `run`) | Streams all agent turns to the context database for observability |
| Coding agent loop | (internal to `run`) | Runs LLM agents for each box node (implement, review, postmortem, etc.) |

**No longer used (replaced by deterministic compilation):**

| Component | Command | Replaced by |
|-----------|---------|-------------|
| LLM-driven pipeline generation | `kilroy attractor ingest` | `compile_dot.rb` — deterministic Ruby compiler. Same input = byte-identical output every time. |

`ingest` is still available in "bootstrap mode" (creating a brand-new pipeline with no config YAML), but existing pipelines use deterministic compilation.

**The separation:**

| Stage | Before | Now |
|-------|--------|-----|
| Pipeline structure (DOT generation) | LLM-driven (`kilroy attractor ingest`) | Deterministic Ruby compiler (`compile_dot.rb` + `verify_dot.rb`) |
| Pipeline validation | After ingest, manual patching | Automated, no LLM (`verify_dot.rb` + `kilroy attractor validate`) |
| Pipeline execution | Kilroy engine | **Still Kilroy engine** (`kilroy attractor run`) |
| Agent loop (implement/review) | Kilroy agents | **Still Kilroy agents** (internal to `kilroy attractor run`) |

### CXDB (Context Debugger)

CXDB is the **observability layer** for Kilroy pipeline runs — a database that persists everything agents produce.

**What it stores:** Every agent turn during pipeline execution:
- Prompts and reasoning the agent received
- Tool calls (`write_file`, `bash`, `read_file`, etc.) and their results
- Git checkpoint status at each pipeline node
- Metadata: `node_id`, `branch_key`, `run_id`, `status`, model used

**What it provides:**
- **Real-time monitoring** — web console at `localhost:9120` with live SSE updates
- **Run history** — persistent record of every turn across every pipeline run
- **Problem detection** — the `/cxdb:status` skill queries the API to detect error loops, stale agents, failed branches
- **Debugging** — click into any context, walk through turns, see exactly which file an agent was editing and what went wrong

**Architecture:**
- Binary protocol on `127.0.0.1:9109` — where Kilroy streams turns during execution
- HTTP API on `127.0.0.1:9110` — for querying contexts and turns
- Nginx frontend on `127.0.0.1:9120` — the web console UI

See `docs/cxdb-console-guide.md` for detailed console usage.

## Quick Start with Skills

Most steps are automated via `/kilroy:*` Claude Code skills. Run `/kilroy:help` for the full list, or follow this sequence:

```
/kilroy:setup                # build Kilroy, start CXDB, check prereqs
/kilroy:generate-pipeline    # compile pipeline DOT from YAML config
/kilroy:run                  # execute the pipeline
/kilroy:land                 # merge, test, and push
```

## Skill Reference

All skills are defined in `.claude/skills/` and invoked as slash commands.

| Skill | Usage | What it does |
|-------|-------|-------------|
| `/kilroy:setup` | `/kilroy:setup` | One-time setup: builds Kilroy binary from `../kilroy`, starts CXDB on ports 9109/9110, verifies prereqs (go, docker, ruby, claude CLI, API key). |
| `/kilroy:generate-pipeline` | `/kilroy:generate-pipeline` | Compiles pipeline DOT from YAML config + prompt markdown files. Deterministic — no LLM involved. Runs `compile_dot.rb` → `verify_dot.rb` → `kilroy attractor validate`. Falls back to LLM bootstrap mode only when no config YAML exists. |
| `/kilroy:run` | `/kilroy:run` | Runs pre-flight checks, confirms with user, then executes `kilroy attractor run`. Creates an isolated worktree, runs all pipeline nodes with checkpoint commits. |
| `/kilroy:status` | `/kilroy:status` | Lists existing runs in `~/.local/state/kilroy/attractor/runs/`, checks status, offers to resume or stop interrupted pipelines. |
| `/kilroy:land` | `/kilroy:land` | Lands a completed run: discovers the most recent run, squash-merges the run branch (single commit), runs `script/smoke-test-suite-full`, prompts to push, cleans up worktree. |
| `/kilroy:help` | `/kilroy:help` | Displays the skills guide, available skills, and typical workflow. |
| `/cxdb:status` | `/cxdb:status` | Queries CXDB API to show pipeline context status table, detect stuck agents, error loops, stale contexts, and suggest fixes. |
| `/land-the-plane` | `/land-the-plane` | Runs smoke tests, then commits and pushes changes. Stops on first failure. |

**Typical workflow:** `/kilroy:setup` → `/kilroy:generate-pipeline` → `/kilroy:run` → `/kilroy:status` or `/cxdb:status` to monitor → `/kilroy:land` to merge, test, and push.

## Pipeline Configuration

Pipeline config is a version-controlled YAML + markdown file set:

```
factory/
├── pipeline-config.yaml        # nodes, edges, gates, stylesheet
├── prompts/
│   ├── implement.md            # prompt for implement node
│   ├── review.md               # prompt for review nodes
│   └── ...                     # one .md per node with a prompt
└── run.yaml                    # Kilroy run configuration
```

The compiled DOT file (`pipeline.dot`) at the repo root is a **generated artifact**. Never edit it directly — update the YAML/prompt sources and recompile with `/kilroy:generate-pipeline`.

### Run Config

The run config (`factory/run.yaml`) configures Kilroy execution: target repo path, CXDB endpoints, LLM provider, git settings, and setup commands that run in the worktree before the pipeline starts.

## How Kilroy Validates Work (With Holdout Scenarios)

Our setup adds a true holdout layer on top of Kilroy's built-in validation.

**How the holdout works:**

The pipeline receives the specification file (`specification/intent/cxdb-graph-ui-spec.md`). The `holdout-scenarios/` directory is excluded from the factory worktree via git sparse checkout (configured in `factory/run.yaml` setup commands). The implementing agent must produce correct behavior from the specification alone.

**Kilroy's three validation tiers:**

**Tier 1 — Deterministic tool gates (strongest):** Shell commands that check build, tests, and formatting. Pass or fail, no LLM interpretation. For this project: `go vet ./...`, `go test ./...`, `go build ./...`. Objective and ungameable.

**Tier 2 — Multi-agent LLM review (independent):** Three separate reviewer agents, each reading the same Definition of Done, each producing an APPROVED/REJECTED verdict. A consensus node requires 2 of 3 approvals.

**Tier 3 — Postmortem loop:** When reviews fail, a postmortem node analyzes the failure and the pipeline loops back to re-plan and re-implement, preserving working code.

## Specification

The specification is curated and source-controlled, not generated:

```
specification/
└── intent/
    └── cxdb-graph-ui-spec.md  # Complete architectural specification

holdout-scenarios/
└── cxdb-graph-ui-holdout-scenarios.md   # Behavioral scenarios (holdout)

specification-critiques/                 # Iterative critique/acknowledgement history
```

The spec file is the single source of truth. The holdout scenarios are withheld from the implementing agent and used for validation.

## Prerequisites

- Go (to build Kilroy and this project)
- Docker (for CXDB)
- Ruby 3+ (for pipeline generation scripts)
- `claude` CLI installed and authenticated
- `ANTHROPIC_API_KEY` environment variable (handled by direnv in this repo)

## Running Pipelines Manually

The skills automate everything below. These manual instructions are for reference or debugging.

### Build Kilroy and Start CXDB

```bash
cd ../kilroy && go build -o kilroy ./cmd/kilroy
./script/start-cxdb.sh
```

Verify: `curl -sf http://localhost:9110/healthz`

### Generate the Pipeline (Deterministic)

```bash
env -u CLAUDECODE direnv exec "$PWD" ruby \
  .claude/skills/kilroy-generate-pipeline/script/generate_pipeline.rb .
```

This runs `compile_dot.rb` → `verify_dot.rb` → `kilroy attractor validate`. Use `--force` to bypass the checksum cache.

### Run the Pipeline

```bash
env -u CLAUDECODE direnv exec . ../kilroy/kilroy attractor run \
  --graph pipeline.dot \
  --config factory/run.yaml
```

The `env -u CLAUDECODE` prefix unsets the nested-session guard variable (Kilroy invokes `claude` internally). The `direnv exec` ensures environment variables from `.env` are loaded.

Kilroy will:
1. Create an isolated git worktree under `~/.local/state/kilroy/attractor/runs/<run_id>/worktree`
2. Create a run branch `attractor/run/<run_id>` at current HEAD
3. Run `setup.commands`
4. Execute each pipeline node, committing after each one
5. Record everything to CXDB
6. Loop through postmortem → re-plan → re-implement if validation fails

### Resume / Check Status

```bash
# Status
../kilroy/kilroy attractor status --logs-root ~/.local/state/kilroy/attractor/runs/<run_id>

# Resume
../kilroy/kilroy attractor resume --logs-root ~/.local/state/kilroy/attractor/runs/<run_id>

# Stop
../kilroy/kilroy attractor stop --logs-root ~/.local/state/kilroy/attractor/runs/<run_id> --grace-ms 30000
```

The CXDB UI at `http://localhost:9120` shows turn-by-turn history. Use `/cxdb:status` for a quick summary.

## Known Limitations and Workarounds

### Spec drift

The spec file is the source of truth. If you edit it between runs, the next run will use the updated version. But a resumed run uses the worktree's copy. If you need spec changes to take effect mid-run, stop and start a new run.

### Landing completed runs

Each Kilroy run commits only to its own worktree branch. Use `/kilroy:land` to squash-merge a completed run back into the repo, run smoke tests, and push.

## When to Stop and Revise the Spec

If the pipeline loops through postmortem with the same failure pattern, the spec is usually the problem — not the agent. Stop the run, look at the worktree's spec file, identify what's underspecified, and revise `specification/intent/cxdb-graph-ui-spec.md`.

The spec is the source of truth. The code is disposable. Revise and re-run.

## References

- [The Software Factory: A Practitioner's Guide](docs/reference/software-factory-practitioners-guide-v01.md) — comprehensive reference for spec-driven development methodology, covering the Attractor pattern, holdout scenario validation, interactive/non-interactive shift work, specification evolution, and SOA boundary coordination. This repo is an implementation of the patterns described in the guide.
- [Kilroy repo](https://github.com/danshapiro/kilroy) (we run a [fork](https://github.com/thewoolleyman/kilroy) with upstream PRs pending)
- [StrongDM Software Factory](https://factory.strongdm.ai)
- [Attractor spec](https://factory.strongdm.ai/products/attractor)
- `docs/cxdb-console-guide.md` — detailed CXDB web console usage
