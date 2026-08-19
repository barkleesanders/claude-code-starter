# climaker — Augmentation Registry

Upstream repos whose ideas/code can make the **CLI Printing Press** (`mvanhorn/cli-printing-press`)
stronger, mapped to the press's pipeline stage they upgrade. The press is third-party — these are
**integration / idea sources**, not drop-in patches. Wiring one in = a PR to the press (or to a
generated CLI), never an edit to the local binary. climaker's job is to *know* and *route to* them.

> Star counts are live as of **2026-06-26** (`gh api repos/<r>`). Re-verify before citing —
> run `gh api "repos/<owner>/<name>" --jq '.stargazers_count'`.

## Press pipeline stages (what can be upgraded)

1. **Discovery** — resolve/navigate the OpenAPI spec (esp. huge specs).
2. **Sniff / `--har`** — website-with-no-docs → spec (the weakest input path).
3. **CLI codegen core** — OpenAPI → Go Cobra CLI + typed `internal/client`.
4. **MCP server codegen** — OpenAPI → `<api>-pp-mcp` server.
5. **CLI ergonomics** — agent-native flags, response filtering, auth schemes.

## Ranked registry (by GitHub stars, verified 2026-06-26)

| ★ | Repo | Lang | Stage | How it strengthens climaker |
|---|------|------|-------|------------------------------|
| 8834 | [mark3labs/mcp-go](https://github.com/mark3labs/mcp-go) | Go | MCP core | Most-starred Go MCP impl — base the emitted `<api>-pp-mcp` on it instead of a hand-rolled server. |
| 8417 | [oapi-codegen/oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) | Go | CLI core | Battle-tested Go client/server gen from OpenAPI 3 — harden the typed `internal/client`. |
| 4727 | [modelcontextprotocol/go-sdk](https://github.com/modelcontextprotocol/go-sdk) | Go | MCP core | **Official** Go MCP SDK (Google collab) — standards-track alternative to mark3labs for emitted MCP servers. |
| 3779 | [microsoft/kiota](https://github.com/microsoft/kiota) | C# | CLI core | Multi-language OpenAPI client gen; reference for auth providers + request builders (ideas, not Go code). |
| 2093 | [ogen-go/ogen](https://github.com/ogen-go/ogen) | Go | CLI core | Reflection-free, fast Go OpenAPI v3 codegen — alt to oapi-codegen for the typed client. |
| 1318 | [rest-sh/restish](https://github.com/rest-sh/restish) | Go | CLI ergonomics | danielgtaylor's REST CLI — gold standard for response-shorthand filtering, auth schemes, agent-native UX. |
| 894 | [janwilmake/openapi-mcp-server](https://github.com/janwilmake/openapi-mcp-server) | TS | Discovery | "Wade through complex OpenAPIs in simple language" — helps the research phase on huge specs. |
| 272 | [higress-group/openapi-to-mcpserver](https://github.com/higress-group/openapi-to-mcpserver) | Go | MCP codegen | Direct prior art: OpenAPI → MCP server config in Go. |
| 214 | [danielgtaylor/openapi-cli-generator](https://github.com/danielgtaylor/openapi-cli-generator) | Go | CLI codegen | The original OpenAPI→CLI generator (superseded by Restish); pattern source. |
| 151 | [taskade/mcp](https://github.com/taskade/mcp) | TS | MCP codegen | OpenAPI→MCP codegen, multi-client. |
| 132 | [jonluca/har-to-openapi](https://github.com/jonluca/har-to-openapi) | TS | Sniff/`--har` | Directly powers website-no-docs mode: HAR → OpenAPI. |
| 107 | [twilio-labs/mcp](https://github.com/twilio-labs/mcp) | TS | MCP codegen | OpenAPI→MCP tool generator (whole Twilio API). |
| 39 | [cnoe-io/openapi-mcp-codegen](https://github.com/cnoe-io/openapi-mcp-codegen) | — | MCP codegen | OpenAPI→MCP server code generator. |
| 33 | [criteo/openapi-to-mcp](https://github.com/criteo/openapi-to-mcp) | — | MCP codegen | MCP server for your API. |

## Wire-first recommendation (highest leverage → most surgery)

1. **jonluca/har-to-openapi** — smallest, most targeted; plugs straight into `--har`/sniff mode, the press's weakest input path. Low risk, high fit.
2. **mark3labs/mcp-go** (or the official **go-sdk**) — base the emitted MCP server on a real Go MCP lib for protocol correctness + future-proofing.
3. **rest-sh/restish** — mine its response-filtering shorthand + auth-scheme handling to upgrade the press's agent-native flag set.
4. **oapi-codegen / ogen** — only if hardening the typed `internal/client` becomes a priority; biggest surgery.

## How to act on this

- These are upstream PR targets for `mvanhorn/cli-printing-press`, or libraries a *generated* CLI could vendor. Do **not** patch the local `cli-printing-press` binary.
- To propose an integration, open an issue/PR on the press repo citing the row above.
- Re-run the survey any time:
  ```bash
  for r in mark3labs/mcp-go oapi-codegen/oapi-codegen modelcontextprotocol/go-sdk \
           microsoft/kiota ogen-go/ogen rest-sh/restish janwilmake/openapi-mcp-server \
           higress-group/openapi-to-mcpserver danielgtaylor/openapi-cli-generator \
           jonluca/har-to-openapi; do
    gh api "repos/$r" --jq '"\(.stargazers_count)\t\(.full_name)\t\(.description)"'
  done | sort -rn
  ```
