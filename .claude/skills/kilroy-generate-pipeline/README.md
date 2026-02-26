# kilroy-generate-pipeline

Generate, patch, and verify the Kilroy pipeline DOT file from YAML config
definitions. This skill turns a declarative YAML config into a complete
Graphviz DOT pipeline that the Kilroy attractor can execute.

## Quick start

```bash
# Generate the pipeline (deterministic compile from YAML + prompt files)
/kilroy:generate-pipeline

# Force regeneration (recompile even if checksum matches)
/kilroy:generate-pipeline --force
```

## How it works

The pipeline generator operates in one of two modes, selected automatically
based on whether a config YAML exists.

### Default mode: Deterministic compilation (config YAML exists)

When `pipeline-config/pipeline-config.yaml` exists, the pipeline is compiled
deterministically from the YAML config and prompt files. No LLM is
involved — the same input always produces byte-identical output.

```
pipeline-config/pipeline-config.yaml + pipeline-config/*.md
        │
        ▼
  compile_dot.rb ──► DOT file (byte-identical every run)
        │
        ▼
  verify_dot.rb ──► PASS / FAIL
        │
        ▼
  kilroy attractor validate ──► structural check
        │
        ▼
  pipeline.dot
```

1. **compile_dot.rb** reads the YAML config and prompt markdown files,
   then emits a complete DOT file. Node order, edge order, formatting,
   and all attributes are fully determined by the config.
2. **verify_dot.rb** confirms the compiled DOT matches the YAML source
   of truth — gates, prompts, stylesheet, edges, node inventory.
3. **kilroy attractor validate** performs a final structural correctness
   check on the DAG itself.

### Bootstrap mode: LLM-assisted (no config YAML yet)

When no config YAML exists, the LLM generates the initial pipeline.
This is the "bootstrap" path for new pipelines.

```
  (no config YAML exists)
        │
        ▼
  render_prompt.rb + kilroy attractor ingest ──► raw DOT
        │
        ▼
  patch_dot.rb ──► patched DOT
        │
        ▼
  extract_prompts.rb ──► pipeline-config/*.md
        │
        ▼
  verify_dot.rb + kilroy attractor validate
```

After bootstrap, you should manually create the config YAML (using
`extract_config.rb` as a starting point) so subsequent runs use
deterministic compilation.

### Safety check

If a DOT file exists but no corresponding config YAML exists, the
script **refuses to continue** with a clear error. This prevents
accidental overwrites of hand-tuned DOT files.

```
DOT exists + no config YAML → ERROR: "DOT exists without config YAML"
```

To fix this, either create the config YAML or delete the DOT file.

## Prompt files

Box node prompts and hexagon questions are stored as separate markdown
files alongside the YAML config in `pipeline-config/<node_id>.md`.
This keeps the YAML config manageable (prompts are typically 30-100 lines
each) and allows prompts to be edited independently.

```
pipeline-config/
├── pipeline-config.yaml
├── implement.md
├── review.md
├── postmortem.md
├── human_gate.md
└── ...
```

The `expand_spec` node is special — its prompt lives in the YAML config
as `expand_spec_prompt` (not as a file), since it's typically a short
one-liner.

## Config file reference

The config file lives at `pipeline-config/pipeline-config.yaml`.

### Fields

| Field | Required | Description |
|---|---|---|
| `target` | yes | Target name |
| `repo_path` | yes | Path to the target repo, relative to this repo root (`.` for this repo) |
| `output_dot` | yes | Output DOT filename (`pipeline.dot`) |
| `graph_id` | no | Deterministic graph ID for the DOT digraph. |
| `graph_goal` | no | One-line goal description for the graph-level `goal` attribute. |
| `default_max_retry` | no | Default max retry count (integer, typically 3). |
| `topology` | no | One of `no-fanout`, `full-fanout`, or `custom`. Controls verification rules. |
| `retry_target` | no | Node ID that retry loops should route to (e.g. `implement`). |
| `fallback_retry_target` | no | Node ID for escalation when retries are exhausted (e.g. `human_gate`). |
| `nodes` | yes* | Node inventory — list of nodes with shapes. Drives compilation and verification. |
| `edges` | yes* | Edge definitions — list of edges with optional conditions. Drives compilation. |
| `required_gates` | yes | List of verification gate definitions (see below). |
| `expand_spec_prompt` | yes | Prompt text for the `expand_spec` node. |
| `model_stylesheet` | yes | CSS-like stylesheet assigning LLM models to node classes. |
| `goal` | bootstrap | Multi-line description for LLM prompt (only used in bootstrap mode). |
| `rules` | bootstrap | List of rules for the LLM (only used in bootstrap mode). |

