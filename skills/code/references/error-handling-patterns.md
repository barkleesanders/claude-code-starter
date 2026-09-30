# Error Handling Patterns

## Pattern 1: Catch-All Error Handling Masking Root Cause

**Rank: #3 production debugging trap.**

A single `try-catch` wrapping multiple operations returns a generic error, making it impossible to identify which operation actually failed.

### Symptoms
- Error message says one thing (e.g., "Token verification failed") but actual failure is different (e.g., API down, DB timeout)
- Logs show generic error but not the specific operation that threw
- Can't reproduce locally because the failing external service works in dev

### Quick Detection
```bash
# Find catch blocks returning generic errors in middleware/handlers
grep -B2 -A5 "catch.*error" --include="*.ts" -r src/worker/ | grep -A5 "return.*json.*error"

# Find large try-catch blocks (catch far from try = multiple wrapped operations)
grep -n "} catch" --include="*.ts" -r src/worker/middleware/
```

### Fix Pattern
```typescript
// CATCH-ALL: All errors return same message + status code
try {
  const token = await verifyToken(jwt);        // Auth failure
  const user = await clerkApi.getUser(sub);    // API failure
  const data = await db.query("SELECT ...");   // DB failure
} catch (error) {
  return json({ error: "Authentication failed" }, 401);  // MISLEADING!
}

// SPLIT: Each failure mode gets correct status + message
let token;
try {
  token = await verifyToken(jwt);
} catch (e) {
  console.error("JWT verification failed:", e.message);
  return json({ error: "Token verification failed" }, 401);
}

try {
  const user = await clerkApi.getUser(token.sub);
  const data = await db.query("SELECT ...");
} catch (e) {
  console.error("Auth lookup error:", e.message);
  return json({ error: "Service temporarily unavailable" }, 503);
}
```

### Status Code Guide
| Failure Mode | Status Code | When |
|-------------|-------------|------|
| JWT/token verification | 401 | Bad token, expired, wrong key |
| External API (Clerk, Stripe) | 503 | Service unavailable |
| Database error | 503 or 500 | Connection failed, query error |
| Business logic validation | 400 or 422 | Bad input |

### Real-World Case: AIVA Benefits Finder (2026-02-27)
- **Symptom**: "Unauthorized: Token verification failed" on every benefits search
- **Root cause**: Clerk API call in the same try-catch was failing, but the catch returned 401
- **Fix**: Split into JWT try-catch (401) and service try-catch (503)
- **File**: `src/worker/middleware/clerkAuth.ts`
- **Commit**: `5aeec79`

---

## Pattern 15: External Municipal Form Category Hard-500 (SF311/Verint)

**Rank: High for civic reporting apps that proxy city web forms.**

Some city form platforms return a generic 500 for specific category/form combinations even when auth, session, CSRF, address, photo upload, and payload shape are otherwise valid. Do not treat every `500 Internal Server Error` as a broken global submit path.

### Symptoms
- Submit or resubmit works for one category, then fails after "Improve with AI" or a manual category change
- Error text is generic, for example: `SF311 save 500: {"message":"500 Internal Server Error","status":"ERROR"}`
- The same photo, address, title, and description work when submitted through another request type
- City platform uses a combined department/category field such as `request_type_id`

### Root Cause
Some SF311/Verint form routes are category-specific. A non-default form can hard-fail on `/api/save` while the known-good default form succeeds with the same session and location data. In ImproveBayArea this happened with non-default SF categories after AI rewrite/resubmit; the correct fix was a controlled fallback, not changing auth, photo upload, or generic retry behavior.

### Quick Detection
```bash
# Find the code paths that select external city form/category ids
rg -n "SF311 save 500|Verint|request_type_id|api/save|complete=N|category_fallback|sf311_category_fallback" src tests

# Check whether category changes can alter the downstream form target
rg -n "selectedCategory|requestType|request_type_id|rewrite-text|analyze|resubmit" src tests
```

### Debug Protocol
1. Reproduce the failing non-default category using the same first-party city save path the app uses. For Verint, prefer a draft/save probe (`complete=N`) when available so you can isolate form validation from final filing.
2. Re-run the same session, photo/address payload, and description against the known-good default form/category.
3. If the default path succeeds and the non-default path returns 500, record it as a category/form compatibility failure.
4. Preserve the user's selected category in the submitted description or telemetry so the city still sees the user's intent.
5. Add regression coverage that mocks non-default form 500, then proves fallback to the known-good form succeeds.

### Fix Pattern
```typescript
const requestedCategory = selectedCategory;
let result = await saveToCityForm(selectedCategory, payload);

if (isMunicipalFormHard500(result) && selectedCategory.city === "san-francisco") {
  const fallbackPayload = {
    ...payload,
    description: [
      `Requested category: ${requestedCategory.label}`,
      payload.description,
    ].join("\n\n"),
    metadata: {
      ...payload.metadata,
      sf311_category_fallback: true,
      requested_request_type_id: requestedCategory.id,
      requested_form: requestedCategory.form,
      fallback_reason: "verint_save_500",
    },
  };
  result = await saveToCityForm(SF311_KNOWN_GOOD_DEFAULT_CATEGORY, fallbackPayload);
}
```

