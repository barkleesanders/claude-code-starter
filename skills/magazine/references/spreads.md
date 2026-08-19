# Spread Treatments Catalog

Each treatment is copy-paste-ready CSS + HTML. Pick from this catalog — don't reinvent. Each treatment has a `bestFor` list to guide selection.

## How to use this catalog

1. Read `design-system.md` first for the shared shell. **The overflow-protection rules there are mandatory.**
2. Walk the source content. For each item, pick the treatment whose `bestFor` matches the item's tone.
3. Customize content but keep the structural CSS intact.
4. Number the spreads 01 → NN. Class names follow `s01`, `s02`, etc.

## Known content-cutoff traps (learned the hard way)

- **Ledger/ASCII-art `<pre>` blocks** with long dotted lines like `federal cuts........-$225M` **overflow viewports** under ~1400px. Use short column layouts (max ~55 chars/line), `white-space: pre-wrap`, and font-size `clamp(14px, 1.4vw, 19px)`.
- **Bigstat numerals** like `$290,000` at font-size `clamp(180px, 26vw, 420px)` render ~1400px wide — overflows any laptop. Cap at `clamp(96px, 18vw, 280px)`.
- **Poster headlines** like `TAX THE RICH` at `clamp(80px, 12vw, 200px)` overflow when the word is long. Cap at `clamp(56px, 9vw, 140px)`.
- **Masthead title** at `clamp(80px, 14vw, 240px)` overflows with multi-word titles. Cap at `clamp(72px, 13vw, 220px)`.
- **Decorative pseudo-elements** (the giant `EXODUS`, `BROKEN`, `RECALL` stamps positioned off-edge) must have `pointer-events: none; z-index: 0;` and the parent must set `.parent > * { position: relative; z-index: 1; }` or they steal clicks and stack above content.
- **Equation blocks** with `display: inline-block` refuse to wrap. Use `display: block; white-space: pre-wrap; overflow-wrap: break-word;`.

---

## TREATMENT 1 — HERO (cream + accent)

**bestFor:** Cover story, the most important item, anything where you want quiet authority. Good for spread 01.

```css
.s01 {
  background: #f5f3ee;
  color: #1a1a1a;
  border-top: 12px solid #c33;
}
.s01 .numeral {
  font-size: clamp(220px, 32vw, 460px);
  color: #c33;
  margin-bottom: -40px;
  letter-spacing: -0.06em;
}
.s01 h2 {
  font-family: 'Fraunces', serif;
  font-weight: 900;
  font-size: clamp(56px, 8vw, 120px);
  line-height: 0.95;
  letter-spacing: -0.03em;
  max-width: 1300px;
  font-variation-settings: 'opsz' 144;
}
.s01 .standfirst {
  font-family: 'Fraunces', serif;
  font-style: italic;
  font-size: clamp(26px, 3vw, 38px);
  line-height: 1.35;
  color: #555;
  max-width: 980px;
  margin-top: 40px;
}
```

```html
<section class="spread s01">
  <div class="kicker">No. 01 · TOPIC · Cover Story</div>
  <span class="badge-applies">★ Applies directly to you</span>
  <div class="numeral">01</div>
  <h2>The headline goes here in big serif type.</h2>
  <p class="standfirst">The standfirst lede in italic Fraunces, sets up the rest.</p>
  <p class="source-line">Source · <a href="#">link</a> · metadata</p>
</section>
```

---

## TREATMENT 2 — ROSE ALERT STAMP (coral + rotated stamp)

**bestFor:** Things that broke, urgent warnings, security incidents, broken backups, bugs in prod.

