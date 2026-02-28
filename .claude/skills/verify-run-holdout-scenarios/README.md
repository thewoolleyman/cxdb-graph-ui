# run-holdout-scenarios

Acceptance test skill for the CXDB Graph UI. Runs the holdout scenarios using Playwright MCP browser automation and shell commands.

## Structure

```
.claude/skills/run-holdout-scenarios/
├── SKILL.md            # Skill definition — read by LLM when invoked
├── mock-cxdb.js        # Browser-injectable fetch mock for CXDB API
└── README.md           # This file

holdout-scenarios/
├── fixtures/           # DOT files used as test inputs
│   ├── simple-pipeline.dot     # Main fixture: LLM+tool+human gate pipeline
│   ├── all-shapes.dot          # All 11 node shapes
│   ├── html-injection.dot      # HTML/XSS content in node prompts
│   ├── html-tab-label.dot      # HTML-like graph ID for tab label test
│   ├── syntax-error.dot        # Intentionally invalid DOT syntax
│   ├── quoted-ids.dot          # Quoted graph and node identifiers
│   └── multi-tab-b.dot         # Second pipeline for multi-tab tests
└── cxdb-graph-ui-holdout-scenarios.md  # The scenario specs
```

## How the Mock Works

`mock-cxdb.js` overrides `window.fetch` in the browser to intercept all `/api/cxdb/*` requests. The skill injects it via `playwright_evaluate` immediately after navigation.

Switch scenarios at runtime:
```javascript
window.__mockCxdb.setScenario('pipeline_running');
```

Available scenarios are listed in the top comment of `mock-cxdb.js`.

## Scenario Split

| Category | Count | Method |
|---|---|---|
| DOT Rendering | 14 | Playwright (UI) |
| CXDB Status Overlay | 21 | Playwright + mock CXDB |
| Detail Panel | 12 | Playwright + mock CXDB |
| CXDB Connection Handling | 10 | Playwright + mock CXDB |
| Server CLI | 6 | Shell (go build + exit code) |
| Deferred (complex mocking) | ~9 | — |

## Deferred Scenarios

These scenarios require stateful multi-poll simulation that is impractical with a simple fetch mock:

- Gap recovery / `lastSeenTurnId` tracking (multi-poll state machine)
- `MAX_GAP_PAGES` pagination cap
- Null-tag backlog ordering (`NULL_TAG_BATCH_SIZE`)
- Supplemental fetch dedup merge

These may be testable in a future iteration with a stateful mock HTTP server.
