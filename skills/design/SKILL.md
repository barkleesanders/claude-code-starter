---
name: design
description: Design and build frontend interfaces with high design quality. Picks a bold aesthetic direction, then hands the brief to the Hallmark anti-AI-slop engine (default) to design/build/audit/redesign — or generates screens via Google Stitch MCP when the user explicitly asks for Stitch. Use for UI design, screen mockups, design systems, building components / pages / apps, or any "design" / "build a [component/page/UI]" request.
user-invocable: true
---

# /design — Direction-First Frontend Design & Build

You are a Design Systems Lead. Every `/design` invocation runs in **two phases**:

1. **Phase 0 — Lock the aesthetic direction.** No exceptions, no skipping.
2. **Phase 1 — Route to the right engine.** **Hallmark is the default design engine.** Stitch is opt-in, only when the user explicitly asks for it.

The direction picked in Phase 0 is the single source of truth for whatever runs in Phase 1 — it becomes the *brief* handed to Hallmark.

> **Engine precedence (added 2026-07-14):** `hallmark` (github.com/nutlope/hallmark, installed at `~/.claude/skills/hallmark/`) is the design engine for ALL design work — new pages, components, redesigns, audits, reference-study. It ships 20 themes, 21 macrostructures, and a 57-gate anti-slop test, and it enforces **structural** variety (two briefs must not share the same hero → 3-feature → CTA rhythm), which is exactly the failure mode Stitch and raw code-writing both fall into. **Do not reach for Stitch unless the user names it.**

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

## Phase 1 — Route to Engine

**Default: Hallmark.** Route away from it only on the explicit signals in the last two rows.

| User intent signals | Engine | How to run it |
|---|---|---|
| **Anything design-shaped with no Stitch mention** — "design a [page/screen]", "build a landing page / app / component", "make me a UI", "implement this in React/Next/Vue/Svelte/Astro", "write the code for…" | **Hallmark → default Design flow** | `Skill(hallmark)`, hand it the Phase 0 brief |
| "Redesign / restyle / improve the look of an EXISTING app or screen", "make it look like [X]", "match this design" | **Hallmark → `redesign`** | `Skill(hallmark)` with `hallmark redesign <target>` |
| "Is this AI-slop?", "review / score / critique this UI", "what's wrong with this page" | **Hallmark → `audit`** | `Skill(hallmark)` with `hallmark audit <target>` (read-only, never edits) |
| User pastes a **URL or screenshot** of a design they admire | **Hallmark → `study`** | `Skill(hallmark)` with `hallmark study <url\|image>` — extracts DNA, never copies pixels |
| "Create a design system", "extract design tokens", "give me a `DESIGN.md`" | **Hallmark + Code** | Hallmark `study`/`design-md` for the DNA, then `references/code-implementation.md` to wire tokens into the repo |
| **User explicitly names Stitch** — "in Stitch", "list Stitch projects", "edit screen X", a Stitch project URL pasted | **Stitch** (opt-in only) | `references/stitch-workflows.md` |
| Repo plumbing *after* a design exists — framework wiring, CSP, islands, build config, a11y retrofit | **Code** | `references/code-implementation.md` |

**If genuinely ambiguous** (the user just said `/design` with no context): ask what they're designing, then route — the answer almost always lands on Hallmark. Do **not** ask "Stitch or code?" as the opening question anymore; Stitch is no longer a coequal default.

### Handing the Phase 0 brief to Hallmark

Hallmark runs its own Step 0 pre-flight (existing tokens/fonts/framework), Step 1 genre detection, and Step 2.6 theme dispatch. Phase 0's output doesn't replace those — it **feeds** them:

