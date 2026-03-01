# Postmortem Analysis

## Task

Analyze the failure and write a postmortem that guides the next repair iteration.

## Context

One of the pipeline stages failed. Read the failure diagnostics and create `.ai/postmortem_latest.md` to guide the implement node's repair iteration.

## Files to Read

- `.ai/spec.md` — Original specification
- `.ai/review_final.md` — If review failed, read this for specific AC failures
- Source files that failed (`ui/main.go`, `ui/index.html`, `ui/go.mod`)

## Files to Write

- `.ai/postmortem_latest.md` — Root cause analysis and repair guidance

## What to Do

1. Identify the failure mode:
   - **Format failure** — `gofmt` reports files needing formatting
   - **Vet failure** — `go vet` reports issues (e.g., invalid struct tags, unreachable code, shadowed variables)
   - **Build failure** — `go build` fails (compilation error, missing package, import cycle)
   - **Test failure** — `go test` panics or assertions fail
   - **Review failure** — Missing functionality, wrong behavior, incomplete spec coverage (see `.ai/review_final.md`)

2. Root cause analysis:
   - What specific code caused the failure?
   - What requirement from the spec was violated?
   - Is this a new failure or a repeat?

3. Write `.ai/postmortem_latest.md` with:
   - **Summary** — One-sentence description of failure
   - **Evidence** — Exact error messages, line numbers, failing test output
   - **Root Cause** — Technical explanation
   - **Repair Guidance** — Specific steps for the implement node:
     - Which files to modify (`ui/main.go`, `ui/index.html`, or `ui/go.mod`)
     - What to change (be specific: file + line range + what to fix)
     - What NOT to change (preserve working code)
   - **Verification** — How to confirm the fix worked

4. Be specific. Don't say "fix the DOT parser", say "main.go line 142: `parseNodeAttrs` does not handle `+` string concatenation — add a loop that joins consecutive quoted fragments when a `+` token follows a closing quote"

## Acceptance Checks

- `.ai/postmortem_latest.md` exists
- Contains all required sections
- Repair guidance is specific and actionable
- Identifies which files need changes

## Status Contract

Write status JSON to `$KILROY_STAGE_STATUS_PATH` (absolute path). If unavailable, use `$KILROY_STAGE_STATUS_FALLBACK_PATH`.

Success: `{"status":"success"}`
Failure: `{"status":"fail","failure_reason":"<reason>","details":"<details>","failure_class":"deterministic"}`

Do not write nested `status.json` files after `cd`.