```css
.s02 { background: #f7d4c8; color: #2a1010; position: relative; overflow: hidden; }
.s02::before {
  content: 'BROKEN';  /* swap for SCAM, ALERT, RECALL, etc */
  position: absolute; top: 80px; right: -40px;
  font-family: 'Inter', sans-serif; font-weight: 900;
  font-size: 220px; color: #c12c2c; opacity: 0.18;
  transform: rotate(-12deg); letter-spacing: -0.04em;
}
.s02 .stamp {
  display: inline-block;
  border: 6px solid #c12c2c; color: #c12c2c;
  padding: 18px 36px;
  font-family: 'Inter', sans-serif; font-weight: 900;
  font-size: 32px; letter-spacing: 0.2em;
  transform: rotate(-4deg); margin-bottom: 40px;
}
.s02 .numeral { font-size: clamp(180px, 24vw, 360px); color: #c12c2c; line-height: 0.9; }
.s02 h2 {
  font-family: 'Fraunces', serif; font-weight: 800;
  font-size: clamp(48px, 6.5vw, 96px); line-height: 1;
  letter-spacing: -0.025em; max-width: 1200px; margin-top: -20px;
}
.s02 .standfirst {
  font-family: 'Inter', sans-serif;
  font-size: clamp(22px, 2.4vw, 30px); line-height: 1.5;
  max-width: 920px; margin-top: 36px; font-weight: 400;
}
```

```html
<section class="spread s02">
  <div class="kicker">No. 02 · CATEGORY · Alert</div>
  <div class="stamp">SILENTLY BROKEN</div>
  <div class="numeral">02</div>
  <h2>The thing that broke.</h2>
  <p class="standfirst">What broke, when, and what to do about it.</p>
  <p class="source-line">Source · link · metadata</p>
</section>
```

---

## TREATMENT 3 — DARK MIDNIGHT (black + neon cyan)

**bestFor:** Security stories, hacking, supply-chain attacks, surveillance, privacy. Tech with a dark edge.

```css
.s03 { background: #0a0e1a; color: #d4ddef; }
.s03 .kicker { color: #6cf; }
.s03 .numeral {
  font-family: 'JetBrains Mono', monospace;
  font-size: clamp(180px, 26vw, 380px);
  color: #6cf; font-weight: 700;
  text-shadow: 0 0 60px rgba(102, 204, 255, 0.4);
}
.s03 h2 {
  font-family: 'Fraunces', serif; font-weight: 700;
  font-size: clamp(48px, 6.5vw, 96px); line-height: 1.02;
  letter-spacing: -0.02em; max-width: 1300px; color: #ffffff;
}
.s03 .standfirst {
  font-family: 'Inter', sans-serif;
  font-size: clamp(22px, 2.4vw, 30px); line-height: 1.5;
  max-width: 950px; margin-top: 36px; color: #a8b3cc;
}
.s03 .terminal-callout {
  font-family: 'JetBrains Mono', monospace;
  font-size: 24px; background: #1a2030;
  border-left: 4px solid #6cf;
  padding: 24px 32px; margin-top: 40px;
  color: #ffd166; max-width: 800px;
}
```

---

## TREATMENT 4 — MAGAZINE COVER (gradient + outlined numeral)

**bestFor:** Creative software, design tools, art, photography, video, anything visual.

```css
.s04 {
  background: linear-gradient(135deg, #1a1a3a 0%, #5e2ca5 50%, #ec5990 100%);
  color: #fff; overflow: hidden; position: relative;
}
.s04 .kicker { color: #fff; opacity: 0.7; }
.s04 .numeral {
  font-size: clamp(220px, 30vw, 440px);
  color: transparent;
  -webkit-text-stroke: 4px #fff;
  line-height: 0.9; font-style: italic;
  font-variation-settings: 'opsz' 144, 'SOFT' 100, 'WONK' 1;
}
.s04 h2 {
  font-family: 'Fraunces', serif; font-weight: 900;
  font-size: clamp(56px, 8vw, 120px); line-height: 0.92;
  letter-spacing: -0.03em; max-width: 1300px; margin-top: -40px;
}
.s04 .standfirst {
  font-family: 'Fraunces', serif; font-style: italic;
  font-size: clamp(24px, 2.8vw, 34px); line-height: 1.4;
  max-width: 950px; margin-top: 36px;
  color: rgba(255,255,255,0.92); font-weight: 300;
}
.s04 .price-tag {
  display: inline-block;
  background: #fff; color: #1a1a3a;
  padding: 14px 28px;
  font-family: 'Fraunces', serif; font-weight: 900;
  font-size: 36px; margin-top: 32px;
  transform: rotate(2deg);
}
```