\* Required for deterministic compilation. If `nodes` and `edges` are missing,
the script falls back to the legacy LLM-based flow.

### `nodes` entries

Each node is a map with:

| Key | Required | Description |
|---|---|---|
| `id` | yes | Node ID. Must match the DOT node ID exactly. |
| `shape` | yes | Graphviz shape (`box`, `diamond`, `parallelogram`, `hexagon`, `Mdiamond`, `Msquare`). |
| `class` | no | CSS class for model_stylesheet assignment (e.g. `hard`, `verify`, `review`). |
| `goal_gate` | no | Boolean. If true, adds `goal_gate=true` attribute to the node. |
| `choices` | no | Choices string for hexagon nodes (human gates). |
| `options` | no | Options string for hexagon nodes (alternate attribute name). |
| `edges` | no | Edges string for hexagon nodes (alternate attribute name). |

### `edges` entries

Each edge is a map with:

| Key | Required | Description |
|---|---|---|
| `from` | yes | Source node ID. |
| `to` | yes | Target node ID. |
| `condition` | no | Condition string (e.g. `"outcome = success"`). |
| `loop_restart` | no | Boolean. If true, adds `loop_restart=true` attribute. |
| `label` | no | Edge label text. |

### `required_gates` entries

Each gate is a map with:

| Key | Required | Description |
|---|---|---|
| `id` | yes | Node ID in the DOT file. Must match exactly. |
| `tool_command` | yes | Shell command the gate runs. |
| `timeout` | no | Timeout string (e.g. `"120s"`, `"300s"`). |
| `max_retries` | no | Maximum retry count override for this gate. |

### Node shapes and their roles

| Shape | Role | Notes |
|---|---|---|
| `Mdiamond` | Start node | Always `id: start` |
| `Msquare` | Exit node | Always `id: exit` |
| `box` | LLM work node | Prompt loaded from `pipeline-config/<id>.md` |
| `diamond` | Check/routing node | Routes on `outcome=success`, `outcome=fail`, and a bare default |
| `parallelogram` | Verification gate | Carries `tool_command` and optional `timeout` |
| `hexagon` | Human gate | Blocks for operator input when retries are exhausted |

## What you need to edit

### Always edit in YAML + prompt files, not in DOT

The YAML config and prompt files in `pipeline-config/` are the
source of truth. Never hand-edit the DOT file — your changes will be
overwritten on the next generation run.

### Common edits

**Changing a node's prompt:** Edit the markdown file at
`pipeline-config/<node_id>.md`. Then regenerate.

**Adding a new verification gate:**

```yaml
required_gates:
  # ... existing gates ...
  - id: verify_new_thing
    tool_command: "mise exec -- sh -c 'your command here'"
    timeout: "60s"   # optional
```

Then add the node and edges to the config:

```yaml
nodes:
  # ... existing nodes ...
  - id: verify_new_thing
    shape: parallelogram
  - id: check_new_thing
    shape: diamond

edges:
  # ... existing edges ...
  - from: previous_node
    to: verify_new_thing
  - from: verify_new_thing
    to: check_new_thing
  - from: check_new_thing
    to: next_node
    condition: "outcome = success"
  - from: check_new_thing
    to: implement
    condition: "outcome = fail"
```

**Changing an LLM model assignment:** Edit `model_stylesheet`:

```yaml
model_stylesheet: |
  * { llm_model: claude-sonnet-4-6; llm_provider: anthropic; max_tokens: 65536; }
  .hard { llm_model: claude-opus-4-6; llm_provider: anthropic; max_tokens: 65536; }
```

