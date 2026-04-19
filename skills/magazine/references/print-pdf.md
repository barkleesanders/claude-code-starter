# Print / PDF Output

Every magazine HTML file MUST include the print stylesheet below. When the user asks for a PDF — either via `--pdf` flag in the /magazine args, the word "pdf" in their request, or "print" — render the HTML first, then use Chrome headless to produce a PDF with one spread per page and no blank pages.

## Why this exists

Without a print stylesheet, converting a `min-height: 100vh` magazine to PDF produces a blank page after every spread (because spread height ≠ paper page height). It also drops background colors because browsers default to "print backgrounds off."

## MANDATORY print stylesheet — paste verbatim at the end of `<style>`

Paste this block right before `</style>` in every magazine HTML output. Do not omit. Do not abbreviate. These exact values were validated against a 13-page magazine — every page renders without clipping, blank pages, or overlapping text.

### Critical rules learned the hard way

1. **Page size: 1280×1024.** (Not 800. At 800 the content gets clipped.) Almost all dense spreads (score tables, step tables, address lists) need the extra 224px.
2. **`justify-content: flex-start`** on every spread (NOT `center`). When content overflows with `center`, it spills BOTH the top AND the bottom — clipping both. With `flex-start`, content anchors to the top and only overflows down, which is safe because `.source-line` has `margin-top: auto` pushing it to the bottom.
3. **`source-line { margin-top: auto }`** pins source attribution to the bottom of the page even with top-anchored content.
4. **`-webkit-print-color-adjust: exact`** on `*` — without it, Chrome drops all background colors.
5. **Per-spread overrides are not optional.** Dense content (`>8 rows` or `>15 bullet items`) requires a dedicated `@media print` block that shrinks padding and font sizes. The full per-spread override set below is validated.

```css
/* ===== PRINT / PDF OPTIMIZATION =====
   Each spread becomes exactly one PDF page.
   No blank pages between spreads.
   Background colors preserved.                    */
@media print {
  @page {
    size: 1280px 1024px;
    margin: 0;
  }
  html, body {
    margin: 0 !important;
    padding: 0 !important;
  }
  * {
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
    color-adjust: exact !important;
  }
  .spread, .masthead, .colophon {
    min-height: 1024px !important;
    height: 1024px !important;
    max-height: 1024px !important;
    width: 1280px !important;
    padding: 50px 70px !important;
    page-break-after: always !important;
    page-break-inside: avoid !important;
    break-after: page !important;
    break-inside: avoid !important;
    overflow: hidden !important;
    box-sizing: border-box !important;
    display: flex !important;
    flex-direction: column !important;
    justify-content: flex-start !important;  /* CRITICAL: top-anchor, not center */
  }
  .masthead { justify-content: space-between !important; }
  .colophon { page-break-after: auto !important; break-after: auto !important; justify-content: center !important; }
  .source-line { margin-top: auto !important; padding-top: 16px !important; font-size: 13px !important; }

  /* Base type scale */
  .numeral { font-size: 130px !important; margin-bottom: 0 !important; letter-spacing: -0.04em !important; }
  .kicker { font-size: 13px !important; margin-bottom: 14px !important; }
  .standfirst { font-size: 18px !important; margin-top: 20px !important; line-height: 1.4 !important; }
  h2 { font-size: 42px !important; line-height: 1.05 !important; }

  /* Hero spreads (s01, s11) get a larger numeral */
  .s01 .numeral, .s11 .numeral { font-size: 180px !important; }
  .s01 h2, .s11 h2 { font-size: 58px !important; line-height: 1 !important; }

  /* Masthead */
  .masthead-title { font-size: 128px !important; line-height: 0.85 !important; margin: 30px 0 30px !important; }
  .masthead-sub { font-size: 28px !important; margin-bottom: 40px !important; }
  .masthead-top { font-size: 14px !important; padding-bottom: 18px !important; }
  .masthead-bottom { font-size: 15px !important; padding-top: 18px !important; }
  .masthead-bottom b { font-size: 12px !important; margin-bottom: 4px !important; }

  /* Colophon */
  .colophon h3 { font-size: 72px !important; }
  .colophon p { font-size: 20px !important; line-height: 1.4 !important; }
  .colophon .footer-meta { font-size: 14px !important; margin-top: 36px !important; padding-top: 20px !important; }
}
```

