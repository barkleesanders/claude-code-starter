# Aesthetic Core — Design Direction & Anti-Slop Rules

**Load this for**: every `/design` invocation, before Stitch or Code mode fires. The direction chosen here feeds into whichever transport runs next.

---

## 4-Pillar Design Thinking

Before any prompt or code: pin these four.

1. **Purpose** — what problem does this interface solve? Who actually uses it?
2. **Tone** — pick ONE extreme. Don't average. Don't hedge.
3. **Constraints** — framework, performance budget, accessibility floor.
4. **Differentiation** — what's the ONE thing someone will remember a week later?

Bold maximalism and refined minimalism both work. **Intentionality** is what matters, not intensity.

---

## Aesthetic Direction Menu (pick ONE, don't blend)

| Tone | Signature traits |
|---|---|
| **Brutalist / raw** | Exposed structure, mono-grid, raw concrete colors, oversized type, no shadows |
| **Maximalist chaos** | Overlapping layers, clashing-on-purpose colors, dense ornament, vibrating motion |
| **Retro-futuristic** | CRT glow, scanlines, chromatic aberration, monospace + display pairing |
| **Organic / natural** | Hand-drawn curves, paper/grain textures, muted earth palette, gentle motion |
| **Luxury / refined** | Generous whitespace, fine hairlines, deep blacks, gold/champagne accents, serif display |
| **Playful / toy-like** | Bouncy spring physics, candy colors, rounded everything, oversized illustrations |
| **Editorial / magazine** | Big drop caps, asymmetric grids, body-text-as-hero, rule lines, footnotes as design |
| **Art deco / geometric** | Symmetric ornament, gold-on-black, stepped forms, condensed sans + script |
| **Pastel / soft** | Low-saturation palette, gradient meshes, frosted glass, gentle blur |
| **Industrial / utilitarian** | Mono fonts, technical diagrams, gridlines visible, status-bar-everywhere |

You may invent one. You may NOT pick "modern" — that's not a direction, it's a non-answer.

---

## The Five Aesthetic Areas

Once direction is locked, every decision below must serve it.

### 1. Typography
- **Pair a distinctive display font with a refined body font.** Two fonts is the minimum, three is fine, four is too many.
- Display fonts to consider: Fraunces, Söhne, GT Sectra, Migra, Cabinet Grotesk, IBM Plex Serif, Druk, Domaine Display, Tiempos Headline, JetBrains Mono (yes, for headlines, intentionally).
- Body fonts to consider: Source Serif, Crimson Pro, IBM Plex Sans, Geist, GT America, Söhne, Inter Tight (when you genuinely need it — see ban below).
- Use real type-scale ratios (1.25 / 1.333 / 1.5 / golden), not arbitrary px jumps.

### 2. Color & Theme
- **Use OKLCH, not hex/rgb/hsl.** OKLCH gives perceptually uniform lightness — `oklch(0.6 0.15 250)` reads the same brightness as `oklch(0.6 0.15 30)`. Hex doesn't. Reduce chroma as lightness approaches 0 or 100; high chroma at extremes looks garish.
- **Never `#000` or `#fff` raw.** Tint every neutral toward the brand hue (chroma 0.005–0.01 is enough). Pure black/white reads as undesigned default.
- **CSS variables** for every color. No raw color values in component code.
- **Pick a color strategy** before picking colors. Four steps on the commitment axis:
  - **Restrained** — tinted neutrals + one accent ≤10%. Product default; brand minimalism.
  - **Committed** — one saturated color carries 30–60% of the surface. Brand default for identity-driven pages.
  - **Full palette** — 3–4 named roles, each used deliberately. Brand campaigns; product data viz.
  - **Drenched** — the surface IS the color. Brand heroes, campaign pages.
  - The "60-30-10 / one accent ≤10%" rule applies to **Restrained only**. Committed / Full palette / Drenched exceed it on purpose. Don't collapse every design to Restrained by reflex.
- Pick a *temperature* (warm or cool) and stick to it. Mixed-temperature palettes look accidental.
- **Dark vs light is never a default.** Not dark "because tools look cool dark." Not light "to be safe." Before choosing, write **one sentence of physical scene**: who uses this, where, under what ambient light, in what mood. If the sentence doesn't force the answer, it's not concrete enough — add detail until it does. *"Observability dashboard"* does not force an answer. *"SRE glancing at incident severity on a 27-inch monitor at 2am in a dim room"* does. Run the sentence, not the category.

### 3. Motion
- **One well-orchestrated page load with staggered reveals** beats twenty scattered micro-interactions.
- CSS-first for HTML/Vue/Svelte. Motion (formerly Framer Motion) for React. GSAP for sequence-heavy work.
- Use scroll-triggering and hover states that **surprise** — magnetic buttons, text-mask-on-hover, scrambling type.
- Don't animate everything. The point of motion is contrast: things that move feel important *because* most things don't.

