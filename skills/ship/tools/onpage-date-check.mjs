#!/usr/bin/env node
/**
 * Does every page's "Last updated" / "Effective date" still tell the truth?
 *
 * Repo-agnostic. Discovers date claims in source rather than taking a
 * hardcoded page map, so it works on a repo it has never seen.
 *
 * WHY (example, 2026-08-25): a site has TWO "last updated" facts and they go
 * stale independently. The sitemap <lastmod> is a crawler hint and /ship
 * already gated it. The on-page line is a sentence a HUMAN uses to decide
 * whether a contract changed since they last read it, and nothing gated it —
 * so four of five public pages were lying, by up to four months, while the
 * sitemap gate ran and passed.
 *
 * WHAT IT COMPARES: each claimed date against the last commit that changed that
 * file's VISIBLE TEXT — tags, attributes, imports and the date line itself
 * stripped. Not "any commit": a formatting pass or a class-name tweak must
 * never demand a date bump, or the gate cries wolf and gets switched off.
 *
 * VERDICTS — four, never two:
 *   ok          claimed date == the day the copy last changed
 *   stale       copy changed AFTER the claimed date         -> exit 1
 *   overstated  claimed date is AFTER any copy change       -> exit 1
 *               (the inverse lie: sends a reader hunting a change that
 *                never happened. Caught two hand-entered dates on the
 *                original run.)
 *   unknown     a claim exists but the date could not be resolved or git
 *               history is unavailable                       -> exit 2
 *
 * A `@governed-by <IDENT>` annotation was tried, to follow the specific clauses
 * a date is scoped to instead of the whole file. It is NOT here because its
 * failure path could not be demonstrated: a scratch clone with a real commit
 * revising a governed clause still passed. A check whose red path cannot be
 * shown is not a check, so `unknown` — honest, and resolvable by a human —
 * stands instead.
 *
 * "unknown" is never folded into "ok". A checker that reports what it could not
 * measure as healthy is the exact failure this class of bug lives in.
 *
 * NO CLAIMS FOUND is reported explicitly, not as a silent green — most repos
 * have no dated pages and that must be distinguishable from a broken scan.
 *
 * Usage: node onpage-date-check.mjs <repo-path> [--json] [--verbose]
 */
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const repo = process.argv[2];
const asJson = process.argv.includes("--json");
const verbose = process.argv.includes("--verbose");
if (!repo || !existsSync(join(repo, ".git"))) {
  console.error("usage: onpage-date-check.mjs <repo-path> [--json] [--verbose]");
  console.error("  (path must be a git repository)");
  process.exit(3);
}

const git = (...a) =>
  execFileSync("git", ["-C", repo, ...a], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });

const EXT = /\.(tsx|jsx|ts|js|mjs|html|astro|svelte|vue)$/;
const SKIP_DIR =
  /(^|\/)(node_modules|dist|build|out|\.next|\.wrangler|\.git|coverage|vendor|ios|android|__fixtures__|__mocks__|__snapshots__|fixtures|testdata|examples)(\/|$)/;
const SKIP_FILE = /(\.test\.|\.spec\.|\.d\.ts$|\.min\.js$|-[A-Za-z0-9_]{8}\.js$)/;

function walk(dir, acc = []) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return acc;
  }
  for (const name of entries) {
    const full = join(dir, name);
    const rel = relative(repo, full);
    if (SKIP_DIR.test(`/${rel}/`)) continue;
    let st;
    try {
      st = statSync(full);
    } catch {
      continue;
    }
    if (st.isDirectory()) walk(full, acc);
    else if (EXT.test(name) && !SKIP_FILE.test(rel)) acc.push(rel);
  }
  return acc;
}

/**
 * The phrases that constitute a freshness claim to the reader. "Effective"
 * alone counts — improvebayarea labels its terms date exactly that way, and
 * requiring the full phrase "effective date" made this tool blind to a live
 * /terms page it was built to cover.
 */
const CLAIM_STRONG =
  /(last[\s-]updated|last[\s-]revised|last[\s-]modified|effective\s+date)\b/i;
/**
 * A bare "Effective" / "Updated" label is a claim ONLY when a <time> element
 * sits beside it. Without that guard the word matches CSS (`animation: just
 * updated .2s`), TTL constants and sitemap <changefreq> — 11 false findings on
 * the first run. A checker that fires on CSS gets switched off, which is worse
 * than not having one.
 */
const CLAIM_WEAK = /(^|[^-_\w])(effective|updated|revised|modified)\b/i;

const MONTHS =
  "January|February|March|April|May|June|July|August|September|October|November|December";
