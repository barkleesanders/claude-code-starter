---
name: csci
description: >-
  Control the user's local Claude for Life Sciences ("Claude Science" / operon) app from the
  Claude Code CLI via the `csci` command. Use when the user wants to drive the science app —
  ask/continue a research conversation with the OPERON agent, list or read projects, pull
  artifacts/results, inspect the 33 wired connectors (Google Drive, Gmail, Calendar + 24 bio
  databases like BioMart/PubMed/ChEMBL/ClinVar), check agents/skills/kernels, or search synced
  data. Triggers: "csci", "claude science", "the science app", "my life sciences app", "ask
  OPERON", "science project", "localhost:8765", "operon", "run this on my genomics/DNA data".
  Not for general bioinformatics Q&A (use the app's own agent for that) — this is the control layer.
---

# csci — control the local Claude Science (operon) app from Claude Code

`csci` is a purpose-built CLI (generated via the Printing Press, then hand-polished for
operon's cookie/CSRF auth + WebSocket agent-drive) that lets Claude Code fully drive the
local **Claude for Life Sciences** daemon running at `http://localhost:8765`. Every action
the web UI chat box can take, `csci` can take — from the terminal.

- Binary: `csci` (alias `csci-pp-cli`) on PATH at `~/go/bin/csci`.
- Source: `~/.claude-science-cli-build/run/working/csci-pp-cli/` · ground-truth API map: `~/.claude-science-cli-build/GROUND-TRUTH.md`.
- MCP server (optional, for native Claude Code tools): `~/.claude-science-cli-build/run/working/csci-pp-cli/build/csci-pp-mcp-darwin-arm64.mcpb`.

## Prerequisites (check first, every session)

1. **Daemon running?** `claude-science status` must show `"running": true`. If not: `claude-science serve --app --port 8765 --detached` (or tell the user to start it).
2. **Session valid?** Run **`csci login`** once per session (or when any command returns 401). It shells out to `claude-science url`, establishes the nonce session, and caches the `operon_auth` + `operon_csrf` pair to `~/.config/csci-pp-cli/config.toml`. Cheap and idempotent — just run it at the start.

If a command returns an auth error, re-run `csci login` and retry. That is the entire auth story.

## The flagship: drive the research agent

```bash
# Start a NEW conversation in a project (streams the agent's reply, ~30-120s for real work):
csci ask "Analyze the CRISPR screen data in my Drive folder and propose a QC plan" --project proj_186c20c79516

# CONTINUE a conversation (pass the frame id printed after the last reply):
csci ask "Now generate the figure" --project proj_186c20c79516 --frame <frame-id>

# Fire-and-forget (don't wait for the reply — returns the frame id immediately):
csci ask "kick off the long alignment" --project proj_186c20c79516 --no-wait

# Machine-readable (returns {"frame_id","reply"}):
csci ask "summarize connectors" --project proj_x --json
```

`ask` POSTs the turn to `POST /api/request` (target agent `OPERON`, model `claude-opus-4-8`,
effort `high`, thinking on by default), then polls the frame until the daemon reports it's done
and prints the assistant's text. Flags: `--frame` (continue), `--model`, `--effort low|medium|high`,
`--no-thinking`, `--ultra`, `--no-wait`, `--wait-timeout 5m`. **Every `ask` spends real Anthropic
quota and runs the agent — confirm intent before firing on the user's behalf for anything non-trivial.**

The raw endpoint is also available as `csci request --project-id <id> --input-data-request "<msg>"`
(no streaming — returns `{status:accepted}`); prefer `ask` for interactive control.

## Reading state (safe, no side effects)

```bash
csci projects list                 # list projects (proj_...)
csci projects dashboard            # projects + counts + recent activity
csci projects get <proj_id>        # one project incl. onboarding context
csci projects artifacts <proj_id>  # results / files / plots produced in a project
csci artifacts versions <artifact_id>            # versions of an artifact
csci artifacts get-version <version_id>          # download a result/file version
csci mcp-servers list-connectors   # the 33 connectors (Drive, Gmail, Calendar + 24 bio DBs)
csci agents                        # OPERON + subagents (BOOKMARKER/REVIEWER/...) and their skills
csci models                        # available models
csci skills catalog                # skills the agent can use (alphafold2, boltz, proteinmpnn, ...)
csci environments                  # python/r/operon-mcp kernel status
csci frames messages <frame_id> --limit 200      # full transcript of a conversation
csci frames trace-shallow <frame_id>             # steps / tool calls
csci frames verification <frame_id>              # reviewer/verifier findings
csci memory categories             # agent memory
csci me · csci health · csci usage # identity / daemon health / token+cost velocity
```

All read commands support `--json`, `--select <fields>`, `--compact`, `--limit`. Add `--agent`
for the full non-interactive JSON preset. `csci sync` mirrors data into local SQLite and `csci search`
does offline FTS — useful for large artifact sets.

## How to use this skill

1. **Verify prereqs** (daemon up, `csci login`).
2. **Find the project**: `csci projects list` → grab the `proj_...` id. the user's onboarding project analyzing his genealogy/DNA data is `proj_186c20c79516`.
3. **Drive or read**: use `csci ask` to make the agent do work; use the read commands to inspect what it produced.
4. **Pull results**: `csci projects artifacts <proj>` → `csci artifacts get-version <vid>` to retrieve figures/files/tables the agent generated.
5. **Chain with the user's other tooling**: the science app already has Google Drive/Gmail/Calendar connectors, so the agent can reach his files directly; for anything the app can't do, combine `csci` output with Claude Code's own connectors/skills.

## Notes & gotchas

- **Auth is session-cookie based** (not a bearer token). `csci login` is the only setup. Sessions expire — re-login on 401.
- **`ask` is the write path** and goes through operon's CSRF gate (`x-operon-csrf` header + `Origin`), handled automatically once logged in.
- **KNOWN BUG (`csci ask` early-return, 2026-07-01):** `streamFrameReply` treats `/streaming`==null as done, but null also occurs *between tool calls* and *before a slow agent starts*, so `ask` on a long multi-tool OPERON run returns an EMPTY reply while the agent is still working. **Workaround until fixed:** use `--no-wait`, capture the `frame_id`, then poll the frame directly — wait for the assistant text to STABILIZE (unchanged for 2 polls) AND `/streaming`==null, concatenating ALL assistant text blocks. Fix pending: make `streamFrameReply` wait for true completion (frame status ≠ `processing`), not the first null.
- **OPERON network-approval sandbox + chrome-auth (going forward):** the daemon sandboxes outbound network; when OPERON runs code hitting an external host (gnomAD/PubMed/NCBI/EBI), the call blocks pending a UI **approval card** — and grants are **UI-only, no CLI/API** (per `claude-science --help`). If a deep analysis stalls with the frame stuck `processing` and no output: (1) `/chrome` → open `http://localhost:8765/projects/<pid>` in the REAL Chrome (fcdp) (mint a nonce with `claude-science url`), find the pending network-grant card (conversation view or **Customize → Permissions**) and approve it, then re-poll the frame; OR (2) the durable fix — restart the daemon with pre-granted hosts / `serve --dangerously-skip-approvals` **only for prompts you wrote and trust** (removes every network+file+tool check — never on untrusted input). The user authorized chrome-based approval of these local research-app cards. If no card is surfaced and the frame stays `processing` a long time, the analysis may just be slow (multi-tool gnomAD/PubMed runs take 10-30 min) — keep polling before concluding it's stuck.
- **Reply rendering** polls `/api/frames/:id/streaming` (null = done) then reads the last assistant message; long runs show a `.` heartbeat on stderr. Token-by-token live streaming via the WebSocket `/api/ws` (`view_session` → `text_chunk`) is in `GROUND-TRUTH.md` as a future upgrade.
- **This is the control layer, not a bio expert.** Don't answer genomics/protein questions yourself — route them to the agent via `csci ask`, which has the bio connectors + skills (AlphaFold2, Boltz, ProteinMPNN, DiffDock, literature-review, etc.).
- To expose `csci` as native Claude Code MCP tools instead of shell commands, install the `.mcpb` bundle above into Claude Desktop / configure the `csci-pp-mcp` server.
