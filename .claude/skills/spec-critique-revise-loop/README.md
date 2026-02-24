# spec:critique-revise-loop

Automated loop that alternates `/spec:critique` and `/spec:revise` until the critique finds no remaining issues (or only minor ones).

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
| `LOOP_EXIT_CRITERIA` | `no_issues_found` \| `no_major_issues_found` | `no_major_issues_found` | When to stop |
| `MAX_ROUNDS` | Positive integer | `3` | Max critique-revise cycles |
| `CRITIQUE_PROMPT` | Quoted string | _(none)_ | Extra instructions for `/spec:critique` |
| `REVISE_PROMPT` | Quoted string | _(none)_ | Extra instructions for `/spec:revise` |

### LOOP_EXIT_CRITERIA

- **`no_major_issues_found`** (default) — Stops when zero issues remain, or all issues are minor/cosmetic.
- **`no_issues_found`** — Stops only when zero `## Issue #N:` headings exist. Stricter.

## Flowchart

```
    ┌──────────────────────────┐
    │  Parse ARGUMENTS         │
    │  Set round = 0           │
    └────────────┬─────────────┘
                 │
    ┌────────────▼─────────────┐
    │  [A] round++ ◄───────────┼──────────────────────────────┐
    │      round > MAX?        │                              │
    │      yes → EXIT: LIMIT   │                              │
    └────────────┬─────────────┘                              │
            no   │                                            │
    ┌────────────▼─────────────┐                              │
    │  [B] Run /spec:critique  │                              │
    │      + CRITIQUE_PROMPT   │                              │
    └────────────┬─────────────┘                              │
                 │                                            │
    ┌────────────▼─────────────┐                              │
    │  [C] Read critique file  │                              │
    │      Extract issue titles│                              │
    └────────────┬─────────────┘                              │
                 │                                            │
    ┌────────────▼─────────────┐                              │
    │  [D] Exit condition met? │                              │
    │      yes → EXIT: CONV.   │                              │
    │      same as last round? │                              │
    │      yes → EXIT: STUCK   │                              │
    └────────────┬─────────────┘                              │
            no   │                                            │
    ┌────────────▼─────────────┐                              │
    │  [E] Run /spec:revise    │                              │
    │      + REVISE_PROMPT     │                              │
    └────────────┬─────────────┘                              │
                 │                                            │
    ┌────────────▼─────────────┐                              │
    │  [F] Round summary       │                              │
    │      ✓/~/✗ per issue     │                              │
    └────────────┬─────────────┘                              │
                 │                                            │
    ┌────────────▼─────────────┐                              │
    │  [G] ROUND COMPLETE      │                              │
    │  [H] Return to A ────────┼──────────────────────────────┘
    └──────────────────────────┘

    EXIT: CONVERGED ──┐
    EXIT: ROUND LIMIT ┼──► FINAL REPORT
    EXIT: STUCK ──────┘
```

## Round Summary Output

After each revise, the loop prints:

```
[STEP F] Round 1 summary
  ✓ Issue #1: Missing error codes — applied
  ~ Issue #2: Incomplete auth flow — partial: deferred OAuth
  ✗ Issue #3: Naming inconsistency — skipped: intentional
  + REVISE_PROMPT: added backward-compat note
  Issues: 3 | Applied: 1 | Partial: 1 | Skipped: 1
=== ROUND 1 COMPLETE ===
[STEP H] Returning to step A
```

## Exit Conditions

| Exit | Trigger |
|------|---------|
| **Converged** | Critique found no issues (or only minor ones per `LOOP_EXIT_CRITERIA`) |
| **Round limit** | `round > MAX_ROUNDS` |
| **Stuck** | Two consecutive critiques raise identical issue titles |

## Loop Reliability

The loop uses three mechanisms to prevent premature stopping:

1. **Step labels** — Every step prints `[STEP X]` before executing, keeping the agent aware of loop position.
2. **Post-skill reminders** — After steps B and E (skill invocations), the loop explicitly states "you are still inside the loop, your next step is X."
3. **Sub-skill exit warnings** — Both `/spec:critique` and `/spec:revise` print a warning at completion: "If you are in a loop, you are NOT done."

## Related Skills

- `/spec:critique` — Single critique pass
- `/spec:revise` — Single revision pass