- Pass the **Purpose + Tone + Constraints + Differentiation** as the brief text.
- A named tone (brutalist / luxury / editorial / …), a named brand color, or a named multi-attribute vibe **is a creative-intent signal** — it fires Hallmark's *custom-theme* branch (one-off OKLCH palette + free-font pairing) instead of the 20-theme catalog. That's the intended behavior, not a bug.
- Hallmark's internal genre taxonomy includes a `modern-minimal` genre. That is an *internal* label and is fine. The `/design` ban on "modern" applies to what the **user** is allowed to give as a direction — don't accept "make it modern" as a brief.

---

## Phase 1b — Preview-then-Apply (visual mockup before code)

When the user wants to **redesign or restyle an EXISTING app/UI** (there's already working code to change), don't jump straight into writing CSS. Agree on the look before touching production code.

**Default path — Hallmark `redesign`.** It emits real HTML/CSS you can open in a browser, so the "preview" IS the artifact:

1. **Lock the direction** (Phase 0).
2. **`Skill(hallmark)` → `hallmark redesign <target>`.** It preserves copy, routes, component ownership, and information architecture, and replaces only the visual/interaction layer. It will state which files it expects to modify/create/delete **before** editing — deletions require explicit confirmation.
3. **Show the user the rendered result** (`open` the HTML, or screenshot it) and get a yes before it lands in the live code path.
4. **Deploy stays with `/ship` — never auto-deploy.**

**Stitch mockup path — only when the user asks for a Stitch canvas.** Kept because a throwaway canvas mockup is occasionally the cheaper way to settle a layout argument:

1. **Generate the design in Stitch** — `create_project` (or reuse one) → `generate_screen_from_text` with a prompt encoding the direction + the real screen's content/data. Use `MOBILE` for app-like UIs (`DESKTOP` is often rejected by the API — on `invalid argument`, fall back to `MOBILE`).
2. **Render it for the user** — `get_project` → parse `.thumbnailScreenshot.downloadUrl` (`list_screens` is often empty right after generation; these calls exceed the tool token cap and get saved to a file — that's success, `jq` the saved JSON). `curl` the PNG and send it with `SendUserFile` so the user SEES the design.
3. **ASK before applying** — `AskUserQuestion`: "Apply this design to the live code, or iterate on the mockup first?" Do NOT port to code without a yes.
4. **On yes → port it through Hallmark**, not by hand — feed the approved Stitch layout to Hallmark as the brief so the 57 slop gates still run on the code that actually ships.

Why preview at all (2026-07-02, ecobee dashboard): restyling directly in code produced a layout with a dead void; only after seeing a rendered version (balanced 2×2 bento + gradient hero) did the right layout become obvious. The lesson is *look at it before you ship it* — Hallmark's emitted HTML satisfies that just as well as a Stitch canvas, and it carries the anti-slop gates.

---

## Cross-Mode Rules (apply regardless of engine)

- **Phase 0 direction feeds Phase 1.** The Hallmark brief, the Stitch prompt, and the React/HTML code ALL must reflect the direction. If the output doesn't show the direction, the direction didn't land — redo.
- **Anti-slop applies everywhere — strictest rule wins.** Two banlists are now in play and they are **additive, never subtractive**:
  - **Hallmark's 57 gates + 6 disciplines** (pre-emit self-critique, honest copy / no fabricated metrics, locked tokens, no re-drawn browser/phone/IDE chrome, mobile-verified at 320/375/414/768, no italic headers) are **authoritative whenever Hallmark runs.** Do not relax one of these because `aesthetic-core.md` is silent on it.
  - **`aesthetic-core.md`'s Absolute Bans** (side-stripe borders, gradient text, decorative glassmorphism, hero-metric template, identical card grids, modal-first) and the **two-altitude AI slop test** (first-order category reflex + second-order category-plus-anti-reference reflex) stay binding **on top of** Hallmark's gates, including on Stitch output and hand-written code where Hallmark never ran.
  - Where they overlap, take the stricter reading. Neither list is a ceiling.
- **Hallmark's honest-copy discipline is non-negotiable and matches this account's global rules.** Never invent a metric, testimonial, logo, or case-study count to fill a stat-led layout — use a real number, a labelled placeholder, or a different macrostructure. This is the same fabrication ban as CLAUDE.md's Document Fabrication Prevention; a landing page is not exempt because it's "just design."
- **Hallmark's implementation safety rail is binding in existing repos.** It must state the exact files it will modify/create/delete before editing; deletions need explicit confirmation. Never let a redesign bulldoze route trees, component directories, or an existing site.
- **Color uses OKLCH, neutrals tinted.** No raw `#000`/`#fff`. Pick a color strategy (Restrained / Committed / Full palette / Drenched) before picking colors. See `aesthetic-core.md` → Color & Theme.
- **Theme by scene, not category.** Write a one-sentence physical scene before choosing dark vs light. See `aesthetic-core.md` → Color & Theme.
- **Code mode runs `npx impeccable detect`** before declaring done. 27 deterministic anti-pattern checks, no API key. See `code-implementation.md` → Deterministic Anti-Pattern Scan.
- **One focused edit at a time** (whether `edit_screens` or refactoring a component).
- **No "modern" / "clean" / "sleek"** as a direction. Push back to the user.
- **UI descriptions:** Do not add subtitles, helper text, or descriptive copy beneath headings, labels, cards, or settings by default. Prefer one concise, self-explanatory heading or label. Only add supporting copy when the user explicitly asks for it or when it is necessary to prevent misunderstanding or error, and never use it to restate the heading.
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

## Prerequisites by Engine

- **Hallmark (default)** — no external prerequisites, no API key, no MCP server. Installed at `~/.claude/skills/hallmark/` (source: `github.com/nutlope/hallmark`, MIT, by Together AI; installed 2026-07-14 at v1.1.0). Invoke with `Skill(hallmark)`. To update:
  ```bash
  ! npx skills add nutlope/hallmark
  ```
- **Stitch (opt-in)** requires the `stitch` MCP server running (configured in `~/.claude/settings.json`). If Stitch tools are unavailable, tell the user to run:
  ```bash
  ! npx @_davideast/stitch-mcp init
  ```
- **Code** has no external prerequisites. It runs in any repo.

---

## Reference Files (load on demand, not always)

| File | When loaded |
|---|---|
| `references/aesthetic-core.md` | **Always** — Phase 0 |
| `Skill(hallmark)` → its own `references/` (20 themes, 21 macrostructures, 57 slop gates, component archetypes) | **Default** — every design/build/redesign/audit/study |
| `references/code-implementation.md` | Repo plumbing, design-system wiring, or porting an approved design into the framework |
| `references/stitch-workflows.md` | Only when the user explicitly names Stitch |

This skill follows the progressive-disclosure pattern (same as `/carmack`): the entry-point `SKILL.md` stays lean and routes to references that load only when their mode fires. Hallmark is itself progressive — its SKILL.md pulls only the theme / macrostructure / component files the brief actually needs.

---

## Quick Trigger Examples

- `/design build a hospital ledger landing page` → Phase 0 (pick direction, e.g., "editorial / magazine") → **Hallmark** default Design flow
- `/design build a sticky pricing card component in this Next.js repo` → Phase 0 (e.g., "brutalist raw") → **Hallmark** Component-scope flow (all 8 interactive states mandatory)
- `/design make example.com look less AI-generated` → Phase 0 → **Hallmark `audit`** (read-only punch list) → then `redesign` on approval
- `/design here's a site I love: https://…` → **Hallmark `study`** (extract DNA — never copies pixels; refuses template-marketplace URLs)
- `/design create a design system for example.org` → Phase 0 → **Hallmark** for the DNA + `design.md` → `code-implementation.md` to wire the tokens
- `/design generate a hospital ledger landing page **in Stitch**` → Phase 0 → Stitch mode (explicit opt-in) → `generate_screen_from_text`
- `/design` (no context) → ask what they're designing, then route (almost always Hallmark)
