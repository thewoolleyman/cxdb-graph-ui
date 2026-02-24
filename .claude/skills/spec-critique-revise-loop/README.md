# spec:critique-revise-loop

Automated loop that alternates between critiquing and revising the CXDB Graph UI specification until the critique finds no remaining issues (or only minor ones).

## Usage

```
/spec:critique-revise-loop
/spec:critique-revise-loop MAX_ROUNDS=5
/spec:critique-revise-loop LOOP_EXIT_CRITERIA=no_issues_found MAX_ROUNDS=10
/spec:critique-revise-loop CRITIQUE_PROMPT="focus on API completeness" REVISE_PROMPT="preserve backward compatibility"
```

## Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `LOOP_EXIT_CRITERIA` | `no_issues_found` \| `no_major_issues_found` | `no_major_issues_found` | When to stop the loop |
| `MAX_ROUNDS` | Any positive integer | `3` | Maximum critique-revise cycles before forced exit |
| `CRITIQUE_PROMPT` | Quoted string | _(none)_ | Additional instructions forwarded to `/spec:critique` |
| `REVISE_PROMPT` | Quoted string | _(none)_ | Additional instructions forwarded to `/spec:revise` |

### LOOP_EXIT_CRITERIA

- **`no_major_issues_found`** (default) — The loop stops when the critique raises zero issues, OR when every issue it raises is explicitly minor/cosmetic/nitpick. This is the pragmatic default: minor polish items don't warrant another full revision cycle.
- **`no_issues_found`** — The loop stops only when the critique raises literally zero `## Issue #N:` headings. Stricter, but may take more rounds.

### MAX_ROUNDS

Safety cap on the number of critique-revise cycles. If the spec hasn't converged after this many rounds, the loop stops and reports what happened. Default is 3.

### CRITIQUE_PROMPT / REVISE_PROMPT

Optional free-text instructions forwarded to the respective sub-skills. Use these to steer the critique focus or constrain revisions without modifying the skill definitions.

## Flowchart