/** A literal date in any shape a human writes on a page. */
const LITERAL = new RegExp(
  `((?:${MONTHS})\\s+\\d{1,2},?\\s+\\d{4}|(?:${MONTHS})\\s+\\d{4}|\\d{4}-\\d{2}-\\d{2})`,
  "i",
);
/** HTML's own "this is a date" marker — the strongest, most portable signal. */
const TIME_TAG = /<time\b[^>]*>/i;
/**
 * Identifiers inside a ${...} or {...} expression. SCREAMING_CASE first because
 * that is the convention for a date constant, but any identifier is tried —
 * the value may be wrapped in a call like ${escapeText(TERMS_EFFECTIVE_DATE)},
 * which a bare {IDENT} pattern cannot see through.
 */
function expressionIdents(text) {
  const out = [];
  for (const m of text.matchAll(/\$?\{([^{}]*)\}/g)) {
    for (const id of m[1].matchAll(/[A-Za-z_$][\w$]*/g)) {
      if (!out.includes(id[0])) out.push(id[0]);
    }
  }
  out.sort((a, b) => {
    const A = /^[A-Z][A-Z0-9_]*$/.test(a) ? 0 : 1;
    const B = /^[A-Z][A-Z0-9_]*$/.test(b) ? 0 : 1;
    return A - B;
  });
  return out;
}
/** A quoted key used to index a registry: X["/terms"] */
function keyIn(text) {
  const m = /\[\s*["']([^"']+)["']\s*\]/.exec(text);
  return m ? m[1] : null;
}

/**
 * Find freshness claims. A claim = a freshness LABEL with a date, a <time>
 * element, or a date expression WITHIN A SHORT WINDOW of lines — markup
 * routinely splits the label and the value across elements.
 *
 * A bare "Last Updated" with nothing date-like nearby is a TABLE COLUMN LABEL
 * or a form field, not a claim about the page. Including those would bury the
 * real findings.
 */
const WINDOW = 3;

function findClaims(rel) {
  const lines = readFileSync(join(repo, rel), "utf8").split("\n");
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const strong = CLAIM_STRONG.exec(lines[i]);
    const weak = strong ? null : CLAIM_WEAK.exec(lines[i]);
    if (!strong && !weak) continue;
    const isComment = /^\s*(\/\/|\*|\/\*|#)/.test(lines[i]);
    const window = lines.slice(i, i + WINDOW + 1).join("\n");
    // Cut everything before the label so a date EARLIER on the line (a
    // copyright year, an unrelated timestamp) cannot be mistaken for it.
    const after = window.slice((strong ?? weak).index);

    const lit = LITERAL.exec(after);
    const hasTime = TIME_TAG.test(after);
    const idents = expressionIdents(after);
    // A weak label needs <time> to count at all. Reject WITHOUT advancing:
    // a rejected candidate must never consume the lines that follow it.
    if (!strong && !hasTime) continue;
    // An expression is a DATE expression only when <time> marks it as one, or
    // an identifier is shaped like a date constant. Everything else in a
    // template literal is ordinary interpolation, not a freshness claim.
    // SCREAMING_CASE only. This gate is about HARDCODED dates that rot in
    // source; a date computed at runtime (updatedAt, view.updated_datetime,
    // new Date()) is per-record data that cannot go stale, and flagging it
    // produced noise on every ticket and dashboard page.
    const dateShaped = idents.filter(
      (id) =>
        /^[A-Z][A-Z0-9_]*$/.test(id) &&
        /(DATE|UPDATED|MODIFIED|REVISED|EFFECTIVE|LASTMOD)/.test(id),
    );
    const usable = dateShaped;
    if (!lit && usable.length === 0) continue;

    if (lit && !hasTime && idents.length === 0) {
      out.push({ kind: "literal", value: lit[1], isComment, line: lines[i].trim() });
    } else if (usable.length > 0) {
      out.push({
        kind: "reference",
        idents: usable,
        key: keyIn(after),
        isComment,
        line: lines[i].trim(),
      });
    } else if (lit) {
      out.push({ kind: "literal", value: lit[1], isComment, line: lines[i].trim() });
    }
    i += WINDOW; // one finding per claim site, not one per window line
  }
  return out;
}

/**
 * Resolve a date constant anywhere in the repo. Handles BOTH shapes:
 *   const X = "August 25, 2026"                     (scalar)
 *   const X = { "/terms": "August 25, 2026", ... }  (keyed registry)
 * The registry is the shape this gate RECOMMENDS, so failing to resolve one
 * would make the tool blind on exactly the repos that already did it right.
 */
