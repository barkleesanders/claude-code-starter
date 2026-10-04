#!/usr/bin/env bash
# favicon-check.sh — does this site serve a favicon a BROWSER will actually render?
#
# Born 2026-09-20: car.example.org shipped three times that day with a
# <link rel="icon" href="data:image/svg+xml;base64,…"> in every <head>, and every
# grep-shaped check (`rel="icon"` present? yes) passed — while the SVG inside the
# data URI was malformed XML (`viewBox="0 0 32 32"#>` plus a stray glyph), so
# Chrome/Safari silently drew the default tab icon. Presence is not rendering.
#
# The check DECODES what the tag points at and validates it the way a browser
# would, per icon:
#   data:image/svg+xml (base64 or percent-encoded)  → must parse as well-formed
#       XML whose root element is <svg>
#   data:image/png|jpeg|gif|x-icon|webp             → magic bytes must match
#   http(s) / relative URL                          → fetched: 2xx, image/* type,
#       and an SVG body must again be well-formed XML with an <svg> root
#
# Verdicts (three outcomes, never two — an unreachable page is not a clean one):
#   ok          ≥1 declared icon renders                            exit 0
#   bad         icons declared but none renders, or none declared   exit 1
#   unmeasured  page unreachable / not HTML / no <head> to inspect  exit 2
#
# Advisory by default, BLOCKING under --strict (or FAVICON_STRICT=1):
#   ico=<status>   GET /favicon.ico — Safari, bookmark bars, feed readers and most
#                  crawlers request this path regardless of the <link>; 404 = warn
#   touch=y|n      any <link rel="apple-touch-icon"> (iOS home-screen icon)
#
# --strict  (2026-09-20: 8 services had shipped for months with verdict=ok and
#            ico=404 because the warning never blocked anything — HOME-d75go)
#            ico must be a 2xx image AND an apple-touch-icon must be declared and
#            resolve, or the verdict is `bad`. /ship Phase 1.4b runs strict, and it
#            runs it PRE-deploy (--html <built head> <dist|public dir>, or a local
#            `wrangler dev` URL) so the miss is caught before upload, not after.
#            `~/tools/favicon-pack <svg> <public/>` emits both files in one call.
#
# Usage:
#   favicon-check.sh [--strict] <url>      one page (follows same-host redirects)
#   favicon-check.sh --list <file>         file of URLs (or "name url" lines)
#   favicon-check.sh --html <file> [base]  validate a saved/rendered HTML file. base =
#                                          https origin (icons fetched live; for auth-gated
#                                          pages captured via fcdp) or a build dir / omitted
#                                          (icons resolved on disk next to the file — the
#                                          PRE-DEPLOY check on dist/ or public/)
# Output: one line per page —
#   favicon-check: <url> verdict=<ok|bad|unmeasured> icons=<n> valid=<n> ico=<code> touch=<y|n> [reason=…]
# With --list, exit is the worst verdict across the list (bad > unmeasured > ok).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "favicon-check: unmeasured — python3 not available"; exit 2
fi

exec python3 - "$@" <<'PY'
import base64, html, re, sys, urllib.parse, urllib.request, urllib.error, ssl
import xml.parsers.expat

import os
STRICT = os.environ.get("FAVICON_STRICT", "") == "1"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128 Safari/537.36 favicon-check/1"
CTX = ssl.create_default_context()

def fetch(url, timeout=20, want_bytes=True):
    """Return (status, content_type, body_bytes, final_url) or (None, reason, b'', url)."""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*", "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            body = r.read(2_000_000) if want_bytes else b""
            return r.status, (r.headers.get("content-type") or "").lower(), body, r.geturl()
    except urllib.error.HTTPError as e:
        # 401/403 pages often still carry a full <head> (tesla-fleet does) — keep the body.
        try:
            body = e.read(2_000_000)
        except Exception:
            body = b""
        return e.code, (e.headers.get("content-type") or "").lower(), body, url
    except Exception as e:
        return None, f"{type(e).__name__}: {e}", b"", url