```
                ┌─────────────────────────────────┐
                │  Parse ARGUMENTS                 │
                │                                  │
                │  LOOP_EXIT_CRITERIA ─────────────┼──► controls exit check
                │  MAX_ROUNDS ─────────────────────┼──► controls round limit
                │  CRITIQUE_PROMPT ────────────────┼──► forwarded to critique
                │  REVISE_PROMPT ──────────────────┼──► forwarded to revise
                └────────────────┬────────────────┘
                                 │
                                 ▼
                ┌────────────────────────────────┐
        ┌───── │  round = round + 1              │ ◄────────────────┐
        │      └────────────────┬───────────────┘                  │
        │                       │                                  │
        │                       ▼                                  │
        │      ┌────────────────────────────────┐                  │
        │      │  round > MAX_ROUNDS?            │                  │
        │      └─────────┬──────────────┬───────┘                  │
        │                │ no           │ yes                       │
        │                ▼              ▼                           │
        │      ┌─────────────────┐   ┌──────────────────┐          │
        │      │ Run             │   │ FORCED EXIT       │          │
        │      │ /spec:critique  │   │ (round limit)     │────┐     │
        │      │                 │   └──────────────────┘    │     │
        │      │ + CRITIQUE_     │                           │     │
        │      │   PROMPT        │                           │     │
        │      └────────┬────────┘                           │     │
        │               │                                    │     │
        │               ▼                                    │     │
        │      ┌────────────────────────────────┐            │     │
        │      │  Read critique file             │            │     │
        │      │  Extract issue titles           │            │     │
        │      └────────────────┬───────────────┘            │     │
        │                       │                            │     │
        │                       ▼                            │     │
        │      ┌────────────────────────────────┐            │     │
        │      │  EXIT CONDITION met?            │            │     │
        │      │  (per LOOP_EXIT_CRITERIA)       │            │     │
        │      └─────────┬──────────────┬───────┘            │     │
        │                │ no           │ yes                 │     │
        │                ▼              ▼                     │     │
        │      ┌─────────────────┐   ┌──────────────────┐    │     │
        │      │ Same issues as  │   │ NORMAL EXIT       │    │     │
        │      │ last round?     │   │ (converged)       │──┐ │     │
        │      └────┬─────────┬──┘   └──────────────────┘  │ │     │
        │           │ no      │ yes                         │ │     │
        │           ▼         ▼                             │ │     │
        │    ┌────────────┐ ┌──────────────────┐            │ │     │
        │    │ Run        │ │ FORCED EXIT       │            │ │     │
        │    │/spec:revise│ │ (stuck)           │────┐       │ │     │
        │    │            │ └──────────────────┘    │       │ │     │
        │    │ + REVISE_  │                         │       │ │     │
        │    │   PROMPT   │                         │       │ │     │
        │    └─────┬──────┘                         │       │ │     │
        │          │                                │       │ │     │
        │          ▼                                │       │ │     │
        │    ┌────────────────────────────────┐     │       │ │     │
        │    │  ROUND SUMMARY                 │     │       │ │     │
        │    │                                │     │       │ │     │
        │    │  Per issue from critique:      │     │       │ │     │
        │    │  ✓ Applied to spec             │     │       │ │     │
        │    │  ~ Partially addressed         │     │       │ │     │
        │    │  ✗ Not addressed (with reason) │     │       │ │     │
        │    │  + Extra REVISE_PROMPT changes  │     │       │ │     │
        │    │                                │     │       │ │     │
        │    │  Totals: N raised / N applied  │     │       │ │     │
        │    │          / N partial / N skip  │     │       │ │     │
        │    └─────┬──────────────────────────┘     │       │ │     │
        │          │                                │       │ │     │
        │          │  loop back                     │       │ │     │
        └──────────┼────────────────────────────────┼───────┼─┼─────┘
                   │                                │       │ │
                   │                                ▼       ▼ │
                   │                     ┌──────────────────────┐
                   │                     │   Final Report       │
                   │                     │                      │
                   │                     │ • Rounds completed   │
                   │                     │ • Exit reason        │
                   │                     │ • Cumulative summary │
                   │                     │ • Files created      │
                   │                     └──────────────────────┘
```

## Round Summary Output

After each revise step, the loop prints a structured summary:

```
=== ROUND 1 SUMMARY ===
  ✓ Issue #1: Missing error codes — applied to spec
  ~ Issue #2: Incomplete auth flow — partially addressed: deferred OAuth section
  ✗ Issue #3: Naming inconsistency — not addressed: intentional per style guide
  + Additional (REVISE_PROMPT): added backward-compat note to migration section
  Issues raised: 3
  Applied: 1 | Partial: 1 | Skipped: 1
=== ROUND 1 COMPLETE. LOOPING BACK. ===
```

## Exit Conditions

| Exit | Trigger | Meaning |
|------|---------|---------|
| **Converged** | Critique found no issues (or only minor ones per `LOOP_EXIT_CRITERIA`) | Spec is stable |
| **Round limit** | `round > MAX_ROUNDS` | Didn't converge in time; review manually |
| **Stuck** | Two consecutive critiques raise identical issue titles | Critique and revise are going in circles |

## Examples

**Quick polish pass (defaults):**
```
/spec:critique-revise-loop
```
Runs up to 3 rounds, stops when no major issues remain.

**Thorough review:**
```
/spec:critique-revise-loop LOOP_EXIT_CRITERIA=no_issues_found MAX_ROUNDS=8
```
Keeps going until the critique is completely clean, up to 8 rounds.

**Focused on a specific area:**
```
/spec:critique-revise-loop CRITIQUE_PROMPT="focus only on the graph traversal API and ignore UI concerns" REVISE_PROMPT="only modify sections related to the graph traversal API"
```

## Related Skills

- `/spec:critique` — Run a single critique pass
- `/spec:revise` — Run a single revision pass