function resolveConstant(name, key, files) {
  const scalar = new RegExp(
    `(?:const|let|var|export const)\\s+${name}\\s*(?::[^=]+)?=\\s*["'\`]([^"'\`]+)["'\`]`,
  );
  const mapBlock = new RegExp(
    `(?:const|let|var|export const)\\s+${name}\\s*(?::[^=]+)?=\\s*\\{([\\s\\S]*?)\\n\\s*\\};`,
  );
  for (const f of files) {
    const src = readFileSync(join(repo, f), "utf8");
    const s1 = scalar.exec(src);
    if (s1) return s1[1];
    const m1 = mapBlock.exec(src);
    if (m1 && key) {
      const entry = new RegExp(
        `["'\`]${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'\`]\\s*:\\s*["'\`]([^"'\`]+)["'\`]`,
      ).exec(m1[1]);
      if (entry) return entry[1];
    }
  }
  return null;
}

/** Reduce a source file to the words a reader sees. */
function visibleText(src) {
  return src
    // The date line is metadata ABOUT the copy, not copy. Without this the
    // check is self-referential: bumping a date changes the "visible text",
    // which demands another bump, forever.
    .replace(
      /(last[\s-]updated|last[\s-]revised|effective date)[^\n]*/gi,
      "$1 <DATE>",
    )
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/^\s*(import|export)\s[\s\S]*?from\s+["'][^"']+["'];/gm, " ")
    .replace(/<style[\s\S]*?<\/style>/g, " ")
    .replace(/<script[\s\S]*?<\/script>/g, " ")
    .replace(/\$?\{[^{}]*\}/g, " ")
    .replace(/<[^>]*>/g, " ")
    .replace(/&[a-z]+;/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Day (local calendar) of the newest commit that changed this file's copy. */
function lastCopyChange(rel) {
  let log;
  try {
    log = git("log", "--format=%H %cd", "--date=short", "--", rel).trim();
  } catch {
    return null;
  }
  if (!log) return null;
  for (const line of log.split("\n")) {
    const [sha, day] = line.split(" ");
    let after, before;
    try {
      after = visibleText(git("show", `${sha}:${rel}`));
    } catch {
      continue;
    }
    try {
      before = visibleText(git("show", `${sha}^:${rel}`));
    } catch {
      before = "";
    }
    if (after !== before) return { sha: sha.slice(0, 7), day };
  }
  return null;
}

/** Normalize a human date to a local YYYY-MM-DD. Month-only -> that month. */
function toDay(value) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return { day: value, precision: "day" };
  const monthOnly = new RegExp(`^(${MONTHS})\\s+\\d{4}$`, "i").test(value);
  const d = new Date(`${value.replace(",", "")} 12:00:00`);
  if (Number.isNaN(d.getTime())) return null;
  const day = [
    d.getFullYear(),
    String(d.getMonth() + 1).padStart(2, "0"),
    String(d.getDate()).padStart(2, "0"),
  ].join("-");
  return { day, precision: monthOnly ? "month" : "day" };
}

const files = walk(repo);
const results = [];

// Count reader-facing claims per file first, so the ambiguity guard below can
// tell a single-page file from a multi-page one.
const claimsInFile = new Map();
const claimsByFile = new Map();
for (const rel of files) {
  const cs = findClaims(rel);
  claimsByFile.set(rel, cs);
  claimsInFile.set(rel, cs.filter((c) => !c.isComment).length);
}

