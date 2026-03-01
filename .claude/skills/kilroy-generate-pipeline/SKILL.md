---
name: kilroy:generate-pipeline
description: Generate or regenerate the Kilroy pipeline DOT file from YAML config. Runs deterministic compilation, verifies correctness, and validates structure.
user-invocable: true
allowed-tools: Bash, Read
---

Generate the Kilroy pipeline DOT file from a YAML config. This runs
deterministic compilation from YAML + prompt files, then verifies and
validates the output.

## How it works

The generator auto-selects one of two modes based on whether a config
YAML exists.

### Default mode: Deterministic compilation

When `factory/pipeline-config.yaml` exists (with `nodes` and `edges`),
the pipeline is compiled deterministically. No LLM is involved.

```
 factory/
 +----------------------------+  +-------------------+
 | pipeline-config.yaml       |  | prompts/           |
 | graph_id, graph_goal       |  |   implement.md     |
 | nodes (id, shape, class)   |  |   postmortem.md    |
 | edges (from, to, condition)|  |   human_gate.md    |
 | required_gates             |  | ...               |
 | expand_spec_prompt         |  +-------------------+
 | model_stylesheet           |          |
 +----------------------------+          |
              |                          |
              +----------+---------------+
                         |
                         v
 +----------------------------+
 | 1. compile_dot.rb          |
 |                            |
 |    Reads YAML + prompt     |
 |    files. Emits DOT with   |
 |    deterministic ordering. |
 |    Same input = identical  |
 |    output every time.      |
 +----------------------------+
              |
              | compiled DOT file
              v
 +----------------------------+
 | 2. verify_dot.rb           |
 |                            |
 |    Confirms gates, prompts,|
 |    stylesheet, edges, and  |
 |    node inventory match.   |
 +----------------------------+
              |
              | exit 0 = pass
              v
 +----------------------------+
 | 3. kilroy attractor        |
 |    validate                |
 |                            |
 |    Structural correctness  |
 |    check on the DAG.       |
 +----------------------------+
              |
              v
 pipeline.dot                  (final output)
```

### Bootstrap mode: LLM-assisted (no config YAML)

When no config YAML exists, the LLM generates the initial pipeline.
A safety check prevents accidental overwrites: if a DOT file already
exists without a config YAML, the script refuses to continue.

```
  (no config YAML, no DOT)
        │
        ▼
  render_prompt.rb + kilroy attractor ingest ──► raw DOT
        │
        ▼
  patch_dot.rb ──► patched DOT
        │
        ▼
  extract_prompts.rb ──► factory/prompts/*.md
        │
        ▼
  verify_dot.rb + kilroy attractor validate
```

## Verify prerequisites

Check that:
1. `../kilroy/kilroy` binary exists (suggest `/kilroy:setup` if not)
2. CXDB is running: `curl -sf http://localhost:9110/healthz > /dev/null`
   (suggest `/kilroy:setup` if not)
3. Ruby 3+ is available: `ruby --version`
4. Script tests pass:
   ```bash
   bash .claude/skills/kilroy-generate-pipeline/tests/run_tests.sh
   ```
   If tests fail, fix the scripts before proceeding.

## Skill directory layout

```
.claude/skills/kilroy-generate-pipeline/
├── SKILL.md
├── README.md
├── script/
│   ├── compile_dot.rb
│   ├── extract_field.rb
│   ├── extract_prompts.rb
│   ├── generate_pipeline.rb
│   ├── patch_dot.rb
│   ├── render_prompt.rb
│   └── verify_dot.rb
└── tests/
    ├── run_tests.sh
    ├── test_compile_dot.rb
    ├── test_extract_field.rb
    ├── test_extract_prompts.rb
    ├── test_generate_pipeline.rb
    ├── test_patch_dot.rb
    ├── test_render_prompt.rb
    └── test_verify_dot.rb
```

**Scripts** (all invoked via `ruby <script>`):

- **`script/compile_dot.rb`** `<yaml> [<output>]` --
  Deterministic DOT compiler. Reads YAML config + prompt markdown files,
  emits a complete DOT file. Same input always produces identical output.
- **`script/extract_prompts.rb`** `<dot> <target>` --
  Extract prompts from an existing DOT file into per-node markdown files
  alongside the YAML config
- **`script/verify_dot.rb`** `<yaml> <dot>` --
  Verify a DOT file matches the YAML config (gates, prompts, stylesheet,
  edges, node inventory). Exit 0 = pass, exit 1 = fail with details.
- **`script/render_prompt.rb`** `<yaml>` --
  Render a YAML config into a markdown ingest prompt (bootstrap mode only)
- **`script/patch_dot.rb`** `<yaml> <dot>` --
  Patch deterministic values from YAML into a DOT file (bootstrap mode only)
- **`script/extract_field.rb`** `<yaml> <field>` --
  Extract a top-level YAML field to stdout
- **`script/generate_pipeline.rb`** `[--force] <target>` --
  Full pipeline generation: auto-selects compile or bootstrap mode, runs all steps

## Run the pipeline generation

Execute the generation script. The target for this repo uses the config at
`factory/pipeline-config.yaml` and outputs `pipeline.dot`:

```bash
env -u CLAUDECODE direnv exec "$PWD" ruby \
  .claude/skills/kilroy-generate-pipeline/script/generate_pipeline.rb .
```

The `.` target means "this repo" — the script resolves it to find
`factory/pipeline-config.yaml` and output `pipeline.dot`.

To force recompilation (ignores checksum cache):

```bash
env -u CLAUDECODE direnv exec "$PWD" ruby \
  .claude/skills/kilroy-generate-pipeline/script/generate_pipeline.rb --force .
```

### Checksum-based skip

On successful compilation, a `config_sha256` attribute is written into
the DOT file's graph-level attributes. On subsequent runs, if the config
YAML checksum matches the stored value, compilation is skipped. Use
`--force` to bypass this check.

## Report results

After completion, summarize:
1. Pipeline DOT generated (path)
2. Mode used (compile or bootstrap)
3. Gates verified (list of gate IDs)
4. Edges verified (count)
5. Nodes verified (count)
6. Verification result (pass/fail)
7. Validation result

If verification fails, report the specific mismatches.

Remind the user the next step is `/kilroy:run`.