### Per-spread overrides (append to same `@media print` block)

Add these targeted overrides when a spread contains dense content. These are proven to fit on a 1280×1024 page:

```css
@media print {
  /* Score/fact-check tables (10–12 rows): tighten aggressively */
  .s05 { padding: 36px 60px !important; }
  .s05 .numeral { font-size: 110px !important; }
  .s05 h2 { font-size: 36px !important; }
  .s05 .score-table { margin-top: 22px !important; }
  .s05 .score-row { padding: 6px 0 !important; grid-template-columns: 40px 1fr 140px !important; gap: 16px !important; }
  .s05 .score-row .claim { font-size: 13px !important; line-height: 1.3 !important; }
  .s05 .score-row .mark { font-size: 22px !important; }
  .s05 .score-row .verdict { font-size: 10px !important; grid-column: auto !important; text-align: right !important; }

  /* Step/procedure tables (10–12 rows) */
  .s08 { padding: 36px 60px !important; }
  .s08 .numeral { font-size: 100px !important; }
  .s08 h2 { font-size: 36px !important; }
  .s08 .step-row { padding: 7px 18px !important; grid-template-columns: 36px 1fr 110px !important; }
  .s08 .step-row .step-n { font-size: 16px !important; }
  .s08 .step-row .step-what { font-size: 13px !important; line-height: 1.3 !important; }
  .s08 .step-row .step-verdict { font-size: 10px !important; grid-column: auto !important; text-align: right !important; }

  /* Dense address / facility / link lists with columns */
  .s09 { padding: 36px 50px !important; }
  .s09 .numeral { font-size: 90px !important; }
  .s09 h2 { font-size: 32px !important; padding-bottom: 10px !important; }
  .s09 .addr-group { margin-top: 10px !important; }
  .s09 .addr-group h3 { font-size: 12px !important; padding-bottom: 5px !important; margin-bottom: 6px !important; }
  .s09 .addr-list { columns: 3 !important; column-gap: 18px !important; }
  .s09 .addr-list li { font-size: 10px !important; padding: 3px 0 !important; line-height: 1.25 !important; }
  .s09 .addr-list li b { font-size: 11px !important; margin-bottom: 1px !important; }

  /* Terminal/pre blocks (for code or formatted text spreads) */
  .s02 pre { font-size: 14px !important; padding: 16px 20px !important; margin-top: 18px !important; line-height: 1.35 !important; }

  /* 2x2 intent grids or verdict grids */
  .s10 .intent-grid, .s11 .verdict-grid { grid-template-columns: 1fr 1fr !important; gap: 18px !important; margin-top: 24px !important; }
  .s10 .intent-card { padding: 14px 18px !important; }
  .s10 .intent-card h5 { font-size: 17px !important; line-height: 1.2 !important; }
  .s10 .intent-card p { font-size: 12px !important; line-height: 1.4 !important; }

  /* Big-stat grids */
  .s03 .penalty-grid .pcell .amount { font-size: 72px !important; }
  .s03 .penalty-grid .pcell .desc { font-size: 13px !important; line-height: 1.35 !important; }

  /* Timeline entries */
  .s07 .timeline .event { margin-bottom: 14px !important; }
  .s07 .timeline .year { font-size: 22px !important; }
  .s07 .timeline .what { font-size: 15px !important; line-height: 1.3 !important; }

  /* Academic drop-cap spreads */
  .s04 .body p { font-size: 16px !important; margin-bottom: 12px !important; line-height: 1.45 !important; }
  .s04 .body p:first-of-type::first-letter { font-size: 4.5em !important; margin: 4px 12px 0 0 !important; }
  .s04 .callout { font-size: 15px !important; padding: 16px 20px !important; margin-top: 16px !important; }
}
```