---

## TREATMENT 5 — TERMINAL (CRT green-on-black)

**bestFor:** CLI tools, version control, dev infrastructure, sysadmin, anything that lives in the terminal.

```css
.s05 { background: #0d1117; color: #00ff88; font-family: 'JetBrains Mono', monospace; }
.s05 .kicker { color: #00ff88; font-family: 'JetBrains Mono', monospace; font-size: 18px; }
.s05 .kicker::before { content: '$ '; opacity: 0.5; }
.s05 .numeral {
  font-family: 'JetBrains Mono', monospace;
  font-size: clamp(200px, 28vw, 400px);
  color: #00ff88; line-height: 0.9; font-weight: 700;
}
.s05 h2 {
  font-family: 'JetBrains Mono', monospace; font-weight: 700;
  font-size: clamp(44px, 5.5vw, 78px); line-height: 1.1;
  color: #fff; max-width: 1200px; margin-top: 20px;
}
.s05 .blinker { display: inline-block; animation: blink 1s steps(2) infinite; color: #00ff88; }
@keyframes blink { 50% { opacity: 0; } }
.s05 .standfirst {
  font-family: 'JetBrains Mono', monospace;
  font-size: clamp(20px, 2.2vw, 26px); line-height: 1.6;
  max-width: 950px; margin-top: 36px; color: #c9d1d9;
}
.s05 .standfirst .hl { color: #ffd166; }
.s05 pre {
  background: #161b22; border-left: 3px solid #00ff88;
  padding: 24px 28px; margin-top: 36px;
  font-size: 22px; color: #79c0ff;
  max-width: 800px; overflow-x: auto;
}
```

---

## TREATMENT 6 — POSTER (yellow + black manifesto)

**bestFor:** Civic action, protest, activism, manifestos, urgent calls to action. High visual energy.

```css
.s06 { background: #ffe600; color: #000; }
.s06 .numeral {
  font-family: 'Inter', sans-serif; font-weight: 900;
  font-size: clamp(220px, 30vw, 440px); line-height: 0.85;
  letter-spacing: -0.06em; color: #000;
}
.s06 h2 {
  font-family: 'Inter', sans-serif; font-weight: 900;
  font-size: clamp(80px, 12vw, 200px); line-height: 0.85;
  letter-spacing: -0.05em; text-transform: uppercase; margin-top: -20px;
}
.s06 h2 span {
  background: #000; color: #ffe600;
  padding: 0 16px; display: inline-block;
}
.s06 .standfirst {
  font-family: 'Inter', sans-serif; font-weight: 600;
  font-size: clamp(24px, 3vw, 38px); line-height: 1.3;
  max-width: 1200px; margin-top: 40px;
}
.s06 .action-bar {
  border-top: 8px solid #000; border-bottom: 8px solid #000;
  padding: 24px 0; margin-top: 48px;
  font-family: 'Inter', sans-serif; font-weight: 800;
  font-size: clamp(22px, 2.5vw, 32px);
  letter-spacing: 0.05em; text-transform: uppercase;
}
```

---

## TREATMENT 7 — VINYL VINTAGE (cream sepia + record SVG)

**bestFor:** Cultural heritage, archives, music, art history, anything where warmth and nostalgia fit.

