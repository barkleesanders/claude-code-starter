---
name: pdf-fill
description: Fill out fillable PDF forms (government, legal, tax, healthcare, insurance) using PyMuPDF (fitz). Triggered when user provides a PDF and asks to fill it out, complete it, populate fields, or auto-fill data. Covers AcroForm and XFA forms, text fields, radio buttons, checkboxes, and signature fields. Enforces fabrication prevention, visual verification, and multi-section form correctness (don't check boxes you don't qualify for).
---

# pdf-fill — Reliable Form Filling with PyMuPDF

## When to use

- User uploads a fillable PDF and says: "fill this out", "complete this form", "populate the fields", "auto-fill from my data"
- Government forms (IRS, FTB, state SOS, USCIS, VA, DMV)
- Legal forms (court filings, sworn declarations)
- Tax forms (1040, 1023, 990, FTB 3500A, state returns)
- Healthcare and insurance forms

## When NOT to use

- Flat PDFs (no form fields). Use `image` or `image-editor` skills instead.
- Forms that require integration with a portal API (e.g. VA.gov 21-526EZ via API). Use the dedicated skill (if one exists) if it exists.
- Documents that need wet-ink signatures only — those have no fillable widgets.

## Hard rules (NEVER violate)

### Rule 1 — Fabrication prevention

**Every value you fill MUST come from a verified source.** Do not invent EINs, SSNs, dates, addresses, names, dollar amounts, IRS classifications, or any other fact.

Source priority:
1. Documents the user just provided in this turn
2. Documents in user's Drive/email/local filesystem (verify by fetching + reading)
3. User's prior statements in this conversation
4. **Ask the user** if you can't find it. Never guess.

Apply the CLAUDE.md Document Fabrication Prevention rule: every phone number, citation, date, name must trace to a source document.

### Rule 2 — Visual verification (MANDATORY)

