# Critique v60 — JavaScript Unit Tests Have No Pipeline Enforcement and No Implementation Path

**Author:** js-unit-tests-enforcement
**Date:** 2026-03-01

## Severity: MAJOR

## Summary

Section 12.2 specifies a comprehensive JavaScript unit test layer using Vitest with 100% coverage, scoped to Invariant 20's client-side logic behaviors. However:

1. **No pipeline stage runs these tests.** The pipeline has `verify_tests` (Go unit tests) and now `verify_browser` (browser smoke), but nothing executes `vitest run`. The spec requirement is a dead letter — the factory will never be prompted to write or run JS tests.

2. **The prerequisite (JS module extraction) is unspecified.** Section 12.2 states the JS must be "extracted from inline `<script>` tags into importable ES modules" but gives no guidance on the module structure, file layout, or build step. The factory cannot implement this without concrete direction.

3. **The build step to inline modules back into `index.html` is unspecified.** Section 1.2 says "no build toolchain" for the deployed artifact, and Section 12.2 acknowledges "the source can be modular ES modules that are inlined (or concatenated) as part of a simple build step." But no such build step is defined. Without it, the factory cannot reconcile "source in modules" with "deploy as single HTML file."

4. **Section 12.3 (browser smoke) and 12.4 (Playwright) also lack pipeline enforcement**, though v59 addresses the browser smoke gap. The Playwright layer (12.4) remains a skill-only verification with no pipeline gate, but that is a separate concern since Playwright tests are intentionally run post-pipeline as holdout scenario verification.

## Detailed Analysis

### What Invariant 20 requires testing

The spec explicitly lists these client-side behaviors as needing JS unit tests (not UI tests):

- `fetchFirstTurn` pagination and `MAX_PAGES` cap
- `knownMappings` caching and null-entry semantics
- `determineActiveRuns` ULID-based run selection
- Gap recovery (`lastSeenTurnId` cursor, `MAX_GAP_PAGES` bound)
- Error loop detection scoped per context
- `cqlSupported` flag lifecycle (set, reset on reconnect, fallback path)
- `NULL_TAG_BATCH_SIZE` batch limiting
- Supplemental context list dedup merge
- `cachedContextLists` population for liveness checks

These are internal state machine behaviors that cannot be observed through the DOM. They are the most complex logic in the entire application and the most likely source of subtle bugs. Yet they have zero automated test coverage and no pipeline gate to enforce it.

### What the spec needs to add

**1. Module extraction structure.** Define which modules to extract and where they go. A concrete proposal:

```
ui/
├── index.html              ← deployed artifact (single file, inline JS)
├── main.go                 ← Go server
├── go.mod
├── src/
│   ├── discovery.js        ← pipeline discovery state machine
│   ├── status.js           ← status overlay logic (turn processing, node status derivation)
│   ├── detail.js           ← detail panel rendering (turn formatting, show-more logic)
│   └── constants.js        ← shared constants (POLL_INTERVAL_MS, STATUS_CLASSES, etc.)
├── test/
│   ├── discovery.test.js   ← tests for discovery.js
│   ├── status.test.js      ← tests for status.js
│   └── detail.test.js      ← tests for detail.js
├── package.json            ← vitest + v8 coverage config (dev dependency only)
└── vitest.config.js
```

**2. Build step.** Define a simple concatenation/inlining step that combines `src/*.js` back into `index.html` for deployment. This could be a shell script (e.g., `script/build-html`) that reads a template `index.html` with a placeholder marker and inlines the module source. The Go `//go:embed index.html` then embeds the built artifact.

**3. Pipeline enforcement.** The following pipeline changes are needed:

- **New node: `verify_js_tests`** (tool gate, shape=parallelogram) — runs `npm test` or `npx vitest run --coverage --coverage.provider=v8 --coverage.100` in the `ui/` directory.
- **New node: `check_js_tests`** (conditional, shape=diamond) — routes on pass/fail.
- **Placement:** After `verify_tests` / `check_tests` and before `verify_browser`. The flow becomes: `check_tests` → `verify_js_tests` → `check_js_tests` → `verify_browser` → `review_final`.
- **Failure routing:** `check_js_tests` failure loops back to `implement` (transient) or `postmortem` (deterministic), matching the pattern of other verification gates.
- **New required gate entry in `pipeline-config.yaml`:**
  ```yaml
  - id: verify_js_tests
    tool_command: "cd ui && npx vitest run --coverage --coverage.provider=v8 --coverage.100"
    timeout: "120s"
  ```

- **New node: `verify_build_html`** (tool gate, shape=parallelogram) — runs the build/inline step and verifies that `index.html` is up-to-date with the source modules. This should come before `verify_build` to ensure the Go build embeds the latest HTML.
- **New node: `check_build_html`** (conditional, shape=diamond) — routes on pass/fail.
- **Placement:** After `check_implement` and before `fix_fmt`. The flow becomes: `check_implement` → `verify_build_html` → `check_build_html` → `fix_fmt`.

**4. `review_final.md` update.** Add acceptance criteria:
- **AC-26**: `ui/src/` contains extracted JS modules covering all Invariant 20 behaviors
- **AC-27**: `ui/test/` contains Vitest test files with 100% line and branch coverage
- **AC-28**: `ui/package.json` exists with vitest as a dev dependency
- **AC-29**: `ui/index.html` is the built artifact with inlined modules (not hand-edited)

**5. `implement.md` update.** The implement stage prompt needs to know about the module structure so the factory writes code in the right places. Add to the deliverables:
- Source modules in `ui/src/` (discovery, status, detail, constants)
- Test files in `ui/test/`
- Build script that inlines modules into `index.html`

### What this does NOT change

- Go unit tests (12.1) remain as-is with their existing pipeline gate
- Browser smoke tests (12.3 / `verify_browser`) remain as-is — they test the assembled artifact in a real browser
- Playwright holdout scenarios (12.4) remain a post-pipeline manual verification skill
- The "no build toolchain" principle (1.2) still applies to the deployed artifact — the build step is a simple dev-time script, not a webpack/bundler chain

## Section 12.5 Update

The testing layer boundaries table should add:

| Scenario Category | Testing Layer |
|---|---|
| Discovery state machine (Invariant 20 behaviors) | JS unit tests (12.2) with pipeline gate |
| HTML build artifact freshness | Build verification gate (new) |

## Relationship to Other Critiques

- **v58** (failed holdout scenarios): identified the broken msgpack CDN URL
- **v59** (browser smoke tests): adds the `verify_browser` stage to catch CDN/rendering failures
- **v60** (this critique): addresses the deeper gap — the client-side logic has no test coverage at all, and the spec doesn't provide enough detail for the factory to implement it