def svg_wellformed(data: bytes):
    """Browsers reject an SVG data URI that is not well-formed XML. Return (ok, reason)."""
    roots = []
    p = xml.parsers.expat.ParserCreate()
    def start(name, attrs):
        if not roots:
            roots.append(name)
    p.StartElementHandler = start
    try:
        p.Parse(data, True)
    except xml.parsers.expat.ExpatError as e:
        return False, f"svg not well-formed: {e}"
    if not roots or roots[0].split(":")[-1].lower() != "svg":
        return False, f"svg root element is <{roots[0] if roots else '?'}>, not <svg>"
    return True, "svg ok"

MAGIC = {
    "png":  (b"\x89PNG\r\n\x1a\n",),
    "jpeg": (b"\xff\xd8\xff",),
    "jpg":  (b"\xff\xd8\xff",),
    "gif":  (b"GIF87a", b"GIF89a"),
    "x-icon": (b"\x00\x00\x01\x00",),
    "vnd.microsoft.icon": (b"\x00\x00\x01\x00",),
    "webp": (b"RIFF",),
}

def check_raster(subtype: str, data: bytes):
    sigs = MAGIC.get(subtype)
    if not sigs:
        return False, f"unsupported image subtype {subtype}"
    if any(data.startswith(s) for s in sigs):
        return True, f"{subtype} ok"
    return False, f"{subtype} magic bytes missing"

def validate_data_uri(href: str):
    m = re.match(r"data:([^;,]+)((?:;[^;,]+)*),(.*)$", href, re.S)
    if not m:
        return False, "data URI unparseable"
    mime, params, payload = m.group(1).lower(), m.group(2).lower(), m.group(3)
    try:
        raw = base64.b64decode(payload, validate=False) if ";base64" in params else urllib.parse.unquote_to_bytes(payload)
    except Exception as e:
        return False, f"data URI decode failed: {e}"
    if not raw:
        return False, "data URI empty"
    if mime == "image/svg+xml":
        return svg_wellformed(raw)
    if mime.startswith("image/"):
        return check_raster(mime.split("/", 1)[1], raw)
    return False, f"data URI is {mime}, not an image"

def validate_url_icon(href: str, base: str):
    url = urllib.parse.urljoin(base, href)
    st, ct, body, _ = fetch(url)
    if st is None:
        return None, f"{url}: fetch failed ({ct})"
    if not (200 <= st < 300):
        return False, f"{url}: HTTP {st}"
    if not ct.startswith("image/"):
        # Some servers mislabel .ico; accept if the bytes are an ICO/PNG.
        for sub in ("x-icon", "png"):
            ok, _ = check_raster(sub, body)
            if ok:
                return True, f"{url}: {sub} bytes (content-type was {ct or 'missing'})"
        return False, f"{url}: content-type {ct or 'missing'} is not image/*"
    if "svg" in ct:
        ok, why = svg_wellformed(body)
        return ok, f"{url}: {why}"
    sub = ct.split("/", 1)[1].split(";")[0].strip()
    ok, why = check_raster(sub, body)
    if not ok and sub not in MAGIC:
        return True, f"{url}: {ct} (unverified subtype, 2xx image/*)"
    return ok, f"{url}: {why}"

LINK_RE = re.compile(r"<link\b[^>]*>", re.I | re.S)
ATTR_RE = re.compile(r"""([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))""", re.S)

def links(doc: str):
    out = []
    head_end = doc.lower().find("</head>")
    scope = doc if head_end < 0 else doc[:head_end]
    for tag in LINK_RE.findall(scope):
        attrs = {}
        for m in ATTR_RE.finditer(tag):
            attrs[m.group(1).lower()] = html.unescape(m.group(3) or m.group(4) or m.group(5) or "")
        rel = attrs.get("rel", "").lower().split()
        if not rel:
            continue
        out.append((rel, attrs.get("href", "")))
    return out

