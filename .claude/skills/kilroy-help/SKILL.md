---
name: kilroy:help
description: Explain the Kilroy software factory skills and the process to follow.
user-invocable: true
---

Print the following guide to the user. Do not run any commands.

# Kilroy Software Factory — Skills Guide

This project uses Kilroy to run an AI-powered implementation pipeline against the CXDB Graph UI specification. The project is a single Go repo with one pipeline.

## Available Skills

| Skill | What it does | Example |
|-------|-------------|---------|
| `/kilroy:setup` | Build Kilroy binary, start CXDB, verify prerequisites | `/kilroy:setup` |
| `/kilroy:generate-pipeline` | Generate pipeline DOT from YAML config: compile, verify, validate | `/kilroy:generate-pipeline` |
| `/kilroy:run` | Run the pipeline | `/kilroy:run` |
| `/kilroy:status` | Check status of a Kilroy run, resume, or stop it | `/kilroy:status` |
| `/kilroy:land` | Land a completed run — merge, test, and push | `/kilroy:land` |
| `/cxdb:status` | Query CXDB for pipeline context status, detect stuck agents | `/cxdb:status` |

## Typical Workflow

```
/kilroy:setup                # once: build binary, start CXDB
/kilroy:generate-pipeline    # compile pipeline DOT from YAML config
/kilroy:run                  # execute the pipeline
/kilroy:land                 # merge, test, and push
```

## Key Concepts

- **Single pipeline file:** `pipeline.dot` at the repo root (generated artifact — never edit directly).
- **Single run config:** `factory/run.yaml`.
- **Spec file:** `specification/intent/cxdb-graph-ui-spec.md` is the source of truth for what agents implement.
- **Holdout scenarios:** `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` are behavioral test scenarios withheld from agents.
- **Pipeline config:** `factory/pipeline-config.yaml` + per-node prompt markdown files in `factory/prompts/` define the pipeline structure.
- **If a pipeline generates bad structure:** revise the spec file, then re-run `/kilroy:generate-pipeline`.
- **See `docs/software-factory.md`** for full manual instructions and background on how Kilroy validation works.
