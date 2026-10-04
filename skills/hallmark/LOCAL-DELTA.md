# Local delta vs upstream

Installed from `github.com/nutlope/hallmark` @ `aeb42fb` (2026-06-04), v1.1.0, MIT.
Installed 2026-07-14 for the `/design` skill (which routes to Hallmark as its default engine).

## Why this file exists

Upstream's install instructions say "copy `SKILL.md` and the `references` folder." But
`SKILL.md` and 5 reference files link to assets that live **outside** `skills/hallmark/`
in the repo. A literal SKILL.md+references install leaves those links dangling.

The load-bearing one is `site/css/tokens.css` — it holds the 20 catalog themes' actual
OKLCH token blocks **and** the per-theme diversification axis comments (paper band /
display style / accent hue) that SKILL.md Step 2 and Step 2.5 read to enforce the
theme-rotation rule. Catalog is the *default* theme route, so without this file the
default path is degraded.

## What was changed

**Vendored in** (so nothing escapes the skill dir):

| Upstream path | Local path |
|---|---|
| `site/css/tokens.css` | `references/tokens.css` |
| `site/examples/cobalt-01/` | `examples/cobalt-01/` |
| `site/_tests/03-maple-bakery/` | `examples/03-maple-bakery/` |
| `site/_tests/05-tracejam-saas/` | `examples/05-tracejam-saas/` |
| `docs/recipes.md` | `docs/recipes.md` |
| `docs/study-examples.md` | `docs/study-examples.md` |

**Link targets repointed** (markdown label text left as-is; only the `(target)` changed):

- `SKILL.md` → `references/tokens.css`, `docs/recipes.md`, `docs/study-examples.md`
- `references/custom-theme.md` → `tokens.css`
- `references/themes/{carnival,cobalt,hum,lumen}.md` → `../tokens.css`
- `references/themes/cobalt.md` → `../../examples/cobalt-01/`
- `references/hero-enrichment.md` → `../examples/{03-maple-bakery,05-tracejam-saas}/`

No prose, rules, gates, or theme content was modified. Only link targets.

## On update

`npx skills add nutlope/hallmark` (or any re-copy of upstream) will **overwrite SKILL.md
and references/ and re-break these links.** After updating, re-apply the repointing above,
or re-run the vendoring. Verify with:

```bash
cd ~/.claude/skills/hallmark
grep -rno '](\(\.\./\)\{2,\}[a-zA-Z0-9/_.-]*)' SKILL.md references/   # should print nothing
```

If that prints anything, a link escapes the skill directory and is dangling.