After filling, you **must** render the saved PDF as PNG and `Read` it as an image to confirm:
- Text appears in the right boxes (font may render but be invisible if widget appearance stream isn't regenerated)
- Radio buttons show their selected state with a visible mark
- Checkboxes show ☒ not ☐ when intended
- No fields are missing, overflowing, or rendered with garbled characters

```python
import fitz
doc = fitz.open(filled_path)
for i, page in enumerate(doc):
    pix = page.get_pixmap(dpi=180)
    pix.save(f'/tmp/filled-p{i+1}.png')
```

Then call `Read(file_path='/tmp/filled-p1.png')` for each page. **You only see what's rendered, not what's in the PDF dict.**

### Rule 3 — Multi-section forms: only fill the sections that apply

Many government forms have multiple parallel sections (e.g. FTB 3500A has Part III with 6 sections — one per IRC subsection: 501(c)(3), (4), (5), (6), (7), (19); USCIS forms often have "Section A: Petitioner / Section B: Beneficiary").

**Read each section header carefully.** Headers like *"Exemption based on IRC Section 501(c)(X) Federal Determination Letter — Check the organization's primary purpose and activity"* are **conditional**: only fill if your entity has THAT classification. Checking boxes for a classification you don't hold is FALSE under the form's penalty-of-perjury declaration.

For multi-purpose forms (one form, many subsection users), the form header usually says "...sections X, Y, Z, **or** A..." — the "or" tells you you pick ONE.

### Rule 4 — Save to a different path (avoid mutation traps)

```python
doc = fitz.open('/path/to/source.pdf')
# ... fill ...
doc.save('/path/to/source-FILLED.pdf', deflate=True)  # different filename
doc.close()
```

Saving back to the source path requires `incremental=True` (extra constraint) and risks data loss if filling fails halfway. Always save to a new path.

### Rule 5 — Single iteration per page (weak-ref GC trap)

PyMuPDF (`fitz`) widgets are weakly referenced. If you call `page.widgets()` twice and operate on widgets from the first iteration after starting the second, you get `RuntimeError: Annot is not bound to a page`.

**Pattern**:
```python
for page in doc:
    for w in page.widgets():       # ONE iteration
        if w.field_name in text_data:
            w.field_value = text_data[w.field_name]
            w.update()
        elif w.field_name in radio_targets:
            target = radio_targets[w.field_name]
            if w.on_state() == target:
                w.field_value = target
                w.update()
```

Anti-pattern (will GC-crash):
```python
ws1 = list(page.widgets())       # iteration A
for w in ws1: ...                # OK so far
for w in page.widgets():         # iteration B starts
    ...
ws1[0].field_value = "x"; ws1[0].update()  # ❌ RuntimeError: not bound to a page
```

## The fill workflow (six phases)

### Phase 1 — Inspect

Dump every widget's name, type, position, and current value. This is the field map.

```python
import fitz
doc = fitz.open('/path/to/form.pdf')
for i, page in enumerate(doc):
    print(f"=== Page {i+1}: {len(list(page.widgets()))} widgets ===")
    for w in page.widgets():
        r = w.rect
        kind = {2:"CB", 3:"RB", 4:"TXT", 5:"LB", 7:"SIG"}.get(w.field_type, str(w.field_type))
        print(f"  y={round(r.y0):4} x={round(r.x0):4} w={round(r.x1-r.x0):3} [{kind:3}] {w.field_name!r}")
```

Note: many government forms label widgets by ordinal (`Form 1001`, `Form 1002`...) not by semantic name. You'll need Phase 2 to map them.

### Phase 2 — Render the blank form + map fields to labels

Government PDF widgets often have meaningless names. To map widget → form label:

```python
for i, page in enumerate(doc):
    pix = page.get_pixmap(dpi=200)
    pix.save(f'/tmp/form-p{i+1}.png')
```

Then `Read(file_path='/tmp/form-p1.png')` and visually correlate each widget's `(y, x)` position with the printed label on that page. Cross-check with `doc[i].get_text()` to get the label text in reading order.

The widget at the highest y-coordinate near a labeled blank is your match.

### Phase 3 — Gather verified data

Build a dict mapping `field_name -> value`. **Every value must have a source.**

If you don't have a value for a field:
- For optional fields (phone, fax) → leave blank
- For required fields → ask the user. Never invent.
- For date-of-signature → leave blank (wet-sign on paper)

### Phase 4 — Fill (single pass per page)

```python
doc = fitz.open(src)
text_data = { 'Form 1001': 'C4752548', 'Form 1003': 'Example Nonprofit Inc.', ... }
radio_targets = { 'Form 1021 RB': '1' }   # 'on_state' value of chosen radio

for page in doc:
    for w in page.widgets():
        if w.field_name in text_data:
            w.field_value = text_data[w.field_name]
            w.update()
        elif w.field_name in radio_targets:
            target = radio_targets[w.field_name]
            if w.on_state() == target:
                w.field_value = target
                w.update()
        # checkboxes: set field_value to 'Yes' or the on-state from w.button_states()
doc.save(dst, deflate=True)
doc.close()
```

### Phase 5 — Verify in the dict

Re-open and confirm every intended field is non-empty / non-Off:

```python
doc2 = fitz.open(dst)
for pg in range(len(doc2)):
    for w in doc2[pg].widgets():
        v = w.field_value
        if v and v != 'Off':
            print(f"  p{pg+1} {w.field_name!r:30} = {v!r}")
```

### Phase 6 — Visual verification (MANDATORY)

Render every page as PNG and Read it back:

```python
for i, page in enumerate(doc2):
    pix = page.get_pixmap(dpi=180)
    pix.save(f'/tmp/filled-p{i+1}.png')
```

Then `Read(file_path='/tmp/filled-p1.png')` for each page. Confirm text is visible, checkboxes are checked, no overflow, no garbled glyphs.

**Why this is mandatory**: `widget.update()` writes the value to the PDF's form dictionary BUT does not always regenerate the visible "appearance stream" on government XFA forms. The form data is there; the print rendering may not show it. This trap broke a VA disability filing in 2026-04 — only visual rendering catches it.

If the rendered PNG shows blank where a value should be:
- Force appearance regeneration: set `w.field_value`, call `w.update()`, then explicitly call `w.button_states()` once to trigger the recompute, OR
- Use `pikepdf` to flatten + regenerate, OR
- Fall back to overlay: draw text on top of the widget's `rect` with `page.insert_text()`

## Radio button & checkbox API reference

`fitz` represents radio groups oddly:

- Each radio **option** is a separate widget. They all share the same `field_name` (e.g. `"Form 1021 RB"`).
- Each widget has a unique `on_state()` method that returns a **string** like `'0'`, `'1'`, `'2'` — the export value when THAT specific option is selected.
- To select an option: find the widget whose `on_state() == target_string` and set `field_value = target_string`.
- Setting one option to its on-state automatically deselects the others (radio group semantics enforced by `rb_parent`).
- Inspect available options via `widget.button_states()`:
  ```
  {'normal': ['1'], 'down': ['1', 'Off']}
  ```

For Yes/No questions, you usually have two widgets sharing one `field_name`:
- Widget A: `on_state() == '0'`, at the left position (typically "Yes")
- Widget B: `on_state() == '1'`, at the right position (typically "No")

Confirm by checking widget `rect.x0` against the visual layout — `x0=506` is left column, `x0=547` is right column on FTB 3500A.

**Checkboxes** (single, independent) work the same way: get `w.button_states()['normal']`, pick the non-`'Off'` value, set `w.field_value = that_value`.

## Common traps catalog

| Trap | Symptom | Fix |
|---|---|---|
| `RuntimeError: Annot is not bound to a page` | Crash on `w.update()` | Single iteration per page; don't reuse widget references across `page.widgets()` calls |
| `ValueError: save to original must be incremental` | Save fails | Save to a different path, not the source |
| Text fills but PDF renders blank | Visual check fails | Appearance stream not regenerated; use overlay fallback or `pikepdf` flatten |
| Radio button stays "Off" after setting `field_value=1` | Numeric vs string | `on_state()` returns string; set `field_value='1'` not `1` |
| Wrong field gets filled | Widget names are meaningless ordinals | Render + map by `(y, x)` position before assigning |
| Form filled correctly but multi-section "incomplete" complaint from user | Multi-purpose form | Explain Rule 3 — only fill sections matching your classification |
| EIN/date/citation comes from "memory" | Fabrication risk | Always trace to a source document; ask if unverified |
| Save succeeds but next open shows no fills | `incremental` save without flush | Use `doc.save(path, deflate=True)` then `doc.close()` |
| User reports field overflow | Long values in narrow widgets | Check `w.rect` width; abbreviate or use multi-line field if available |
| Two widgets same `field_name`, both filled | Tried to fill both halves of a radio | Only set the WIDGET WHOSE on_state matches your choice |

## Multi-section perjury check

Before declaring done on any government form with parallel sections:

1. Identify the form's main classification (e.g. "this is a 501(c)(3) filing")
2. For each multi-section block, identify which sections are conditional on classifications you DO hold
3. Only fill those sections
4. Leave the other sections blank
5. When a user says "you missed filling section X" — verify which classification section X conditions on. If user doesn't hold it, explain the perjury risk; do NOT fill on user instruction without that verification.

## File outputs

- Always save filled PDF to `~/Downloads/<original-name>-FILLED.pdf` (or user-specified path)
- Render verification PNGs to `/tmp/<form>-FILLED-p<N>.png` (ephemeral)
- After verification, `open <path>` the filled PDF so user can preview before signing
- Tell user explicitly what's filled, what's blank, and why

## Reference incident (2026-05-26 — FTB 3500A for Example Nonprofit Inc.)

- 96 widgets, 32 fields needed filling
- Verified every value from source: IRS determination letter (OCR'd from Drive), governance package, tax-return prep README
- Skipped Part III sections 2-6 (501(c)(4)–(c)(19)) because Example Org is a 501(c)(3) only — checking those would be perjury
- User initially asked "why didn't you fill sections 2-6?" — answered with form text quote: "Exemption based on IRC Section 501(c)(X) Federal Determination Letter — Check the organization's primary purpose and activity" is conditional on holding subsection X
- Visual verification caught the radio buttons rendering with proper marks; text widgets all rendered correctly

## Related skills

- `docuseal-cli` — for e-signature workflows (when applicable, but most gov forms require wet ink)
- `image` — for non-fillable PDFs that need annotation overlays
