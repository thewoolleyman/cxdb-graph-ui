You are critiquing the CXDB Graph UI specification.

## Step 1: Determine Author Name

The critique filename includes an author identifier. Determine the author name:

- If the user provided an author name via `$ARGUMENTS` (look for `--author <name>` or `author=<name>`), use that value.
- Otherwise, default to the LLM model name as a single lowercase word with no spaces:
  - Claude Opus → `opus`
  - Claude Sonnet → `sonnet`
  - Claude Haiku → `haiku`
  - Gemini → `gemini`
  - GPT-4o → `gpt4o`
  - o3 → `o3`
  - Codex → `codex`
  - For any other model, use a short lowercase slug of the model name (no spaces, no special characters).

The author name must be safe for filenames: lowercase letters and numbers only, no spaces or special characters.

## Step 2: Read the Specification

Read the specification file:

- `specification/intent/cxdb-graph-ui-spec.md`

## Step 3: Read the Holdout Scenarios

Read the holdout scenarios for reference:

- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`

## Step 4: Determine Critique Version

List the files in `specification-critiques/` and find the highest existing version number N.

Version numbers are extracted from filenames matching patterns:
- `vN.md` (legacy single-author format)
- `vN-<author>.md` (multi-author format)
- `vN-acknowledgement.md` (legacy acknowledgement format)
- `vN-<author>-acknowledgement.md` (multi-author acknowledgement format)

Your critique will be version **N+1**.

**Important:** Multiple authors can write critiques for the same version. If you find that version N+1 already has critique files from other authors (e.g., `v{N+1}-gemini.md` exists), then use N+1 as your version too — you are adding your critique alongside theirs. Only increment past N+1 if N+1 already has an acknowledgement file.

If the `specification-critiques/` directory does not exist yet, create it and use version 1.

## Step 5: Read Previous Critique Context

Read ALL critique files from version N (both legacy `vN.md` and multi-author `vN-<author>.md` files). Also read any acknowledgement files for version N (`vN-acknowledgement.md` or `vN-<author>-acknowledgement.md`).

Use this context to:
- **Avoid re-raising** issues that were already addressed
- **Follow up** on issues that were rejected if you believe they are still relevant
- **Acknowledge** improvements from the previous revision cycle

If this is the first critique (version 1), skip this step.

## Additional Direction from User

$ARGUMENTS

## Step 6: Write the Critique

Evaluate the specification against the holdout scenarios. Focus on whether an agent could **fully implement everything as specified** and whether the holdout scenarios adequately cover the spec.

Review for:
- **Completeness** — Are there gaps an implementing agent would hit?
- **Technical correctness** — Are the approaches sound?
- **Specificity** — Are instructions concrete enough to implement without guesswork?
- **Consistency** — Do the spec sections agree with each other?
- **Testability** — Do the holdout scenarios cover the spec's invariants and edge cases?
- **Edge cases** — What scenarios might be missed?

Write your critique to:

```
specification-critiques/v{VERSION}-{AUTHOR}.md
```

Use this format:

```markdown
# CXDB Graph UI Spec — Critique v{VERSION} ({AUTHOR})

**Critic:** {author} ({full-model-name})
**Date:** {YYYY-MM-DD}

## Prior Context

{Brief summary of what changed since the last critique, based on the acknowledgement file(s)}

---

## Issue #1: {title}

### The problem
{description}

### Suggestion
{what should change in the spec}

## Issue #2: ...
```

If there are no major issues, say so explicitly and note any minor suggestions.

## Step 7: Report

Tell the user:
- The critique file path created
- The author name used
- How many issues were found
- A one-line summary of the most significant finding