for (const rel of files) {
  for (const claim of claimsByFile.get(rel)) {
    let raw = null;
    // Remember WHICH identifier resolved to the date. The first identifier in
    // an expression is often a helper (escapeAttr(DATE_CONST)), and looking up
    // the @governed-by annotation under the helper's name finds nothing.
    let resolvedIdent = null;
    if (claim.kind === "literal") {
      raw = claim.value;
    } else {
      for (const id of claim.idents) {
        const v = resolveConstant(id, claim.key, files);
        if (v && toDay(v)) {
          raw = v;
          resolvedIdent = id;
          break;
        }
      }
    }
    if (!raw) {
      results.push({
        file: rel,
        verdict: "unknown",
        why:
          `claims a date via {${(claim.idents || []).join("|")}` +
          `${claim.key ? `["${claim.key}"]` : ""}} but no such date constant resolved`,
      });
      continue;
    }
    const parsed = toDay(raw);
    if (!parsed) {
      results.push({ file: rel, verdict: "unknown", why: `unparseable date "${raw}"` });
      continue;
    }
    // AMBIGUITY GUARD. Comparison is FILE-level, so a file that renders more
    // than one dated page cannot have a change attributed to the right one.
    // improvebayarea's trust_pages.ts renders /about, /terms and /contact
    // together with two separate effective dates, each scoped by its own
    // comment to specific clauses. Reporting STALE there would have had me
    // editing a live legal effective date on evidence that could not support
    // it. When the instrument's granularity does not match the claim's, the
    // honest answer is "could not measure".
    // A COMMENT claim is a maintainer note and can never be a block, so it must
    // not reach the ambiguity guard — otherwise the doc comment that explains a
    // date constant becomes an "unknown" about the page it documents.
    if (claim.isComment) {
      const cc = lastCopyChange(rel);
      results.push({
        file: rel,
        verdict: "note",
        why: cc
          ? `comment note; file copy last changed ${cc.day} (${cc.sha}), note says "${raw}"`
          : `comment note: "${raw}"`,
      });
      continue;
    }

    if (claimsInFile.get(rel) > 1) {
      results.push({
        file: rel,
        verdict: "unknown",
        why:
          `renders ${claimsInFile.get(rel)} dated pages from one file — a file-level ` +
          `diff cannot say which page's copy changed. Split the file per page, ` +
          `or verify by hand and record what you checked.`,
      });
      continue;
    }
    const change = lastCopyChange(rel);
    if (!change) {
      results.push({
        file: rel,
        verdict: "unknown",
        why: "no git history for this file",
      });
      continue;
    }
    // A month-only claim ("April 2026") is satisfied by any change in that
    // month — holding it to a day would demand a precision the page never
    // offered.
    const claimKey =
      parsed.precision === "month" ? parsed.day.slice(0, 7) : parsed.day;
    const changeKey =
      parsed.precision === "month" ? change.day.slice(0, 7) : change.day;

    if (changeKey > claimKey) {
      results.push({
        file: rel,
        verdict: claim.isComment ? "note" : "stale",
        why: `copy changed ${change.day} (${change.sha}) but page says "${raw}"`,
      });
    } else if (claimKey > changeKey) {
      results.push({
        file: rel,
        verdict: claim.isComment ? "note" : "overstated",
        why: `page says "${raw}" but copy last changed ${change.day} (${change.sha})`,
      });
    } else {
      results.push({
        file: rel,
        verdict: claim.isComment ? "note-ok" : "ok",
        why: `copy last changed ${change.day}, page says "${raw}"`,
      });
    }
  }
}

// Two claim lines in one file (a badge and a footer, say) are ONE finding, not
// two — duplicate rows bury the real ones.
const seen = new Set();
const deduped = results.filter((r) => {
  const k = `${r.file}|${r.verdict}|${r.why}`;
  if (seen.has(k)) return false;
  seen.add(k);
  return true;
});
results.length = 0;
results.push(...deduped);

if (asJson) {
  console.log(JSON.stringify({ repo, scanned: files.length, results }, null, 2));
} else if (results.length === 0) {
  // Explicit, not silent. "Zero claims" and "the scan is broken" must look
  // different to whoever reads this.
  console.log(
    `  no on-page date claims found (${files.length} source files scanned) — nothing to verify`,
  );
} else {
  for (const r of results) {
    if ((r.verdict === "ok" || r.verdict === "note-ok") && !verbose) continue;
    const tag = {
      ok: "ok        ",
      "note-ok": "note      ",
      note: "note      ",
      stale: "STALE     ",
      overstated: "OVERSTATED",
      unknown: "unknown   ",
    }[r.verdict];
    console.log(`  ${tag} ${r.file}\n             ${r.why}`);
  }
  const n = (v) => results.filter((r) => r.verdict === v).length;
  const notes = n("note") + n("note-ok");
  console.log(
    `  -- ${n("ok")} ok, ${n("stale")} stale, ${n("overstated")} overstated, ` +
      `${n("unknown")} unknown, ${notes} comment-note (${files.length} files scanned)`,
  );
  if (n("note") > 0) {
    console.log(
      "     comment-notes are maintainer metadata on harvested data, not a claim\n" +
        "     to a reader — they do NOT block here. See /ship Phase 1.56b.",
    );
  }
}

const bad = results.some((r) => r.verdict === "stale" || r.verdict === "overstated");
const unknown = results.some((r) => r.verdict === "unknown");
if (bad) {
  console.error(
    "\nBLOCK: a page's stated date does not match its own copy. Set it to the day\n" +
      "the copy actually changed — not to today; dating an untouched page today is\n" +
      "the OVERSTATED failure, not a fix.",
  );
}
process.exit(bad ? 1 : unknown ? 2 : 0);
