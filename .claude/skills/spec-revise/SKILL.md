---
name: spec:revise
description: Revise the CXDB Graph UI spec based on the latest critique
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash(ls:*), Bash(pwd:*), Bash(date:*)
---

You are revising the CXDB Graph UI specification based on critique feedback.

## Step 1: Read the Specification

Read the specification file:

- `specification/cxdb-graph-ui-spec.md`

## Step 2: Read the Holdout Scenarios

Read the holdout scenarios for reference:

- `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`

## Step 3: Find Unacknowledged Critiques

List ALL files in `specification/critiques/` and find the highest version N that has critique file(s) **without** corresponding acknowledgement file(s).

Critique files match these patterns:
- `vN.md` (legacy single-author format)
- `vN-<author>.md` (multi-author format)

Acknowledgement files match these patterns:
- `vN-acknowledgement.md` (legacy acknowledgement format)
- `vN-<author>-acknowledgement.md` (multi-author acknowledgement format)

A version is considered **fully acknowledged** when every critique file for that version has a corresponding acknowledgement file. For example:
- `v9-opus.md` is acknowledged by `v9-opus-acknowledgement.md`
- `v9-gemini.md` is acknowledged by `v9-gemini-acknowledgement.md`
- `v9.md` (legacy) is acknowledged by `v9-acknowledgement.md`

Find the highest version N that has at least one unacknowledged critique file. If all critiques across all versions have acknowledgements, tell the user to run `/spec:critique` first and stop.

Read ALL unacknowledged critique files for version N. Also read any acknowledgement files from version N-1 for continuity.

## Additional Direction from User

$ARGUMENTS

## Step 4: Apply the Critiques

Process ALL unacknowledged critique files for version N together in a single revision pass. For each issue across all critique files:

1. Evaluate whether the feedback is valid and should be incorporated
2. If valid, edit `specification/cxdb-graph-ui-spec.md` **in place** — this is a living document, not versioned
3. Keep edits focused and surgical — don't rewrite sections that aren't affected by the critique
4. When multiple critics raise the same issue, address it once and reference it in all acknowledgements

**Important:** The spec file is the single source of truth. Edit it directly rather than creating new versions.

## Step 5: Write Acknowledgement Files

Write a **separate** acknowledgement file for **each** unacknowledged critique file. This ensures each critic gets specific feedback on their issues.

For a critique file named `vN-<author>.md`, write the acknowledgement to:
```
specification/critiques/vN-<author>-acknowledgement.md
```

For a legacy critique file named `vN.md`, write the acknowledgement to:
```
specification/critiques/vN-acknowledgement.md
```

Use this format for each acknowledgement:

```markdown
# CXDB Graph UI Spec — Critique vN ({author}) Acknowledgement

{One-paragraph summary of what was done}

## Issue #1: {title from critique}

**Status: {Applied to specification | Not addressed | Partially addressed}**

{Description of what changed and where, OR reasoning for why it was not addressed}

Changes:
- `specification/cxdb-graph-ui-spec.md`: {what changed}

## Issue #2: ...

## Not Addressed (Out of Scope)

- {Any items intentionally deferred, with reasoning}
```

Each acknowledgement must cover **every issue** from its corresponding critique. For items not implemented, provide clear reasoning — the next critic will read this to understand your decisions.

## Step 5b: Apply Holdout Scenario Updates

If any critique issue identifies a gap, correction, or addition to the holdout scenarios (e.g., a scenario that doesn't match the spec's behavior, a missing negative case, or a new scenario implied by a spec change), write the scenario **directly** to `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md`. Do not defer or stage scenarios for later review.

1. Add the scenario to the appropriate section in `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` using the same Given/When/Then format as existing scenarios
2. Only refuse to apply a holdout scenario if it is factually incorrect or invalid (e.g., describes an impossible state, contradicts a verified spec invariant, or was explicitly superseded by a later proposed scenario in the same critique round)
3. In the acknowledgement file, mark the item as **"Applied to holdout scenarios"** and note the scenario title added

This ensures holdout scenario gaps identified during critique are captured immediately in the canonical acceptance suite.

## Step 6: Report

Tell the user:
- Whether the spec file was modified
- The acknowledgement file path(s) created (list all)
- A summary of key changes made
- Any critique items that were intentionally not addressed, and why

Then print exactly:

```
=== REVISE SKILL COMPLETE ===
WARNING: If you are executing this skill as part of a loop (e.g., spec:critique-revise-loop), you are NOT done. Return to the loop protocol now and execute the next step. Check the loop's exit criteria before stopping.
=== END REVISE SKILL ===
```
