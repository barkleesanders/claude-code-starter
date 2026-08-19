# Sourced Links & Archive Backups

When a magazine cites real-world sources (news articles, court filings, government PDFs, agency pages), the user almost always also wants those sources archived locally + linked from the magazine. Treat this as a first-class output, not an afterthought.

This playbook captures the patterns learned the hard way on `doge-phantom-winery` (April 2026). Read it before you generate any magazine that has source-citation footers, or before you do any "fix the archive links" task.

## The MANIFEST.json → INDEX.md → magazine.html pipeline

Single source of truth: `archive/MANIFEST.json` (an array of entries). Everything else regenerates from it.

```
MANIFEST.json (truth)
   │
   ├── regen-archive-index.py ──→  archive/INDEX.md  (browsable per-category table)
   │
   └── magazine.html               (📁 icons next to each in-text link)
```

Manifest entry shape (every field matters):

```json
{
  "url": "https://example.com/article",
  "category": "news",                       // becomes folder name
  "archive_path": "archive/news/example_com__article.html",  // relative to repo root
  "size_bytes": 88273,
  "fetch_status": 200,
  "fetched_ok": true,
  "fetched_at": "2026-04-27",
  "wayback_url": "https://web.archive.org/web/20250901131055/https://example.com/article",
  "wayback_timestamp": "20250901131055",
  "archive_status": "✅ full HTML",
  "github_url": "https://github.com/<user>/<repo>/blob/main/archive/news/example_com__article.html"
}
```

## Five rules that keep links from breaking

### 1. Use GitHub blob/tree URLs in INDEX.md and magazine.html — never relative paths

`archive/INDEX.md` lives **inside** `archive/`. So a markdown link `[X](archive/news/X.html)` from INDEX.md resolves to `archive/archive/news/X.html` on github.com → 404.

Same pattern bites magazine.html when GitHub Pages publishes from `/docs` only. `<a href="../archive/X">` resolves to `https://<user>.github.io/archive/X` — outside the publish source — also 404.

**Rule:** always render archive links as absolute GitHub URLs:

| Target | URL pattern |
|---|---|
| File | `https://github.com/<user>/<repo>/blob/main/<archive_path>` |
| Folder | `https://github.com/<user>/<repo>/tree/main/<archive_path>` |

Files (PDFs, HTML) render in the GitHub UI. Folders show a file listing. Both feel like "real sourced links" to the reader.

### 2. Wayback URLs use `web/<timestamp>/` or `web/*/` — NEVER `web/2026*/`

The `web/2026*/URL` wildcard form opens the Wayback **calendar view** for 2026, which is empty for most URLs and shows a confusing month grid. Users see "no archive" and lose trust.

| Form | What it does | Use when |
|---|---|---|
| `web/<14-digit-timestamp>/URL` | Direct snapshot | Manifest has a real timestamp from the availability API |
| `web/*/URL` | Redirector → latest snapshot or search | Manifest has no timestamp (URL not yet archived) |
| `web/2026*/URL` | Calendar view (empty for most) | **NEVER USE** |

To find real timestamps, query the availability API:

```python
api = 'https://archive.org/wayback/available?url=' + urllib.parse.quote(url, safe=':/?=&')
# Response: {"archived_snapshots": {"closest": {"url": "...", "timestamp": "20250901131055", ...}}}
```

The bulk script is at `scripts/wb-availability.py` in this skill.

### 3. Honest `archive_status` per entry — sub-1KB stubs are NOT backups

A 212-byte HTML file containing `_Incapsula_Resource` is a bot-detection page, not a backup. A 451-byte markdown stub saying "Akamai blocked us, here's a summary" is a note, not a backup. Marking these "✅ full backup" is dishonest and the user will catch it.

Required `archive_status` taxonomy:

| Status | Meaning | Detection |
|---|---|---|
| `✅ full HTML` | Real saved page | `>= 800 bytes` AND no Incapsula marker |
| `✅ full PDF` | Real PDF | Starts with `%PDF-` magic bytes |
| `✅ JSON` / `✅ PNG` | Structured data / screenshot | Valid format |
| `📝 note only` | Markdown summary, not a page archive | `.md` extension |
| `🤖 bot-blocked` | Captured the bot challenge page | Contains `_Incapsula_Resource` (regex) |
| `⚠️ thin` | Suspiciously small HTML | `< 800 bytes` and no other red flag |
| `🔒 login-walled` | Auth required (LinkedIn, paywalls) | Host in known login-wall list |
| `🔧 asset CDN` | Font / asset URL, not a primary source | Host in `fonts.googleapis.com`, etc. |
| `❌ no archive` | Listed in manifest but never fetched | `archive_path` is null or missing on disk |

The classifier is in `scripts/regen-archive-index.py`.

### 4. INDEX.md gets regenerated from the manifest, never hand-edited

Hand-editing INDEX.md drifts from MANIFEST.json the moment you add a new source. Always regenerate:

```bash
python3 scripts/regen-archive-index.py
```

The script reads MANIFEST.json, classifies each file, builds the per-category tables, and writes INDEX.md atomically. Use the version in this skill's `scripts/` directory — it has the lessons baked in.

### 5. Bulk-saving to Wayback needs an API key (don't promise more than you can deliver)

`POST https://web.archive.org/save/<url>` is the Save Page Now endpoint. Anonymous submissions get HTTP 429 rate-limited fast (~70% of bulk submissions fail). For reliable bulk saving, the user needs an archive.org account + S3 API keys:

```
GET https://archive.org/account/s3.php  → "access" + "secret" tokens
Authorization: LOW <access>:<secret>
```

If saving without auth, **don't** claim every URL got snapshotted. Run availability check after; only mark URLs with real `closest.timestamp` as captured. The rest stay on the `web/*/URL` redirector.

## When generating a magazine with cited sources

1. **Capture URLs** as you go. While drafting, keep a list of every URL you cite.
2. **Save locally** before referencing. Use `curl` with a real browser User-Agent, or `unbrowse` for bot-protected sites. Save under `archive/<category>/<slug>.<ext>` where slug = `<host_underscored>__<path_underscored>`.
3. **Build MANIFEST.json** with the entry shape above.
4. **Run** `regen-archive-index.py` to produce INDEX.md.
5. **Embed in magazine** — every cited URL gets a small 📁 icon linking to `https://github.com/<user>/<repo>/blob/main/<archive_path>`. Never `../archive/...`.
6. **Submit to Wayback** — best-effort. Run `wb-save.py` then `wb-availability.py` to capture real timestamps.

## When fixing an existing magazine's broken archive links

Symptoms: 📁 icons return 404, or INDEX.md links don't open the archived files.

1. Check the GitHub Pages config: `gh api repos/<user>/<repo>/pages` — note the source path.
2. If Pages serves `/docs`, every reference to `archive/` from `docs/` must use a GitHub blob URL.
3. Grep for the bug: `grep -c '"\.\./archive/' docs/*.html` should be 0.
4. For INDEX.md inside `archive/`, grep for `](archive/` — should also be 0.
5. Run the manifest classifier — anything not `✅` should have a non-✅ status.
6. Regenerate INDEX.md and commit.

Reference fix: doge-phantom-winery commits `cd9af26` (magazine paths), `14d78f0` (INDEX.md paths + status column), `23c5bda` (Wayback timestamps).