```css
.s07 {
  background: #f0e7d4; color: #2a1f10;
  background-image:
    radial-gradient(circle at 20% 20%, rgba(180, 130, 70, 0.08) 0, transparent 50%),
    radial-gradient(circle at 80% 80%, rgba(180, 130, 70, 0.08) 0, transparent 50%);
  position: relative;
}
.s07::before {
  content: ''; position: absolute;
  top: 80px; right: 80px;
  width: 280px; height: 280px;
  border-radius: 50%;
  background: radial-gradient(circle, #2a1f10 0 30px, #1a1208 31px 60px, #2a1f10 61px 90px, #1a1208 91px 120px, #2a1f10 121px 140px);
  border: 8px solid #2a1f10;
}
.s07::after {
  content: ''; position: absolute;
  top: 200px; right: 200px;
  width: 40px; height: 40px;
  border-radius: 50%;
  background: #c12c2c; border: 4px solid #2a1f10;
}
.s07 .kicker { color: #8b5a2b; font-family: 'Fraunces', serif; font-style: italic; font-weight: 600; }
.s07 .numeral {
  font-size: clamp(180px, 24vw, 340px); color: #2a1f10;
  font-style: italic;
  font-variation-settings: 'opsz' 144, 'SOFT' 100, 'WONK' 1;
  line-height: 0.9;
}
.s07 h2 {
  font-family: 'Fraunces', serif; font-weight: 700;
  font-size: clamp(48px, 6.5vw, 92px); line-height: 1.05;
  letter-spacing: -0.02em; max-width: 1100px;
  font-variation-settings: 'opsz' 144;
}
.s07 .standfirst {
  font-family: 'Fraunces', serif; font-style: italic;
  font-size: clamp(24px, 2.6vw, 32px); line-height: 1.45;
  max-width: 900px; margin-top: 36px; color: #4a3520;
}
.s07 .lineup {
  font-family: 'Fraunces', serif; font-weight: 800;
  font-size: clamp(28px, 3vw, 40px); margin-top: 36px;
  color: #2a1f10; letter-spacing: 0.02em;
}
.s07 .lineup span { color: #c12c2c; }
```

---

## TREATMENT 8 — ACADEMIC DROP-CAP (paper + scholarly serif)

**bestFor:** Longform analysis, web standards, policy explainers, anything that wants to feel like a printed essay.

```css
.s08 { background: #faf7f0; color: #1a1a1a; padding: 100px 8vw; }
.s08 .kicker {
  font-family: 'Fraunces', serif; font-style: italic;
  font-weight: 400; letter-spacing: 0.08em;
  color: #888; text-transform: none; font-size: 22px;
}
.s08 .numeral {
  font-size: clamp(180px, 26vw, 380px);
  color: #1a1a1a; font-weight: 300;
  font-variation-settings: 'opsz' 144;
  line-height: 0.9;
}
.s08 h2 {
  font-family: 'Fraunces', serif; font-weight: 400;
  font-size: clamp(56px, 7vw, 100px); line-height: 1.05;
  letter-spacing: -0.025em; max-width: 1300px;
  font-variation-settings: 'opsz' 144;
}
.s08 h2 em { font-style: italic; color: #5a3a78; }
.s08 .body { margin-top: 48px; max-width: 920px; }
.s08 .body p {
  font-family: 'Fraunces', serif;
  font-size: clamp(22px, 2.3vw, 28px); line-height: 1.5;
  margin-bottom: 24px;
}
.s08 .body p:first-of-type::first-letter {
  font-family: 'Fraunces', serif; font-weight: 900;
  font-size: 6em; line-height: 0.85;
  float: left; margin: 8px 16px 0 0;
  color: #5a3a78;
  font-variation-settings: 'opsz' 144;
}
```

---

## TREATMENT 9 — BIG-STAT FINISH (black + amber, single huge number)

**bestFor:** Stats, data points, outcomes, headline metrics, "the number you need to remember."