def check_html(doc: str, base: str, ico_status):
    ls = links(doc)
    icon_links = [(r, h) for r, h in ls if "icon" in r and "apple-touch-icon" not in r]
    touch = any("apple-touch-icon" in r for r, _ in ls)
    results = []
    for rel, href in icon_links:
        if not href:
            results.append((False, "icon link has empty href")); continue
        if href.lower().startswith("data:"):
            results.append(validate_data_uri(href))
        else:
            results.append(validate_url_icon(href, base))
    valid = sum(1 for ok, _ in results if ok is True)
    reasons = [why for ok, why in results if ok is not True]
    if valid > 0:
        verdict = "ok"
    elif icon_links:
        verdict = "bad"
        reasons = reasons or ["declared icons all failed"]
    else:
        # No <link rel=icon>: a 2xx image at /favicon.ico still renders in every browser.
        if ico_status == "200-image":
            verdict, valid = "ok", 1
            reasons = ["no <link rel=icon>; /favicon.ico serves an image"]
        else:
            verdict = "bad"
            reasons = ["no <link rel=icon> and /favicon.ico is not an image"]
    if STRICT and verdict == "ok":
        strict_fail = []
        if ico_status != "200-image":
            strict_fail.append("strict: /favicon.ico is not a 2xx image (Safari/bookmarks/crawlers request it regardless of <link>)")
        touch_hrefs = [h for r, h in ls if "apple-touch-icon" in r]
        if not touch_hrefs:
            strict_fail.append("strict: no <link rel=apple-touch-icon>")
        else:
            bad_touch = [why for ok, why in (validate_url_icon(h, base) if not h.lower().startswith("data:") else validate_data_uri(h) for h in touch_hrefs) if ok is not True]
            if len(bad_touch) == len(touch_hrefs):
                strict_fail.append("strict: apple-touch-icon does not resolve to an image (" + "; ".join(bad_touch) + ")")
        if strict_fail:
            verdict = "bad"
            reasons = strict_fail + reasons
    return verdict, len(icon_links), valid, touch, "; ".join(reasons)

def probe_ico(base: str):
    st, ct, body, _ = fetch(urllib.parse.urljoin(base, "/favicon.ico"))
    if st is None:
        return "ERR", "ERR"
    if 200 <= st < 300 and (ct.startswith("image/") or check_raster("x-icon", body)[0] or check_raster("png", body)[0]):
        return str(st), "200-image"
    return str(st), f"{st}-{'image' if ct.startswith('image/') else 'noimage'}"

def report(label, verdict, icons, valid, ico, touch, reason):
    line = f"favicon-check: {label} verdict={verdict} icons={icons} valid={valid} ico={ico} touch={'y' if touch else 'n'}"
    if ico not in ("200",) and verdict != "unmeasured":
        line += " warn=favicon.ico-missing"
    if not touch and verdict != "unmeasured":
        line += " warn=apple-touch-icon-missing"
    if reason:
        line += f" reason={reason}"
    print(line)

