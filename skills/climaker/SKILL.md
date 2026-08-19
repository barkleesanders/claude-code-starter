---
name: climaker
description: Generate a token-efficient Go CLI + MCP server for ANY API or website using the CLI Printing Press (mvanhorn/cli-printing-press). Use when the user wants to "make a CLI", "print a CLI", "wrap an API in a CLI", "generate an MCP server for an API", build an agent-native CLI, reprint/polish/publish a generated CLI, or score/dogfood/verify one. Triggers: "climaker", "printing press", "/printing-press", "make a CLI for <API>", "build a CLI from these docs", "wrap <service> as a CLI", "generate an MCP server".
---

# climaker — CLI Printing Press wrapper

`/climaker` is a memorable entry point to the **CLI Printing Press** (`mvanhorn/cli-printing-press`): a Go generator + a set of Claude Code skills that read an API's docs (or sniff a website with no docs), absorb every competing CLI/MCP feature, and print a token-efficient Go CLI **plus** an MCP server with a local-SQLite data layer, FTS5 search, compound insight commands, and agent-native flags.

**This skill does not reimplement the press.** The press ships its own well-built `/printing-press*` skills. `/climaker` (1) installs the tool if missing, then (2) routes your request to the correct underlying skill or binary subcommand. Know what not to build — wrap the real tool.

## Quick Start

```text
/climaker Notion                          # print a CLI+MCP for an API by name
/climaker https://postman.com/explore     # ...or point at a website (no spec needed)
/climaker --har ./capture.har             # ...or a HAR export from DevTools
```

If the press isn't installed yet, run the Preflight below first, then re-issue the command — it expands to the `/printing-press` skill the press provides.

## Preflight — ensure the press is installed

Two parts are required: the **binary** (`cli-printing-press`) and the **Printing Press skills** (`/printing-press …`). Check both; install whatever is missing.

```bash
# 1. Binary present?
cli-printing-press --version 2>/dev/null || echo "BINARY MISSING"

# 2. Skills present?  (look for the /printing-press slash command)
npx -y skills@latest list -g -a claude-code 2>/dev/null | grep -qi printing-press \
  && echo "SKILLS OK" || echo "SKILLS MISSING"
```

Install (does both — binary via `go install`, then refreshes all press skills):

```bash
curl -fsSL https://raw.githubusercontent.com/mvanhorn/cli-printing-press/main/scripts/install.sh | bash
```

One side only:

```bash
curl -fsSL https://raw.githubusercontent.com/mvanhorn/cli-printing-press/main/scripts/install.sh | bash -s -- --cli-only
curl -fsSL https://raw.githubusercontent.com/mvanhorn/cli-printing-press/main/scripts/install.sh | bash -s -- --skills-only
```

Codex target instead of Claude Code: append `--agent codex`.

**Prerequisites:** Go 1.26.4+, Node/npm (for `npx`), Claude Code. Verify with `cli-printing-press --version`. If `command not found` after a good `go install`, add `$GOPATH/bin` (default `~/go/bin`) to your `PATH`.

**After a skills install/refresh you MUST reload the agent session** so the new `/printing-press` slash commands load. Tell the user to restart Claude Code, then re-run their `/climaker …` request.

## Routing — map the request to the press

After Preflight passes, translate the user's intent to the underlying command and invoke it. The press's slash commands ARE the supported interface; `/climaker` is the alias that gets you there.

| User intent | Run |
|---|---|
| Make / print a CLI for an API or website | `/printing-press <name-or-URL>` |
| ...with 60% fewer Opus tokens (offload codegen to Codex) | `/printing-press <name> codex` |
| ...from a HAR capture (site uses websockets/bot-detection) | `/printing-press --har ./capture.har` |
| Reprint an existing CLI under the latest machine | `/printing-press-reprint <name>` |
| Targeted fix-up of a generated CLI (diagnostics → fixes → clean) | `/printing-press-polish <name>` |
| Publish a finished CLI to the public library (validate → PR) | `/printing-press-publish <name>` |
| Turn friction from a dogfooding session into a library PR | `/printing-press-amend [name]` |
| Score / dogfood / verify a CLI dir (any CLI, even hand-built) | binary subcommands below |
| Check which env tokens a printed CLI needs | `cli-printing-press auth doctor` |

The press also ships `printing-press-catalog`, `printing-press-import`, `printing-press-output-review`, `printing-press-retro`, and `printing-press-score` skills — surface those if the request matches (browse catalog, import a backup, review output, write a retro, score).

## Binary subcommands (verification, no LLM loop)

Run these directly on any CLI directory + spec — they don't need the skill layer:

```bash
# Two-tier quality scorecard (Grade A = 85+): infrastructure + domain correctness
cli-printing-press scorecard --dir ./my-pp-cli --spec ./openapi.json

# Dogfood: catches dead flags, dead functions, auth mismatches, invalid paths
cli-printing-press dogfood  --dir ./my-pp-cli --spec ./openapi.json

# Runtime verify against real API (read-only) or mock server
cli-printing-press verify   --dir ./my-pp-cli --spec ./openapi.json --api-key "$TOKEN"

# Baseline snapshot for the improvement cycle
cli-printing-press emboss    --dir ./my-pp-cli --spec ./openapi.json --audit-only

# Which library CLIs would benefit from new MCP spec surface
cli-printing-press mcp-audit

# Token diagnostics for printed CLIs (fingerprints only, never full tokens)
cli-printing-press auth doctor [--json]
```

