# Responsive Design & Frontend Principles

### Responsive Design Rules (MANDATORY)

Every UI component must work on BOTH mobile (375px) and desktop (1440px). The approach differs by audience:

**User-facing pages** (Welcome, Dashboard, FAQ, Privacy, Terms, Benefits Finder):
- Design for mobile AND desktop simultaneously — both must look polished
- Use responsive breakpoints: `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`
- Padding: `p-4 sm:p-6 md:p-8` (progressive)
- Text: readable at 375px without horizontal scroll
- Touch targets: minimum 44x44px on interactive elements
- Test at 375px viewport before marking any UI task complete

**Admin pages** (AdminCases, AdminCaseDetail, AdminReferrals, AdminFaxStatus):
- Desktop is the primary experience — optimize for efficiency
- BUT must be functional on mobile — never hide data, use card views instead
- Tables: add `md:hidden` mobile card view + `hidden md:block` desktop table
- Cards use Apple-like labeled fields: `text-[11px] text-navy-300 uppercase tracking-wider`
- Side-by-side layouts: `flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3`
- Tab bars: `overflow-x-auto` + `whitespace-nowrap` + compact mobile padding

**Quick responsive scan (run after ANY UI change):**
```bash
# Tables hiding data on mobile (need card view alternative)
grep -rn 'hidden md:table-cell\|hidden lg:table-cell' --include="*.tsx" src/
# Grids without responsive breakpoint
grep -rn 'grid-cols-[2-9]' --include="*.tsx" src/ | grep -v 'sm:grid-cols\|md:grid-cols\|grid-cols-1'
# Side-by-side without mobile stacking
grep -rn 'flex.*items-center.*justify-between' --include="*.tsx" src/ | grep -v 'flex-col\|sm:flex-row'
# Wide padding without mobile variant
grep -rn 'px-6\|px-8' --include="*.tsx" src/ | grep -v 'sm:px-\|md:px-'
```

---

### Frontend Design Principles

When creating new UI components or pages, commit to a **bold aesthetic direction** before coding:

- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist, retro-futuristic, organic/natural, luxury/refined, playful, editorial, brutalist, art deco, soft/pastel, industrial. Commit to one, execute precisely.
- **Differentiation**: What makes this UNFORGETTABLE? What will someone remember?

**Typography**: Choose beautiful, unique fonts. Avoid Arial, Inter, Roboto. Pair a distinctive display font with a refined body font.

**Color**: Commit to cohesive aesthetic. CSS variables for consistency. Dominant colors + sharp accents outperform timid balanced palettes.

**Motion**: CSS-only for HTML. Motion library for React. One well-orchestrated page load with staggered reveals beats scattered micro-interactions.

**Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Grid-breaking elements.

**Backgrounds**: Gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows — create atmosphere.

NEVER use generic AI aesthetics: overused fonts (Inter, Space Grotesk), cliche purple gradients on white, predictable layouts.

Component reference: Browse https://component.gallery/ (60 components, 95 design systems, 2,676 examples).
