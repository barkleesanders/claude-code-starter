# climaker — Toolbelt (local augmentation CLIs)

Real, installed augmentation tools that strengthen the **CLI Printing Press**
(`cli-printing-press`, v4.20.1) pipeline. Each maps to a press pipeline stage in
`../references/augmentation-registry.md`.

> **The press binary is NOT modified.** These are standalone CLIs climaker shells
> out to *around* the press — never patches into it. Wiring an idea *into* the press
> is a PR to `mvanhorn/cli-printing-press`, not an edit to the local binary.

Installed-and-verified: **2026-06-26** on macOS 26 / arm64, Go 1.26.4, Node v26.4, npm 11.17.0.
Re-verify any tool with the `verify` command in its row.

## Pipeline stages (recap)

1. **Discovery** — resolve/navigate the OpenAPI spec.
2. **Sniff / `--har`** — website-with-no-docs → spec (weakest input path).
3. **CLI codegen core** — OpenAPI → Go Cobra CLI + typed `internal/client`.
4. **MCP server codegen** — OpenAPI → `<api>-pp-mcp` server.
5. **CLI ergonomics** — agent-native flags, response filtering, auth schemes.

## Installed tools

| Tool | Version | Stage | What it does for climaker |
|------|---------|-------|---------------------------|
| `har-to-openapi` | 2.5.0 | 2 — Sniff/`--har` | HAR capture → OpenAPI spec. Powers website-no-docs mode; the bridge into `cli-printing-press --spec`. |
| `restish` | v2.2.0 | 5 — CLI ergonomics | danielgtaylor's REST CLI (now `rest-sh/restish`). Reference + live tool for response-shorthand filtering, auth schemes, agent-native UX. |
| `ogen` | v1.22.0 | 3 — CLI core | Reflection-free, fast Go OpenAPI v3 codegen. Alt typed-client generator to compare against the press's `internal/client`. |
| `oapi-codegen` | v2.7.1 | 3 — CLI core | Battle-tested Go client/server gen from OpenAPI 3. Harden / cross-check the typed `internal/client`. |

### Install commands (exact, as run)

```bash
# har-to-openapi (npm global; bin -> /opt/homebrew/bin/har-to-openapi)
npm i -g har-to-openapi

# restish — NOTE: module moved danielgtaylor/restish -> rest-sh/restish (now /v2),
# and main() lives in cmd/restish, NOT the repo root. The registry's old
# `go install github.com/danielgtaylor/restish@latest` path is STALE.
go install github.com/rest-sh/restish/v2/cmd/restish@latest

# ogen
go install github.com/ogen-go/ogen/cmd/ogen@latest

# oapi-codegen (v2 module)
go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest
```

### Verify (each exits 0)

```bash
har-to-openapi --help     | head -1   # "Usage: har-to-openapi [input.har|-] [options]"
restish --version                     # "restish version 2.0.0-dev"  (build mod = v2.2.0)
ogen --version                        # "ogen version v1.22.0 (built with go1.26.4) darwin/arm64"
oapi-codegen --version                # prints module path; exit 0 == runnable (mod = v2.7.1)
```

> Go binaries land in `~/go/bin` (on PATH). The npm bin is a symlink at
> `/opt/homebrew/bin/har-to-openapi`. If `npm`/`npx` is missing from PATH despite
> node being present, it sits beside node: `dirname "$(which node)"`.

## How climaker invokes each tool (press pipeline mapping)

### `har-to-openapi` → via `tools/har2spec.sh` → press Stage 2
The user has a `.har` (DevTools export, or a website-sniff capture) but no docs.
Convert it to a spec, then hand the spec to the press:

```bash
# 1. HAR -> OpenAPI spec
.claude/skills/climaker/tools/har2spec.sh capture.har openapi.json

# 2. feed the spec to the press (binary or skill)
cli-printing-press scorecard --dir ./my-pp-cli --spec ./openapi.json
# or route the user to:  /printing-press --spec ./openapi.json
```
`har2spec.sh` defaults to a single collapsed spec (`--force-all-requests-in-same-spec`)
with auth-header detection (`--guess-authentication-headers`) — press-friendly. Extra
har-to-openapi flags pass through after `--`. No args → usage, exit 2.

### `restish` → press Stage 5 (ergonomics reference / smoke-test)
Two uses: (a) **reference** — when polishing a generated CLI's flags, mine restish's
response-shorthand (`restish ... -f 'body.items[].name'`) and auth-scheme handling as
the gold standard; (b) **live** — quickly hit an API a user is wrapping to sanity-check
shape before/after printing (`restish api configure <name>` then `restish <name> <op>`).

### `ogen` / `oapi-codegen` → press Stage 3 (codegen cross-check, biggest surgery)
Only when hardening the typed `internal/client` is the goal. Generate a reference Go
client from the same spec and diff against what the press emitted, to spot missing
auth providers, request builders, or type fidelity:

```bash
oapi-codegen -generate types,client -package ref openapi.json > ref_client.go
# or
ogen --target ./ref-ogen --package ref openapi.json
```
These are **comparison / PR-evidence** generators, not part of a normal `/printing-press`
run. Don't bolt their output into a generated CLI without a deliberate PR to the press.

## Libraries — NOT installed as CLIs (registry rows 1 & 3)

`mark3labs/mcp-go` (★8834) and `modelcontextprotocol/go-sdk` (★4727) are **Go libraries**,
not command-line tools — there is nothing to `go install` as a binary. They are:
- **vendored by generated code** — a press-emitted `<api>-pp-mcp` server would `import`
  one of them for protocol-correct MCP, and
- **PR targets** — the highest-leverage upstream change is basing the press's MCP server
  template on a real MCP lib instead of a hand-rolled server.

To consult their API, read the repos directly (`gh repo view mark3labs/mcp-go`), don't
try to run them.

## Install ledger (per-tool result, 2026-06-26)

| Tool | Result | Proof |
|------|--------|-------|
| har-to-openapi 2.5.0 | ✅ installed | `npm i -g` → `added 55 packages`; `--help` exit 0 |
| restish v2.2.0 | ✅ installed | first `go install` of repo root failed ("not a main package"); fixed to `cmd/restish`; `--version` exit 0 |
| ogen v1.22.0 | ✅ installed | `go install .../cmd/ogen`; `--version` exit 0 |
| oapi-codegen v2.7.1 | ✅ installed | `go install .../v2/cmd/oapi-codegen`; `--version` exit 0 |

No tool failed. The only friction was restish's stale registry path (documented above).
