# UI Duplicate-Affordance Patterns

> **Load when**: user reports "double down arrow", "two chevrons", "double caret",
> "stacked icons", "duplicate arrow", "two carets", "X is showing twice", or any
> visual report of repeated affordances on a single control. Also load when
> auditing a UI page that mixes a CSS framework's `forms`-style plugin with
> native form controls.

## TL;DR — the single most common cause

A `<select>` (or other form control) ends up with **two stacked chevrons** because
two systems independently paint a "dropdown arrow":

1. **Native browser chevron** — drawn whenever `appearance` is not set to `none`
   (this is the default; `appearance: auto` makes it explicit).
2. **CSS framework background-image chevron** — `@tailwindcss/forms`,
   `@tailwindcss/forms-plugin`, `bootstrap` `.form-select`, etc. all paint a
   chevron via `background-image: url(svg)`.

If both are active on the same element → double-down-arrow.

## Real incident (2026-05-17, ImproveBayArea IBA-m69)

Reported at: `https://improvebayarea.com/reports?city=san-francisco` — the
"Closed reports" status filter dropdown showed two stacked ▼ chevrons.

Root cause in `src/ui.ts`:

```css
/* @tailwindcss/forms loaded via CDN paints a background-image chevron on
   every <select>. */
<script src="https://cdn.tailwindcss.com?plugins=forms"></script>

/* .iba-select (used on #city-select) correctly suppresses BOTH layers: */
select.iba-select {
  appearance: none !important;          /* kills native chevron */
  -webkit-appearance: none !important;
  background-image: none !important;    /* kills tailwind chevron */
}

/* .report-select (used on #all-reports-status + #category-select) only
   suppressed the native one and trusted the comment — but the comment was
   wrong. Tailwind's chevron was still there. */
.report-select {
  appearance: auto;          /* keeps native chevron ← intended */
  /* background-image: none !important; ← MISSING. Result: double arrow. */
}
```

Fix: add `background-image: none !important;` to `.report-select`. The native
chevron (from `appearance: auto`) is the intended one — it's accessible and
matches the platform.

Regression test: `src/ui_select_chevron.test.ts` — 5 assertions that lock the
fix and enforce that every `<select>` on the SPA shell carries either
`.iba-select` (native suppressed + inline span) or `.report-select` (native
shown + tailwind suppressed).

## Detection recipe (run during any UI audit)

### Step 1 — Does the page load a forms-styling CSS framework?

```bash
grep -rn "tailwindcss\|bootstrap\|bulma\|@tailwindcss/forms\|plugins=forms\|form-select" src/ public/ --include="*.ts" --include="*.tsx" --include="*.js" --include="*.html" --include="*.css" | head
```

If **yes**, every `<select>`, `<input type="checkbox">`, and `<input type="radio">`
gets an automatic background-image overlay. Continue to Step 2.

If **no**, skip — the bug surface is narrower; only inline-painted icons can
collide.

### Step 2 — Find every form control + classify its chevron strategy

```bash
# Every <select> opening tag with its class list:
grep -rEn '<select\b[^>]*>' src/ | grep -v "// " | grep -v "<!--"

# Cross-reference against CSS rules that touch chevrons:
grep -rEn '\bappearance\s*:\s*(none|auto)\b|background-image\s*:\s*(none|url)' src/ --include="*.ts" --include="*.css"
```

Each `<select>` must be in exactly **one** of these states:

| Strategy | `appearance` | `background-image` | Visible affordance |
|---|---|---|---|
| Native chevron only | `auto` (default) | `none !important` | Browser's built-in ▼ |
| Inline-icon only | `none !important` | `none !important` | Adjacent `<span>` icon |
| Anything else | … | … | **BUG — likely two chevrons** |

The forbidden state: `appearance: auto` (or unset) **AND** `background-image`
unset **AND** a forms-plugin is loaded.

### Step 3 — Verify against the rendered output (live or snapshot)

