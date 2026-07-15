---
name: libby-dl
description: Download Libby audiobooks (MP3/m4b, odmpy or Chrome CDP) and eBooks to PDF/EPUB (libby-dl pdf/ebook). Triggers on libby download, libby audiobook, libby ebook, libby pdf, odmpy libby, libby-dl.
---

# libby-dl

CLI: `~/tools/libby-cli` — **v1.6.1** — `libby-dl` on PATH (`~/bin/libby-dl`).

## Agent rule: odmpy setup runs first (automatic)

**Before any download**, the CLI runs `ensureOdmpySetup` on these commands:

| Command | Auto-setup |
|---------|------------|
| `run` | Step 0 (always unless `--skip-setup`) |
| `download` | Before odmpy (audiobook) |
| `ebook` / `pdf` | Before odmpy (eBook) |
| `doctor` | Before checks |
| `finish` | Before odmpy |
| `setup` | Explicit configure / `--check` |

**Non-interactive agents** (no TTY): auth will fail until the user provides an 8-digit Libby code:

```bash
libby-dl setup --code 12345678
# or any command with global flag:
libby-dl --code 12345678 run -d ~/Downloads/my-book --title-id 12519104
```

Libby app → ☰ Menu → **Get setup code** (8 digits, ~10 min expiry).

Token file (optional): `~/.config/libby-dl/libby-token` or `LIBBY_TOKEN` env.

---

## Mandatory step order (agents — follow exactly)

### A. Audiobook (MP3 spine, `PartNN.mp3`)

| Step | Command | Notes |
|------|---------|-------|
| **0** | `libby-dl setup --check` or `libby-dl setup --code …` | **Never skip** unless odmpy already passes `--check` |
| **1** | Confirm format | Loan page has **Listen** / audiobook — not Read/eBook |
| **2** | `libby-dl init -d DIR` | If new download dir |
| **3** | `libby-dl discover -d DIR` | Debug-CDP Chrome (`libby-dl chrome`) → `spine.json` (skip if odmpy will run first and `--from-files` later) |
| **4** | `libby-dl gate -d DIR` | Loan active, Listen iframe, odmpy or CDP viable |
| **5** | `libby-dl run -d DIR --title-id ID --loan-url URL` | **Preferred** — auto setup → odmpy → gate → CDP gaps → merge/tag |
| **6** | `libby-dl verify -d DIR` | Exit 0 = all `requiredParts` full |
| **7** | Return Libby loan | **Only after step 6 passes** |

Partial recovery (loan still active): `libby-dl plan -d DIR` then `libby-dl cdp --missing-only`.

### B. eBook → PDF / EPUB

| Step | Command |
|------|---------|
| **0** | `libby-dl setup --code …` (uses `scripts/libby_setup.py` + TLS patch) |
| **0b** | `libby-dl deps` — install calibre + Adobe Digital Editions if missing |
| **1** | `libby-dl hp` or `libby-dl pdf --title-id <id> -d DIR` (**PDF default** for HP) |
| **1b** | Pipeline: odmpy/Chrome `.acsm` → ADE → `book.epub` → calibre; on **DRM** → `chrome_read_to_pdf.py` (Libby reader screenshots) |
| **1c** | Requires `:9222` Chrome with Libby signed in; installs/repairs Calibre (`brew reinstall --cask calibre` if stub) |

Do **not** use `run`, `cdp`, `discover`, or `verify` for eBooks.

| Output | Meaning |
|--------|---------|
| `.pdf` | Ready (open PDF or converted EPUB) |
| `.epub` | Open EPUB — use as-is or `brew install calibre` for conversion |
| `.acsm` | Adobe DRM — **success for epub goal**; open in **Adobe Digital Editions** → get `.epub` |

See `~/tools/libby-cli/docs/EBOOK.md`.

---

## One command (audiobook)

```bash
libby-dl run -d ~/Downloads/libby-my-title-LOANID-TITLEID \
  --title-id TITLEID \
  --loan-url 'https://libbyapp.com/open/loan/LOANID/TITLEID'
```

Pipeline order inside `run`:

1. **odmpy setup** (`ensureOdmpySetup`)
2. **doctor** preflight
3. **odmpy** full download (if ready)
4. **gate** → **Chrome CDP** for gaps only
5. **merge** + tag **FULL BOOK** only if `verify` would pass

Use `--allow-partial` only when the user explicitly accepts a partial archive.

---

## Full book = per-title `spine.json`

See `~/tools/libby-cli/docs/SPINE.md`.

- `libby-dl discover -d DIR` — Listen UI labels → `spine.json`
- `libby-dl discover -d DIR --from-files` — after odmpy
- `libby-dl verify` — required parts ≥400KB; previews &lt;200KB or label heuristics

---

## Safeguards

| Failure | Guard |
|---------|--------|
| No odmpy auth | Auto `setup` on run/download/doctor; fail with instructions if no TTY/code |
| Returned loan mid-CDP | `gate` + 403 blockers |
| Preview as chapter | `spine.previewOnlyParts` + byte thresholds |
| False FULL BOOK | `tag` / `run` require `verify` |
| eBook mistaken for audiobook | Check **Listen** vs **Read** on Libby page |

---

## Commands (quick reference)

| Command | Purpose |
|---------|---------|
| `setup` / `setup --check` | Configure or verify odmpy |
| `run` | Full pipeline (setup first) |
| `download` | Audiobook odmpy only |
| `ebook` / `pdf` | eBook → PDF/EPUB/ACSM (+ EPUB→PDF) |
| `doctor` | Preflight (setup first) |
| `gate` | Pre-CDP checklist |
| `plan` | Ordered recovery steps |
| `discover` | Build `spine.json` |
| `verify` | Hard completeness gate |
| `cdp` | Chrome capture (gate first) |
| `merge` / `tag` | ffmpeg m4b; FULL only if complete |

## Global flags

- `--code <8digits>` — Libby setup code for non-interactive agents
- `--skip-setup` — CDP-only debug (fails if odmpy needed and missing)
- `--json` — machine-readable output

## Chrome

```bash
libby-dl chrome --loan-url '...'   # brings up the CDP debug Chrome this tool needs and opens the loan
```

> Note: `libby-dl`'s own `discover`/`chrome`/`cdp` commands drive a dedicated CDP debug
> Chrome internally (their own capture logic, separate from `fcdp`/`ccb`) — this is the
> libby-cli tool's own mechanism, not the general logged-in-browser default. See the
> `logged-in-browser` skill for driving any OTHER logged-in site.

## When loan returned / 403

Re-borrow or use odmpy (`libby-dl run` after setup). CDP cannot stream expired URLs.

Never tag **FULL BOOK** until `libby-dl verify` exits 0.