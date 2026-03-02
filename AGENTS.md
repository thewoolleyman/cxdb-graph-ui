# Codebase Search

When searching codebases, always attempt to use the `knowledge-graph` MCP server first. It indexes code structure and relationships, making searches faster and more accurate than raw file/grep searches. Fall back to Glob/Grep/Read tools only if the knowledge graph doesn't have the information you need.

---

# Dependencies

This project uses [Kilroy](https://github.com/danshapiro/kilroy), an AI software factory CLI built on
[Attractor](https://github.com/strongdm/attractor) by strongDM ([product page](https://factory.strongdm.ai/products/attractor)).

We are currently based on a [fork of Kilroy](https://github.com/thewoolleyman/kilroy) which includes
patches for bugs and features encountered during development. These patches have been submitted as
upstream PRs to the [main Kilroy repo](https://github.com/danshapiro/kilroy).

Clone Kilroy as a peer directory (`../kilroy` relative to this repo) so that LLM agents can read its
source and so you can diagnose or fix new bugs directly.

---

# Purpose of this repo

A local web dashboard that renders [Attractor](https://github.com/strongdm/attractor) pipeline DOT files
as interactive SVG graphs with real-time execution status from [CXDB](https://github.com/strongdm/cxdb).

The DOT graph is the pipeline definition; CXDB holds the execution trace. The UI overlays one on the
other — nodes are colored by their execution state, and clicking a node shows its CXDB activity.

**Tech stack:** Rust HTTP server (axum/tokio) with railway-oriented programming + single HTML file with vanilla JavaScript and
Graphviz WASM (CDN-loaded). No frontend build toolchain, no npm, no framework.

---

# Internal directories (this repo)

## Skills (`.claude/skills/`)

Slash-command skills that automate specification and Kilroy pipeline workflows.

| Skill | What it does |
|---|---|
| `spec:critique` | Critiques the spec against its goals, invariants, and holdout scenarios. Writes versioned critique files to `specification-critiques/`. |
| `spec:revise` | Revises the spec based on unacknowledged critique feedback. Edits the spec in place and writes acknowledgement files. |
| `kilroy:setup` | One-time setup: builds Kilroy binary from `../kilroy`, starts CXDB on ports 9109/9110, verifies prereqs (go, docker, ruby, claude CLI, API key). |
| `kilroy:generate-pipeline` | Compiles pipeline DOT from YAML config + prompt markdown files. Deterministic — no LLM involved. Runs `compile_dot.rb` → `verify_dot.rb` → `kilroy attractor validate`. |
| `kilroy:run` | Runs pre-flight checks, confirms with user, then executes `kilroy attractor run`. Creates an isolated worktree, runs all pipeline nodes with checkpoint commits. |
| `kilroy:status` | Lists existing runs, checks status, offers to resume or stop interrupted pipelines. State in `~/.local/state/kilroy/attractor/runs/`. |
| `kilroy:help` | Displays guide to the Kilroy software factory, available skills, and typical workflow. |
| `kilroy:land` | Lands a completed run — squash-merges the run branch, runs `script/smoke-test-suite-full`, and pushes. |
| `cxdb:status` | Queries CXDB API (`http://127.0.0.1:9120`) to show pipeline context status, detect stuck agents, error loops, stale contexts. |
| `land-the-plane` | Runs smoke tests, then commits and pushes changes. Stops on first failure. |

**Typical workflow:** `kilroy:setup` → `kilroy:generate-pipeline` → `kilroy:run` → `kilroy:status` / `cxdb:status` to monitor → `kilroy:land` to merge, test, and push.

**IMPORTANT — Pipeline DOT file is a generated artifact:**
The `pipeline.dot` file at the repo root is compiled output. **NEVER edit it directly.** Always update the YAML/prompt sources under `factory/` and then regenerate via `/kilroy:generate-pipeline`. Direct edits will be overwritten on the next generation and will diverge from the source-of-truth config.

## Specification

| Path | Purpose |
|---|---|
| `specification/intent/` | **The intent specification.** Split across per-section files (overview, server, DOT rendering, CXDB integration, status overlay, detail panel, UI layout). See `specification/intent/README.md` for the index. |
| `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` | Behavioral test scenarios (Given/When/Then) covering DOT rendering, CXDB status overlay, pipeline discovery, detail panel, connection handling, and server operations. |
| `specification-critiques/` | Iterative critique/acknowledgement pairs used during spec refinement. |

## Scripts (`script/`)

Shell scripts for environment setup, infrastructure management, and testing.

| Script | What it does |
|---|---|
| `setup.sh` | One-time workspace bootstrap: checks Rust toolchain, clones the CXDB repo, and builds the CXDB Docker image. Pass `--rebuild-cxdb` to force a Docker image rebuild. |
| `start-cxdb.sh` | Starts the CXDB Docker container by delegating to `../kilroy/script/start-cxdb.sh` with line-buffered output for real-time logging. |
| `stop-cxdb.sh` | Stops the CXDB Docker container (`kilroy-cxdb`). Respects `KILROY_CXDB_CONTAINER_NAME` env var. |
| `start-cxdb-ui.sh` | Opens the CXDB web UI by delegating to `../kilroy/script/start-cxdb-ui.sh`. Forces the UI URL to port 9120 (nginx frontend) instead of 9110 (raw API). |
| `smoke-test-suite-full` | Runs the full smoke test suite: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo build`, and `cargo test`. Exits non-zero on any failure. |

## Path conventions

All paths in run configs and pipeline configs MUST be portable:
- **Never** hardcode absolute paths (e.g. `/Users/cwoolley/workspace/...`)
- `repo.path` in run YAMLs: use `.` (self) or `../sibling-repo` (resolved from CWD at invocation)
- `modeldb` paths: use `../kilroy/...` (resolved from CWD at invocation)

## Documentation (`docs/`)

Reference documentation for the project. **Keep these in sync when skills, workflows, or architecture change.**

| File | What it covers |
|---|---|
| `docs/software-factory.md` | **Primary guide.** Architecture overview (Attractor, Kilroy, CXDB), what parts of Kilroy we use, skill reference, pipeline configuration, validation tiers, manual instructions. Update this when skills change or Kilroy usage evolves. |
| `docs/reference/software-factory-practitioners-guide-v01.md` | **Methodology reference.** The Software Factory practitioner's guide: spec-driven development patterns, holdout scenario validation, the Attractor pattern, interactive/non-interactive shift work, specification evolution, and SOA boundary coordination. This repo implements the patterns described here. Consult for methodology questions — why we use holdout scenarios, how specs should be structured, what the factory loop looks like. |
| `docs/cxdb-console-guide.md` | CXDB web console usage: dashboard layout, turn-by-turn inspection, keyboard shortcuts, interpreting agent activity. |

---

# External peer repos

## Kilroy (`../kilroy`)

CLI (written in Go) for running AI software-factory pipelines. Converts English requirements into checkpoint-aware pipelines executed by AI agents in isolated git worktrees.

**Core flow:** YAML config + prompt files → deterministic `compile_dot.rb` → Graphviz DOT graph → `validate` → `run` (node-by-node in worktree with checkpoint commits) → `resume` on failure. The LLM-based `ingest` command is only used in bootstrap mode (no config YAML exists).

**Key directories:**

| Path | What's there |
|---|---|
| `cmd/kilroy/` | CLI entry points: `ingest`, `validate`, `run`, `resume`, `status`, `stop`, `serve` |
| `internal/attractor/` | Pipeline engine: DOT parser, execution engine, validation, runtime state, checkpointing, model stylesheets |
| `internal/agent/` | Coding agent loop: turn-based LLM + tool execution, provider-specific toolsets, event-driven |
| `internal/llm/` | Unified LLM client: provider-agnostic interface across OpenAI, Anthropic, Google, etc. |
| `internal/cxdb/` | Execution database integration: run history, typed events, artifact storage |

**Build:** `go build -o ./kilroy ./cmd/kilroy` | **Test:** `go test ./...` | **Validate:** `./kilroy attractor validate --graph <file.dot>`

## CXDB (`../cxdb`)

AI Context Store for agents and LLMs. Provides fast, branch-friendly storage for conversation histories and tool outputs with content-addressed deduplication. Built on a Turn DAG + Blob CAS architecture.

**Key features:** Branch-from-any-turn, fast append, BLAKE3 content deduplication, type-safe msgpack storage with typed JSON projections, built-in React UI.

**Key directories:**

| Path | What's there |
|---|---|
| `server/` | Rust server: binary protocol (:9109) and HTTP API (:9110) |
| `gateway/` | Go gateway: OAuth, frontend serving, reverse proxy to server |
| `frontend/` | React frontend: turn visualization, custom renderers |
| `clients/` | Client SDKs for interacting with CXDB |
| `docs/` | Protocol and API documentation |

**Build:** `cargo build --release` (server) | `cd gateway && go build` (gateway) | **Ports:** 9109 (binary), 9110 (HTTP API), 9120 (nginx frontend via gateway)

## Attractor (`../attractor`)

Three NLSpecs (Natural Language Specifications) that define the architecture Kilroy implements. These are the canonical design documents — treat them as authoritative.

| Spec | What it defines |
|---|---|
| `attractor-spec.md` | Pipeline orchestration using Graphviz DOT. Node types (LLM tasks, human review, conditionals, parallel), state management, validation/linting, model stylesheets, condition expressions. |
| `coding-agent-loop-spec.md` | Autonomous coding agent: agentic loop (LLM call → tool exec → repeat), provider-aligned toolsets (use each provider's native tools), execution environments (local/Docker/K8s), subagent spawning, loop detection, steering/interruption. |
| `unified-llm-spec.md` | Provider-agnostic LLM SDK. Single interface across all providers, streaming-first, middleware/interceptor pattern, structured outputs. Four layers: provider spec → utilities → core client → high-level API. |

**Architecture stack:** Unified LLM Client (bottom) → Coding Agent Loop (middle) → Pipeline Orchestration (top). Changes to Kilroy should align with these specs.