```css
.s09 { background: #1a1a1a; color: #fff; }
.s09 .kicker { color: #ffd166; }
.s09 .numeral { font-size: clamp(160px, 22vw, 320px); color: #ffd166; line-height: 0.9; }
.s09 .bigstat {
  font-family: 'Fraunces', serif; font-weight: 900;
  font-size: clamp(180px, 24vw, 360px); line-height: 0.85;
  letter-spacing: -0.05em; color: #ffd166; margin-top: 24px;
  font-variation-settings: 'opsz' 144;
}
.s09 h2 {
  font-family: 'Fraunces', serif; font-weight: 700;
  font-size: clamp(48px, 6vw, 88px); line-height: 1;
  letter-spacing: -0.025em; max-width: 1200px; margin-top: 24px;
}
.s09 .standfirst {
  font-family: 'Inter', sans-serif;
  font-size: clamp(22px, 2.4vw, 30px); line-height: 1.5;
  max-width: 950px; margin-top: 36px; color: #d0d0d0;
}
.s09 .closer {
  font-family: 'Fraunces', serif; font-style: italic;
  font-weight: 400; font-size: clamp(28px, 3vw, 40px);
  line-height: 1.3; color: #ffd166; margin-top: 48px;
  max-width: 900px; border-left: 4px solid #ffd166; padding-left: 28px;
}
```

---

## TREATMENT 10 — SCIENTIFIC (graph paper + equation block)

**bestFor:** Research papers, data findings, technical breakthroughs, academic results.

```css
.s10 {
  background: #ecebe7; color: #1a1a1a;
  background-image:
    linear-gradient(rgba(0,0,0,0.04) 1px, transparent 1px),
    linear-gradient(90deg, rgba(0,0,0,0.04) 1px, transparent 1px);
  background-size: 40px 40px;
}
.s10 .kicker {
  font-family: 'Space Grotesk', sans-serif;
  color: #1a1a1a; background: #fff;
  display: inline-block; padding: 8px 16px;
  border: 2px solid #1a1a1a;
}
.s10 .numeral {
  font-family: 'Space Grotesk', sans-serif;
  font-size: clamp(200px, 28vw, 400px);
  color: #1a1a1a; line-height: 0.9; font-weight: 700;
}
.s10 h2 {
  font-family: 'Space Grotesk', sans-serif; font-weight: 700;
  font-size: clamp(48px, 6.5vw, 92px); line-height: 1.05;
  letter-spacing: -0.025em; max-width: 1300px;
}
.s10 .standfirst {
  font-family: 'Inter', sans-serif;
  font-size: clamp(22px, 2.4vw, 30px); line-height: 1.5;
  max-width: 950px; margin-top: 36px;
}
.s10 .equation {
  font-family: 'JetBrains Mono', monospace;
  font-size: clamp(24px, 2.8vw, 34px);
  background: #fff; border: 2px solid #1a1a1a;
  padding: 24px 32px; margin-top: 40px;
  display: inline-block; box-shadow: 8px 8px 0 #1a1a1a;
}
.s10 .equation span.gain { color: #c33; font-weight: 700; }
.s10 .institutions {
  font-family: 'Space Grotesk', sans-serif; font-weight: 500;
  font-size: clamp(18px, 1.9vw, 22px); margin-top: 32px;
  color: #555; letter-spacing: 0.05em; text-transform: uppercase;
}
```

---

## TREATMENT 11 — FIELD NOTES (newsprint + dateline)

**bestFor:** Meeting minutes, civic body reports, transcript-derived items, anything with a "filed by reporter" feel.

