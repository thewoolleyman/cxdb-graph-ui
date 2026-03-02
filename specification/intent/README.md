# CXDB Graph UI Specification — Intent

A local web dashboard that renders Attractor pipeline DOT files as interactive SVG graphs with real-time execution status from CXDB. The DOT graph is the pipeline definition; CXDB holds the execution trace. The UI overlays one on the other — nodes are colored by their execution state, and clicking a node shows its CXDB activity.

## Specification Structure

This specification is split across three directories under `specification/`:

- **`intent/`** — This directory. Architecture, design rationale, and behavioral intent.
- **`contracts/`** — API surface definitions: [server-api.md](../contracts/server-api.md) (downstream HTTP API) and [cxdb-upstream.md](../contracts/cxdb-upstream.md) (upstream CXDB API consumed).
- **`constraints/`** — [Invariants](../constraints/invariants.md), [non-goals](../constraints/non-goals.md), [definition of done](../constraints/definition-of-done.md), and [testing requirements](../constraints/testing-requirements.md).

## Table of Contents

1. [Overview and Goals](overview.md) — Problem statement, design principles, architecture
2. [Server](server.md) — Cross-references and server properties
3. [DOT Rendering](dot-rendering.md) — Graphviz WASM, SVG identification, pipeline tabs, initialization
4. [CXDB Integration](cxdb-integration.md) — Pipeline discovery, context mapping, caching
5. [Status Overlay](status-overlay.md) — Polling, node status map, CSS classes
6. [Detail Panel](detail-panel.md) — DOT attributes, CXDB activity, shape mapping
7. [UI Layout and Interaction](ui-layout.md) — Layout, connection indicator, interaction
