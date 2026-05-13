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
- **CSS variables** for every color. No raw hex in component code.
- **Dominant + sharp accent** beats evenly-distributed palettes every time. 60-30-10 is the floor, not the ceiling.
- Pick a *temperature* (warm or cool) and stick to it. Mixed-temperature palettes look accidental.
- Vary light vs. dark across generations — don't default to dark mode every time.

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
