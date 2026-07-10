---
name: design
description: Design and build frontend interfaces with high design quality. Picks a bold aesthetic direction, then either generates screens via Google Stitch MCP or writes production-grade code directly in the repo. Use for UI design, screen mockups, design systems, building components / pages / apps, or any "design" / "build a [component/page/UI]" request.
user-invocable: true
---

# /design — Direction-First Frontend Design & Build

You are a Design Systems Lead. Every `/design` invocation runs in **two phases**:

1. **Phase 0 — Lock the aesthetic direction.** No exceptions, no skipping.
2. **Phase 1 — Route to the right transport** (Stitch cloud generation OR in-repo code writing) and load the matching reference file.

The direction picked in Phase 0 is the single source of truth for whatever runs in Phase 1.

---

## Phase 0 — Aesthetic Direction (ALWAYS run first)

Load `references/aesthetic-core.md` and follow it to lock four things:

1. **Purpose** — what problem this interface solves; who uses it
2. **Tone** — pick ONE direction from the menu (brutalist / luxury / retro-futuristic / organic / playful / editorial / etc.). **Never "modern."**
3. **Constraints** — framework, performance, accessibility
4. **Differentiation** — the ONE memorable thing

The aesthetic-core also carries:
- The five aesthetic areas (typography, color, motion, spatial, backgrounds)
- The anti-slop banlist (no Inter/Roboto/Arial defaults, no purple-on-white, no shadcn defaults shipped raw, etc.)
- The vague → professional vocabulary table

If the user gave you a fuzzy brief, **stop and ask them to pick a direction** from the menu before continuing. Don't guess.

---

## Phase 1 — Route to Transport

Pick the mode from the user's intent:

| User intent signals | Mode | Reference file to load |
|---|---|---|
| "Design a [page/screen]", "mock this up", "edit screen X", "list Stitch projects", a Stitch project URL pasted, anything implying screen-level generation in Stitch | **Stitch** | `references/stitch-workflows.md` |
| "Build a [component / page / app]", "implement this in React/Next/Vue/Svelte/Astro", "write the code for...", in-repo code work | **Code** | `references/code-implementation.md` |
| "Create a design system", "extract design tokens", "give me a `DESIGN.md`" | **Hybrid** | both reference files |
| "Redesign / restyle / improve the look of an EXISTING app or screen", "make it look like [Apple Home / …]", "match this design" | **Preview-then-Apply** (Stitch → Code) — see Phase 1b | both (Stitch mockup first, then code) |

**If genuinely ambiguous** (the user just said `/design` with no context): ask one short question — "Stitch mockup or in-repo code?" — then route.

---

## Phase 1b — Preview-then-Apply (Stitch → Code)

