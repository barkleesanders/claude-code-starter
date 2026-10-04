# Bash Trap Catalog

Every entry is a real incident. The common shape: **the command did not error, and the wrong answer was plausible.**

Machine-readable equivalents live in `~/tools/bashguard`; each rule there carries `test_trips` and `test_clean` cases so `bashguard selftest` proves it both fires and stays quiet.

---

## BG001 — `for X in $VAR` does not word-split in zsh · HIGH

**The Bash tool runs zsh.** In bash, `for D in $DOCS` splits `$DOCS` on whitespace and iterates per item. **In zsh it does not** — the loop body runs exactly once with the entire multi-line string as a single value.

```bash
DOCS=$'a\nb\nc'
for D in $DOCS; do curl "https://x/$D.pdf"; done
# bash: 3 requests.   zsh: ONE request to https://x/a\nb\nc.pdf  -> http=000
```

The tell is uniformity: *every* iteration fails identically, which reads as "the server is blocking me" rather than "my loop is broken."

**Fix** — `while read` behaves the same in both shells:
```bash
while read -r D; do curl "https://x/$D.pdf"; done < <(producer)
```
Or force bash: `bash -c 'for D in $DOCS; do ...; done'`. Or use an array: `for D in "${ARR[@]}"`.

⚠️ Note the asymmetry: an inline Bash-tool command is **zsh**, but `bash script.sh` is **bash**. The same loop can work in a script and fail inline — which makes it feel nondeterministic.

**Incident 2026-08-12** — a House PTR sweep reported 40/40 PDFs unreadable. Hardcoded literal DocIDs fetched fine; extracted ones never did. Four round-trips: first suspected rate-limiting, then a broken loop, then CRLF. BG001 and BG002 were stacked in the same command.

---

## BG002 — CRLF data files put `\r` inside your variables · HIGH

Government and Windows-authored files are frequently CRLF. `awk`/`cut` hand you the field **with the carriage return attached**. It is invisible in terminal output, and it silently corrupts any URL or path built from it.

```bash
awk -F'\t' '{print $9}' 2026FD.txt        # -> "20034201\r"
curl "https://host/$D.pdf"                 # -> https://host/20034201\r.pdf  -> 000
```

**Detect:** `file data.txt` → "with CRLF line terminators", or `od -c` the field.
**Fix:** `| tr -d '\r'` on extraction, or `dos2unix` the file once.

**Incident 2026-08-12** — the House Clerk `<YYYY>FD.txt` index is CRLF. Every extracted DocID was unusable while literals worked, which is exactly the pattern that misleads you toward a network explanation.

---

## BG003 — `curl -o` writes error pages as data · HIGH

Without `--fail` or a status check, curl writes 403/404/500 bodies to the output file and **exits 0**. Downstream stages then parse an HTML error page as the payload.

```bash
curl -sL -o out.json "$URL"     # 403 body lands in out.json, exit 0
jq '.items' out.json            # "empty dataset" — actually a permissions error
```

**Fix:**
```bash
code=$(curl -sL -o out -w '%{http_code}' "$URL")
[ "$code" = 200 ] || { echo "got $code"; exit 1; }
# or
curl -fsSL -o out "$URL"        # --fail: non-2xx becomes a real error
```

**Incident 2026-08-12** — `house-stock-watcher-data.s3...` returned 403 with a 243-byte body. Unchecked, that becomes "the mirror is empty" instead of "the mirror is gone."

---

## BG004 — piped `while read` loses your counters · HIGH

`producer | while read ...` runs the loop in a **subshell**. Variables mutated inside are discarded at the pipe boundary.

```bash
cat ids | while read -r x; do n=$((n+1)); done
echo "$n"        # always empty/0 — the loop DID run
```

**Fix:** keep the loop in the current shell with process substitution or a redirect:
```bash
while read -r x; do n=$((n+1)); done < <(cat ids)
while read -r x; do n=$((n+1)); done < ids
```

A zero tally reads as "found nothing," never as "the counter was thrown away."

---

## BG005 — the working directory resets between calls · warn

The harness resets cwd between Bash invocations. A relative path that worked in the previous call resolves elsewhere — or nowhere — in this one.

**Fix:** absolute paths, or put the `cd` in the *same* command: `cd /abs/dir && bash script.sh`.

**Incident 2026-08-12** — a `/goal` was created from `~/tools`; the shell reset to `$HOME`; the follow-up `goal deliverable done` resolved to a *different* state file. Only a `GOAL_EXPECT` precondition prevented overwriting an unrelated goal's evidence. Note the guard worked precisely because it asserted the expected target rather than trusting the path.

---

## BG006 — `2>/dev/null` on the command you are about to interpret · warn

Discarding stderr on the command whose result becomes your conclusion removes the only signal separating "genuinely zero" from "the tool errored."

**Fix:** capture instead of discard — `out=$(cmd 2>&1) || echo "FAILED: $out"`. Silence stderr only for noise you have already read once.

**Incident 2026-08-12** — `pdfinfo t.pdf >/dev/null 2>&1` inside a sweep turned every malformed-URL fetch into a silent `err++`. The loop reported 40/40 failures with no visible cause, which is what sent the debugging in the wrong direction.

---

## BG007 — a sweep with no positive control · warn

A tally across N items is only trustworthy if the measurement has been proven to fire on a known-good case **first**.

```bash
# before the sweep:
verify_one "$KNOWN_GOOD" || { echo "instrument broken — sweep is void"; exit 1; }
```

If the control fails, do not report the sweep. Report that you could not measure.

**Incident 2026-08-12** — the 40/40 result was disproven in one command by re-running a document that had parsed successfully two minutes earlier.

---

## BG008 — pipeline exit status without `pipefail` · warn

A pipeline's status is the **last** stage's. `producer | filter && echo ok` prints `ok` even when the producer died, because the filter succeeded on empty input.

**Fix:** `set -o pipefail`, or test the producer separately before piping.

---

## Meta-trap: inline Python inside a hook

Writing a formatter as `python3 -c '...'` inside a single-quoted shell string means `\"` reaches Python literally. Inside an f-string expression that is a **SyntaxError** — so the hook prints *nothing*, which is indistinguishable from "the command is clean."

**Fix:** put formatting in the tool (`bashguard check --brief`), not in the hook. The hook should be a pipe and nothing else.

Caught 2026-08-12 by the positive control while building this very skill — the hook's first version silently reported clean on a command with two HIGH findings.