```bash
# Against the live site:
curl -s https://example.com/page | grep -A1 -B1 '<select' | head -60

# Or grep the rendered HTML for naked <select>:
node -e "
import { renderApp } from './src/ui.ts';
const html = renderApp({});
const stripped = html
  .replace(/<!--[\s\S]*?-->/g, '')
  .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
  .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '');
const tags = stripped.match(/<select\b[^>]*>/g) || [];
console.log('Found', tags.length, 'selects in real markup');
for (const t of tags) console.log(t);
"
```

### Step 4 — Other duplicate-affordance shapes (beyond `<select>`)

| Shape | What stacks | Fix |
|---|---|---|
| `<details><summary>` with inline `▾` text | native disclosure triangle (`::-webkit-details-marker`) + inline glyph | `summary { list-style: none; } summary::-webkit-details-marker { display: none; }` then use either the inline glyph OR the native marker, not both |
| `<button>` with leading + trailing icon for same action | two icons telegraphing the same thing | Drop one; usage data picks the survivor |
| Card with badge AND inline status text saying the same thing ("Closed" badge + "Status: Closed") | Two affordances for the same fact | Drop the redundant text; keep the badge |
| Toggle switch with adjacent "On / Off" label that duplicates the switch state | Switch position + redundant label | Make the label a single static category name; let the switch carry the state |
| Sticky header arrow + in-page arrow both pointing "back" on the same screen | Two back affordances | Native `←`/`<` button only |
| Two `aria-hidden="true"` icons inside one labeled control | Visual duplication only — but screen-reader users see "" twice if labels leak | Audit each icon's `aria-hidden` and parent label |

### Step 5 — Where to add a regression test

For each fixed instance, add a unit test that:

1. Renders the page output to a string (no DOM browser required).
2. Asserts the CSS rule contains the suppression token (`background-image: none`).
3. Iterates every `<select>` (or `<details>`, etc.) tag in the **stripped** HTML
   (strip `<!-- -->`, `<script>…</script>`, `<style>…</style>` first — they
   often contain the element name in documentation).
4. Asserts each tag carries one of the project's discipline classes.

Template: `~/tools/improvebayarea/src/ui_select_chevron.test.ts` (IBA-m69 fix).

## Mode-detection triggers (add to SKILL.md)

| User phrase | Mode | Load |
|---|---|---|
| "double down arrow", "double chevron", "double caret" | **debug** + **ui-duplicate-affordance** | this file |
| "two arrows", "two chevrons", "twin chevrons" | **debug** + **ui-duplicate-affordance** | this file |
| "stacked icons", "duplicate icon", "duplicated affordance" | **debug** + **ui-duplicate-affordance** | this file |
| "showing twice", "appears twice", "X is rendered twice" | **debug** + **ui-duplicate-affordance** | this file |
| any UI audit of a page that mixes Tailwind/Bootstrap forms with native controls | **review** + **ui-duplicate-affordance** | this file |

## Hard rule (added to SKILL.md Hard Rules)

When changing any CSS for a form control on a page that loads a forms-styling
CSS framework (`@tailwindcss/forms`, Bootstrap `form-select`, Bulma `select`,
etc.), the CSS rule MUST be unambiguous about which chevron it wants:

```css
.your-select {
  appearance: none !important;
  background-image: none !important;
  /* + inline span chevron in markup */
}
/* OR */
.your-select {
  appearance: auto;                  /* native chevron */
  background-image: none !important; /* kill framework overlay */
}
```

Never leave both `appearance` and `background-image` unset on a `<select>`
when a forms-plugin is loaded — that's the double-chevron trap.

## Closed-loop verification

After applying a fix:

1. `timeout 60 npx vitest run src/<your-regression-test>.ts` — must pass.
2. Open the live page in Chrome DevTools, inspect the control, confirm:
   - In **Computed**, `appearance` is either `none` (with inline span) or
     `auto`.
   - In **Computed**, `background-image` is `none` (or a single intended URL).
3. Screenshot the control before/after; the visual count of chevrons should
   match the design intent (typically: 1).

## Adjacent reading

- `~/.claude/skills/carmack/references/ux-patterns.md` — UX pre-checks
- `~/.claude/skills/carmack/references/css-layout-patterns.md` — layout traps
- `~/.claude/skills/carmack/references/responsive-design.md` — responsive rules
