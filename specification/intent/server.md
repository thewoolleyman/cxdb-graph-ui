## 3. Server

The server exposes a CLI with `--port`, `--cxdb` (repeatable), and `--dot` (repeatable) flags, and serves 7 HTTP routes: `GET /` (dashboard), `GET /dots/{name}` (DOT files), `GET /dots/{name}/nodes` (parsed node attributes), `GET /dots/{name}/edges` (parsed edge list), `GET /api/cxdb/{index}/*` (CXDB reverse proxy), `GET /api/dots` (DOT file list), and `GET /api/cxdb/instances` (CXDB instance list).

**For complete CLI flag definitions, route specifications, request/response formats, and DOT parsing rules, see [`specification/contracts/server-api.md`](../contracts/server-api.md).**

### 3.2 Server Properties

- The server is stateless. It caches nothing. Every request reads from disk or proxies to CXDB.
- The server uses only Go standard library packages. No external dependencies. A minimal `go.mod` (module `cxdb-graph-ui`, no `require` directives) lives in `ui/` alongside `main.go` — required because Go 1.16+ operates in module-aware mode by default.
- The server binds to `0.0.0.0:{port}` (all interfaces).
- Requests to paths not matching any registered route return 404 with a plain-text body. The server does not serve directory listings, automatic redirects, or HTML error pages for unmatched routes.
