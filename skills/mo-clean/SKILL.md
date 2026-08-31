---
name: mo-clean
user-invocable: true
description: Deep-clean and optimize this Mac with Mole (`mo`) — clean caches, purge project build artifacts (mo purge, often 40GB+), inventory unused apps by pref-mtime, sweep leftover browser junk (debug-Chrome clones, Kuri, orphaned Chromium) WITHOUT ever touching the real Chrome profiles, and clear dangling brew casks/EOL leaves. Always dry-runs first, shows a tiered findings report, and gets confirmation before deleting anything. Use when the user says "mo clean", "clean up my computer/Mac", "optimize my computer", "free up disk space", "clear caches", "what can I remove", "old programs I don't use", "purge build artifacts", "remove leftover chrome/kuri/debug browser stuff", "mole", "/mo-clean".
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
  - Write
---

# mo-clean — deep clean + optimize this Mac (Mole) with a confirm gate

`mo` = **Mole** (https://mole.fit), a Mac deep-cleaner installed at `/usr/local/bin/mo` → `/usr/local/bin/mole`.
This skill runs Mole safely and also sweeps leftover **browser junk** the user keeps asking about
(debug-Chrome clones, Kuri, orphaned Chromium) — while never touching the **real** Chrome profiles.

**Golden rule (user's explicit instruction): confirm every risky/destructive action before doing it.**
Dry-run → show the preview → confirm → execute approved items only. Deletions go to **Trash**, never a hard `rm`.

## Mole subcommands (all support `--dry-run`)

| cmd | does |
|---|---|
| `mo clean` | free disk: caches, logs, temp files, leftovers of already-uninstalled apps |
| `mo optimize` | 22 system fixes: DNS/mDNS, LaunchServices, Dock, Spotlight, quarantine db, login-item health |
| `mo uninstall <App>` | remove an app **completely** (app + all leftovers) |
| `mo analyze [path]` · `mo status` · `mo purge` (build artifacts) · `mo installer` · `mo history` | analysis / extras |

Mole protects a lot automatically — it **skips running servers** (Codex, Chrome DevTools MCP, Xcode/CoreSimulator),
**preserves credentials**, protects Spotify offline music and whitelisted paths, and only **flags** (never auto-removes)
iOS backups, orphan dotfiles, broken login items, and project build artifacts.

## 🛡️ MANDATORY step 0: `~/tools/mole-protect/ensure-mole-protections.sh` (2026-08-13)

**Run it BEFORE any `mo purge` / `mo clean` and after any `mo update`.** Upstream mole (≤1.50.0) has a hole:
`mo purge` deletes via `safe_remove`, which honors `is_path_whitelisted` — but **only `bin/clean.sh` ever loads
`~/.config/mole/whitelist`; `bin/purge.sh` never does**, so during purge the whitelist protects NOTHING. On
2026-08-13 purge deleted `~/projects/diy-fax-worker/node_modules` (broke the FAX-policy send path) and
`~/claude-hud/dist` (broke the statusline). The script maintains three layers idempotently: whitelist entries
for the protected set, `~/claude-hud` removed from purge scan roots (line removals stick — rediscovery only
fires on an EMPTY purge_paths), and a marker-tagged patch making purge.sh load the whitelist. **`mo update`
reverts the patch** — the script detects and re-applies; it exits nonzero with a FAIL line if any layer is
missing. Verified end-to-end 2026-08-13: sandboxed real purge deleted an unprotected canary and skipped the
whitelisted one (`Items: 1`). Add new protected paths in the script's `PROTECT` array.

## ⚠️ Three non-obvious traps (this is why a naive `mo clean` call hangs / surprises)

1. **Mole needs a real TTY.** It gates its interactive UI on `[[ -t 0 ]]`. The Bash tool has no TTY, so a bare
   `mo clean` sits forever at a prompt. **Run real (non-dry) Mole commands inside a detached `tmux` session** and drive the keys.
2. **Its prompts are keypress-based, not `y/N`:**
   - `➤ System caches need sudo. Enter continue, Space skip:` → **send `Space`** to skip. The sudo path needs a
     password/Touch ID you can't supply autonomously — pressing Enter will hang. (If the user is present and *wants*
     system caches cleaned, tell them to run `mo clean` themselves in a terminal so they can authenticate.)
   - `➤ Press Enter to confirm, ESC to cancel:` → **send `Enter`**.
3. **`mo clean` MAY empty the user Trash — but do NOT rely on it either way.**
   ⚠️ **MEASURED EXCEPTION 2026-08-27 (Mole 1.52.0):** a full `mo clean` run driven by the tmux driver
   below, answering `Space` at the sudo/system-caches prompt, **did NOT empty the Trash.** Trash went
   10 -> 7 items; every Keyboard Maestro item survived, and the log tail never printed the
   `✓ Trash · emptied` line. Emptying appears gated behind the sudo path that `Space` skips.
   **Consequence: verify the Trash yourself after the run — never report it as emptied, and never
   report it as preserved, without looking.** Both directions have bitten:
   - assuming emptied -> you tell the user something is permanently gone when it is recoverable
   - assuming preserved -> you leave items the user asked to be fully removed
   🛑 **And when verifying "is X gone everywhere", remember `~/.Trash` is NOT under `~/Library`.**
   A `find ~/Library /Library /Applications` returns 0 while the item sits in Trash — that exact
   scope bug produced a false "FULLY REMOVED (Trash included)" on 2026-08-27. Search `~/.Trash`
   explicitly, and positive-control the search against an app you know is installed.

3b. **(original note, still true when the sudo path runs)** `mo clean` EMPTIES the user Trash (verified: its log prints `✓ Trash · emptied, N items`). This is
   *permanent* deletion. Consequences you must respect:
   - **Tell the user `mo clean` will empty their Trash** as part of the confirm — anything sitting in Trash is gone.
   - **Never trash something and then run `mo clean` in the same pass** expecting it to be recoverable — `mo clean`
     will permanently delete it. Either (a) do the browser-sweep trashing and let the user inspect/Put-Back **before**
     running `mo clean`, or (b) state plainly that the trashed items will be permanently removed by this run.

## Workflow

### 1. Recon (read-only, safe) — always start here
```bash
mo clean --dry-run     | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -70   # what would be freed + total GB
mo optimize --dry-run  | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -30
mo purge --dry-run     | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -10   # build artifacts — often the BIGGEST win (47GB on 2026-07-14)
mo installer --dry-run | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -10
```
Also scan for browser leftovers (see §Browser sweep). Present a compact findings table to the user.

### 2. Confirm the risky stuff (AskUserQuestion)
Ask before: the real `mo clean`, the real `mo optimize`, `mo purge`, removing any browser leftover, uninstalling any real app.
Default the *safe* option first. Never empty Trash yourself (that's permanent — `mo clean` will do it as part of an approved run, see trap #3).

### 2.5 Execution ORDER for a multi-part cleanup (learned 2026-07-14)
When one approved pass includes trash-removals + brew + purge + clean, run in THIS order so nothing is lost early:
1. `trash` the small approved leftovers (dotfiles, stubs) — still recoverable at this point
2. `brew uninstall` items (no Trash involvement)
3. `mo purge` (interactive, tmux driver below) — deletes directly, biggest space win
4. **`mo clean` LAST** — clears caches AND empties the Trash, making step 1 permanent. Say so in the report.
5. `trash-empty 30` (trash-cli, `~/.local/bin`) — mole doesn't know trash-cli's separate
   `~/.local/share/Trash` (upstream #1423), so empty its >30-day entries here. Recent
   entries stay recoverable via `trash-restore`. Skip silently if trash-cli is absent.

### 3. Run Mole in a tmux TTY and auto-answer prompts
Reusable driver — handles both prompt types and stops on completion:
```bash
run_mo () {  # usage: run_mo clean   |   run_mo optimize
  local sub="\$1" S="mo_\$1" LOG="/tmp/mo_\$1.$$.log"; : > "$LOG"
  tmux kill-session -t "$S" 2>/dev/null
  tmux new-session -d -s "$S" -x 200 -y 50
  tmux send-keys -t "$S" "mo $sub 2>&1 | tee '$LOG'; echo __EXIT_\$? >> '$LOG'" Enter
  for i in $(seq 1 150); do
    sleep 2
    grep -q "__EXIT_" "$LOG" 2>/dev/null && break
    last=$(tmux capture-pane -t "$S" -p 2>/dev/null | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -vE '^\s*$' | tail -1)
    case "$last" in
      *"Enter continue, Space skip"*) tmux send-keys -t "$S" Space ;;   # skip sudo/system-caches
      *"to confirm"*)                 tmux send-keys -t "$S" Enter ;;    # confirm the run
    esac
  done
  sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$LOG" | grep -vE '^\s*$' | tail -50
  tmux kill-session -t "$S" 2>/dev/null
}
```
`mo clean` can take a few minutes (deleting thousands of small files) — use a generous Bash `timeout` (≥300000 ms)
and, if it still runs long, re-check with `tmux capture-pane -t mo_clean -p` and `grep __EXIT_` on the log rather than assuming a hang.
Report Mole's own summary line (`Tracked cleanup: N GB | Items: … | Free space: … (+N GB)`).
A second `mo clean` in the same week yields little (skips things "cleaned Nd ago") — don't promise a repeat of the first pass's number.

## mo purge — the interactive build-artifact purge (usually the BIGGEST win)

`mo purge` has NO auto-confirm flag; drive its TUI in tmux. Keys: `↑↓` move · `Space` toggle · `Enter` confirm · `A` all · `I` invert · `Q` quit.
```bash
tmux new-session -d -s mopurge -x 220 -y 50
tmux send-keys -t mopurge "mo purge" Enter
# scan takes 1-3 min; poll capture-pane until "Select Categories to Clean" appears, then REVIEW the list, then:
tmux send-keys -t mopurge Enter      # accept selection; watch for "Purge complete"
```
What tonight (2026-07-14, 47.34GB freed) taught about the selection screen:
- **Mole pre-selects by recency**: `●` stale projects, `○` anything touched in the last few days. Its defaults are good —
  review, don't rebuild. Spot-check that active projects (recent `○` rows) stayed unselected before pressing Enter.
- **Estimates are inflated by case-duplicate rows**: APFS is case-insensitive, so `~/Code/x` and `~/code/x` list twice.
  Expect the real freed number to be 10-20% below the dry-run estimate. Not an error.
- Everything it targets is **regenerable** (node_modules / .venv / target / dist / caches) — the cost of a wrong pick is
  one `npm install` / `cargo build`, not data loss. Rust `target/` deletion does NOT touch installed binaries in `~/.cargo/bin`.
- ⚠️ **"Regenerable" ≠ safe when a launchd service depends on it at RUNTIME.** Purging `node_modules` from a project that
  backs a `KeepAlive` LaunchAgent doesn't cost "one `npm install`" — it puts that agent into a silent infinite crash-loop
  that respawns forever and can write a multi-GB log before anyone notices. **Real case (found 2026-07-26):**
  `~/quick/services/node_modules` was gone, so `com.quick.services` crash-looped on `Cannot find package 'hono'`
  **3,343,284 times → 71 MB log**. Nothing surfaced it; the service was simply dead.
  **Before confirming a purge, cross-check the selection against active agents:**
  ```bash
  # any LaunchAgent whose program/args point into a project you're about to purge?
  grep -lE "$(ls ~/Library/LaunchAgents/*.plist >/dev/null 2>&1 && echo .)" /dev/null 2>/dev/null
  for p in ~/Library/LaunchAgents/*.plist; do
    /usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$p" 2>/dev/null | grep -qE '/(Users|opt)/' \
      && echo "$(basename "$p"): $(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" 2>/dev/null)"
  done
  # then: deselect any project dir that appears above, or reinstall deps + kickstart the agent right after purging.
  ```
  After any purge that hit a service-backed project: `launchctl list | awk '\$2!=0 && \$2!="-"'` to catch new failures.
- Big single wins to expect: multi-GB tool/data caches (e.g. a genomics GWAS cache), Rust `target/` dirs, old clones' node_modules.

## Cleanup-candidate inventory (the "what else can go?" dry-run)

Tiered read-only sweep; output an HTML report to `~/Claude-Reports/` per the HTML-default rule.
- **Tier 1 (big, near-zero risk):** `mo purge --dry-run` total · old iOS backups (`~/Library/Application Support/MobileSync/Backup/*` —
  date via `Info.plist :Date` or dir mtime; a missing Info.plist = incomplete/tool-made backup; flag EMPTY device dirs too) ·
  stale `~/Library/CloudStorage/<Provider> (M-D-YY …)` relink folders (see trap below).
- **Tier 2 (unused apps — user decides):** rank `/Applications/*.app` by **preference-plist mtime**, NOT Spotlight:
  ```bash
  for app in /Applications/*.app; do bid=$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)
    p="$HOME/Library/Preferences/$bid.plist"; ts=$([ -f "$p" ] && stat -f '%m' "$p")
    echo "${ts:+$(date -r $ts '+%Y-%m-%d')}${ts:-0000-no-pref}|$(du -sh "$app"|cut -f1)|$(basename "$app")"; done | sort | head -35
  ```
  (Prefs are written when an app runs → old/absent pref ≈ unused. Spotlight `kMDItemLastUsedDate` reads (null) for
  everything mid-rebuild — unusable then.) Corroborate big candidates: a VM app with an empty `Virtual Machines.localized`
  (40K) has zero VMs; an SDK app pairs with its data dir (`Android Studio` + `~/Library/Android`).
  NEVER auto-remove Tier 2 — present the list; plausibly-active tools stay off it.
- **Tier 3 (hygiene):** `brew leaves` (flag EOL runtimes like `node@18`) · dangling casks · orphan dotfiles mole flags
  (`~/.EasyOCR`-class) · `mo installer --dry-run`.

### CloudStorage traps (both bit us 2026-07-14)
- **`du` on `<Provider> (date)` relink folders is APFS-clone-inflated** — the "36GB" folder freed ~0 real bytes when it
  went away (blocks were clone-shared). Never promise a relink folder's `du` number as reclaimable space.
- **macOS cleans these itself**: fileproviderd/DriveFS garbage-collected all four dated relink folders mid-session.
  Re-`ls` targets right before acting — they may already be gone.
- **0-byte provider stubs (e.g. `ExpanDrive`) are TCC-protected**: `trash` fails ("volume doesn't have one"), `rm -rf`
  gets permission-denied/blocked. They're harmless — LEAVE them, note it, move on.

### Downloads triage (part of every full cleanup — user expects it)
Read-only inventory first: `ls -lahtT ~/Downloads` newest-first + per-folder `du`. Then:
- **Only delete what you can PROVE dead**: byte-identical dupes (`md5 -q a b` — same-size+name-"(1)" is NOT proof, hash it;
  2026-07-14: `form` vs `form.pdf` looked like dupes, md5s differed), zips whose extract dir exists with content, `.DS_Store`.
- **Age-map to active work**: files ≤2 weeks old that match active cases/projects are WORKING files — list them grouped
  by case as *move* candidates, never delete. If a file set feeds an active goal (`goal list`), hold even the moves.
- **Check for `.tmp.driveupload`** — its presence means something Drive-syncs the folder; moving files out changes what's
  backed up. Note it before proposing moves.
- Deletions → `trash` (recoverable until the next `mo clean` empties it — sequence per §2.5).

### Dangling-cask cleanup (after any app was removed outside brew)
`brew list --cask` reads Caskroom **directories**, so a manually-deleted app still "lists". If `brew uninstall --cask X`
says "not installed" yet X still lists: `brew uninstall --cask --force X` clears stale version dirs, and a renamed cask
(e.g. `eloston-chromium → ungoogled-chromium`) leaves a **symlink** that even `--force` skips — `unlink` it directly.

## Per-app uninstall — `~/tools/app-uninstall` (use this, NOT `mo uninstall`)

`mo uninstall <App>` exists, but for removing ONE app use **`~/tools/app-uninstall`**. It carries
AppCleaner 3.6.8's own 66 search paths (extracted from its binary 2026-08-27, saved verbatim at
`~/tools/appcleaner-search-paths.txt`) applied under BOTH `~/Library` and `/Library`, **plus the
four things AppCleaner structurally cannot see**:

| Gap | Why it matters |
|---|---|
| **`~/.Trash`** | AppCleaner calls `trashItemAtURL:` to DELETE but never SEARCHES the Trash. Residue from an earlier partial/manual removal is invisible to it — this is the exact blind spot that produced a false "FULLY REMOVED" on 2026-08-27. |
| **`$TMPDIR`** | per-user `/private/var/folders/...` caches are in no AppCleaner path. |
| **TCC grants** | orphaned Accessibility/ScreenCapture rows survive the uninstall. Reported only — `TCC.db` is SIP-protected, never hand-edit it. |
| **Confidence tiers** | AppCleaner matches by fuzzy `containsStringIgnoringCase:` on 4 keys with no tiering, so a short app name substring-matches unrelated files. Ours tiers HIGH (bundle-id) vs med (name/display/exec) and refuses bare substring on keys <5 chars. |

```bash
~/tools/app-uninstall --self-test                 # negative control: proves the search is live
~/tools/app-uninstall <AppName|bundle-id|/path/App.app>          # DRY RUN (default)
~/tools/app-uninstall <App> --apply               # after reviewing the list
```

**EXIT CODES (stable contract — `/mo-clean` relies on these for the verification pass):**

| code | meaning |
|---|---|
| `0` | CLEAN — searched with >=1 usable key, found nothing |
| `10` | ARTIFACTS FOUND (or, with `--apply`, items still remain) |
| `2` | usage error |
| `3` | **COULD NOT MEASURE** — no usable match key, so NOTHING was searched. This is NOT clean. |

Three outcomes, never two. `3` fires when the app is not installed (no bundle-id readable) and the
name is under 5 chars, so every match key gets dropped — previously that printed `(none)` and
returned 0, which reads as "no leftovers" but means "I searched for nothing".

```bash
~/tools/app-uninstall "$APP"; case $? in
  0)  echo "clean" ;;
  10) echo "leftovers remain" ;;
  3)  echo "UNMEASURED — pass the bundle-id or the .app path" ;;
esac
```

**ORDERING (critical, ties into trap #3):** run `app-uninstall` and move items to Trash
**BEFORE** any `mo clean`, and tell the user those items become permanent when the Trash is
emptied. Then re-run `app-uninstall <App>` afterwards as the verification pass — it is the only
step in this skill that looks inside `~/.Trash`, so it is what proves the removal is complete.

## Browser sweep — remove leftover browser junk, protect the real one

The old `:9222` debug-Chrome clone subsystem was retired 2026-07-14 (fcdp/ccb replaced it). Residue to check for
and, with confirmation, send to **Trash**:
```bash
for d in "$HOME/.claude/chrome-debug-profile" "$HOME/.kuri" "$HOME/.kuri/chrome-profile" \
         "$HOME/tools/chrome-debug-on.sh" "$HOME/tools/chromectl"; do
  [ -e "$d" ] && printf "leftover %s  %s\n" "$(du -sh "$d" 2>/dev/null|cut -f1)" "$d"
done
```
Removal — `trash` (Apple's `/usr/bin/trash`, macOS 14+) moves to `~/.Trash`, recoverable via Finder **Put Back**:
```bash
trash "$HOME/.kuri"        # only if no Kuri.app is installed (check: ls -d /Applications/Kuri.app)
```
> ⚠️ **Sequencing:** `mo clean` empties the Trash (trap #3). So "recoverable" only holds **until** a `mo clean` runs.
> If you're doing both in one session, do the browser-sweep trashing **first** and let the user Put-Back anything
> they want **before** you run `mo clean` — otherwise the trashed leftovers are permanently deleted by the clean.

**Separate installed browsers** (e.g. `Chromium.app`) are NOT debug clones — confirm explicitly, then:
```bash
pgrep -x Chromium >/dev/null && echo "quit it first"
trash "/Applications/Chromium.app" "$HOME/Library/Application Support/Chromium"
# (or: run_mo "uninstall Chromium" for a full leftover sweep — needs the tmux driver)
```

### 🚫 NEVER touch these — real Chrome, real logins
`~/Library/Application Support/Google/Chrome/{Default, Profile 1, Profile 2, Profile 4, Profile 5, Guest Profile, System Profile}`.
These hold live logged-in sessions (one holds the primary login). "Clean up chrome besides the default one" means the
**debug/clone/leftover** browsers above — it does **not** mean deleting real Chrome profiles. If the user truly wants a
specific real profile removed, confirm that exact profile by name first.

## Manual follow-ups Mole surfaces (report, don't auto-do)
- **Broken login items** (e.g. "Cloudflare WARP · app not found") → System Settings → General → Login Items.
- **Database optimization skipped** because an app is open (e.g. Messages) → note it; user can close + re-run.
- **iOS/iPhone backups** (often 10 GB+), **orphan dotfiles**, **build artifacts** (`mo purge`) → offer, never auto-delete.

## Do / Don't
- ✅ Dry-run first; show totals; confirm before deleting; Trash not `rm`. Tell the user `mo clean` empties the Trash.
- ✅ Multi-part pass ORDER: trash small stuff → brew → `mo purge` → `mo clean` LAST (§2.5).
- ✅ `Space` to skip the sudo/system-caches step (can't authenticate headless).
- ✅ Re-verify targets exist right before acting (macOS may have self-cleaned CloudStorage relink folders).
- ❌ Don't run bare `mo clean`/`mo optimize`/`mo purge` outside tmux (they hang on keypress prompts).
- ❌ Don't delete real Chrome profiles, manually empty Trash, or type a sudo password.
- ❌ Don't quote a relink folder's `du` as reclaimable GB (APFS clones), don't fight TCC-protected 0-byte provider stubs,
  and don't auto-remove any Tier-2 app without the user picking it by name.
