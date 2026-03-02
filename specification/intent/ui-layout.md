## 8. UI Layout and Interaction

### 8.1 Layout

```
┌──────────────────────────────────────────────────────┐
│  [Pipeline A] [Pipeline B] [Pipeline C]    ● CXDB OK │
├──────────────────────────────────────┬───────────────┤
│                                      │               │
│           SVG Pipeline Graph         │    Detail     │
│                                      │    Panel      │
│           (rendered from DOT)        │   (sidebar)   │
│                                      │               │
└──────────────────────────────────────┴───────────────┘
```

- **Top bar:** Pipeline tabs (one per `--dot` file), CXDB connection indicator
- **Center:** SVG graph area
- **Right sidebar:** Detail panel (hidden until a node is clicked)

### 8.2 CXDB Connection Indicator

The top bar displays connection status for each configured CXDB instance:

- **Green dot + "CXDB OK":** All instances reachable on last poll
- **Yellow dot + "1/2 CXDB":** Some instances reachable, some not. Hover shows per-instance status.
- **Red dot + "CXDB unreachable":** No instances reachable. Includes the configured URLs for diagnostics.

The indicator updates on every poll cycle. When a CXDB instance is unreachable, the graph remains visible with the last known status from that instance. Polling continues — status resumes automatically when instances become reachable.

When all contexts for the active pipeline's active run have `is_live == false` and at least one node is "stale" (was "running" but the pipeline has no active sessions), the indicator shows a warning: **"Pipeline stalled — no active sessions."** This alerts the operator that the agent process may have crashed and no further progress is expected without intervention.

**HTML escaping.** CXDB URLs displayed in the indicator (e.g., in the "CXDB unreachable" state or the hover tooltip for partial connectivity) must be rendered as text-only — via `textContent` assignment or explicit HTML entity escaping. CXDB URLs come from command-line `--cxdb` flags and may contain query parameters with `&` or other characters that would be interpreted as HTML if inserted via `innerHTML`. This matches the tab label (Section 4.4) and detail panel (Section 7.1) escaping policies.

### 8.3 Interaction

- **Click node:** Opens detail panel for that node
- **Click outside panel or close button:** Closes detail panel
- **Click pipeline tab:** Switches to that pipeline's DOT file, re-renders SVG
- **Browser zoom (Ctrl+scroll):** Zooms the SVG natively
