---
name: docuseal-cli
description: Use `dscli` for ALL DocuSeal work — uploading templates, placing fields, creating submissions, sharing signing URLs. The CLI bakes in workarounds for DocuSeal's quirks (silent page-drop on /templates/pdf, submission field-state caching at create time, immediate-email-on-create traps, default_value bleed). Triggers on "docuseal", "dscli", "send a signature request", "create a signing form", anything involving DocuSeal templates or submissions.
---

# DocuSeal CLI (`dscli`)

`dscli` is the agent-friendly DocuSeal client. Located at
`$HOME/tools/docuseal/dscli`, symlinked to `~/.local/bin/dscli`.

API key at `~/.config/docuseal/api-key.txt` (or `DOCUSEAL_API_KEY` env).

## DO NOT bypass dscli with raw curl/HTTP unless `dscli` lacks the operation
you need. The CLI exists because every raw-call path has at least one trap
that ate hours on 2026-05-06. Specifically:

1. **`POST /templates/pdf` silently drops field `area.page`.** Every field
   you upload with `page=N` ends up at `page=0` regardless. `dscli template
   upload` therefore creates the template *without* fields; use
   `dscli template set-fields` to attach fields via PUT, which DOES respect
   `page` (because the CLI also passes `attachment_uuid` per area).

2. **Submissions cache the template's field layout at create time.** Editing
   a template after a submission exists DOES NOT update the in-flight
   submission's signing UI. Always `dscli submission archive` and recreate
   after changing template fields.

3. **`POST /submissions` with `send_email=true` sends emails IMMEDIATELY.**
   Archiving the submission afterwards does not recall the email — the
   recipient's inbox now has a link that 404s with "This submission has
   been deleted." `dscli submission create` defaults `send_email=false`;
   you opt in only after verifying field placement via `dscli pdf preview`
   or `dscli url screenshot`.

4. **`default_value` on a text field renders as static text on the PDF
   underlay.** It can visually bleed near adjacent fields and confuse
   signers. Avoid unless really needed; pass user-provided values via the
   submitter's `values` map at submission create instead.

5. **Match signature field rects to the PDF's signature-line widget rects.**
   DocuSeal renders an icon-sized "click to sign" indicator at the field
   position; making the rect huge just covers nearby printed labels and
   makes the user think the box is doing something it isn't. Use
   `dscli pdf widgets` to extract the form's actual widget rects.