**Reference implementation:** `/Users/<user>/Desktop/ab2624-magazine.html` — the AB 2624 magazine has all 13 page types validated clean.

## The `--pdf` flag

When the user invokes `/magazine --pdf "..."` OR their request explicitly says "pdf" / "print" / "printable", the skill must:

1. Generate the HTML as usual (with mandatory print stylesheet above).
2. Render it to PDF via Chrome headless (exact command below).
3. Open the PDF instead of (or in addition to) the HTML.

### Render command — Chrome headless

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless \
  --disable-gpu \
  --no-pdf-header-footer \
  --print-to-pdf="<output.pdf>" \
  --print-to-pdf-no-header \
  --no-margins \
  --virtual-time-budget=5000 \
  "file://<absolute-path-to.html>"
```

- `--virtual-time-budget=5000` gives Google Fonts time to load.
- Default page size is controlled by the `@page` CSS rule above — do not override with `--print-paper-*` flags.
- Verify page count after: `mdls -name kMDItemNumberOfPages <file.pdf>` — should equal (spread count + masthead + colophon). If higher, there are blank pages — diagnose which spread's content exceeds 800px and add a print override.

### Save path

Default: `~/Downloads/<slug>-YYYY-MM-DD.pdf` (same directory as the HTML, `.pdf` extension).

## Upload to Drive (when user asks)

For PDFs, Composio's `GOOGLEDRIVE_UPLOAD_FILE` action requires a URL-based file source, which doesn't work with local paths. Use the two-step pattern from the user's CLAUDE.md:

1. Fetch Composio-managed Drive OAuth token:
   ```bash
   COMPOSIO_API_KEY="<COMPOSIO_API_KEY>"  # from ~/tools/composio/composio-client.cjs
   TOKEN=$(curl -sS -H "X-API-Key: ${COMPOSIO_API_KEY}" \
     "https://backend.composio.dev/api/v3/connected_accounts?toolkit_slug=googledrive&limit=100" \
     | python3 -c "
   import sys, json
   d = json.load(sys.stdin)
   for a in d.get('items', []):
       if a.get('toolkit', {}).get('slug') == 'googledrive' and a.get('status') == 'ACTIVE':
           print(a['data']['access_token']); break
   ")
   ```
2. Upload via Drive native multipart API:
   ```bash
   BOUNDARY="----gdrive-boundary-$$-$(date +%s)"
   {
     printf -- "--%s\r\n" "$BOUNDARY"
     printf "Content-Type: application/json; charset=UTF-8\r\n\r\n"
     printf '{"name":"<file.pdf>","mimeType":"application/pdf"}\r\n'
     printf -- "--%s\r\n" "$BOUNDARY"
     printf "Content-Type: application/pdf\r\n\r\n"
     cat "<local-path.pdf>"
     printf "\r\n--%s--\r\n" "$BOUNDARY"
   } | curl -sS -X POST \
     "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: multipart/related; boundary=${BOUNDARY}" \
     --data-binary @-
   ```
3. Make public via Composio:
   ```bash
   node ~/tools/composio/composio-client.cjs execute \
     GOOGLEDRIVE_ADD_FILE_SHARING_PREFERENCE \
     '{"file_id":"<ID>","role":"reader","type":"anyone"}'
   ```

Share link format: `https://drive.google.com/file/d/<FILE_ID>/view`

## Validation checklist before reporting done

- [ ] Print stylesheet pasted verbatim into HTML `<style>` block
- [ ] PDF renders without blank pages (`mdls -name kMDItemNumberOfPages` = spread count)
- [ ] Background colors visible in PDF (not white-on-white)
- [ ] Display type (numerals, headlines) fits within page bounds
- [ ] If uploaded to Drive, sharing is set to "Anyone with the link → Viewer"