## Toolbelt (local augmentation CLIs)

Real augmentation tools installed in `tools/` that climaker shells out to *around* the
press (never patched *into* the binary). Full versions, install commands, and per-stage
mapping: **`tools/README.md`**. The "why each matters" ranking: **`references/augmentation-registry.md`**.

| Tool | Shell out when… | Command |
|------|-----------------|---------|
| `har2spec.sh` (wraps **har-to-openapi** 2.5.0) | user has a `.har`/sniff capture but no docs — bridge into the press's `--spec`/`--har` path (Stage 2) | `tools/har2spec.sh capture.har openapi.json` → then `cli-printing-press scorecard --spec ./openapi.json` or `/printing-press --spec ./openapi.json` |
| **restish** v2.2.0 | polishing a printed CLI's flags/auth (mine its response-shorthand + auth schemes), or smoke-testing a real API's shape (Stage 5) | `restish --version` · `restish api configure <name>` · `restish <name> <op> -f 'body.items[].name'` |
| **ogen** v1.22.0 | hardening the typed `internal/client` — generate a reference Go client to diff vs the press output (Stage 3) | `ogen --target ./ref-ogen --package ref openapi.json` |
| **oapi-codegen** v2.7.1 | same Stage 3 cross-check, alt generator | `oapi-codegen -generate types,client -package ref openapi.json > ref_client.go` |

`mark3labs/mcp-go` and `modelcontextprotocol/go-sdk` are **libraries, not CLIs** — nothing to
install/run. They're vendored by a generated `<api>-pp-mcp` server and are PR targets for the
press's MCP template; consult the repos, don't shell out.

## What you get from one run

Each `/printing-press <api>` run produces two binaries — `<api>-pp-cli` (Cobra CLI) and `<api>-pp-mcp` (MCP server) — sharing one `internal/client`, `internal/store`, and auth. Plus research docs, verification proofs, and a Quality Score.

- **Agent-native flags on every command:** `--json`, `--select`, `--dry-run`, `--stdin`, `--csv`, `--compact`, `--quiet`, `--yes`, `--no-input`, `--no-cache`, `--no-color`. Auto-JSON when piped (no `--json` needed). Typed exit codes: `0` success, `2` usage, `3` not-found, `4` auth, `5` API, `7` rate-limited.
- **Local-first data layer:** domain SQLite tables (not JSON blobs), FTS5 search, incremental `sync` with cursors. `sync` pulls, `search` finds in ms, `sql` queries raw, `export`/`tail`.
- **Compound / insight commands** (from domain archetype): `stale`, `orphans`, `load`, `channel-health`, `reconcile`, `health`, `similar`, `trends`, `bottleneck`.

## Where output goes

- Active runs: `~/printing-press/.runstate/<scope>/runs/<run-id>/working/<api>-pp-cli`
- Published CLIs: `~/printing-press/library/<api>`
- Archived manuscripts: `~/printing-press/manuscripts/<api>/<run-id>/` (`research/`, `proofs/`, `discovery/`, `pipeline/`)

`<scope>` derives from the git checkout path so parallel worktrees don't collide. `--output` overrides the generated CLI location.

## Three input modes

1. **API name** → press resolves the OpenAPI spec (19 pre-verified APIs in catalog: Asana, Discord, GitHub, Stripe, Twilio, …).
2. **Website URL, no docs** → browser-sniff gate launches a browser, captures traffic, reverse-engineers the spec.
3. **`--spec ./openapi.json`** or **`--har ./capture.har`** → explicit spec or DevTools capture.

## Guidelines

- **Default to the press's own skills.** `/climaker` installs + routes; it does not duplicate the generation pipeline. After Preflight, hand off to `/printing-press*`.
- **Reload after a skills install** before expecting the `/printing-press` slash commands to exist.
- **Legal:** technical capability ≠ permission. Many services' ToS prohibit automated access. Confirm the user is authorized before sniffing or wrapping a service. (The press echoes this limitation; respect it.)
- **Live verify is read-only** (GET, `--limit 1`, 10s timeout, stops on 401) — it never mutates.
- **Codex fallback is automatic:** after 3 consecutive Codex failures, codegen falls back to local Opus, no intervention.
- **Browser-sniff is manual capture** — point a browser or import a HAR; the press doesn't crawl autonomously.

## Reference

- Repo: https://github.com/mvanhorn/cli-printing-press
- Library / catalog: https://github.com/mvanhorn/printing-press-library · https://printingpress.dev
- Codex notes: `docs/CODEX.md` · Pipeline contract: `docs/PIPELINE.md`
- **Augmentation registry:** `references/augmentation-registry.md` — ranked upstream repos (mcp-go, oapi-codegen, restish, har-to-openapi, …) mapped to the press pipeline stage each can strengthen. Consult when asked to make climaker/the press "stronger" or to source an integration.