### Verification
- Targeted test asserts non-default category 500 triggers fallback and final result succeeds.
- Test asserts title/description keep the user's selected category context.
- Test asserts telemetry includes requested category id/label/form, response status, and fallback reason.
- Live verification checks the returned city ticket in the official tracker, not just the app database.

### Real-World Case: ImproveBayArea SF311 Resubmit (2026-05-09)
- **Symptom**: Resubmitting an SF ticket after "Improve with AI" failed with `SF311 save 500`.
- **Root cause**: SF Verint accepted the known-good street-cleaning form but hard-500ed on specific alternate category forms.
- **Fix**: Detect Verint save 500, fall back to the proven SF category, preserve the requested category in the description, and log structured fallback telemetry.

---

## Pattern 11: CI False Positives from Local Grep

**Rank: Common time-waster in CI debugging.**

Local `grep` for code patterns produces false matches that lead to wrong conclusions about what CI is actually checking.

### Symptoms
- You "fix" what grep tells you is wrong, but CI still fails
- grep matches patterns inside string literals, comments, or unrelated code
- CI uses a project-specific validator with different rules than your grep

### Quick Detection
```bash
# Don't guess -- read the actual CI logs
gh run view <RUN_ID> --log-failed

# Or get all check-runs for latest commit
gh api repos/<owner>/<repo>/commits/<SHA>/check-runs --jq '.check_runs[] | {name, conclusion}'
```

### Real-World Case: topgrade i18n (2026-03-07)
- Grepped for `t!("...")` to find locale strings needing translations
- `format!("...")` matched because `format` ends in `t`, making grep think it was `t!(...)`
- Wasted a round of CI. Should have read the actual CI checker script or used `gh run view --log-failed`

---

## Pattern 14: Admin Route Auth Missing DB Fallback (Metadata-Only Check)

**Rank: Silent 403 for production admin -- every admin route fails with no obvious cause.**

Custom `requireAdmin()` functions in route files that only check Clerk `publicMetadata.role === "admin"` silently block the real production admin, who is set via `is_admin = 1` in the DB (not Clerk metadata).

### Symptoms
- Admin tabs (Referrals, Users, etc.) show "Could not load data" or "Failed to load" for the real admin
- `/api/admin/*` routes return 403 for `help@aivaclaims.com`
- No error in logs because the `throw new Error("Admin access required")` is caught and returned as 403
- Works fine in local dev if you set Clerk metadata there but not in production

### Root Cause
Two separate admin authorization mechanisms exist:
1. **`adminMiddleware`** in `src/worker/index.ts` -- checks Clerk metadata OR DB `is_admin=1` (correct)
2. **Custom `requireAdmin()`** in individual route files -- may only check Clerk metadata (wrong)

The production admin (`help@aivaclaims.com`) uses `is_admin = 1` in the DB. It does NOT have `publicMetadata.role === "admin"` in Clerk. Any route that uses a metadata-only check returns 403 for this user.

### Quick Detection
```bash
# Find custom requireAdmin functions in route files
grep -rn "requireAdmin\|require_admin" src/worker/routes/ --include="*.ts"

# Check if any are synchronous (sync = no DB fallback = metadata-only)
grep -B2 -A10 "function requireAdmin" src/worker/routes/*.ts

# Check adminMiddleware in index.ts for comparison
grep -A15 "adminMiddleware" src/worker/index.ts
```

### Fix Pattern
```typescript
// WRONG -- metadata-only, silently blocks DB-based admin
function requireAdmin(c: Context) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role !== "admin") {
    throw new Error("Admin access required");
  }
  return user;
}

// CORRECT -- must be async, matches adminMiddleware pattern
async function requireAdmin(c: Context<{ Bindings: Env }>) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role === "admin") return user;
  // DB fallback -- production admin uses is_admin=1, not Clerk metadata
  const dbUser = await c.env.DB.prepare(
    "SELECT is_admin FROM users WHERE id = ?",
  ).bind(user.id).first<{ is_admin: number }>();
  if (dbUser?.is_admin === 1) return user;
  throw new Error("Admin access required");
}

// All call sites must await: requireAdmin(c) -> await requireAdmin(c)
```

### Real-World Case: AIVA adminClerk.ts (2026-03-13)
- **Symptom**: Referrals tab, user lookup, referrers list all showed "Could not load data" for `help@aivaclaims.com`
- **Root cause**: `requireAdmin()` was synchronous and metadata-only. Production admin has `is_admin=1` but no Clerk metadata role.
- **Fix**: Made `requireAdmin` async with DB `is_admin` fallback; updated all 6 call sites from `requireAdmin(c)` to `await requireAdmin(c)`. Added `Context<{ Bindings: Env }>` type so `c.env.DB` was accessible.
- **Files**: `src/worker/routes/adminClerk.ts`

---

## Admin Route Returns 500 Instead of 403

- **Symptom**: Admin check fails but returns 500 (Internal Server Error) instead of 403 (Forbidden)
- **Quick Detection**: `grep -A5 "function requireAdmin" --include="*.ts" src/worker/ | grep "throw new Error"`
- **Fix**: `throw new HTTPException(403, { message: "Admin access required" })` instead of `throw new Error(...)`
- **Incident (2026-03-15)**: `adminClerk.ts` routes returned 500 for non-admin users