```css
.s11 {
  background: #e8e3d8; color: #1a1a1a;
  background-image:
    repeating-linear-gradient(0deg, transparent, transparent 38px, rgba(0,0,0,0.04) 38px, rgba(0,0,0,0.04) 39px);
}
.s11 .kicker {
  font-family: 'Inter', sans-serif; font-weight: 700;
  color: #1a3a5c;
}
.s11 .dateline {
  font-family: 'Fraunces', serif; font-style: italic;
  font-weight: 700; font-size: clamp(24px, 2.4vw, 30px);
  text-transform: uppercase; letter-spacing: 0.1em;
  margin-bottom: 16px; color: #1a3a5c;
}
.s11 .numeral {
  font-size: clamp(180px, 24vw, 360px);
  color: #1a3a5c; line-height: 0.9;
}
.s11 h2 {
  font-family: 'Fraunces', serif; font-weight: 800;
  font-size: clamp(48px, 6.5vw, 92px); line-height: 1.02;
  letter-spacing: -0.02em; max-width: 1200px;
  font-variation-settings: 'opsz' 144;
  border-bottom: 4px solid #1a1a1a; padding-bottom: 24px;
}
.s11 .body p {
  font-family: 'Fraunces', serif;
  font-size: clamp(22px, 2.4vw, 30px); line-height: 1.55;
  max-width: 920px; margin-top: 32px;
}
.s11 .pullquote {
  font-family: 'Fraunces', serif; font-style: italic;
  font-size: clamp(28px, 3.2vw, 44px); line-height: 1.3;
  color: #1a3a5c;
  border-left: 6px solid #c33;
  padding-left: 28px; margin: 36px 0;
  max-width: 1000px;
}
```

---

## TREATMENT 12 — OCEAN (deep blue + teal accent)

**bestFor:** Environmental, infrastructure, marine, water utilities, climate adaptation. (Bonus: works for anything San Francisco / Bay Area / coastal.)

```css
.s12 { background: #0d2438; color: #e8e3d8; }
.s12 .kicker { color: #5fb8b8; }
.s12 .numeral {
  font-size: clamp(200px, 28vw, 400px);
  color: #5fb8b8; line-height: 0.9;
  font-variation-settings: 'opsz' 144;
}
.s12 h2 {
  font-family: 'Fraunces', serif; font-weight: 700;
  font-size: clamp(48px, 6.5vw, 96px); line-height: 1.02;
  letter-spacing: -0.02em; max-width: 1300px; color: #fff;
}
.s12 .standfirst {
  font-family: 'Fraunces', serif; font-style: italic;
  font-size: clamp(24px, 2.6vw, 32px); line-height: 1.4;
  max-width: 950px; margin-top: 36px; color: #b8c8d4;
}
```

---

## TREATMENT 13 — FOREST (deep green + cream)

**bestFor:** Nature, biology, climate, food systems, sustainability.

```css
.s13 { background: #1a2a1a; color: #e8e3d8; }
.s13 .kicker { color: #a8c47e; }
.s13 .numeral {
  font-size: clamp(200px, 28vw, 400px);
  color: #a8c47e; line-height: 0.9;
  font-variation-settings: 'opsz' 144;
}
.s13 h2 {
  font-family: 'Fraunces', serif; font-weight: 700;
  font-size: clamp(48px, 6.5vw, 96px); line-height: 1.02;
  letter-spacing: -0.02em; max-width: 1300px; color: #fff;
}
.s13 .standfirst {
  font-family: 'Fraunces', serif; font-style: italic;
  font-size: clamp(24px, 2.6vw, 32px); line-height: 1.4;
  max-width: 950px; margin-top: 36px; color: #c0c8b0;
}
```

---

## Treatment selection cheat-sheet

When picking treatments, run through this list:

| Item tone | Treatment |
|---|---|
| Cover / hero | 1 (Hero cream) |
| Broken / urgent / warning | 2 (Rose alert stamp) |
| Security / hacking / surveillance | 3 (Dark midnight) |
| Creative software / design / video | 4 (Magazine cover) |
| Dev tools / CLI / version control | 5 (Terminal) |
| Civic action / protest / manifesto | 6 (Poster) |
| Cultural / archival / music | 7 (Vinyl vintage) |
| Longform / policy / web standards | 8 (Academic drop-cap) |
| Single-stat or finishing finding | 9 (Big-stat) |
| Research / scientific / data | 10 (Scientific graph paper) |
| Meeting minutes / civic body / report | 11 (Field notes newsprint) |
| Environmental / infrastructure / coastal | 12 (Ocean) |
| Nature / climate / biology | 13 (Forest) |

If two items would land on the same treatment, escalate one to a different palette (e.g., second security story → use 9 with security-themed copy instead of 3 again).
