# Magazine Design System

The shared chrome that every magazine output uses. Read once per conversation; reuse across all spreads.

## Fonts (always load)

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght,SOFT,WONK@9..144,300..900,0..100,0..1&family=Inter:wght@300;400;500;600;700;800;900&family=JetBrains+Mono:wght@400;700&family=Space+Grotesk:wght@400;500;700&display=swap" rel="stylesheet">
```

- **Fraunces** — serif display. Use for hero titles, vintage spreads, academic spreads. Always specify `font-variation-settings` (opsz, SOFT, WONK) for character. WONK=1 with italic gives the swashed editorial look.
- **Inter** — sans body. Use for kickers, source lines, poster spreads, all body text.
- **JetBrains Mono** — terminal/code spreads only.
- **Space Grotesk** — scientific spreads only.

## Type scale rules

- **Body text minimum: 22px.** Never go smaller anywhere in the document.
- **Standfirst (lede paragraph): clamp(22px, 2.4vw, 30px)**
- **Section headlines (h2): clamp(48px, 6.5vw, 96px)**
- **Display headlines (hero): clamp(56px, 8vw, 120px)**
- **Numerals (01, 02 markers): clamp(180px, 26vw, 380px)** — these are part of the design, must dominate
- **Kickers (section labels): 18px, letter-spacing 0.25em, uppercase, weight 700**
- **Source lines (attribution): 18px, weight 500, opacity 0.65**

Use `clamp()` everywhere for fluid scaling. Never hard-code px for display type.

## Body shell (always include)

```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
html { scroll-behavior: smooth; overflow-x: hidden; }
body {
  font-family: 'Inter', sans-serif;
  font-size: 22px;
  line-height: 1.5;
  color: #1a1a1a;
  background: #f5f3ee;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
  overflow-x: hidden;
}
a { color: inherit; text-decoration: underline; text-decoration-thickness: 2px; text-underline-offset: 4px; }
a:hover { text-decoration-thickness: 4px; }

/* MANDATORY overflow guards — never ship a magazine without these */
h1, h2, h3, .bigstat, .numeral, .masthead-title, .equation, .ledger {
  overflow-wrap: break-word;
  word-break: break-word;
  hyphens: auto;
  max-width: 100%;
}
.spread, .masthead, .colophon { overflow-x: clip; }
```

## Overflow protection — NON-NEGOTIABLE

Magazine output regularly failed with "text cut off" until these rules were baked in. Follow all six:

1. **Never use `white-space: pre` on `<pre>` blocks.** Use `white-space: pre-wrap` so monospace ledgers reflow on narrow viewports. ASCII art with long dotted lines (`........`) WILL overflow any phone or laptop. Use short columns with spaces, not dots.
2. **Clamp ceilings must fit the viewport.** `clamp(min, fluid, max)` — the `max` must never exceed `viewport_width × 0.9` for any realistic reading viewport. For display type, cap at `260px`. For bigstat numbers, cap at `280px`. For hero headlines, cap at `140px` unless you've tested the actual content length.
3. **Any decorative pseudo-element that bleeds off-edge needs `overflow: hidden` on its parent AND `z-index: 0` on itself AND `z-index: 1` on sibling content.** Otherwise decoration eats content.
4. **Equation / ledger / code blocks**: `display: block`, `max-width: 100%`, `white-space: pre-wrap`, `overflow-wrap: break-word`. Never `display: inline-block` with long content — it refuses to wrap.
5. **Bar charts (.payer-row etc.)**: always set a mobile breakpoint at `max-width: 700px` that wraps the flex row and lets labels stack above bars.
6. **Big numerals (`$290,000`, giant `01`)**: test against the actual content string. `$290,000` at `26vw` on a 1024px viewport is 266px wide for the digits alone — at `font-size: 420px` the glyph width exceeds viewport. Cap bigstat at `clamp(96px, 18vw, 280px)` and validate.

Before saving the file: mentally scroll through at viewports of 375px (phone), 768px (tablet), 1440px (laptop). If any block of content would exceed the viewport width at any of those, fix the clamp or reflow the block BEFORE writing the file.

## Spread shell (always include)

```css
.spread {
  min-height: 100vh;
  padding: 80px 8vw;
  display: flex;
  flex-direction: column;
  justify-content: center;
  position: relative;
}
.kicker {
  font-family: 'Inter', sans-serif;
  font-weight: 700;
  font-size: 18px;
  letter-spacing: 0.25em;
  text-transform: uppercase;
  margin-bottom: 32px;
}
.badge-applies {
  display: inline-block;
  background: #c33;
  color: white;
  padding: 8px 20px;
  font-family: 'Inter', sans-serif;
  font-weight: 800;
  font-size: 18px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-bottom: 32px;
  transform: rotate(-1deg);
}
.source-line {
  font-family: 'Inter', sans-serif;
  font-size: 18px;
  font-weight: 500;
  margin-top: auto;
  padding-top: 60px;
  opacity: 0.65;
}
.numeral {
  font-family: 'Fraunces', serif;
  font-weight: 900;
  line-height: 1;
  font-variation-settings: 'opsz' 144;
}
@media (max-width: 768px) {
  .spread { padding: 60px 6vw; }
}
```

## Color palettes (pick one per spread)

Each palette below lists `bg / text / accent`. Mix freely across spreads — variety is the design.

| Name | bg | text | accent | Best for |
|---|---|---|---|---|
| **Cream / red** | `#f5f3ee` | `#1a1a1a` | `#c33` | Hero, default editorial |
| **Coral alert** | `#f7d4c8` | `#2a1010` | `#c12c2c` | Urgent, broken thing, warnings |
| **Midnight cyan** | `#0a0e1a` | `#d4ddef` | `#6cf` | Security, hacking, supply chain |
| **Violet gradient** | `linear-gradient(135deg, #1a1a3a 0%, #5e2ca5 50%, #ec5990 100%)` | `#fff` | `#fff` | Creative software, design |
| **Terminal green** | `#0d1117` | `#00ff88` | `#ffd166` | Dev tools, CLI, version control |
| **Yellow poster** | `#ffe600` | `#000` | `#000` | Civic action, manifesto, protest |
| **Vinyl cream** | `#f0e7d4` | `#2a1f10` | `#c12c2c` | Cultural, archival, heritage, music |
| **Paper academic** | `#faf7f0` | `#1a1a1a` | `#5a3a78` | Scholarly, longform, web standards |
| **Black amber** | `#1a1a1a` | `#fff` | `#ffd166` | Stats, data, big-number finish |
| **Graph paper** | `#ecebe7` | `#1a1a1a` | `#c33` | Scientific, technical, research |
| **Newsprint** | `#e8e3d8` | `#1a1a1a` | `#1a3a5c` | Field notes, classic newspaper |
| **Ocean** | `#0d2438` | `#e8e3d8` | `#5fb8b8` | Environmental, infrastructure, marine |
| **Forest** | `#1a2a1a` | `#e8e3d8` | `#a8c47e` | Nature, climate, biology |

