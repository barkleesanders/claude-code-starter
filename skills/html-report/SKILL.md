---
name: html-report
user-invocable: true
description: "Default output format for reports, summaries, analyses, dashboards, audits, comparisons, digests, briefings, and any deliverable with structured/spatial information. Generates a single self-contained HTML file (no external dependencies) the user can open in a browser, share, print to PDF, or paste into Notion. Lightweight cousin of /design and /magazine — no AI generation server, no editorial chrome, just clean Tailwind-via-CDN HTML that beats Markdown on scannability, comparison, and feel. Use whenever the user asks for a report, summary, breakdown, analysis, audit, dashboard, comparison, or any deliverable that previously would have been a .md file. Triggers: 'report', 'summary', 'audit', 'analysis', 'dashboard', 'compare', 'breakdown', 'rundown', 'brief', 'digest', 'overview', 'recap', 'write up', 'document', 'deliverable'. Reference: https://thariqs.github.io/html-effectiveness/"
---

# /html-report — HTML by default, not Markdown

**Core thesis** (per [thariqs.github.io/html-effectiveness](https://thariqs.github.io/html-effectiveness/)): HTML beats Markdown for AI-generated outputs because it transforms linear, text-heavy documents into spatial, interactive, visually scannable artifacts that users actually engage with. Diffs, comparisons, status grids, timelines, and call graphs are spatial information; Markdown flattens them.

**This skill is the default.** When the user asks for a report / summary / audit / breakdown / dashboard / comparison / brief / digest / analysis / write-up / deliverable, write a single self-contained `.html` file — not `.md`.

## When to use HTML (default)

Use HTML for anything with structure, comparison, or status:

- Reports, audits, post-mortems, status updates
- Side-by-side comparisons (before/after, A/B, vendors, options)
- Dashboards: KPIs, metrics, health checks, score cards
- Timelines, roadmaps, gantt-ish layouts
- Tables of records (vendors, tasks, files, findings) with badges/states
- Architecture diagrams, flow descriptions, decision trees
- Reading lists / link roundups / research summaries
- Anything you'd otherwise reach for Markdown headers + bullet lists for

## When to keep Markdown

Markdown is still right for:

- Inline chat replies and conversational answers
- Code review notes posted as PR comments
- Technical specs / design docs / RFCs that live in a repo and need diffing
- Beads descriptions, git commit messages, README sections
- Any output explicitly headed for a Markdown-rendering destination (GitHub, Linear, Notion-as-MD, blog post source)

If unsure: ask the user where the output is going. Notion / Slack / "send to my team" / "I want to share this" / "open it" → HTML. PR / commit / repo file → Markdown.

## Output rules (hard)

1. **Single self-contained `.html` file.** No external CSS files, no separate JS, no asset folders. Tailwind via CDN is allowed and encouraged.
2. **Document order: `<body>` → `<script>` → `<style>`** (NOT the traditional `<head><style><script></head><body>`). Body content first, then scripts, then styles last. See the template below — this dramatically improves generation quality by forcing content-first output. Do not "correct" it back to standard head layout.
3. **Save to `~/Claude-Reports/` by default**, named `<slug>-<YYYY-MM-DD>.html`, unless the user specifies a path. `~/Claude-Reports` is a symlink to the Google-Drive-synced folder `My Drive/Claude Reports` (Drive-for-Desktop mount `~/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/Claude Reports`), so every report auto-syncs to Drive. Use the clean symlink path (no spaces) in `Write`/`open` commands. If the symlink is missing (e.g. a machine without the mount), fall back to `~/Downloads/`.
4. **`<meta charset="utf-8">` MUST be the first line of the file.** Non-negotiable. Without it Chrome falls back to a Latin-1 guess and every `—`, `·`, `§`, `×`, `→` renders as mojibake (`â€"`, `Â·`, `Â§`, `Ã—`, `â†'`) — in the PDF, in Drive's preview, and in any browser that doesn't guess right. It is in the template below; do not omit it when hand-writing a file. (Burned 2026-07-29: a full 12-page report rendered with corrupted punctuation on every page.)
5. **Always emit a PDF sibling, not just the HTML** — run `~/tools/report-pdf <file.html>`. Google Drive, email, and most share targets **cannot render `.html`**; a Drive link to an HTML report is a download, not a document. The PDF is the shareable artifact. `report-pdf` serves the file over localhost, drives real Chrome via `fcdp` so Tailwind-via-CDN actually applies, then verifies page count, text-layer extractability, and zero mojibake. It **refuses** (exit 2) if rule 4 was violated. Never hand the user a Drive/share link to the `.html` when a PDF exists.
6. **Open it after writing**: run `open <file>` so the user sees the result immediately. Don't require them to ask.
7. **Print-friendly**: include a `@media print` block so the PDF (and Cmd-P) comes out without blank pages or cut-off cards. Give wide tables `min-width:0` inside `@media print` so they don't overflow the page box.
6. **No JavaScript unless it earns its keep.** A static HTML page is fine. Add JS only for genuine interactivity (filters, tabs, sortable tables) — not for cosmetic flourish.
7. **Cite sources inline.** If the report references files, URLs, or data, link them with `<a href>` so the reader can click through.

## Default template

Use this skeleton. Edit content; keep structure. Tailwind via CDN keeps the file self-contained.

```html
<!doctype html>
<html lang="en" class="bg-zinc-50">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>REPLACE — Title</title>

<body class="text-zinc-900">
<main class="mx-auto max-w-5xl px-6 py-10 space-y-10">

  <header class="border-b border-zinc-200 pb-6">
    <p class="text-xs uppercase tracking-widest text-zinc-500">REPLACE — Kicker (e.g. Audit · 2026-05-08)</p>
    <h1 class="mt-2 text-4xl font-semibold tracking-tight">REPLACE — Headline</h1>
    <p class="mt-3 text-lg text-zinc-600 max-w-2xl">REPLACE — One-sentence dek that summarizes the finding/recommendation.</p>
  </header>

  <!-- TL;DR card — always lead with this -->
  <section class="rounded-xl bg-white border border-zinc-200 p-6 shadow-sm">
    <h2 class="text-sm font-semibold uppercase tracking-wider text-zinc-500">TL;DR</h2>
    <ul class="mt-3 space-y-2 text-zinc-800">
      <li class="flex gap-3"><span class="text-emerald-600">✓</span><span>REPLACE — Top finding 1</span></li>
      <li class="flex gap-3"><span class="text-emerald-600">✓</span><span>REPLACE — Top finding 2</span></li>
      <li class="flex gap-3"><span class="text-amber-600">!</span><span>REPLACE — Risk / open question</span></li>
    </ul>
  </section>

  <!-- KPI / metric grid (delete if not applicable) -->
  <section class="grid grid-cols-2 md:grid-cols-4 gap-4">
    <div class="rounded-lg bg-white border border-zinc-200 p-4">
      <p class="text-xs uppercase text-zinc-500">REPLACE — Metric</p>
      <p class="mt-1 text-3xl font-semibold tabular-nums">42</p>
      <p class="text-xs text-zinc-500 mt-1">REPLACE — context</p>
    </div>
    <!-- repeat -->
  </section>

  <!-- Findings table — use for repeating records with status -->
  <section>
    <h2 class="text-2xl font-semibold tracking-tight mb-4">Findings</h2>
    <div class="overflow-x-auto rounded-lg border border-zinc-200 bg-white">
      <table class="min-w-full divide-y divide-zinc-200 text-sm">
        <thead class="bg-zinc-50">
          <tr class="text-left text-zinc-600">
            <th class="px-4 py-2 font-medium">Item</th>
            <th class="px-4 py-2 font-medium">Status</th>
            <th class="px-4 py-2 font-medium">Notes</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-100">
          <tr>
            <td class="px-4 py-3 font-medium">REPLACE</td>
            <td class="px-4 py-3"><span class="inline-flex items-center rounded-full bg-emerald-50 px-2 py-1 text-xs font-medium text-emerald-700">OK</span></td>
            <td class="px-4 py-3 text-zinc-600">REPLACE</td>
          </tr>
          <tr>
            <td class="px-4 py-3 font-medium">REPLACE</td>
            <td class="px-4 py-3"><span class="inline-flex items-center rounded-full bg-amber-50 px-2 py-1 text-xs font-medium text-amber-700">Warn</span></td>
            <td class="px-4 py-3 text-zinc-600">REPLACE</td>
          </tr>
          <tr>
            <td class="px-4 py-3 font-medium">REPLACE</td>
            <td class="px-4 py-3"><span class="inline-flex items-center rounded-full bg-rose-50 px-2 py-1 text-xs font-medium text-rose-700">Fail</span></td>
            <td class="px-4 py-3 text-zinc-600">REPLACE</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>

  <!-- Side-by-side comparison block (delete if not applicable) -->
  <section class="grid md:grid-cols-2 gap-4">
    <div class="rounded-lg border border-rose-200 bg-rose-50/50 p-5">
      <p class="text-xs font-semibold uppercase tracking-wider text-rose-700">Before</p>
      <pre class="mt-2 whitespace-pre-wrap text-sm text-zinc-800">REPLACE</pre>
    </div>
    <div class="rounded-lg border border-emerald-200 bg-emerald-50/50 p-5">
      <p class="text-xs font-semibold uppercase tracking-wider text-emerald-700">After</p>
      <pre class="mt-2 whitespace-pre-wrap text-sm text-zinc-800">REPLACE</pre>
    </div>
  </section>

  <!-- Detail / prose section — use sparingly, the whole point is to avoid walls of text -->
  <section class="prose prose-zinc max-w-none">
    <h2>Detail</h2>
    <p>REPLACE — keep prose tight. If a paragraph is more than 4 sentences, ask whether it should be a list, a table, or a comparison block instead.</p>
  </section>

  <footer class="pt-8 border-t border-zinc-200 text-xs text-zinc-500 flex justify-between">
    <span>Generated <time>REPLACE — date</time></span>
    <span class="no-print">Save as PDF · Cmd-P</span>
  </footer>

</main>
</body>

<!-- Scripts AFTER body. Tailwind CDN here works fine — it scans the DOM at runtime. -->
<script src="https://cdn.tailwindcss.com"></script>

<!-- Styles LAST. CSS is order-agnostic for matching; trailing position keeps the file content-first. -->
<style>
  /* color-scheme:light (never "light dark") — a page that opts into dark
     support without shipping dark tokens gets Chrome's UA dark default
     (color:white) forced onto html + any element with no explicit
     text-color class, while an explicit background stays light: white
     text on a light card. Confirmed live 2026-09-07 under real system
     dark mode (goalzero reports) — <td> cells measured color:rgb(255,255,255)
     on a white table until color-scheme was pinned to light. These are
     static, standalone deliverables, not theme-adaptive Artifacts — they
     must render identically regardless of the viewer's OS/browser theme. */
  :root { color-scheme: light; }
  html { background: #fafafa; color: #18181b; }
  body { font-family: ui-sans-serif, -apple-system, system-ui, sans-serif; background: #fafafa; color: #18181b; }
  @media print {
    body { background: white; }
    .no-print { display: none; }
    /* Every visual container gets BOTH the modern and legacy break property.
       Chrome's headless printToPDF (what report-pdf drives) silently ignores
       break-inside:avoid on a bare `section` selector when the box has a
       background/border-radius — it splits the box mid-content instead of
       pushing the whole thing to the next page, leaving an orphaned dark
       fragment floating alone at the top of a blank page. This happened for
       real (2026-09-07): a `bg-stone-900` "Bottom line" callout rendered
       correctly on page 3, but its last bullet spilled onto page 4 as an
       isolated black pill on white — unreadable, looked broken. Targeting
       every card/callout class (not just `section`) and setting `orphans`/
       `widows` fixes it. */
    section, li, .rounded-xl, .rounded-lg, .rounded-full,
    [class*="bg-"], [class*="border"] {
      break-inside: avoid-page;
      page-break-inside: avoid;
      orphans: 3;
      widows: 3;
    }
  }
</style>
</html>
```

**Colored/dark callout boxes (the "Bottom line", "TL;DR", warning banners) are the highest-risk element for this failure** — keep them to 5 lines or fewer of content. A long one is more likely to exceed the remaining space on the current page, and `avoid-page` can only push the *whole* box to the next page if the whole box actually fits there — an oversized box still gets split with no warning. If a callout is unavoidably long, split it into two shorter boxes rather than one tall one.

## Component palette (mix and match)

Pick the components that fit the data, then write content. Don't write content first then try to retrofit structure.

| If you have… | Use this |
|---|---|
| 3-6 KPIs / metrics | KPI grid (4-col on desktop) |
| Repeating records with status | Findings table with badge column |
| Before vs after / option A vs B | Side-by-side comparison (rose/emerald) |
| Sequential steps or events | Vertical timeline with date column |
| 2-5 mutually exclusive options | Tab strip (or just stacked cards) |
| Hierarchical or tree data | Indented list with monospace prefixes |
| Quote / callout | Left-bordered blockquote with kicker |
| Code or terminal output | `<pre class="bg-zinc-900 text-zinc-100 rounded-lg p-4 text-sm overflow-x-auto">` |
| Source citations | Inline `<a>` with subtle underline; numbered superscript optional |

## Workflow

1. **Decide HTML vs MD.** Default = HTML. Only switch to MD if destination is clearly a Markdown surface (PR, commit, README, blog source).
2. **Pick components from the palette** based on the data shape — not based on aesthetic.
3. **Write the file** using the skeleton + selected components.
4. **Save** to `~/Claude-Reports/<slug>-<YYYY-MM-DD>.html` (override only if user gave a path). This lands in the Google-Drive-synced folder automatically.
5. **Render the PDF**: `~/tools/report-pdf ~/Claude-Reports/<slug>-<YYYY-MM-DD>.html`. Always. It prints the verified page/byte/char counts to stderr — report them. If it exits 2, you omitted `<meta charset="utf-8">`; add it and re-run.
6. **Open it**: `open ~/Claude-Reports/<slug>-<YYYY-MM-DD>.html`. Don't ask permission — opening a local file is harmless and the user wants to see the result.
7. **Tell the user** both paths in your reply (note they're in Google Drive → `My Drive/Claude Reports`), and offer to: (a) share the **PDF** link, (b) paste into Notion, (c) iterate on the design.

### If the user asks for a shareable link
Share the **PDF**, never the `.html` — Drive renders PDFs inline and cannot render HTML.

```bash
# find the synced fileId (wait for Drive sync; do NOT `gog drive upload` into a
# synced folder — that creates a duplicate instead of versioning)
#   -> mcp__claude_ai_Google_Drive__search_files:
#      title contains '<slug>' and mimeType = 'application/pdf'
gog -a you@example.com drive share <fileId> --to=anyone --role=reader --force
# then PROVE it works with no session:
curl -sSL -o /tmp/a.pdf -w '%{http_code} %{size_download}\n' "https://drive.google.com/uc?export=download&id=<fileId>"
```
`--force` is required for public shares (gog's own guard). Omit `--discoverable` so it stays link-only and out of search. **Before sharing publicly, confirm the report contains no PII** — if it does, keep it owner-only and attach the file to an email instead (per the Drive-PII rule).

## Anti-patterns

- Generating a `.md` file when the user said "report" or "summary" or "dashboard" — that's the bug this skill exists to fix.
- Using Markdown headings + bullet lists where a table or grid would communicate faster.
- Writing a 6-paragraph "Executive Summary" when 5 bullets in a TL;DR card would do.
- Adding JavaScript for interactivity the user didn't ask for.
- External CSS files / asset folders — breaks portability. The whole file should travel as one attachment.
- Heavy gradients, drop shadows, or animation flourish — clean and scannable beats decorated.
- **Omitting `<meta charset="utf-8">`** — silently mojibakes every em-dash, `·`, `§`, `×`, `→` in the PDF and in Drive's preview. The template has it; keep it.
- **Delivering only the `.html`** — then handing over a Drive link the recipient can't read. Run `~/tools/report-pdf` and share the PDF.
- **Verifying a PDF by eye alone.** Render a page or two and actually look at it. Tag-balance checks and a 200 status do not catch corrupted glyphs or a table overflowing the page box.
- **Ever writing `color-scheme: light dark` (or `dark`) in a report's `<style>` block, even in a hand-written deviation from this template.** The template's `:root{color-scheme:light}` exists specifically to prevent this. Declaring dark support without shipping real dark tokens makes Chrome force `color:white` onto `html` and any element lacking an explicit Tailwind `text-*` class — while an explicit `background` stays light — producing invisible white-on-white/cream text for any viewer whose OS is in dark mode. Confirmed live 2026-09-07 (`<td>` cells measured `color:rgb(255,255,255)` on a white table) across 4 hand-written Goal Zero reports that added this line without dark overrides. These are static, portable deliverables, not theme-adaptive Artifacts — always pin `color-scheme: light`.
- **Trusting `report-pdf`'s page/byte/char summary as proof the PDF is readable.** It proves the file rendered and has a text layer — it does NOT prove no box got split across a page break. Render **every page** to PNG and look at each one before calling the report done: `pdftoppm -r 100 -png x.pdf /tmp/pg` then `Read` each `/tmp/pg-N.png`. Specifically check the top and bottom few lines of every page — an orphaned fragment of a colored callout box (its background/border survives the split, its content doesn't) is the most common defect and reads as "broken, unreadable text" to the recipient even though the HTML source and on-screen render both look fine. This exact defect shipped 2026-09-07: a `bg-stone-900` "Bottom line" box rendered correctly on page 3 but spilled one bullet onto page 4 as an isolated dark fragment on an otherwise blank page. It was invisible in the light-mode screenshot and invisible in `report-pdf`'s summary — only caught by opening the actual PDF pages one at a time.

## Relationship to other skills

- **`/design`** (Stitch MCP) — for designing actual product UIs that will become real frontend code. Heavy, AI-generative, project-scoped.
- **`/magazine`** — for editorial digests where each item gets its own full-viewport spread. Heavy, prescribed treatments per spread.
- **`/visualise`** — for inline-in-conversation SVG/HTML fragments rendered in a sandboxed iframe (no `<html>` wrapper).
- **`/html-report`** (this skill) — lightweight default for any deliverable previously written as `.md`. One file, one open command, done.

When in doubt between this and another HTML skill: this one is the default. The others are when the user explicitly invokes them or when the content clearly fits their format (UI design → /design, multi-spread editorial → /magazine, inline diagram → /visualise).
