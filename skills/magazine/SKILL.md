---
name: magazine
user-invocable: true
description: "Render any content as a magazine-style HTML editorial — single self-contained file, Fraunces + Inter typography, each section gets its own distinct full-viewport spread (hero, dark midnight, rose alert stamp, terminal, academic drop-cap, big-stat, vinyl vintage, poster, scientific, etc.). Use when the user asks to 'magazine-style', 'editorial layout', 'morning edition', 'render as a zine', or wants any list / digest / report / minutes / curated content rendered as a designed publication instead of raw text. Triggers: 'magazine', 'morning edition', 'editorial', 'newsletter', 'zine', 'magazine-style', 'render this as a magazine', 'make it look like a magazine', 'beautiful html', 'designed digest'. Especially good for: HN/RSS feeds, meeting minutes, research summaries, project status reports, op-ed drafts, link roundups, daily briefings."
---

# Magazine

Turn any content into a single self-contained HTML magazine where each item gets its own full-viewport spread with distinct typography, color, and layout treatment. Inspired by editorial design (NYT Magazine, The Atlantic, Wired, Pitchfork, MIT Technology Review).

## When to use

- User asks for a "morning edition," "daily digest," "newsletter," "magazine," "zine," or "editorial" version of any content
- User wants a list of items (stories, projects, meetings, links) rendered with real visual variety, not as a markdown list
- User wants meeting minutes, research, or reports presented as if for publication, not for a tracker
- User wants something to feel "designed" — different background colors, layout, numeral treatment per item
- User specifically references the previous Morning Edition output and asks to recreate the format for a different topic

## Don't use for

- Plain working documents (memos, code review, technical specs) — use plain markdown / Google Docs
- Single-screen things — magazine layout is for multi-spread digests and lists
- When the user wants editable Google Docs — magazine output is HTML, not Docs-friendly

## Required reading before generating

Before writing any output, read these in order:

1. `references/design-system.md` — fonts, color palettes, type scales, layout chrome
2. `references/spreads.md` — full library of spread treatments with copy-paste CSS
3. `references/print-pdf.md` — **MANDATORY** print stylesheet + `--pdf` flag handling (every magazine HTML must include it so Chrome → PDF produces no blank pages)
3. `references/examples.md` — how to invoke for HN / minutes / research / link roundups

The treatments library is the value. Don't reinvent — pick from the catalog.

## Core flow

1. **Identify source** — what is being rendered? A live feed (HN, RSS), a document (minutes, transcript), or a curated list?
2. **Curate / score** — if the source is a feed, apply taste filters (skip lists, lean-into lists). If the source is a document, extract 8–12 items worth their own spread.
3. **Pick treatments** — assign each item a spread treatment from the catalog based on its tone (security → dark midnight, creative → magazine cover, civic → poster, dev tools → terminal, science → scientific, urgent issue → rose alert stamp, etc.).
4. **Generate HTML** — single self-contained file using the design-system shell. Each item is its own `<section class="spread sNN">` with full viewport height.
5. **Save** — to `~/Downloads/<slug>.html` by default unless user specifies a path. Optionally upload to Google Drive folder if user asks.
6. **Open / report** — `open` the file in the user's browser and report the path + a one-line summary of treatments used.

## Style commitments (non-negotiable)

- **Fonts**: Fraunces (serif display) + Inter (sans body) loaded via Google Fonts. Optional: JetBrains Mono for terminal/code spreads, Space Grotesk for scientific spreads.
- **No small text anywhere.** Body minimum 22px. Spread display sizes use `clamp()` ranging from 48px → 200px+.
- **Each spread is its own world.** No two spreads share the same background color, type treatment, AND numeral treatment. Variety is the whole point.
- **Self-contained.** All CSS inline in `<style>`. No external JS required (except Google Fonts link). User opens one file, it works forever.
- **Numerals matter.** Every spread has a giant numeral (01, 02, 03…) with its own treatment per the spreads catalog.
- **Source line on every spread.** Small (but not tiny — 18px+) attribution line at the bottom: source name + URL + any metadata.

## Curation rules (when input is a feed)

If the user has previously stated a taste profile (love list / skip list), apply it. Otherwise infer from context:

- **Lean in**: AI tools, dev tools, privacy, security, weird science, creative software, civic transparency, infrastructure, anything actionable.
- **Skip**: crypto pumps, generic political flame wars, layoff hot-takes, "I quit my job," dating apps, fundraising press releases, generic Show HN unless useful.
- **Flag "applies to you"** when a story directly intersects something the user is actively working on — use the red rotated badge from the design system.

If you're unsure of taste, ask once at the start. Don't ask per-item.

## Output requirements

- File path: `~/Downloads/<slug>-YYYY-MM-DD.html` unless overridden
- Title in `<title>` should be evocative ("The Morning Edition — April 15, 2026", "Field Notes — SFPUC CAC, April 14")
- Include a masthead spread (cover) and a colophon spread (sign-off) — these are part of the form
- After generation: `open` the file, then in chat give a 5-line max summary (file path, what's in it, treatment list)

## Mandatory follow-up

After the file opens, ask the user if they want a recurring routine to generate this on a schedule (cron, Claude Code Routine, or `loop` skill). Magazine output is high-effort — automating the recurring case is the whole win.
