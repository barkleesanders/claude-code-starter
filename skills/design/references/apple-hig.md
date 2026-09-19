# Apple Human Interface Guidelines — binding design gate for `/design`

**Source of truth:** https://developer.apple.com/design/ → Human Interface Guidelines
https://developer.apple.com/design/human-interface-guidelines/ (all pages below retrieved
2026-09-14 from Apple's own page JSON at
`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json`).
Every number in this file is copied from the HIG page it cites — not from memory. The HIG has
per-page **change logs**; treat this file as a cache and re-fetch the page before relying on a
specific value (Decay Rule).

**How to re-read any HIG page live (no key, ~1s):**
```bash
# whole page as markdown (sosumi MCP): mcp__sosumi__fetchAppleDocumentation path=/design/human-interface-guidelines/<slug>
# or just the bold rule sentences from Apple's JSON:
curl -sL https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<slug>.json
```

---

## Scope — when this gate is binding vs. baseline

| Target surface | HIG status |
|---|---|
| Native iOS / iPadOS / macOS / watchOS / tvOS / visionOS (SwiftUI, UIKit, AppKit, Rust-core + Swift shell) | **BINDING.** Every rule below applies; Phase 0 direction may not override it. |
| Capacitor / WKWebView / SFSafariViewController surfaces, `/ios` webview work, App Clips, widgets | **BINDING** for accessibility, layout, safe areas, control sizes, motion, Dark Mode, writing. System font (SF) via `font-family: -apple-system, system-ui` unless the Phase 0 brief names a licensed custom face that meets the legibility table. |
| Web / Cloudflare sites, HTML reports, Hallmark/Stitch output for the browser | **BASELINE.** The platform-agnostic sections (§1 Accessibility, §3 Layout, §4 Color, §5 Dark Mode, §6 Motion, §8 Writing, §9 Branding) are mandatory minimums layered under `aesthetic-core.md` + Hallmark's 57 gates. Platform-specific items (Liquid Glass, SF Symbols, safe-area insets, system semantic colors) apply only if the brief targets Apple devices. |

**Precedence when rules collide:** strictest wins, and on an Apple platform the HIG is the
strictest. Concretely: `aesthetic-core.md` bans "default" fonts for *web* slop reasons; on a native
Apple surface the HIG says the opposite — use the system fonts and text styles (it forbids
embedding them). The HIG wins there. Everything in Hallmark's honest-copy / no-fabrication
discipline still applies on top.

---

## §1 Accessibility — https://developer.apple.com/design/human-interface-guidelines/accessibility

Apple's three tests: an accessible interface is **Intuitive, Perceivable, Adaptable.**

**Text size (default / minimum, custom fonts included):**

| Platform | Default | Minimum |
|---|---|---|
| iOS, iPadOS | 17 pt | 11 pt |
| macOS | 13 pt | 10 pt |
| tvOS | 29 pt | 23 pt |
| visionOS | 17 pt | 12 pt |
| watchOS | 16 pt | 12 pt |

- Let people enlarge text **≥ 200 %** (140 % on watchOS) — adopt Dynamic Type or ship your own.
- Thin weights need larger sizes; HIG: avoid Ultralight/Thin/Light in UI text.

**Contrast (WCAG AA values Accessibility Inspector enforces):**

| Text | Minimum ratio |
|---|---|
| ≤ 17 pt, any weight | **4.5 : 1** |
| 18 pt, any weight | 3 : 1 |
| Bold, any size | 3 : 1 |

Check contrast in **both** light and dark appearances. If you can't hit it by default, you must at
least hit it when *Increase Contrast* is on.

**Control size (default / minimum):**

| Platform | Default | Minimum |
|---|---|---|
| iOS, iPadOS | **44 × 44 pt** | 28 × 28 pt |
| macOS | 28 × 28 pt | 20 × 20 pt |
| tvOS | 66 × 66 pt | 56 × 56 pt |
| visionOS | 60 × 60 pt | 28 × 28 pt |
| watchOS | 44 × 44 pt | 28 × 28 pt |

- Spacing matters as much as size: **~12 pt padding around bezeled elements, ~24 pt around
  bezel-less ones.**