## Masthead (cover spread)

Every magazine starts with a masthead. Required structure:

```html
<header class="masthead">
  <div class="masthead-top">
    <span>Vol. X · No. Y</span>
    <span>Publication Title</span>
    <span>Date or Price</span>
  </div>
  <div>
    <h1 class="masthead-title">Title<br>line<br>here.</h1>
    <p class="masthead-sub">One-sentence subtitle / dek that sets reader expectations.</p>
  </div>
  <div class="masthead-bottom">
    <div><b>Edition</b>Date</div>
    <div><b>Reader</b>User name or audience</div>
    <div><b>Stories</b>N items</div>
    <div><b>Reading time</b>~N minutes</div>
  </div>
</header>
```

CSS:
```css
.masthead {
  min-height: 100vh;
  background: #f5f3ee;
  padding: 60px 8vw;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  border-bottom: 12px solid #1a1a1a;
}
.masthead-top {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-bottom: 2px solid #1a1a1a;
  padding-bottom: 24px;
  font-weight: 600; font-size: 20px;
  letter-spacing: 0.15em; text-transform: uppercase;
}
.masthead-title {
  font-family: 'Fraunces', serif;
  font-weight: 900;
  font-size: clamp(80px, 14vw, 240px);
  line-height: 0.85;
  letter-spacing: -0.04em;
  margin: 80px 0 40px;
  font-variation-settings: 'opsz' 144;
}
.masthead-title em {
  font-style: italic;
  font-variation-settings: 'opsz' 144, 'SOFT' 100, 'WONK' 1;
  color: #c33;
}
.masthead-sub {
  font-family: 'Fraunces', serif;
  font-style: italic;
  font-size: clamp(28px, 3.5vw, 48px);
  line-height: 1.25;
  max-width: 1100px;
  color: #444;
  margin-bottom: 60px;
}
.masthead-bottom {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 40px;
  border-top: 2px solid #1a1a1a;
  padding-top: 24px;
  font-size: 19px;
  font-weight: 500;
}
.masthead-bottom b {
  display: block; font-size: 14px;
  letter-spacing: 0.12em; text-transform: uppercase;
  color: #888; margin-bottom: 6px; font-weight: 600;
}
@media (max-width: 768px) {
  .masthead-bottom { grid-template-columns: 1fr 1fr; }
}
```

## Colophon (closing spread)

Every magazine ends with a sign-off:

```html
<footer class="colophon">
  <h3>That's the<br>edition.</h3>
  <p>One-sentence editor's note explaining what was filed and why. Optionally what was skipped.</p>
  <div class="footer-meta">Publication Title · Date · Made for [Reader]</div>
</footer>
```

```css
.colophon {
  min-height: 60vh;
  background: #1a1a1a;
  color: #f5f3ee;
  padding: 100px 8vw;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.colophon h3 {
  font-family: 'Fraunces', serif;
  font-weight: 900;
  font-size: clamp(60px, 8vw, 120px);
  line-height: 0.95;
  letter-spacing: -0.03em;
  margin-bottom: 36px;
  font-variation-settings: 'opsz' 144;
}
.colophon p {
  font-family: 'Fraunces', serif;
  font-style: italic;
  font-size: clamp(24px, 2.6vw, 32px);
  line-height: 1.4;
  max-width: 1100px;
  color: #c0bcb0;
  font-weight: 300;
}
.colophon .footer-meta {
  margin-top: 60px;
  border-top: 2px solid #444;
  padding-top: 32px;
  font-weight: 600; font-size: 18px;
  letter-spacing: 0.15em; text-transform: uppercase;
  color: #888;
}
```

## Rules of variety

To make a magazine feel like a magazine and not a slide deck:

1. **No two adjacent spreads share the same background color.** Always alternate.
2. **At least 4 distinct treatments per 10-spread issue.** Don't repeat hero × 10.
3. **Numerals must vary in style.** Solid Fraunces serif on one spread, outlined on the next, monospace on the next, sans-bold on the next.
4. **At least one spread should break the grid.** A rotated stamp, a giant outlined numeral, an SVG element bleeding off the edge.
5. **The hero (spread 01) gets the most weight.** Always the cover story. Always uses the boldest type.
6. **Reserve dark spreads for genuine contrast.** Two or three dark spreads in a 10-issue magazine, not five.