6. **`page` in fields.json is 0-INDEXED — this is the #1 cause of "signature
   placed on the wrong page / didn't render."** (2026-06-24, root cause found
   by reading `dscli` line 291 + `cmd_template_set_fields`.) A multi-page
   records request put its two signature fields on `"page": 2` and `"page": 4`
   (thinking 1-indexed = "the 2nd and 4th printed pages"). The PDF had 4 pages
   = valid 0-indexed pages **0,1,2,3**. So `page:2` landed on the 3rd printed
   page (wrong) and `page:4` **does not exist** → DocuSeal silently dropped/
   mis-placed it; the signer "completed" the form but the signature never
   rendered on the visible signature line. THE FIX: if the signature line is on
   the Nth printed page, use `"page": N-1`. Locate it programmatically:
   `for i,page in enumerate(fitz.open(pdf)): page.search_for("Signature:")` —
   the `i` it prints IS the value to put in `"page"`.
   **ALWAYS pass `--pdf <file>` to `set-fields`** — with `--pdf`, dscli calls
   `pdf_page_size(pdf, page)` which raises `IndexError: page N not in document`
   on an out-of-range index, turning this silent bug into a loud error. Without
   `--pdf` it falls back to 612×792 and places the field on a phantom page.
   (Treat any `IndexError: page N not in document` from set-fields as "your
   page number is too high by one" — do NOT work around it by dropping `--pdf`.)

   Secondary: keep signature rects ≥ 40pt tall and ≥ 250pt wide on a clearly-
   labeled "Signature:" block (a too-short rect can clip the rendered image),
   but the page index is the thing that bit hardest here.

7. **ALWAYS verify the SIGNED PDF, not just `status: completed`.** A
   submission can report `completed` with every field value populated
   server-side while one or more signatures fail to render on the page.
   After any signer finishes, download the signed document
   (`dscli --json submission get <SID>` → `.documents[].url` → curl it)
   and rasterize EVERY signature page (`fitz` → `get_pixmap` → Read the
   PNG) to confirm each signature + date is actually visible at its
   field. `status: completed` is NOT proof the signatures rendered — the
   pixels are. Especially critical for multi-page / multi-signature docs.

8. **Unembedded fonts silently destroy the document downstream — `template upload`
   now BLOCKS on them** (added 2026-07-24). A PDF whose fonts aren't embedded is
   accepted by DocuSeal and looks fine on screen, then fails at the mail vendor:
   **Lob** — now the ONLY mail vendor (PostGrid removed 2026-08-12) — rejects it
   outright with `HTTP 422 unembedded_fonts`, so an unembedded font is a HARD STOP
   on the send, not a cosmetic warning. (The historical alternative was worse and
   is why this gate exists: PostGrid accepted the same file silently and
   *rasterized* it — a 4 MB upload became a **137 MB** print artifact that stalled
   at `status: printing` for 81 days with `errorMessage: null`.)
   `dscli template upload` runs `pdffonts` first and refuses to upload, printing the
   exact remedy. Use `--embed-fonts` to auto-fix via ghostscript (also shrank a real
   87-page packet 4.0 MB → 2.8 MB), or `--allow-unembedded` to override.
   **Also re-embed AFTER signing** — DocuSeal re-renders its own output, so the
   signed PDF must be checked again before it goes to any print/mail vendor:
   `pdffonts signed.pdf | awk 'NR>2 && $(NF-3)=="no"'` must be empty.
   Reference incident: Sanders ABCMR filing, 63 unembedded fonts across 125 total.

## Commands at a glance

```
dscli --help                                      # full reference
dscli [--json] template upload <pdf> [--name X]   # upload, no fields yet
dscli [--json] template add-roles <id> "R1,R2"    # add submitter roles
dscli [--json] template set-fields <id> <json> [--pdf <pdf>]
                                                  # PUT fields (correct path)
dscli [--json] template get <id> [--fields-only]
dscli [--json] template list
dscli [--json] template delete <id> --force       # archives subs first
dscli [--json] template archive-subs <id>

dscli [--json] submission create <tid> <json>
       [--send-email] [--order preserved] [--subject X --body Y]
dscli [--json] submission get <id>
dscli [--json] submission list [--template-id N]
dscli [--json] submission archive <id>
dscli [--json] submission urls <id>               # role | name | status | URL

dscli [--json] pdf widgets <pdf>                  # PDF AcroForm fields
dscli [--json] pdf prefill <pdf> <out> <values.json> [--checkboxes-json '...']
dscli [--json] pdf preview <pdf> --out preview.pdf --template-id <id>
                                                  # Overlay rects on PDF
                                                  # for visual verification

dscli [--json] url check <url>                    # live? archived? title
dscli [--json] url screenshot <url> [--out X --full]   # via agent-browser
```

`--json` is a GLOBAL flag (must come before the subcommand).

## Standard end-to-end flow

```bash
# 1. Pre-fill any data fields on the source PDF (subject info, recipient,
#    reason text, checkboxes). Bake so DocuSeal sees a static document.
dscli pdf widgets form.pdf > /tmp/widgets.json   # discover field names
echo '{"FullName-FLD": "Jane Doe", ...}' > /tmp/values.json
dscli pdf prefill form.pdf /tmp/prefilled.pdf /tmp/values.json \
      --checkboxes-json '["Box1","Box2"]'

# 2. Upload the prefilled PDF as a template (no fields yet).
TID=$(dscli --json template upload /tmp/prefilled.pdf --name "Form X" \
        | jq -r .id)

# 3. Add the signing roles you need. Names become role IDs in submissions.
dscli template add-roles "$TID" "Witness 1,Subject,Witness 2"

# 4. Place signature/text/date/checkbox fields. fields.json schema:
#    [
#      {"name":"W1 Sig", "type":"signature", "role":"Witness 1",
#       "rect":[21,707,303,717], "page":1, "required":true},
#      {"name":"W1 Addr", "type":"text", "role":"Witness 1",
#       "rect":[21,735,303,771], "page":1, "required":true},
#      ...
#    ]
#    Rect is PDF points (top-left origin). Pass --pdf so exact page dims
#    are used (avoids assuming 612×792).
dscli template set-fields "$TID" fields.json --pdf /tmp/prefilled.pdf

# 5. VISUALLY VERIFY before sending. Render a preview with rects overlaid.
dscli pdf preview /tmp/prefilled.pdf --template-id "$TID" \
      --out /tmp/preview.pdf
# Open /tmp/preview.pdf in Preview.app; confirm rects sit where signers
# will actually need to sign / type.

# 6. Create the submission. send_email=false by default — you control how
#    URLs are shared.
cat > /tmp/submitters.json <<EOF
[
  {"role":"Witness 1","email":"a@x.com","name":"Alice"},
  {"role":"Subject",  "email":"b@x.com","name":"Bob"},
  {"role":"Witness 2","email":"c@x.com","name":"Carol"}
]
EOF
dscli --json submission create "$TID" /tmp/submitters.json \
      --order preserved > /tmp/sub.json
SID=$(jq -r .submission_id /tmp/sub.json)

# 7. Surface URLs to the user (or trigger DocuSeal email by recreating
#    with --send-email once you're confident).
dscli submission urls "$SID"

# 8. After signers complete: pull the signed PDF.
dscli --json submission get "$SID" | jq '.documents'
```

## CRITICAL: every field needs a `uuid` attribute

DocuSeal's signing frontend uses `<input name="values[<field.uuid>]">` to
collect each field's value. If a field has no `uuid` attribute, `field.uuid`
is JavaScript-undefined and the input becomes `name="values[undefined]"`.
ALL fields without a uuid then share the SAME form slot — typing in any
one of them overwrites the others. The "type a sig and the address
appears in both" bug is purely a manifestation of this.

`dscli template set-fields` auto-generates a UUIDv4 per field if you
don't supply one. Don't bypass it. If you ever PUT fields directly via
HTTP, include a unique `uuid` per field or expect cross-field overwrites.

Verified 2026-05-08 via chrome-cdp: with `uuid` per field, the live form's
hidden inputs are `values[<sig_uuid>]` and `values[<addr_uuid>]` — separate.
Without uuid, both collapse to `values[undefined]`.

## "Type text" signature mode contaminates next text field (frontend bug)

When a submitter clicks the signature field, picks **"Type text"** mode,
types their name (or any text), and clicks NEXT, DocuSeal does two things:

1. Stores the typed cursive as a signature image attachment (correct).
2. **Writes the image's attachment UUID into the local state of the
   next text field for that submitter** (BUG).

The text field then renders something like
`77866bd2-fe60-4c80-9533-e0f6ccff8e66` until the user manually clears it.
If the submitter has a cached prior value (e.g., they typed their address
into a sig field on an earlier attempt), the cached value renders instead.

The server-side `submitter.values` stays `[]` — this leak is purely
client-side. The REST API does NOT expose `with_typed_signature` at any
level; verified that template, submission, and submitter PUTs with every
plausible shape silently no-op. The rendered HTML always has
`data-with-typed-signature="true"`.

**Workarounds:**
- Tell submitters to use **"Sign on the touchscreen"** (Draw) or **Upload**,
  never "Type text".
- Make signature field rects ≥ 30pt tall. The PDF widget rect for a
  signature LINE is typically ~10pt; reusing that rect causes the typed
  cursive image to render at natural size and visually overflow into the
  field below, looking like a duplicated value even before the actual
  bug fires.

## Browser-side autofill trap (`data-reuse-signature`)

The signing page renders with `data-reuse-signature="true"` hardcoded by
DocuSeal's UI — not exposed via the public REST API. Once a user has typed
*anything* into a signature field on this account/browser before, DocuSeal
caches it in browser localStorage as their "preferred signature" and
auto-suggests it on every new submission, even on freshly-created
submissions with `default_value=""` on all fields. The cached string can
also bleed into adjacent text fields.

**This is NOT fixable via the API.** Verified: `POST /submissions
{reuse_signature: false}`, `PUT /templates/{id} {preferences: {...}}`, and
every other shape silently no-op. The rendered HTML still has
`data-reuse-signature="true"` regardless.

**Fixes are user-side:**

1. **Open the sign URL in incognito/private window** — no localStorage,
   no cached signature.
2. **Click the trash/clear icon in the signature modal** before signing.
3. **Use the "Draw" tab** in the signature modal instead of "Type".

When you hand a sign URL to a user who has previously typed anything into
a signature field on the same browser, **proactively recommend incognito
mode** so they don't get the auto-fill surprise.

## When something looks wrong on the signing page

Don't try to PUT-fix a live submission's layout — it won't update. Always:

1. `dscli url check <url>` — confirms whether it's live or archived.
2. `dscli url screenshot <url> --full --out /tmp/shot.png` — see what the
   signer sees.
3. Adjust template fields with `dscli template set-fields`.
4. Archive AND recreate the submission with `dscli submission archive`
   then `dscli submission create`. Critical: the OLD URL becomes a
   "deleted" page in the recipient's inbox — make sure you tell the user
   to use the NEW URL, not the old email.

## Three instances: CLOUD (default), SELF-HOSTED (`--self`), SEALWORKER (`--seal`)

| | cloud | self-hosted | sealworker |
|---|---|---|---|
| flag | *(default)* | `--self` (or `DOCUSEAL_SELF=1`) | `--seal` (or `SEAL_MODE=1` / `DOCUSEAL_SEAL=1`) |
| base | `https://api.docuseal.com` | `https://docuseal.example.com/api` | `SEALWORKER_API_BASE` env, else `~/.config/docuseal/seal-base.txt`, else `https://seal.example.com/api` |
| key | `~/.config/docuseal/api-key.txt` | `~/.config/docuseal/api-key-selfhosted.txt` | `DOCUSEAL_API_KEY` env or `~/.config/docuseal/api-key-sealworker.txt` |
| edition | Pro (SaaS) | **OSS** — some APIs are Pro-gated (below) | sealworker (Workers-native, `~/sealworker`) — implements the cloud API subset dscli uses, **including `POST /templates/pdf`** (the OSS Pro-gap and Rails-session workaround do NOT apply in seal mode) |
| edge | none | **Cloudflare Access** (email allowlist) | none on `/api/*` (Access is path-scoped to `/admin*` only; if `SEALWORKER_CF_COOKIE` is set, dscli sends it) |

```bash
dscli --json template list           # cloud
dscli --self --json template list    # self-hosted
dscli --seal --json template list    # sealworker
# local sealworker dev:
SEALWORKER_API_BASE=http://localhost:8787/api DOCUSEAL_API_KEY=testkey-sealworker-dev \
  dscli --seal --json template list
```

`--seal` needs no cookie plumbing; `template upload` works there (unlike
`--self`). Signing URLs printed by `submission create`/`submission urls`
PREFER the server-returned `embed_src` verbatim, falling back to deriving the
host from the active API base (`signing_url()`/`sign_origin()` in dscli) —
cloud still prints `https://docuseal.com/s/...` byte-identically, while
`--self`/`--seal` print their own hosts (this fixed two previously hardcoded
`docuseal.com/s/` builders; verified 2026-07-12: `--seal` against wrangler dev
prints `http://localhost:8787/s/<slug>`). Cloud->sealworker migration + PDF
archive: `~/tools/docuseal/migrate-cloud-to-seal.py` (`templates [--dry-run]`
and `archive`; cloud strictly read-only; field uuids preserved verbatim;
idempotent via `external_id "cloud:<id>"`; `--limit N` / `--only ids` for
test runs).

`--self` auto-attaches the CF Access `CF_Authorization` cookie by reading the
logged-in Chrome profile via `~/tools/cookies-txt`. If Access has expired, dscli
tells you to re-open the site in Chrome and finish the OTP. Two other traps it
already handles: CF's Browser Integrity Check **403s (error 1010)** the default
Python-urllib User-Agent (dscli now sends its own UA), and an expired Access
session comes back as a **302 to cloudflareaccess.com**, not a 401.

### Self-hosted is the OSS edition — creating a template from a PDF is Pro-only

Verified live 2026-07-12 against the running instance:

```
POST /api/templates/pdf   -> 404 {"message":"This feature is available in Pro Edition"}
POST /api/templates/html  -> 404   (same)
POST /api/templates/docx  -> 404   (same)
```

So `dscli --self template upload` **cannot work** — that command posts to
`/templates/pdf`. But `PUT /api/templates/{id}` IS in OSS and permits
`external_id`, `submitters[]`, and full `fields[]` (areas/pages/uuids,
conditions, options, validation). The working shape is therefore two-legged:

1. **create + attach the PDF** via the Rails web session
   (`POST /templates_upload`, multipart `files[]`) — exactly what a human does
   in the UI; and
2. **set roles + fields** via `PUT /api/templates/{id}` with the API token.

`~/tools/docuseal/migrate-cloud-to-self.py` implements this (it also signs into
the Rails session using the stored admin password) and is the reference for any
future "put this PDF on the self-hosted box" automation.

## Configuration

- API key (cloud): `~/.config/docuseal/api-key.txt`
- API key (self):  `~/.config/docuseal/api-key-selfhosted.txt`
- API key (seal):  `~/.config/docuseal/api-key-sealworker.txt`
- Base URL: `https://api.docuseal.com`; override with `DOCUSEAL_API_BASE`, or
  pass `--self` / `--seal` (seal base: `SEALWORKER_API_BASE` env, else
  `~/.config/docuseal/seal-base.txt`, else `https://seal.example.com/api`).
- Self-hosted admin password: `~/docuseal-worker/.secrets/DOCUSEAL_ADMIN_PASSWORD`
- PyMuPDF (`fitz`) required for `pdf` subcommands — installed system-wide.
- `agent-browser` required for `url screenshot`.

### Self-hosted upload silently failing? It's the R2 checksum trap.

If a document upload bounces to the dashboard with no error and the template
ends up with **zero documents**, the container is hitting
`Aws::S3::Errors::InvalidRequest: You can only specify one non-default checksum
at a time.` — aws-sdk-ruby's default flexible checksums (`x-amz-checksum-crc32`)
colliding with Active Storage's `Content-MD5` on R2. DocuSeal rescues the error
and redirects to root, so nothing surfaces in `wrangler tail` (`outcome: ok`).
Fix is `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` +
`AWS_RESPONSE_CHECKSUM_VALIDATION=when_required` in the Worker's container env
(`~/docuseal-worker/src/index.ts`). Full write-up: `~/docuseal-worker/DEPLOY.md`.

## Source

- CLI: `$HOME/tools/docuseal/dscli`
- Skill: `$HOME/.claude/skills/docuseal-cli/SKILL.md`
- API key: `~/.config/docuseal/api-key.txt`


## Ground-truth gate (MANDATORY)

Before this skill asserts a stakes-bearing fact or takes any outward/irreversible action, apply the global standard — verify against a **primary source fetched now**, never a cached/remembered value. Full standard: `~/.claude/skills/shared/ground-truth-standard.md`.

**Verify live before you act or assert (this skill):**
- Verify signer identity + the exact document before dispatch; explicit approval; capture the submission id.

Then: dry-run where possible, show the user exactly what will be sent/filed/asserted, get explicit chat approval for any outward action (per CLAUDE.md), capture the confirmation, and write any verified fact back into its source doc. State uncertainty as uncertainty; never assert plausible-but-unverified as fact.