### 4. Spatial Composition
- Unexpected layouts beat predictable ones. **Asymmetry, overlap, diagonal flow.**
- Pick one: **generous negative space** OR **controlled density**. Mid-density is the dead zone.
- Grid-breaking elements (something hangs into the margin, a heading runs full-bleed, a column inverts) make a layout memorable.

### 5. Backgrounds & Visual Details
- Solid colors are the absence of design. Add atmosphere: **gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, grain overlays.**
- Match the texture to the direction. Grain belongs in organic/editorial; chromatic aberration belongs in retro-futuristic; gold leaf belongs in luxury/art-deco.

---

## Anti-Slop Banlist (NEVER ship these defaults)

| Category | Banned default | Why |
|---|---|---|
| **Fonts** | Inter, Roboto, Arial, system-ui (when used alone), Space Grotesk (as the *default* choice) | Every AI-generated SaaS page on the internet uses these. Picking them signals "I didn't decide." |
| **Color schemes** | Purple gradient on white. Blue-to-purple. "Pastel SaaS." Vercel-clone neutral gray. | Look at any Stable Diffusion `--style "minimalist SaaS"` output — these three appear in 90% of them. |
| **Layouts** | Centered hero + three feature cards + testimonial slider + pricing toggle + CTA. | The Linear/Stripe/Vercel template, run a million times. |
| **Components** | Default shadcn-everything. Untouched MUI. Raw Tailwind UI examples without customization. | Free components are starting points, not finished work. |
| **Generic copy** | "Build better, faster." "The all-in-one platform." "Designed for teams." "Powered by AI." | If you'd find it on twenty other landing pages, rewrite it. |

When you catch yourself reaching for one of these, **stop and pick the deliberate opposite** — that's where the design lives.

---

## Absolute Bans (match-and-refuse)

These are visual patterns that are never intentional. If you're about to write any of them, rewrite the element with different structure. Adapted from [Impeccable](https://github.com/pbakaus/impeccable).

- **Side-stripe borders.** `border-left` / `border-right` greater than 1px used as a colored accent on cards, list items, callouts, or alerts. Rewrite with full borders, background tints, leading numbers/icons, or nothing.
- **Gradient text.** `background-clip: text` combined with a gradient background. Decorative, never meaningful. Use a single solid color. Emphasis via weight or size.
- **Glassmorphism as default.** Blurs and frosted-glass cards used decoratively. Rare and purposeful, or nothing.
- **The hero-metric template.** Big number, small label, supporting stats, gradient accent. SaaS cliché.
- **Identical card grids.** Same-sized cards with icon + heading + text, repeated 3×, 4×, 6× endlessly.
- **Modal as first thought.** Modals are usually laziness. Exhaust inline / progressive alternatives first.
- **No em dashes in UI copy.** Use commas, colons, semicolons, periods, or parentheses. Also not `--`.

---

## The AI Slop Test (two altitudes)

If someone could look at the interface and say "AI made that" without doubt, it failed. Run **both** checks:

- **First-order:** could someone guess the theme + palette from the category alone? *"observability → dark blue"*, *"healthcare → white + teal"*, *"finance → navy + gold"*, *"crypto → neon on black"*. If yes, that's the first training-data reflex. Rework the scene sentence and color strategy until the answer isn't obvious from the domain.
- **Second-order:** could someone guess the aesthetic family from category-plus-anti-reference? *"AI workflow tool that's not SaaS-cream → editorial-typographic"*, *"fintech that's not navy-and-gold → terminal-native dark mode"*. That's the trap one tier deeper — the first reflex was avoided, the second wasn't. Rework until **both** answers are not obvious.

---

## Vague → Professional Vocabulary Table

When the user gives a fuzzy brief, translate before passing to Stitch or writing code:

| Vague | Professional |
|:---|:---|
| "menu at the top" | sticky navigation bar with logo and list items |
| "big photo" | high-impact hero section with full-width imagery |
| "list of things" | responsive card grid with hover states and subtle elevations |
| "button" | primary call-to-action button with micro-interactions |
| "form" | clean form with labeled input fields, validation states, and submit button |
| "sidebar" | collapsible side navigation with icon-label pairings |
| "popup" | modal dialog with overlay and smooth entry animation |
| "make it pop" | dominant accent color with a sharp contrast layer + subtle motion on the hero CTA |
| "modern looking" | (refuse — push the user to pick a direction from the menu above) |
| "clean" | controlled negative space, single dominant typeface, restrained palette |

---

## Match Implementation to Direction

The final test: **does the code/Stitch-prompt complexity match the aesthetic complexity?**

- **Maximalist direction** → elaborate code, extensive animations, multiple background layers, custom cursors, ornament.
- **Minimalist direction** → precise spacing, single typeface, deliberate whitespace, one hero motion moment, restraint everywhere else.

If you picked "brutalist raw" and wrote shadcn defaults with a purple gradient — the direction didn't land. Re-do it.