- Convey information with **more than color alone** (shape/icon + color).
- Prefer **system-defined colors** (they carry accessible variants for Increase Contrast).
- Every gesture needs a **non-gesture alternative** (swipe-to-delete ⇒ also an Edit/Delete button).
- Prefer simple system gestures; no custom multi-finger/multi-hand gestures for frequent actions.
- **Minimize time-boxed UI** (auto-dismissing toasts/views) — prefer explicit dismissal.
- Never autoplay audio/video without visible start/stop controls.
- **Reduce Motion:** tighten springs, track gestures directly, no z-axis depth animation, replace
  x/y/z transitions with fades, don't animate into/out of blurs.
- Label everything for VoiceOver / Voice Control / Full Keyboard Access; don't override system
  keyboard shortcuts.
- Ship correct **Accessibility Nutrition Labels** in App Store Connect — never claim a feature
  the app doesn't support (fabrication rule).

## §2 Typography — https://developer.apple.com/design/human-interface-guidelines/typography

- System faces: **SF Pro** (iOS/iPadOS/macOS/tvOS/visionOS), **SF Compact** (watchOS), **New
  York** serif companion. Variable fonts with dynamic optical sizing. **Don't embed the system
  fonts** — use `Font.Design.default` / `.serif`; on the web use `-apple-system, system-ui`.
- Use the **built-in text styles** (Large Title → Caption 2) so Dynamic Type works. iOS "Large"
  (default) scale: Large Title 34/41 Bold-emph · Title 1 28/34 · Title 2 22/28 · Title 3 20/25 ·
  Headline 17/22 Semibold · **Body 17/22** · Callout 16/21 · Subhead 15/20 · Footnote 13/18 ·
  Caption 1 12/16 · Caption 2 11/13 (size/leading pt). macOS Body is 13/16. Full tables incl.
  AX1–AX5 and tracking values are on the page.
- **Minimize the number of typefaces**, even in a highly customised interface.
- Prefer Regular/Medium/Semibold/Bold; **avoid light weights**.
- Layout must survive **every** Dynamic Type size: no truncation of primary text, stack inline
  items at AX sizes, reduce columns, keep hierarchy order stable, scale meaningful icons with text
  (SF Symbols do this for free). Test with Settings › Accessibility › Larger Text on.
- macOS has no Dynamic Type; visionOS uses bolder body/title and prefers 2D text.

## §3 Layout — https://developer.apple.com/design/human-interface-guidelines/layout

- Order content by importance in reading order; align; group; **progressive disclosure**.
- **Differentiate controls from content** — this is what Liquid Glass is for.
- Layout is driven by **size classes, not device type or orientation**; keep functionality
  identical across size classes; consider all combinations.
- **Respect the safe area** (notch, Dynamic Island, home indicator, camera housing). tvOS insets:
  60 pt top/bottom, 80 pt sides.
- macOS: don't put critical controls at the bottom of a window; don't draw behind the camera housing.
- Consistent spacing; preview on multiple devices, size classes, localisations, and text sizes.
- watchOS: ≤ 2–3 controls side by side.

## §4 Color — https://developer.apple.com/design/human-interface-guidelines/color

- Use color **consistently** — one color, one meaning; never rely on color alone.
- Colors must work in **light, dark, and Increase Contrast**; test under real lighting and True Tone.
- **Don't hard-code system color values**; don't redefine semantic colors' meanings.
- **Apply color sparingly on Liquid Glass** — reserve it for elements that truly need emphasis.
- Prefer system color pickers; tag images with color profiles (sRGB baseline, P3 where useful).
- A **limited palette that coordinates with the app icon** communicates brand while deferring to content.
- Prefer color in **bold text and large areas**, not in light text or tiny areas.

## §5 Dark Mode — https://developer.apple.com/design/human-interface-guidelines/dark-mode

- **No app-specific appearance toggle** — follow the system setting (Auto included).
- Both appearances must look good and stay legible with Increase Contrast / Reduce Transparency.
- Use **semantic/system colors** (label primary→quaternary, system backgrounds base/elevated) so
  the app adapts automatically; soften pure-white content backgrounds in dark.
