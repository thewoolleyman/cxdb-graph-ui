# Non-Goals

1. **No pipeline editing.** The UI is read-only. Pipeline modification uses the YAML → compile → DOT workflow.

2. **No execution control.** The UI does not start, stop, pause, or resume pipeline runs.

3. **No CXDB writes.** The UI never writes to CXDB.

4. **No authentication.** This is a local developer tool. No login, no sessions, no access control.

5. **No persistent state.** Closing the browser discards all UI state. Nothing is saved to disk or localStorage.

6. **No custom graph layout.** The UI uses Graphviz's layout engine as-is. Users cannot rearrange nodes.

7. **No historical playback.** The UI shows current or final state. There is no timeline slider or step-through mode.

8. **No server-side rendering.** The frontend is a statically-built SPA. No SSR, no ISR, no server components. Vite builds the frontend into static assets; the Rust server serves them as-is.

9. **No mobile support.** The UI targets desktop browsers at 1200px+ width.

10. **No notifications.** The UI does not produce desktop notifications, sounds, or alerts.

11. **No DOT rendering from CXDB.** Although `RunStarted.graph_dot` embeds the pipeline DOT source at run start time (Section 5.4), the UI reads DOT files from disk via `--dot` flags. This enables: (a) viewing the pipeline graph before any CXDB data exists (e.g., while composing the pipeline), (b) reflecting live DOT file regeneration without requiring a new CXDB run, and (c) rendering pipelines that have never been executed. The `graph_dot` field is available for future features (e.g., historical run reconstruction showing the exact graph used for a past run) but is not used for graph rendering.

12. **No browser-side SSE event streaming.** CXDB exposes a `/v1/events` Server-Sent Events endpoint for real-time push notifications (e.g., `TurnAppended`, `ContextCreated`). The browser uses polling instead for simplicity — no persistent connection management, simpler error recovery, and 3-second latency is sufficient for the "mission control" use case. Note: the server could optionally subscribe to CXDB's SSE endpoint server-side (using the upstream CXDB Go client's `SubscribeEvents` function, or an equivalent Rust HTTP client, with automatic reconnection) to reduce discovery latency — e.g., immediately triggering discovery when a `ContextCreated` event with a `kilroy/`-prefixed `client_tag` arrives, without waiting for the next poll cycle. CXDB emits both `ContextCreated` (when the context is created, with `client_tag` from the session) and `ContextMetadataUpdated` (when the first turn's metadata is extracted, with `client_tag`, `title`, and `labels` from the payload — confirmed in `events.rs` lines 27-36 and the Go client's `ContextMetadataUpdatedEvent` at `clients/go/events.go` lines 19-25). The `ContextMetadataUpdated` event is the more reliable trigger for discovery because it fires after the metadata cache and CQL secondary indexes are populated — meaning a CQL search issued after receiving this event is guaranteed to find the context. A `ContextCreated`-based trigger could race with metadata extraction, requiring a fallback poll if CQL does not yet return the context. This is not required for the initial implementation but is a lower-complexity design point than browser-side SSE, since the browser's polling architecture remains unchanged.