def check_page(url: str):
    st, ct, body, final = fetch(url)
    base = final or url
    ico_code, ico_state = probe_ico(base)
    if st is None:
        report(url, "unmeasured", 0, 0, ico_code, False, f"page fetch failed ({ct})"); return 2
    from urllib.parse import urlsplit as _us
    if _us(base).netloc and _us(url).netloc and _us(base).netloc.lower() != _us(url).netloc.lower():
        # The origin bounced us to ANOTHER host (Cloudflare Access login, SSO, a vendor page).
        # The head we would inspect belongs to that host, not the site under test — grading it
        # produced two phantom "ico=404" entries (cadu/code.example.com → example-org.cloudflareaccess.com,
        # 2026-09-20). Three outcomes, never two: this is "could not measure", not ok and not bad.
        report(url, "unmeasured", 0, 0, ico_code, False, f"redirected off-host to {_us(base).netloc} (access-gated?)"); return 2
    if st >= 500:
        # A 5xx body is the CDN's/origin's error page, not the site's head — inspecting it
        # would grade Cloudflare's 502 template. (packages.example.com, dead tunnel, 2026-09-20)
        report(url, "unmeasured", 0, 0, ico_code, False, f"HTTP {st} — origin down, served head is an error page"); return 2
    doc = body.decode("utf-8", "replace")
    if "text/html" not in ct and "<html" not in doc.lower()[:2000]:
        report(url, "unmeasured", 0, 0, ico_code, False, f"HTTP {st} content-type {ct or 'missing'} is not HTML"); return 2
    if "<head" not in doc.lower() and "<link" not in doc.lower():
        report(url, "unmeasured", 0, 0, ico_code, False, f"HTTP {st} HTML has no <head>/<link> to inspect (login wall?)"); return 2
    verdict, icons, valid, touch, reason = check_html(doc, base, ico_state)
    if st >= 400:
        reason = (f"(page HTTP {st}; head inspected anyway) " + reason).strip()
    report(url, verdict, icons, valid, ico_code, touch, reason)
    return {"ok": 0, "bad": 1}[verdict]

def validate_local_icon(href: str, root: str):
    """Pre-deploy: resolve a relative/root-relative href against the build dir on disk."""
    import os
    rel = href.split("?")[0].split("#")[0].lstrip("/")
    path = os.path.normpath(os.path.join(root, rel))
    if not path.startswith(os.path.normpath(root)):
        return False, f"{href}: escapes the build dir"
    try:
        data = open(path, "rb").read()
    except OSError as e:
        return False, f"{href}: not in build dir ({e.strerror})"
    if path.lower().endswith(".svg"):
        ok, why = svg_wellformed(data); return ok, f"{href}: {why}"
    for sub in ("png", "x-icon", "jpeg", "gif", "webp"):
        if check_raster(sub, data)[0]:
            return True, f"{href}: {sub} ok"
    return False, f"{href}: unrecognised image bytes"

def check_file(path: str, base: str):
    import os
    try:
        doc = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        report(path, "unmeasured", 0, 0, "-", False, f"cannot read file: {e}"); return 2
    if base and re.match(r"https?://", base):
        ico_code, ico_state = probe_ico(base)
        verdict, icons, valid, touch, reason = check_html(doc, base, ico_state)
    else:
        # No origin given: this is a built output dir (dist/, public/). Resolve hrefs on disk.
        root = base or os.path.dirname(os.path.abspath(path))
        global validate_url_icon
        saved = validate_url_icon
        validate_url_icon = lambda href, _b, _r=root: validate_local_icon(href, _r)
        try:
            ico_state = "200-image" if os.path.exists(os.path.join(root, "favicon.ico")) else "404-noimage"
            verdict, icons, valid, touch, reason = check_html(doc, "file:///", ico_state)
        finally:
            validate_url_icon = saved
        ico_code = "200" if ico_state == "200-image" else "404"
    report(path, verdict, icons, valid, ico_code, touch, reason)
    return {"ok": 0, "bad": 1}[verdict]

def main(argv):
    global STRICT
    if argv and argv[0] == "--strict":
        STRICT = True; argv = argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__ or "usage: favicon-check.sh <url> | --list <file> | --html <file> [base]"); return 2
    if argv[0] == "--html":
        if len(argv) < 2:
            print("usage: favicon-check.sh --html <file> [base-url]"); return 2
        return check_file(argv[1], argv[2] if len(argv) > 2 else "")
    if argv[0] == "--list":
        if len(argv) < 2:
            print("usage: favicon-check.sh --list <file>"); return 2
        worst = 0
        rank = {0: 0, 2: 1, 1: 2}
        for line in open(argv[1], encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            url = line.split()[-1]
            rc = check_page(url)
            if rank[rc] > rank[worst]:
                worst = rc
        return worst
    return check_page(argv[0])

sys.exit(main(sys.argv[1:]))
PY
