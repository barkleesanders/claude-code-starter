---
name: notion-link-triage
description: Auto-fetch titles, classify, and dedupe links saved to the user's Notion link-inbox database. Use when the user asks to triage their Notion links, inbox-zero a Notion link database, process saved tweets/posts/articles, or auto-action a Notion page they pasted. Triggers on "triage notion links", "inbox-zero notion", "process notion links", "dedupe notion", or pasting a Notion DB URL with v= query param.
---

# Notion Link Triage

Auto-titles and classifies untitled links in the user's Notion link-inbox database, then surfaces high-signal entries as Linear-issue suggestions.

## When to use

- User says "triage my notion links", "process my notion inbox", "inbox-zero notion"
- User pastes a Notion database URL (`?v=` in URL = database view) and says "look at these"
- A new link was added to the inbox and the user wants it auto-actioned
- User wants to dedupe a Notion link database

## What this does

For every row in the Notion DB:

1. **Auto-title** — if the title is blank or equals the URL:
   - X / Twitter URLs: `publish.twitter.com/oembed` (no auth needed)
   - Other URLs: scrapes `og:title` then `<title>` tag
2. **Auto-tag** — multi-select tags: `ai`, `coding`, `tool`, `aiva`, `va`, `marketing`, `tax`, `nonprofit`, `design`, `personal-finance`, `event`, `shopping`, `startup`, `meme`, `x-post`, `ig-post`, `github`, `video`, `meta-ad`
3. **Dedupe detection** — strips `utm_*`, `fbclid`, `s=12`, etc. and groups by canonical URL
4. **Linear suggestions** — appends a JSONL row to `~/tools/notion-link-triage/suggestions.jsonl` for any entry that hits a high-signal tag (`tool`, `aiva`, `coding`, `ai`, `marketing`, `tax`, `nonprofit`)

## Source database

- DB ID: `1c207f660378818c81a1cfbd2323746b`
- URL: <https://www.notion.so/1c207f660378818c81a1cfbd2323746b?v=1c207f66037881e990ae000c5c56cbd8>
- Schema: `Name` (title), `URL`, `Tags` (multi_select), `Date`, `Created`
- Auth: Composio Notion (already connected, see `node ~/tools/<your-mcp>/client.cjs status`)

## Common invocations

```bash
# Dry-run preview on first 10 untitled rows (no writes)
python3 ~/tools/notion-link-triage/triage.py --dry-run --limit 10

# Backfill: title + tag every untitled row (default behavior)
python3 ~/tools/notion-link-triage/triage.py

# Process only links added since a date (good for daily incremental)
python3 ~/tools/notion-link-triage/triage.py --since 2026-04-25

# Force-reprocess a single row by page_id
python3 ~/tools/notion-link-triage/triage.py --row <page_id> --force

# Show duplicate groups, no writes
python3 ~/tools/notion-link-triage/triage.py --show-dupes
```

## Workflow: full inbox-zero pass

1. Show current state: `python3 ~/tools/notion-link-triage/triage.py --show-dupes`
2. Dry-run sanity check on 10 rows → eyeball the output
3. Run the full backfill — takes ~2-3 min for ~280 rows (0.4s sleep between calls)
4. Review `~/tools/notion-link-triage/suggestions.jsonl` — each line is a candidate for Linear
5. Group suggestions by tag → propose Linear issues to the user → batch-create via `mcp__claude_ai_Linear__save_issue`

## Workflow: action a single new link

When user pastes a Notion link URL or adds a new entry:

1. Find the page_id (it's the last URL segment after the title slug, with dashes)
2. `python3 ~/tools/notion-link-triage/triage.py --row <page_id>`
3. Read `suggestions.jsonl` tail to see the classification
4. If it hit a high-signal tag, propose the Linear issue title + project + priority

## Tag → Linear project mapping

| Tag | Suggested Linear team / project |
|---|---|
| `coding`, `tool`, `ai`, `github` | Personal → Coding Work |
| `aiva`, `va`, `marketing` | AIVA → Marketing |
| `tax`, `nonprofit`, `legal` | AIVA → Admin Work (or Personal → Admin Work) |
| `design` | Personal → Coding Work (UI inspiration) |
| `event`, `shopping`, `meme`, `personal-finance` | Personal → Personal Recurring (or skip) |

Rule: **never auto-create Linear issues**. Always show the user the proposed title + tags + project, then create only the approved ones.

## Daily cron (optional)

If user wants this automated, add a launchd plist on the Mac OR a systemd timer on the VPS that runs the `--since "$(date -v-2d +%Y-%m-%d)"` pass nightly. Per the user's `LLM-vs-Shell` rule this is pure shell — use systemd timer on VPS, **not** `openclaw cron`. Pattern:

```
[Unit]
Description=Notion link triage incremental
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $HOME/notion-link-triage/triage.py --since YYYY-MM-DD
[Install]
```

Plus a Composio Gmail alert on failure.

## Composio actions used

- `NOTION_QUERY_DATABASE` — paginated fetch of all rows
- `NOTION_FETCH_ROW` — verify a single row after update
- `NOTION_UPDATE_PAGE` — write `Name` (title) + `Tags` (multi_select) properties

No new OAuth setup — uses the existing Composio Notion connection.

## Limitations / known gotchas

- **IG posts**: Instagram returns a login wall to non-authed clients, so `og:title` scrape often fails. Title falls back to URL.
- **X cookies stale** (`~/.cookies/x.com`): we sidestep this with oEmbed — no auth needed for public tweets.
- **Rate limit**: 0.4s sleep between rows. ~280 rows → ~2 min. Bump up if oEmbed starts 429-ing (it hasn't yet).
- **Duplicate detection is by canonical URL only** — doesn't compare titles/content. A tweet quoted in two different X URLs won't merge.
- **Tag rules are keyword-based**, not semantic. Iterate `TAG_RULES` in `triage.py` to improve.

## Quick sanity check before reporting done

```bash
# Did the title and tags actually persist?
node ~/tools/<your-mcp>/client.cjs execute NOTION_FETCH_ROW '{"page_id":"<id>"}' \
  | grep -E "plain_text|multi_select"
```

## Source files

- `~/tools/notion-link-triage/triage.py` — the script
- `~/tools/notion-link-triage/suggestions.jsonl` — append-only Linear-issue candidates
- This skill: `~/.claude/skills/notion-link-triage/SKILL.md`


## Ground-truth gate (MANDATORY)

Before this skill asserts a stakes-bearing fact or takes any outward/irreversible action, apply the global standard — verify against a **primary source fetched now**, never a cached/remembered value. Full standard: `~/.claude/skills/shared/ground-truth-standard.md`.

**Verify live before you act or assert (this skill):**
- Read the live Notion state before modifying; confirm the target page/block; explicit approval for destructive edits.

Then: dry-run where possible, show the user exactly what will be sent/filed/asserted, get explicit chat approval for any outward action (per CLAUDE.md), capture the confirmation, and write any verified fact back into its source doc. State uncertainty as uncertainty; never assert plausible-but-unverified as fact.