---

## External Form Description Truncation by Character (#19, 2026-05-11) — Verint dform Request_description bracket bug

**Class of bug**: external municipal/SaaS form silently truncates a text field after a specific character pattern. Looks like a length cap; isn't.

### Symptom

- Filed ticket / record description ends abruptly at a specific punctuation mark, never with `...` or any explicit truncation marker
- Trailing content (user description, footer/signature, navigation links, address) is missing
- Open311 / API readback returns the truncated form
- Field crews / dispatchers complain "no map links", "no address", "where's the rest"
- Symptom appears AFTER you add structured prefixes/suffixes to a description that has user-typed content embedded
- Truncation point is content-dependent, NOT length-dependent (verified by length probe)

### Reference incident: Verint Request_description bracket truncation (improvebayarea.com, 2026-05-11)

- Recategorize policy emitted `[Originally categorized as: X]\n[Auto-routed via DPW-BSES catch-all...]\n\n${user_description}` and submitSf311Verint then appended `\n\n${navFooter(maps, address)}`
- Filed description (mobile311 Open311) was 272 chars, ending right after the SECOND `]` — both user description AND navFooter (Google/Apple/OSM links + address line) dropped
- Initial false hypothesis: ~272-char length cap on `Request_description`. WRONG.
- Empirical length probe (admin-mode submits with descriptions of 100/300/500/1000/2000 chars, NO brackets) stored 481/681/881/1381/2381 chars — full text + navFooter intact in every case. No length cap.
- Empirical bracket probe (admin-mode submits with `[X]\n[Y]\n\nUser text` vs `X\nY\n\nUser text` vs `text [TAG:a] more [TAG:b] more`):
  - Brackets at front → stored 79 chars, ends at second `]`, user text + navFooter dropped
  - No brackets → stored 476 chars, full text + navFooter
  - Inline brackets → stored 87 chars, ends at second `]`, dropped
- Conclusion: Verint's input sanitizer treats the SECOND `]` as end-of-input. Newline `]\n[` is rendered as `]  : [` in the stored text (Verint's separator handling).

### Quick Detection

```bash
# After any change that adds prefixes/suffixes to a description field that flows into an external form:
# 1. Submit one ticket with cache-busted unique content
# 2. Read it back via the upstream's read API (wait for propagation if needed)
# 3. Count chars and check whether the trailing content survived
TS=$(date +%s)
curl -sX POST "<your endpoint>" -d "<body with cb-${TS} marker>"
sleep 60
curl -s "<upstream read api>/<id>" | jq -r '.description | length, .description'

# If filed length < expected, do a content probe:
#   - Same length, no special chars → does it survive?
#   - Same length, with brackets → does it truncate?
#   - Other special chars to try one at a time: `{ } < > | $ % & ;`
```

### Fix Pattern

1. **Sanitize at the boundary**: replace the offending character(s) with safe equivalents in ALL inputs that flow into the description field. Defense in depth — don't just clean the new code path; clean the helper that constructs the final body so future paths are safe too.

   ```ts
   // Replace `[`/`]` with `(`/`)` in any user-supplied or AI-generated text
   export function sanitizeForVerint(text: string | undefined | null): string {
     if (!text) return "";
     return text.replace(/\[/g, "(").replace(/\]/g, ")");
   }
   ```

2. **Order content for survivability**: put the most important content FIRST (user description + navFooter / map links / address). Even if a future upstream quirk truncates the bottom, you lose meta/policy notes — not the field crew's location info or the user's report.

3. **Comment block at the construction site** documenting the empirical evidence (probe ticket IDs, date, what triggered) so future edits don't reintroduce the bug.

4. **Unit test** asserting the constructed description contains no `[` / `]` characters (or whatever character was problematic).

### Anti-patterns (do NOT)

- ❌ Add a character-class blacklist guess without empirical confirmation. Probe the upstream first.
- ❌ Assume "all special characters truncate" — the bug is character-specific. `()` works fine, `[]` doesn't.
- ❌ Trust unit tests on the input prompt/template strings — they verify what you wrote, not what the upstream stored. ALWAYS read back via the upstream's API after deploy with cache-busting.
- ❌ Skip the empirical length probe. The first hypothesis was "length cap"; that was wrong. Don't propose a fix until you've ruled out competing hypotheses with real data.

### Related patterns
- `feedback_verify_with_actual_frontend_body_shape.md` (memory): closed-loop curl must mirror the EXACT frontend body — synthesized curls with cleaner descriptions wouldn't have caught this
- `feedback_post_fix_curl_must_cache_bust.md` (memory): cache-bust the post-fix curl or you'll read stale cached responses
- `~/.claude/skills/shared/upstream-protocol-investigation.md`: when a third-party integration silently drops content, read the upstream's actual sanitizer logic — never trust a "should work" assumption

---

## Pattern 21: Verint structured-location dropped by long-form sf_full_address (2026-05-14)