**Updating retry routing:**

```yaml
retry_target: implement              # where retry loops go
fallback_retry_target: human_gate    # where exhausted retries escalate
```

### Fields you should NOT edit

- `output_dot` — changing this breaks the skill's resolution
- `target` — must match the filename pattern

## Scripts reference

All scripts are in `script/` and invoked with `ruby <script>`:

| Script | Usage | Description |
|---|---|---|
| `compile_dot.rb` | `<yaml> [<output>]` | Deterministic DOT compiler. Reads YAML + prompt files, emits DOT. |
| `extract_prompts.rb` | `<yaml> <dot>` | Extract prompts from a DOT file into per-node markdown files alongside the YAML. |
| `verify_dot.rb` | `<yaml> <dot>` | Verify a DOT file matches the YAML config. Exit 0 = pass, exit 1 = fail. |
| `render_prompt.rb` | `<yaml>` | Render YAML config into a markdown ingest prompt (bootstrap mode). |
| `patch_dot.rb` | `<yaml> <dot>` | Patch a DOT file with deterministic values from YAML (bootstrap mode). |
| `extract_field.rb` | `<yaml> <field>` | Extract a single top-level YAML field to stdout. |
| `generate_pipeline.rb` | `[--force] <target>` | Full pipeline generation: auto-selects mode, runs compile/verify/validate. |

### Running scripts manually

```bash
# Compile the pipeline deterministically
ruby .claude/skills/kilroy-generate-pipeline/script/compile_dot.rb \
  pipeline-config/pipeline-config.yaml pipeline.dot

# Extract prompts from an existing DOT into markdown files
ruby .claude/skills/kilroy-generate-pipeline/script/extract_prompts.rb \
  pipeline-config/pipeline-config.yaml pipeline.dot

# Verify a DOT file
ruby .claude/skills/kilroy-generate-pipeline/script/verify_dot.rb \
  pipeline-config/pipeline-config.yaml pipeline.dot
```

## Tests

Tests are in `tests/` using Ruby's Minitest. Run them all:

```bash
bash .claude/skills/kilroy-generate-pipeline/tests/run_tests.sh
```

Or individually:

```bash
ruby .claude/skills/kilroy-generate-pipeline/tests/test_compile_dot.rb
ruby .claude/skills/kilroy-generate-pipeline/tests/test_extract_prompts.rb
ruby .claude/skills/kilroy-generate-pipeline/tests/test_verify_dot.rb
ruby .claude/skills/kilroy-generate-pipeline/tests/test_generate_pipeline.rb
ruby .claude/skills/kilroy-generate-pipeline/tests/test_render_prompt.rb
ruby .claude/skills/kilroy-generate-pipeline/tests/test_patch_dot.rb
ruby .claude/skills/kilroy-generate-pipeline/tests/test_extract_field.rb
```

Tests use temp files and don't require CXDB or kilroy to be running.

## Prerequisites

- Ruby 3+
- kilroy binary at `../kilroy/kilroy` (run `/kilroy:setup` to build)
- CXDB running on `localhost:9110` (run `/kilroy:setup` to start)
- `ANTHROPIC_API_KEY` set (via direnv) — only needed for bootstrap mode
- direnv configured for the project root

## Troubleshooting

**"Config YAML unchanged, skipping compile"** — the YAML hasn't changed
since the last generation. Use `--force` to recompile anyway.

**Verify fails with MISSING EDGE** — an edge in the YAML config is not
present in the DOT. Check that `edges` in the config matches the
intended pipeline structure.

**Verify fails with MISSING NODE** — a node from the YAML `nodes`
inventory is not in the DOT. Check the config.

**Verify fails with EXTRA BOX NODE** — a `shape=box` node exists in
the DOT but is not in the YAML `nodes` inventory. Either add it to
`nodes` or remove it from the config.

**Verify fails with SHAPE MISMATCH** — a node exists but with the wrong
shape. Update the `nodes` entry in YAML to match the intended shape.

**"DOT exists without config YAML"** — a DOT file exists but no
corresponding config YAML was found. Create the config YAML (use
`extract_config.rb` to generate a starting point) or delete the DOT.