- Prefer **SF Symbols**; supply separate light/dark icon assets only when a single one fails.
- Use system views for text fields/text views; add some transparency in custom component backgrounds.

## §6 Motion — https://developer.apple.com/design/human-interface-guidelines/motion

- Motion is **purposeful**, never decorative; **optional** (Reduce Motion honoured).
- Realistic, gesture-tracking, **brief and precise** feedback; **cancellable** — never make people
  wait for an animation.
- **Don't add motion to frequent interactions** — the system already animates those.
- Animated SF Symbols are allowed where they carry meaning.
- visionOS: avoid peripheral motion, world rotation, sustained oscillation (~0.2 Hz); give a
  stationary frame of reference; fade rather than move relocating objects.

## §7 Materials / Liquid Glass — https://developer.apple.com/design/human-interface-guidelines/materials

Liquid Glass is the current system design language (WWDC25: "Meet Liquid Glass"
https://developer.apple.com/videos/play/wwdc2025/219/ and "Get to know the new design system"
https://developer.apple.com/videos/play/wwdc2025/356/).

- **Don't use Liquid Glass in the content layer** — it exists to separate *controls* from content.
- **Use it sparingly**; standard system components already adopt it. Custom glass on glass = wrong.
- Two variants, *regular* and *clear*: **clear only over visually rich backgrounds.**
- Choose materials by **semantic meaning**, not by the color they impart.
- Put **vibrant** (system) colors on materials for legibility; consider contrast + separation when
  stacking blur/vibrancy.
- This is *not* the `aesthetic-core.md` "decorative glassmorphism" ban being lifted — Apple's own
  page says decorative/extra glass is a mistake. Glass = system chrome layer only.

## §8 Writing — https://developer.apple.com/design/human-interface-guidelines/writing

- Decide the app's **voice**, vary **tone** by context; be **clear**, write for everyone, be
  **action-oriented**, build consistent language patterns and capitalisation.
- Possessive pronouns sparingly ("Favorites", not "Your Favorites").
- **Empty states give clear next steps.** Error messages sit next to the error, say what happened
  and how to fix it. Text fields carry hints. Settings labels stay plain.
- Consistent with this account's UI Copy Minimalism rule: no helper text that restates the label.

## §9 Branding — https://developer.apple.com/design/human-interface-guidelines/branding

- **Branding always defers to content.** Accent color judiciously; brand via **familiar
  components**, not custom chrome. No logo on every screen; **launch screen is not a brand
  billboard.** Apple trademarks never in app name or images; no replicas of Apple hardware.

## §10 Icons / App icons / SF Symbols

- Interface icons: simple, consistent, vector (PDF/SVG), **alt-text for every custom icon**,
  inclusive imagery, text only when essential.
  https://developer.apple.com/design/human-interface-guidelines/icons
- App icons (Icon Composer era, https://developer.apple.com/icon-composer/): layered, vector,
  clearly-defined edges, centered content, **no black backgrounds**, no replicated UI or Apple
  hardware, consistent across platforms, light/dark/tinted variants from the same design, let the
  system apply blur/specular. https://developer.apple.com/design/human-interface-guidelines/app-icons
- SF Symbols (https://developer.apple.com/sf-symbols/): rendering modes Monochrome / Hierarchical /
  Palette / Multicolor; **variable color = change, not depth**; animate judiciously; custom symbols
  follow the template and carry alt-text.
  https://developer.apple.com/design/human-interface-guidelines/sf-symbols

## §11 Patterns — https://developer.apple.com/design/human-interface-guidelines/patterns

Before designing any of these flows, read the matching HIG page live:
Charting data · Collaboration and sharing · Drag and drop · **Entering data** · **Feedback** ·
File management · Going full screen · Launching · Live-viewing apps · **Loading** · **Managing
accounts** · Managing notifications · **Modality** · Multitasking · Offering help · **Onboarding** ·
Playing audio/haptics/video · Printing · Ratings and reviews · **Searching** · **Settings** ·
Undo and redo · Workouts. Slug = kebab-case of the title.

## §12 Components / Inputs / Technologies (component reference index)

Use the **system component** whenever one exists (HIG Branding + Accessibility both say so);
design a custom control only when the system one cannot express the need, and then match its
size, states, and a11y semantics.

**Components** ([Content](content), [Layout and organization](layout-and-organization), [Menus and actions](menus-and-actions), [Navigation and search](navigation-and-search), [Presentation](presentation), [Selection and input](selection-and-input), [Status](status), [System experiences](system-experiences)).

**Inputs** ([Action button](action-button), [Apple Pencil and Scribble](apple-pencil-and-scribble), [Camera Control](camera-control), [Digital Crown](digital-crown), [Eyes](eyes), [Focus and selection](focus-and-selection), [Game controls](game-controls), [Gestures](gestures), [Gyroscope and accelerometer](gyro-and-accelerometer), [Keyboards](keyboards), [Nearby interactions](nearby-interactions), [Pointing devices](pointing-devices), [Remotes](remotes)).

**Technologies** ([AirPlay](airplay), [Always On](always-on), [App Clips](app-clips), [Apple Pay](apple-pay), [Augmented reality](augmented-reality), [CareKit](carekit), [CarPlay](carplay), [Game Center](game-center), [Generative AI](generative-ai), [HealthKit](healthkit), [HomeKit](homekit), [iCloud](icloud), [ID Verifier](id-verifier), [iMessage apps and stickers](imessage-apps-and-stickers), [In-app purchase](in-app-purchase), [Live Photos](live-photos), [Mac Catalyst](mac-catalyst), [Machine learning](machine-learning), [Maps](maps), [NFC](nfc), [Photo editing](photo-editing), [ResearchKit](researchkit), [SharePlay](shareplay), [ShazamKit](shazamkit), [Sign in with Apple](sign-in-with-apple), [Siri](siri), [Tap to Pay on iPhone](tap-to-pay-on-iphone), [VoiceOver](voiceover), [Wallet](wallet)).

---

## The gate — run before declaring an Apple-surface design done

Print this checklist with a ✅/❌/N-A per line in the hand-off. A ❌ on a BINDING surface blocks.

1. Text ≥ platform minimum; body at platform default; Dynamic Type verified at largest AX size (or 200 % web zoom).
2. Contrast ≥ 4.5:1 (≤17 pt) / 3:1 (18 pt+ or bold) in **both** appearances.
3. Every control ≥ 44×44 pt iOS/watchOS (28 macOS, 66 tvOS, 60 visionOS); ~12/24 pt spacing.
4. No information carried by color alone; every custom icon/symbol has alt-text.
5. Every gesture has a button/keyboard alternative; no auto-dismissing critical UI.
6. Reduce Motion honoured; no motion on frequent interactions; all animation cancellable.
7. Follows system appearance — no in-app light/dark toggle; semantic colors, not hard-coded.
8. Safe areas respected; layout by size class; tested on ≥ 2 size classes + a localisation.
9. Liquid Glass only in the control layer, sparingly; no glass on content; no decorative glassmorphism.
10. System fonts/text styles on native; ≤ 2 typefaces; no light weights in UI text.
11. System components first; branding defers to content; no launch-screen branding.
12. Copy: clear, active, consistent case; empty states + errors give a next step.
13. For any pattern in §11 or component in §12 the design uses, the live HIG page was re-read this session (cite slug + date in the hand-off).

Enforcement pairs with Hallmark's 57 gates and `npx impeccable detect` — this list is *additive*.

## Design resources (official downloads)

- Apple Design Resources (Sketch/Figma/Keynote kits, Dynamic Type tables): https://developer.apple.com/design/resources/
- Fonts (SF Pro, SF Compact, SF Mono, New York): https://developer.apple.com/fonts/
- SF Symbols app: https://developer.apple.com/sf-symbols/ · Icon Composer: https://developer.apple.com/icon-composer/
- Design videos: https://developer.apple.com/videos/design/ · What's New: https://developer.apple.com/design/whats-new/ · Get Started pathway: https://developer.apple.com/design/get-started/
- Companion motion skill for the web: `apple-design` (Emil Kowalski, `~/.agents/skills/apple-design`) — physics/springs; it does **not** replace this file's rules.
