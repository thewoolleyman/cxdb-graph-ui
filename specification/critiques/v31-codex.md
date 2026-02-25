# CXDB Graph UI Spec — Critique v31 (codex)

**Critic:** codex (gitlab/duo-chat-gpt-5-2-codex)
**Date:** 2026-02-25

## Prior Context

The v30 cycle incorporated all codex issues (HTML escaping for tab labels/indicator text, msgpack Map handling in `decodeFirstTurn`) and all opus issues except a proposed holdout scenario (CQL flag reset on reconnection). The spec now documents `fetchFirstTurn`'s depth-0 guard, `client_tag` empty-string filtering, deterministic active-run tie-breaking, and HTML escaping across UI surfaces. This critique focuses on correctness of the msgpack decoding options and on a remaining behavioral gap in the holdout scenarios.

---

## Issue #1: `decodeFirstTurn` uses a non-existent msgpack decoder option (`useMaps`) that does not affect Map vs object output

### The problem
Section 5.5’s `decodeFirstTurn` now calls:

```
payload = msgpackDecode(bytes, { useMaps: false })
```

The intent is to force `@msgpack/msgpack` to return plain objects instead of `Map` instances. However, in `@msgpack/msgpack` v3 (including the pinned `3.0.0-beta2` CDN build), the decoder does **not** accept a `useMaps` or `useMap` option. The available `DecoderOptions` include `useBigInt64`, `maxMapLength`, `maxStrLength`, etc. There is no option that switches map decoding between `Map` and plain objects. The library always decodes maps into plain objects, not `Map` instances, and validates map keys are string or number.

As written, the spec now directs implementers to pass a non-existent option, which is misleading and might prompt them to search for a configuration that does not exist. If a different msgpack library were used later, the guidance might be relevant, but it is not accurate for the pinned library and creates ambiguity about expected behavior.

### Suggestion
Update Section 5.5’s `decodeFirstTurn` commentary to remove the `useMaps` option and replace it with a more accurate note:

- State that `@msgpack/msgpack` decodes MessagePack maps to plain objects by default (and in v3 does not expose a Map/Record switch), so bracket indexing works as shown.
- Keep the defensive `payload["8"] || payload[8]` access for integer vs string keys, but drop the `useMaps` option and the `Map`-conversion fallback since it is not applicable to the pinned library.

If you want to keep a forward-looking note, clarify it as hypothetical: “If a different msgpack decoder is used that returns `Map` objects, convert with `Object.fromEntries` before field access.”

---

## Issue #2: Holdout scenarios still lack coverage for the `cqlSupported` flag reset on reconnection

### The problem
The spec (Section 5.5) explicitly states that `cqlSupported[index]` is reset when a CXDB instance becomes unreachable and reconnects, so that a previously non-CQL instance can be re-probed after upgrade. The proposed scenario for this behavior exists in `holdout-scenarios/proposed-holdout-scenarios-to-review.md`, but it is still not incorporated into the main holdout scenarios. The absence of this scenario means an implementation could silently ignore the reset behavior without failing any holdout test, despite contradicting the spec.

### Suggestion
Promote the “CQL support flag resets on CXDB instance reconnection” scenario into `holdout-scenarios/cxdb-graph-ui-holdout-scenarios.md` under **Pipeline Discovery** or **CXDB Connection Handling**. This closes the gap between spec behavior and test coverage.

---

If these are addressed, I do not see other major spec gaps.