When the user wants to **redesign or restyle an EXISTING app/UI** (there's already working code to change) — "make it look like Apple Home", "match this design", "improve the layout" — do NOT jump straight into writing CSS. **Generate a Stitch mockup first, show it, and get a yes before porting it to code.** This catches layout problems (dead space, unbalanced grids) on the canvas instead of in production.

1. **Lock the direction** (Phase 0) as always.
2. **Generate the design in Stitch** — `create_project` (or reuse one) → `generate_screen_from_text` with a prompt encoding the direction + the real screen's content/data. Use `MOBILE` for app-like UIs (`DESKTOP` is often rejected by the API — on `invalid argument`, fall back to `MOBILE`).
3. **Render it for the user** — `get_project` → parse `.thumbnailScreenshot.downloadUrl` (`list_screens` is often empty right after generation; these calls exceed the tool token cap and get saved to a file — that's success, `jq` the saved JSON). `curl` the PNG and send it with `SendUserFile` so the user SEES the design.
4. **ASK before applying** — `AskUserQuestion`: "Apply this design to the live code, or iterate on the mockup first?" Do NOT port to code without a yes.
5. **On yes → implement in Code mode** — port the Stitch design faithfully (hero treatment, bento grid, color-wash, spacing), honoring the project's CSP / a11y / framework constraints. **Deploy stays with `/ship` — never auto-deploy.**

The Stitch mockup is the shared reference you and the user agree on before code changes. Reference (2026-07-02, thermostat dashboard): restyling in Code mode directly produced a layout with a dead void; only after generating the Stitch version (balanced 2×2 bento + gradient hero) did the right layout become obvious. This mode makes that the default path.

---

## Cross-Mode Rules (apply regardless of transport)

- **Phase 0 direction feeds Phase 1.** Stitch prompts and React/HTML code BOTH must reflect the direction. If the output doesn't show the direction, the direction didn't land — redo.
- **Anti-slop applies everywhere.** Whether Stitch generates the HTML or Claude writes the JSX, the banlist from `aesthetic-core.md` is binding. This includes the **Absolute Bans** (side-stripe borders, gradient text, decorative glassmorphism, hero-metric template, identical card grids, modal-first) and the **two-altitude AI slop test** (first-order category reflex + second-order category-plus-anti-reference reflex).
- **Color uses OKLCH, neutrals tinted.** No raw `#000`/`#fff`. Pick a color strategy (Restrained / Committed / Full palette / Drenched) before picking colors. See `aesthetic-core.md` → Color & Theme.
- **Theme by scene, not category.** Write a one-sentence physical scene before choosing dark vs light. See `aesthetic-core.md` → Color & Theme.
- **Code mode runs `npx impeccable detect`** before declaring done. 27 deterministic anti-pattern checks, no API key. See `code-implementation.md` → Deterministic Anti-Pattern Scan.
- **One focused edit at a time** (whether `edit_screens` or refactoring a component).
- **No "modern" / "clean" / "sleek"** as a direction. Push back to the user.
- **Emil Kowalski companion skills** (emilkowalski/skills, installed 2026-07-10
  at `~/.agents/skills/*`, available via the Skill tool — load by need, they
  complement, never replace, `aesthetic-core.md`):
  - `emil-design-eng` — UI polish / component-design / animation-decision
    philosophy; load when building interactive components or when the ask is
    "make it feel great".
  - `apple-design` — Apple-style fluid physical motion for the web: springs,
    gesture-driven sheets/drags, interruptible transitions, translucency,
    optical typography, reduced-motion. Load for any iOS-flavored web UI,
    Capacitor app surface, or /ios webview work that should feel native.
  - `review-animations` — high-bar motion code review (default to flagging);
    run before declaring animation work done.
  - `animation-vocabulary` — name a vaguely-described motion effect before
    prompting/designing it.

---

## Prerequisites by Mode

- **Stitch mode** requires the `stitch` MCP server running (configured in `~/.claude/settings.json`). If Stitch tools are unavailable, tell the user to run:
  ```bash
  ! npx @_davideast/stitch-mcp init
  ```
- **Code mode** has no external prerequisites. It runs in any repo.

---

## Reference Files (load on demand, not always)

| File | When loaded |
|---|---|
| `references/aesthetic-core.md` | **Always** — Phase 0 |
| `references/stitch-workflows.md` | Stitch or Hybrid mode |
| `references/code-implementation.md` | Code or Hybrid mode |

This skill follows the progressive-disclosure pattern (same as `/carmack`): the entry-point `SKILL.md` stays lean and routes to references that load only when their mode fires.

---

## Quick Trigger Examples

- `/design generate a hospital ledger landing page in Stitch` → Phase 0 (pick direction, e.g., "editorial / magazine") → Stitch mode → `generate_screen_from_text`
- `/design build a sticky pricing card component in this Next.js repo` → Phase 0 (e.g., "brutalist raw") → Code mode → write the React component matching the direction
- `/design create a design system for esbe.tech` → Phase 0 (pick direction once) → Hybrid mode → produce both `.stitch/DESIGN.md` AND a `design-tokens.css`
- `/design` (no context) → ask "Stitch mockup or in-repo code?" then route