**Symptom:** SF311 ticket filed via our worker shows in the mobile311 viewer with the description body present (including the navFooter's "Address: …" line) but the dedicated **Location** `<dt>/<dd>` block is completely missing. Open311 readback (`mobile311.sfgov.org/open311/v2/requests/<id>.json`) returns `address: null`, no `lat`, no `long` — even hours after filing, well past the documented backfill window. Other tickets we file at the same form (Street and Sidewalk Cleaning catch-all) show the address fine.

**Triggers:**
- Address surfaces in the description body but not the structured Location field
- Open311 `address`/`lat`/`long` are null for tickets we filed
- "One ticket has location, another doesn't" — same category, same form
- A change touched `src/sf311.ts` → `sf311Data()` → `sf_full_address` or `Location_description`
- `input.address` carries the full "<num> <street>, <city>, <state>, <zip>" form

**Root cause:** Verint's Open311 pipeline silently drops the structured `address`/`lat`/`long` fields when `sf_full_address` carries a comma-delimited long form. EAS enrichment (`sf_cnn`, `sf_address_number`, `sf_primary_street_name`, `sf_zip_code`) populates correctly — but Verint's downstream mapper appears to read from `sf_full_address` and refuses to surface anything when it contains city/state/zip. The public SF.gov Verint web form's property-search widget always emits street-only strings, so this code path is exercised differently on the production form.

**Reference evidence (2026-05-14):**
```
101004039744 — input.address = "212 Utah St" (street only)
  → Open311 surfaces address = "212 Utah St", lat, long ✅

101004053642 — input.address = "118 King St, San Francisco, CA, 94107"
  → Open311 returns address = null, no lat, no long (5+ hours after filing) ❌
```

Both tickets ended up on the same DPW-BSES catch-all form (`pw_street_sidewalkdefect`). Coords for both have valid EAS rows with `cnn` set. The only delta was the shape of `input.address`.

**Fix:** Send the **street-only chunk** (first non-empty comma-separated segment) to `sf_full_address` and `Location_description`. Keep the FULL address inside `Request_description` via the navFooter so dispatch crew still see city/state/zip for context. See `streetOnlyAddress()` in `src/sf311.ts` and `streetOnlyAddress (Hayes-King structured-location fix, 2026-05-14)` test block in `src/sf311.test.ts`.

**⚠️ DEEPER root cause found 2026-08-12 — the field content was never the whole story.** Even with a fully-populated, correctly-formatted structured-location bundle (EAS enrichment OR the city's own reverse-geocode fields), Verint STILL surfaced `address`/`lat`/`long` NULL in Open311 for hours. The missing step is a session-level PROPERTY BIND that SF.gov's own form makes and the field-merge skipped:
1. `POST /api/custom?action=sfpw-reverse-geocode` → authoritative bundle incl. `VerintObjectReferenceID` (form-agnostic — works for pw_/mta_/puc_/rpd_/cs_).
2. `POST /api/setobjectid?objecttype=property&objectid=<VerintObjectReferenceID>&loaddata=true` on the SAME session — **this is what makes the location stick.** Without it the backend treats the `sf_*` fields as unvalidated citizen input and drops them; with it, ticket `101004608311` populated in Open311 in 2 min vs 4 field-merge-only controls null at 23-123 min. Implemented in `reverseGeocodeVerint()` (`src/sf311.ts`); exclude routing fields (`sf_jurisdiction`/`le_queue`) — `applyRoutingContext()` owns those. Monitored via `revgeo:{ok,bind_fail,miss}` KV counters + `/api/admin/revgeo-health` + a 30-min Telegram alert on `down` (see [[negative-control-gate]] Corollary D and `reference_sf311_verint_direct_api.md`). Lesson: when a structured-location merge is byte-perfect but the upstream still drops it, the upstream is doing a BIND/validation step your merge skipped — read its own client's full call sequence, don't just match the save payload.

**Closed-loop verification protocol:**
1. File a test ticket with a **long-form** `input.address` (with city/state/zip).
2. Wait ~10 seconds, then GET `https://mobile311.sfgov.org/open311/v2/requests/<id>.json`.
3. Assert response carries `address`, `lat`, `long` — NOT just an unstructured `description` field.
4. Open the public viewer (`https://mobile311.sfgov.org/tickets/<id>`) and confirm the `<dt>Location</dt>` block renders.

**Prevention rule (now enforced via /ship Phase 1.45b):** Any change to fields sent to **ANY** 311 backend's structured-location slots — Verint (`sf_full_address`, `Location_description`, `sf_address_number`, `sf_primary_street_name`, `sf_zip_code`, `sf_city`, `sf_state_code`), SeeClickFix (`address`, `location_details[*]`), Open311 generic (`address_string`, `address_id`) — **must ship with a regression test that proves the long-form input (`"NNN Street St, City, ST, NNNNN"`) still surfaces the structured location in the backend's readback**. Synthesized "short address" tests do not catch this — the bug only manifests on long forms.

**2026-05-14 follow-up hardening (this is production-critical, never break):**

The original Pattern #21 fix added `streetOnlyAddress()` to normalize Verint inputs. The user then asked for cross-backend hardening:

1. **Coord-fallback class:** `src/index.ts:2921` historically defaulted `body.address` to `\`${lat.toFixed(5)}, ${lng.toFixed(5)}\`` when the frontend didn't send an address. The comma-separated coord string would survive `streetOnlyAddress()` as just `"37.77"` — visible garbage on the dispatch crew's structured-address field. Replaced with empty-string fallback so EAS / ArcGIS enrichment fills the structured slots.

2. **`looksLikeCoordinateString()`** helper added to `src/sf311.ts` — matches `/^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$/`. Used as a guard in both `streetOnlyAddress()` and `fillStructuredAddressFromString()` so coord strings can never propagate into Verint's `sf_full_address` / `sf_address_number` / `sf_primary_street_name`.

3. **SeeClickFix backend** (`src/seeclickfix.ts`): when both ArcGIS reverse-geocode AND `input.address` are empty (rare — frontend should always send something), falls back to a coord string ONLY at the SCF `address` form field. SCF accepts coord strings without silently dropping the rest of the submission (unlike Verint). This is documented inline.

4. **`navFooter()`** in `src/maps.ts` already handles empty `address` cleanly: it just omits the `Address: …` line. So an empty `input.address` still gets Google/Apple/OSM links into the description body.

**Backend-by-backend safe slots for empty-address input:**

| Backend | Empty-address strategy | Where structured location comes from |
|---|---|---|
| SF311/Verint | Empty `sf_full_address` + `Location_description` | `enrichSf311DataWithEas()` + `setobjectid` property bind |
| SeeClickFix | Esri `long_label` → user `input.address` → coord string (last resort) | `reverseGeocodeForScf()` populates `location_details[*]` |
| MyLA311 (Salesforce) | Never lat/lng-only. Full street+city+zip on **sObjCase** | `LA_AddressController.validateAddress` → `addressDetails`. Pattern 36. |

### Related patterns
- Pattern 19 (Verint dform Request_description bracket truncation): same class — Verint sanitizers silently drop content based on character shape.
- Pattern 36 (Experience Cloud catalog-and-submit): same class, different backend — address on the wrong object + skipped GIS bind; also listed≠fileable / unwrap / remint.
- `feedback_verify_with_actual_frontend_body_shape.md`: closed-loop curl must mirror the actual frontend body, not a "cleaner" synthesized one.
- `~/.claude/skills/shared/upstream-protocol-investigation.md`: when third-party output disagrees with input, read the upstream's actual mapper — don't trust "verified YYYY-MM-DD" comments alone.

---

## Pattern 22: SF311 Verint async-caseid is server-config, not client-fixable (2026-05-14)

**Symptom:** Some SF311 ticket submissions through our worker return a UUID `ref` (e.g. `kdf-c2b25843-7715-4ec7-a266-89...`) instead of a numeric 101004… caseid. The user sees a "tracking ref" + handoff to SF.gov instead of a clean filed-case confirmation. The reference ticket `https://mobile311.sfgov.org/tickets/101004046487` got a clean caseid; sibling submissions from the same submitter at SFMTA categories don't.

**Forms affected (Verint async by SF IT design):** `pw_graffiti`, `pw_street_sidewalkdefect`, `pw_damaged_property`, `pw_litter_receptacles`, `pw_tree_maintenance`, `mta_signs`, `cs_block_street_sidewalk`. User-mode submits at the 5 DPW forms now auto-recategorize to BSES catch-all (`pw_street_cleaning`, sync) and get instant caseid; the 2 SFMTA forms (`mta_signs`, `cs_block_street_sidewalk`) can't recategorize (BSES doesn't cross-agency-route to SFMTA per codebase comment at `sf311.ts:103-105`) so they keep returning ref.

**Investigation (re-verification 2026-05-14):**
- Pulled fresh `https://sanfrancisco.form.us.empro.verintcloudservices.com/dformresources/scripts/api.js` (195KB, 5472 lines). Lines 460–540 confirm the public form's save sequence:
  1. POST `/api/save` with `complete: 'Y'`
  2. On `valid:true`: trigger `_KDF_complete`, run `data-completeaction` custom action (with `actionedby=complete_action`)
  3. Always: run `data-saveaction` custom action (with `actionedby=save_action`)
- Probed `/api/content/{form}` for `pw_street_cleaning` (sync baseline) + `mta_signs`, `pw_graffiti`, `pw_tree_maintenance`, `cs_block_street_sidewalk` (async). **ALL FIVE forms declare identical `data-completeaction="update-citizen-interaction"` and `data-saveaction="update-case"`.**
- Only valid `complete:` values in dform are `'Y'` and `'N'`. No hidden "force-sync" flag.
- Open311 lat/long query params are advertised but ignored — empirically the endpoint returns 50 unfiltered results regardless of coord.

**Conclusion:** there is **no missing client-side action**. Our worker already calls everything the public SF.gov form calls. Async behavior is enforced server-side by Verint based on per-form SF IT configuration. The 2026-05-09 read was correct; the "blind spot" hypothesis (that we might be missing an API call) is empirically disproved.

**Therefore the only correct fix is to OBSERVE what SF311's backend does:** the public 10-digit caseid is assigned async by SF311 within ~30s–5min. We poll Open311's `/open311/v2/requests.json` for the just-filed ticket (filtering by ts window + service_name + lat/lng proximity client-side since the lat/long query params are broken) and reflect the caseid back via a `/api/lookup-caseid?ref=<UUID>` endpoint that the frontend polls.

**Implementation:** `src/sf311_caseid_resolver.ts` (`kickOffCaseidResolution()` runs as `ctx.waitUntil()` background task, polls for up to 5min at 30s intervals; results stored in KV `sf311:ref-caseid:<UUID>` with 7-day TTL). `/api/submit` returns `lookup_caseid_url` when `caseid_pending:true`; `/api/lookup-caseid?ref=<UUID>` returns 202 pending or 200 with the resolved caseid. Tests in `src/sf311_caseid_resolver.test.ts` cover the match + proximity-reject + service-name-loose-match paths.

**Don't reopen this without new evidence.** The investigation cost ~1h of token budget; the answer is "Verint backend per-form config decides sync vs async". Any future "let's try this API call" should start by re-reading this pattern + the codebase comment at `sf311.ts:1680-1700`.

---

## Pattern 23: Third-party signal-extractor false-negatives because tests used synthetic fixtures (2026-05-27)

**Symptom (verbatim from logs / user reports):**
- "every IBA-submitted DBI complaint shows up as `validation` error" — but the city actually recorded them all
- "form was rejected but I see it on DataSF" / "filed via API failed but appeared at the agency"
- "`{ok: false, error: 'validation', message: 'DBI re-rendered the form'}`" — but no validation actually fired
- Tests pass (often a "returns ok=true on parsable success page" test using a hand-written fragment) while production is 100% broken
- The deployed code's success-detection heuristic uses an HTML feature that's present in **both** success and failure responses (`Sub_Button0`, `CheckBox1`, generic form-layout strings)

**Class of bug:** signal-extraction-from-third-party-response. The detector was written and tested without ever seeing a **real** captured success response from the live system; the test fixture was imagined ("Thank you. Your complaint number is 202512345.") while the real success response is 46KB and shares all "form layout" strings with the failure response.

**Reference incident (2026-05-27):**
- `src/sfdbi.ts` `dbiSubmitComplaint`: `looksLikeEchoedForm = html.includes("Sub_Button0") && html.includes("CheckBox1")` matched every success page too.
- DBI never returns a 9-digit complaint number on the response page — only DataSF gm2e-bten exposes it 1-3 days later. So `parseComplaintNumber()` returning `undefined` was normal; the detector treated it as failure.
- The only feature that distinguishes the two pages: `<span id="InfoReq1_lblError" class="style12">Your complaint has been recorded. Thank you.</span>` (success) vs empty `lblError` or `"Please select 4 checkboxes only"` (failure).
- Existing test `src/sfdbi.test.ts` had a `SUCCESS_HTML = "<html><body><h1>Thank you</h1>..."` synthetic fixture. The test passed because the synthetic HTML didn't contain `Sub_Button0`, so `looksLikeEchoedForm` was false — but the real DBI success page DOES contain `Sub_Button0`. **Synthetic fixtures masked the bug for ~10 days.**

**Fix (the same fix that should have shipped originally):**

1. Write a **live-traffic probe** under `tools/repro/` that exercises the third-party once and saves both responses:
   ```
   tools/repro/<integration>-probe.mjs  # runs steps 1..N, dumps step-N responses for success + failure
   src/__fixtures__/<integration>/<endpoint>-success.html
   src/__fixtures__/<integration>/<endpoint>-failure.html
   ```
   Check both fixture files in. Re-run the probe whenever you suspect drift.

2. **Diff the two fixtures** to find a feature that's present in exactly one. Anchor on a stable DOM id / JSON field, NOT on generic substring matching:
   ```ts
   // Wrong: matches success AND failure
   const failed = html.includes("Sub_Button0") && html.includes("CheckBox1");
   // Right: anchor on the id, extract dynamic text, classify
   const lblErrorText = parseLblErrorContent(html); // /<span[^>]*id="InfoReq1_lblError"[^>]*>([\s\S]*?)<\/span>/
   const ok = lblErrorText && /has been recorded|thank you/i.test(lblErrorText);
   ```

3. **Tests must use the captured fixtures**, not synthetic HTML. Add at least:
   - `it("detects ok=true on the real success fixture")` — reads `src/__fixtures__/<integration>/...-success.html`
   - `it("detects ok=false on the real failure fixture")` — reads `...-failure.html`
   - A self-contained no-fixture regression that hardcodes the minimum HTML demonstrating the anti-pattern (so the regression intent survives even if fixtures get deleted).

4. **Pass the upstream's actual reason through to the caller** on failure:
   ```ts
   return {
     ok: false,
     error: "validation",
     message: lblErrorText
       ? `DBI rejected the submission: ${lblErrorText.slice(0, 200)}`
       : "DBI re-rendered the form (validation rejected the submission)",
   };
   ```
   The caller can render this to the user instead of a generic "form rejected" message.

**How to catch this in code review or `/ship`:**

```bash
# Find third-party-response parsers
grep -rn "response\.text().*includes\|html\.match\|html\.includes" src/ | grep -v node_modules | grep -v __fixtures__

# Find detector helpers without companion fixtures
grep -rln "export function parse\|export function detect\|export function extract" src/ | while read f; do
  base=$(basename "$f" .ts)
  test_file="${f%.ts}.test.ts"
  fixtures_dir="src/__fixtures__/${base%.*}"
  if [ -f "$test_file" ] && [ ! -d "$fixtures_dir" ] && grep -q "third-party\|external API\|webform\|verint\|dform\|asp\.net\|aspx" "$f"; then
    echo "WARNING: $f looks like a third-party parser but has no $fixtures_dir/"
  fi
done

# Find tests that only assert ok=true and never load a real fixture
grep -B5 'expect(.*ok).toBe(true)' src/**/*.test.ts | grep -v 'readFileSync\|loadFixture\|__fixtures__'
```

If any match in a diff that touches third-party-response parsing: **BLOCK** until real fixtures are captured.

**Don't conflate this with:**
- **Pattern 1 (catch-all masking root cause)** — that's about hiding the real error in a wrapper; this is about misclassifying the response shape entirely.
- **Pattern 15 (external form hard-500)** — that's about the third party returning 5xx for one specific input shape; this is about misreading a 200 response.
- **Pattern 19 (Verint bracket truncation)** — that's content the third party silently mutates; this is signal we incorrectly extract.

**Related:**
- `~/.claude/skills/shared/third-party-signal-fixtures.md` — the generalized rule, fixture layout, audit greps.
- `~/.claude/skills/shared/upstream-protocol-investigation.md` — the broader "read upstream's actual client / capture real traffic" doctrine. This pattern is a specialization: same doctrine applied to **response parsing**, not just **request shaping**.
- `/feedback_dig_deep_on_site_fixes` (MEMORY.md) — token cost is irrelevant for ground-truth verification.

---

## Pattern 36: Experience Cloud catalog-and-submit envelope (MyLA311, 2026-08-15)

**Class:** Salesforce Experience Cloud / Aura ApexAction civic portals — and any sibling whose "catalog" is a list of labels, whose IDs remint per session, and whose SUCCESS envelopes nest the real payload. The day-long Improve LA pass was this class, not a locator-only bug. `/code` builds against it; `/debug` diagnoses it; `/ship` refuses to deploy a catalog that faked it.

### A. Locator bind — address on the wrapper, not the Case

**Symptom:** A just-filed MyLA311 case (`C-NNNNNNNN`) is live (submit returned `isSuccess` + `sCaseNumber`) but:

- **My Requests** search for that number returns nothing
- **All Service Requests** finds it only with Status=New; `caseAddress` is `", , CA."` and `caseStreetAddress` is null
- Socrata 2026 (`data.lacity.org/resource/2cy6-i7zn.json?casenumber=NNNNNNNN`, **no `C-` prefix**) has lat/lng and no `locator_gis_returned_address`
- Status stays `New` while sibling graffiti cases from the official client go `Workorder Created` the same minute
- Searching `C-04342632` on the **2025** dataset (`h73f-gn57`) returns [] — that dataset ends 2025-11

**Root cause (decompiled `c/laCaseCreationFlow.submitRequest` + `c/laRiDetails` + live case C-04342632):**

The official client writes location in THREE places. We only filled the form wrapper:

1. `sObjCase.Street_Address__c` / `City__c` / `State__c` / `Zipcode__c` / `Google_Address__c` (from map + locator `ShortLabel`/`City`/`Postal`)
2. `addressDetails = JSON.stringify(locatorResponse.locatorDetails)` — the GIS bind from `LA_AddressController.validateAddress({latitude, longitude, addressType:"City Boundary"})`
3. `sCaseQuestionJSON.caseLocation` — form-only, **not** what dispatch/Socrata read

A lat/lng-only `sObjCase` inserts successfully. Salesforce then renders `caseAddress: ", , CA."`. Empty contact (`bIsLogin:false`) also keeps the case out of **My Requests** (`?q=true`).

**Lookup contract (view-service-request):**
`POST /s/sfsites/aura` → `X11_ViewServiceRequestsController.getSearchRequests` with `userSearch` JSON `{isViewAllRequest, startDate, endDate, requestStatus, requestType, requestId, councilDistrict, neighbourhoodCouncilName, isFollowRequest}`. `requestId` accepts `C-04342632`. Default **My Requests** view is `isViewAllRequest:false`. Cookie-jar replay without the live Aura CSRF → `invalid_csrf`; capture the POST from the real tab (`fhar rec`).

**Fix (improve-la `src/la311.ts`):**
- `parseFullAddress` + `buildSObjCase` put street/city/zip on the Case sObject
- `buildCreateCaseEnvelope` emits the official named params (`sObjCase`, `sObjContact`, `sCaseQuestionJSON`, `sFileLinks`, `isSNC`, `addressDetails`)
- live `submitCase` throws `MissingAddressError` if street/zip are empty
- dry-run warns when `locatorDetails` is missing

**Closed-loop check:** after any MyLA311 submit, GET `https://data.lacity.org/resource/2cy6-i7zn.json?casenumber=<unprefixed>` and assert `locator_gis_returned_address` is non-empty. A submit `isSuccess` with blank locator is **not** a complete filing.

**Don't:** search only `h73f-gn57` and conclude "not in Socrata"; search only My Requests and conclude "case doesn't exist"; put the address solely on `caseLocation`.

### B. Design the catalog against official models — do not spend a day rediscovering this

These rules are why the first "file every listed type" pass took a full day. Load this section **before** writing catalog JSON or a submit envelope.

1. **Listed ≠ fileable.** A portal directory of labels is not the submit contract. Guest-resolve every label. Persist no-rows as no-rows. Open-data rollups (Socrata groups) are not Case Types. MyLA311: 92 listed, 77 guest ids, 15 no-rows, 7 Socrata rollups — 30 pin-only fileable from official defaults + locator.

2. **SUCCESS envelope ≠ captured model.** `fetchCaseTypeDetails` `{isSuccess:true}` with empty `sId` / `sCaseType` / `lstCaseQuestion` is a **captureFailure**. Persist that flag. Never invent dummy `modelFlags` so tests pass. Structural test: every id-bearing type has `caseConfigId` (`a3S*`) + `sCaseType` **or** an explicit `captureFailure`. 13 of 77 MyLA types returned empty SUCCESS wrappers.

3. **Unwrap before you send.** Official clients nest the payload. Sending the toast/wrapper NPEs Apex and looks like "the city rejected this type":
   - `validateAddress` returns `{toastPayload, isSuccess, response}`. `addressDetails` is `JSON.stringify(response)` (`{address, location}` / `locatorDetails`) — **never** `toastPayload`.
   - `fetchCaseTypeDetails` returns `{scaseTypeLst, objCaseConfigWrapper}`. Questions live on the wrapper. A top-level `lstCaseQuestion` lookup is empty on a live SUCCESS.

4. **Session-encrypted IDs remint.** `getCaseTypeIdPortalUsr` mints IssueTypeIds per session. Never invent them. Never treat a persisted id as durable. Remint at submit. Guest mint = `fwuid` from `/s/` + `aura.token=null`. Logged-in cookie jar + `token=null` → `invalid_csrf`.

5. **Classify on field API names, not question text.** Use `sFieldtoUpdate`, `sDisplayMap`, `sBoundary`, `isSNC`, `SRFlow`. Question text mentioning "Permit Number" as an example is not a permit type (Taxi `Vehicle_ID` misclassified this way). Permit/asset refuse names `Permit_Number__c` / `Receptacle_ID__c`, even when `lstValidations.required` is false.

6. **Named refuse from official fields.** File only types whose official required answers are filled by defaults + locator. Otherwise refuse **naming the official field** (`Permit_Number__c`, `Type_of_DeadAnimal__c`, `Receptacle_ID__c`). Never a generic "extra step" stub. Check `captureFailure` first.

7. **Apex NPE ≠ city rejection.** Unknown Apex param names arrive as null and NPE. That is our envelope. Decompile `c/laCaseCreationFlow.submitRequest`; do not guess param names.

8. **Experience-shell apps.** Official Android/iOS MyCommunity EXPERIENCE shells (`facade.textproto` `servers.url` = the site) have no native submit API. Decompile the site LWC, not jadx smali. `/decompile` routes there.

9. **KV/catalog version.** A schema change (ids, models, `captureFailure`) that does not bump the cache key keeps serving the CSRF-era snapshot. MyLA311: `la311:catalog:v4`.

10. **Proof budget.** One representative live file **twice** of a pin-only type (Street Sweeping `C-04343038/039`, graffiti `C-04343078/079`). Not 77 tickets. Then `/ship` + cache-busted `GET /api/categories` matching the structural counts (ids / captured / captureFailure / dummy=0 / CSRF=0 / submittable). `/code` does not `wrangler deploy`.

**Design-time order (so the next build does not relearn this):**
1. Confirm Experience-shell (`facade.textproto`) → decompile site LWC.
2. Persist official `fetchCaseTypeDetails` for every listed type (`captureFailure` on empty SUCCESS).
3. Classify from form-model flags; file pin-only + required-filled; refuse by official field name.
4. Structural tests: toast fixture unwraps to locator keys; every id is real-model **or** `captureFailure`; refuse strings contain the field API name.
5. Two live files of one type. Then `/ship`.

**Don't:** treat a listed catalog as fileable; persist dummy flags; send `toastPayload` as `addressDetails`; invent IssueTypeIds; classify from question labels; refuse with a class stub; treat Apex NPE as the city saying no; file 77 tickets to "prove" the catalog; deploy the Worker from `/code`.

**Local tools (installed 2026-08-14):**
- `gron` — flatten a captured Aura/validateAddress JSON and grep the path. `toastPayload` present + `response.address` missing = you sent the toast wrapper.
- `hurl --test` — replay a captured Aura POST and assert jsonpath (`$.isSuccess`, `$.sCaseNumber`, locator keys). Prefer this over a one-off curl for 1.45g structural tests.
- `fhar distill` then `hurl` — capture once, assert forever. Never commit the raw HAR.
