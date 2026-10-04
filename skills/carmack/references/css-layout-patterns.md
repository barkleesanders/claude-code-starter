# CSS & Layout Patterns

## Pattern 12: Text Overflow in Flex+Grid Layouts (min-w-0 Missing)

**Rank: #1 mobile layout bug -- text escapes card boundaries at 375px.**

Flex items have `min-width: auto` by default. Inside a CSS grid cell, a flex child containing long text expands to its natural content width, overflowing the cell even though the grid constrains it.

### Symptoms
- Text overflows card/box right edge on mobile (375px) but looks fine on desktop
- Long words ("Templates", "Referral Program") escape container boundaries
- `ExternalLink` / trailing icon pushed off-screen in `justify-between` flex rows
- Bug invisible until explicitly testing at 375px viewport

### Root Cause
Grid creates constrained cells (`minmax(0, 1fr)`), but flex children inside those cells have `min-width: auto` -- they claim their natural content width regardless of the cell width constraint. `overflow-hidden` on the card clips the overflow visually but doesn't fix the layout -- other elements still get pushed.

### Two Variants

**Variant A -- Icon + Text row (most common)**
```jsx
// BAD: Text div claims full content width, overflows grid cell
<div className="flex items-center gap-3">
  <div className="w-10 h-10 rounded-xl">  {/* icon */}</div>
  <div>
    <h4 className="text-sm font-semibold">Long Title Text</h4>
  </div>
</div>

// GOOD: min-w-0 on outer flex + inner text wrapper lets them shrink properly
<div className="flex items-center gap-3 min-w-0 flex-1">
  <div className="w-10 h-10 rounded-xl flex-shrink-0">  {/* icon */}</div>
  <div className="min-w-0">
    <h4 className="text-sm font-semibold break-words">Long Title Text</h4>
  </div>
</div>
```

**Variant B -- Text + trailing icon (justify-between)**
```jsx
// BAD: Text expands naturally, pushes ExternalLink icon off the right edge
<div className="flex items-center justify-between gap-3">
  <div>
    <h4>Long Title Text That Might Be 80px Wide</h4>
  </div>
  <ExternalLink className="w-4 h-4 flex-shrink-0" />
</div>

// GOOD: flex-1 + min-w-0 on text div gives icon guaranteed space
<div className="flex items-center justify-between gap-3">
  <div className="min-w-0 flex-1">
    <h4 className="break-words">Long Title Text That Might Be 80px Wide</h4>
  </div>
  <ExternalLink className="w-4 h-4 flex-shrink-0" />
</div>
```

### Grid Column Fix (Mobile-First)
```jsx
// BAD: 2-column on mobile = ~131px cells -- too narrow for icon+text rows at 375px
<div className="grid grid-cols-2 gap-3">

// GOOD: Single column on mobile, 2 from sm breakpoint (640px+)
<div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
```

### Quick Detection
```bash
# Flex rows with text content missing min-w-0
grep -rn "flex items-center gap" --include="*.tsx" src/ | grep -v "min-w-0"

# 2-column grids without sm: responsive breakpoint
grep -rn "grid-cols-2" --include="*.tsx" src/ | grep -v "sm:grid-cols"

# Fixed-size icon divs in flex rows without flex-shrink-0
grep -rn '"w-10 h-10\|w-8 h-8\|w-6 h-6"' --include="*.tsx" src/ | grep -v "flex-shrink-0"

# justify-between rows without flex-1 on text child
grep -rn "justify-between" --include="*.tsx" src/ | grep -v "flex-1"
```

### Complete Fix Checklist
- [ ] Flex row outer div: `min-w-0 flex-1`
- [ ] Icon div: `flex-shrink-0`
- [ ] Text wrapper div: `min-w-0`
- [ ] Long text headings: `break-words`
- [ ] Card container: `overflow-hidden` (safety net -- clipping only, not a substitute for min-w-0)
- [ ] 2-col grids: test at 375px or change to `grid-cols-1 sm:grid-cols-2`

### Real-World Case: Production App Dashboard (2026-03-13)
- **Symptom**: "Templates", "Referral Program" text escaping card boxes on iPhone
- **Root cause**: `grid-cols-2` -> 65px cells, but text divs had `min-width: auto` -> claimed ~70px
- **Fix**: `min-w-0 flex-1` on flex containers, `flex-shrink-0` on icons, `grid-cols-1 sm:grid-cols-2`
- **Files**: `Dashboard.tsx` (10 Quick Action items, Document Templates grid), `Welcome.tsx`
- **Commit**: `37792a2`

---

## Fixed Grid Breaks on Mobile

- **Symptom**: Content crammed into narrow columns on mobile screens
- **Quick Detection**: `grep -rn "grid-cols-[2-9]" --include="*.tsx" src/ | grep -v "sm:\|md:\|lg:"`
- **Fix**: `grid-cols-2 md:grid-cols-4` instead of `grid-cols-4`
- **Incident (2026-03-15)**: `AdminReferrals.tsx` had `grid-cols-4` without responsive breakpoints

---

## iOS Safari Rendering Issues

**Common mobile-only failure.** Feature works on desktop, blank on iPhone.

### iOS Safari Doesn't Render PDFs/Blobs in Iframes

#### Root Cause
iOS Safari has no built-in PDF viewer for `<iframe>` tags. Blob URLs (`blob:...`) inside iframes render as blank white boxes. This also affects `<object>` and `<embed>` tags with PDF blobs on iOS.

#### Quick Detection
```bash
# Find iframe/object/embed with blob URLs or PDF rendering
grep -rn "iframe.*src.*blob\|iframe.*pdf\|<object.*pdf\|<embed.*pdf" --include="*.tsx" --include="*.ts" src/
# Find blob URL creation for documents
grep -rn "URL.createObjectURL" --include="*.tsx" src/ | grep -v "download"
```

#### Fix Pattern
```typescript
// Detect iOS
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.userAgent.includes("Mac") && navigator.maxTouchPoints > 1);

// iOS: show Open/Download buttons instead of iframe
// Desktop: render iframe with blob URL
{isIOS ? (
  <button onClick={() => window.open(blobUrl, "_blank")}>Open PDF</button>
) : (
  <iframe src={blobUrl} />
)}
```

### Other iOS Safari Gotchas
- **`vh` units** -- Don't use `max-h-[90vh]` for modals. Use `max-h-[90dvh]` (dynamic viewport height) because iOS address bar changes viewport height
- **`position: fixed`** -- Can behave unexpectedly when virtual keyboard opens. Use `position: sticky` or `inset-0` with viewport units
- **Blob URL lifetime** -- iOS Safari may garbage-collect blob URLs faster than desktop. Don't revoke URLs while they're still in use
- **`<input type="file">`** -- iOS opens the photo picker, not file system. Use `accept` attribute to filter

### Real-World Case: Production App (2026-03-15)
- **Symptom**: Document preview worked on desktop, blank/unresponsive on iPhone
- **Root cause**: `PDFPreview.tsx` used `<iframe src={blobUrl}>` -- iOS Safari can't render PDFs in iframes
- **Fix**: Detect iOS, show "Open PDF" + "Download PDF" buttons instead of iframe. Desktop keeps inline viewer.
- **Files**: `src/react-app/components/previews/PDFPreview.tsx`, `src/react-app/components/DocumentPreviewModal.tsx`
