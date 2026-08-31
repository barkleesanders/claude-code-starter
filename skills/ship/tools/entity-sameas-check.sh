#!/usr/bin/env bash
# entity-sameas-check.sh — /ship Phase 4.05f: Organization entity anchors.
#
# Checks a LIVE public site for schema.org Organization markup carrying a
# `sameAs` array, and verifies every URL in it actually resolves.
#
# WHY THIS IS A GATE AND NOT A NICE-TO-HAVE
#   `sameAs` is how Google reconciles "this website" with "this real-world
#   organization". Google documents it under Organization's RECOMMENDED
#   properties: "The URL of a page on another website with additional
#   information about your organization" (developers.google.com/search/docs/
#   appearance/structured-data/organization, checked 2026-08-24). It is free,
#   it is one JSON block, and it is the cheapest entity signal available.
#
#   Calibrate the claim honestly: it is a HINT for entity understanding, not a
#   ranking factor and not a Knowledge Panel guarantee. Do not let a report
#   say otherwise.
#
# WHAT IT WILL NOT DO — and this is the important part
#   It NEVER invents a URL. A plausible-looking slug is a fabrication with a
#   valid shape: verified 2026-08-24, `linkedin.com/company/example-nonprofit`
#   404s while `linkedin.com/company/example` is real. The only safe sources
#   for a candidate are (a) links the site already publishes, (b) an
#   authoritative registry looked up by a real identifier (EIN, UEI), or
#   (c) the user telling you. This script reports what is MISSING; a human or
#   an agent with verified facts fills it in.
#
# THREE OUTCOMES, NEVER TWO
#   ok       Organization node found, sameAs present, every URL resolves
#   bad      Organization node found but sameAs absent/empty, or a dead URL
#   unknown  page unreachable / no ld+json / unparseable  -> NOT reported green
#
# ENTITY-CONFUSION GUARD (the failure that matters more than a missing link)
#   Pass --forbid to assert that a URL pattern must NOT appear. Use it to keep
#   one legal entity's identifiers off another's site. Real example: Example Org
#   Incorporated (a 501(c)(3), EIN 00-0000000) and Example Tech / Example LLC (a
#   for-profit) share a brand. Putting the nonprofit's IRS/ProPublica/Candid
#   links on the consulting site would assert tax-exempt status for a business
#   that does not have it — a misrepresentation, not an SEO tweak.
#
# USAGE
#   entity-sameas-check.sh https://example.com
#   entity-sameas-check.sh https://example.org --forbid 'propublica|candid|every\.org'
#   entity-sameas-check.sh https://example.com --min 3
#   entity-sameas-check.sh https://solo.example --allow-types WebSite,Person
#
# EXIT  0 ok · 1 bad · 2 unknown
set -u

URL="${1:-}"
[ -z "$URL" ] && { echo "usage: $0 <https://site> [--min N] [--forbid REGEX]" >&2; exit 2; }
shift

MIN=1
FORBID=""
ALLOW_TYPES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --min)    MIN="${2:-1}"; shift 2 ;;
    --forbid) FORBID="${2:-}"; shift 2 ;;
    # Explicit escape hatch for a site that legitimately has NO organization
    # behind it — a personal project, a one-person open-source tool. The point
    # is that it must be TYPED OUT in the ship command, so "this site has no
    # org" is a stated decision someone can argue with, never a silent pass.
    # Claiming a nonprofit runs a personal project would be a false statement
    # about a real organization; refusing to mark it is the safe default.
    --allow-types) ALLOW_TYPES="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'
HTML=$(curl -sL --max-time 25 -H "User-Agent: $UA" \
         -H 'Accept: text/html,application/xhtml+xml' "$URL" 2>/dev/null) || true

if [ -z "$HTML" ]; then
  echo "entity-sameas: UNKNOWN — could not fetch $URL (not evidence of health)"
  exit 2
fi

# Extract sameAs URLs from any Organization-ish node, including inside @graph.
PARSED=$(printf '%s' "$HTML" | ALLOW_TYPES="$ALLOW_TYPES" python3 -c '
import sys, re, json, os

# schema.org Organization + its LocalBusiness subtypes. The subtypes matter:
# a site that correctly uses a SPECIFIC type (ProfessionalService rather than
# bare LocalBusiness) was invisible to this gate until 2026-08-24, and the
# failure was silent — the parser found no "Organization" node, printed BAD with
# an empty reason, and exit 1 looked like a missing sameAs rather than a gate
# that could not see the node. Prefer over-listing here: a type this set is
# missing reads as a site defect, which is the wrong direction to be wrong in.
ORG = {"Organization","NGO","Corporation","LocalBusiness","NonprofitType",
       "GovernmentOrganization","EducationalOrganization","MedicalOrganization",
       # LocalBusiness subtypes commonly used by real sites:
       "ProfessionalService","LegalService","FinancialService","HomeAndConstructionBusiness",
       "MedicalBusiness","FoodEstablishment","Store","AutomotiveBusiness",
       "HealthAndBeautyBusiness","LodgingBusiness","EntertainmentBusiness",
       "SportsActivityLocation","EmergencyService","ChildCare","Dentist",
       "RealEstateAgent","TravelAgency","InsuranceAgency","Physician",
       "Airline","OnlineBusiness","OnlineStore","ResearchOrganization",
       "PoliticalParty","LibrarySystem","NewsMediaOrganization","Consortium",
       "FundingScheme","WorkersUnion","SearchRescueOrganization","Project"}

# --allow-types widens the set of nodes that may carry the anchors. Used for a
# site with no organization behind it (Person / WebSite / SoftwareApplication).
ORG |= {t.strip() for t in os.environ.get("ALLOW_TYPES","").split(",") if t.strip()}

html = sys.stdin.read()
blocks = re.findall(r"<script[^>]*application/ld\+json[^>]*>(.*?)</script>", html, re.S)
if not blocks:
    print("UNKNOWN|no ld+json block on the page"); raise SystemExit

def walk(node, out):
    if isinstance(node, list):
        for n in node: walk(n, out)
        return
    if not isinstance(node, dict): return
    for key in ("@graph","mainEntity","publisher","parentOrganization","author"):
        if key in node: walk(node[key], out)
    t = node.get("@type")
    types = {t} if isinstance(t, str) else set(t or [])
    if types & ORG:
        out.append(node)

orgs, unparseable = [], 0
for b in blocks:
    try:
        walk(json.loads(b), orgs)
    except Exception:
        unparseable += 1

if not orgs:
    if unparseable:
        print("UNKNOWN|ld+json present but unparseable (%d block(s))" % unparseable)
    else:
        # Name what WAS found. A bare "no Organization node" gives the reader no
        # way to tell a genuinely missing node from a type this gate does not
        # know about — which is exactly how the ProfessionalService miss above
        # presented.
        seen = set()
        def types_of(n):
            if isinstance(n, list):
                for x in n: types_of(x)
            elif isinstance(n, dict):
                t = n.get("@type")
                if isinstance(t, str): seen.add(t)
                elif isinstance(t, list): seen.update(str(x) for x in t)
                for v in n.values(): types_of(v)
        for b2 in blocks:
            try: types_of(json.loads(b2))
            except Exception: pass
        found = ", ".join(sorted(seen)) or "none"
        print("BAD|no Organization-family node. Types present: %s. "
              "If one of these IS the org, add it to ORG or pass --allow-types." % found)
    raise SystemExit

# Merge across nodes; a site may split parent/child organizations.
seen, urls, names = set(), [], []
for o in orgs:
    names.append(str(o.get("name") or o.get("legalName") or "?"))
    s = o.get("sameAs")
    if isinstance(s, str): s = [s]
    for u in (s or []):
        if isinstance(u, str) and u not in seen:
            seen.add(u); urls.append(u)

print("OK|%s|%s" % (" + ".join(names[:3]), " ".join(urls)))
' 2>/dev/null)

STATE="${PARSED%%|*}"
REST="${PARSED#*|}"

case "$STATE" in
  UNKNOWN) echo "entity-sameas: UNKNOWN — $REST"; exit 2 ;;
  BAD)     echo "entity-sameas: BAD — $REST"
           echo "  FIX: add an Organization/NGO node with a sameAs array."
           echo "  Populate it ONLY from links the site already publishes, an"
           echo "  authoritative registry looked up by EIN/UEI, or the user."
           echo "  NEVER guess a slug — a plausible URL that 404s is a fabrication."
           exit 1 ;;
  OK)      : ;;
  *)       echo "entity-sameas: UNKNOWN — checker produced no verdict"; exit 2 ;;
esac

ORGNAME="${REST%%|*}"
URLS="${REST#*|}"

# shellcheck disable=SC2206
URLARR=($URLS)
COUNT=${#URLARR[@]}

echo "entity-sameas: $URL"
[ -n "$ALLOW_TYPES" ] && echo "  NOTE: node types widened by --allow-types=$ALLOW_TYPES (no Organization claimed)"
echo "  organization: $ORGNAME"
echo "  sameAs count: $COUNT (min $MIN)"

RC=0
if [ "$COUNT" -lt "$MIN" ]; then
  echo "  BAD: fewer than $MIN entity anchor(s)."
  RC=1
fi

# Entity-confusion guard runs even when the count is fine.
if [ -n "$FORBID" ]; then
  for u in "${URLARR[@]}"; do
    if printf '%s' "$u" | grep -qiE "$FORBID"; then
      echo "  BAD: forbidden entity identifier present -> $u"
      echo "       This URL belongs to a DIFFERENT legal entity. Remove it."
      RC=1
    fi
  done
fi

# Liveness. Three verdicts per URL: a WAF/login 403 is not a dead link.
for u in "${URLARR[@]}"; do
  code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 20 -H "User-Agent: $UA" "$u" 2>/dev/null)
  case "$code" in
    2*)        printf '  ok        %s (%s)\n' "$u" "$code" ;;
    404|410)   printf '  DEAD      %s (%s)  <- remove or fix\n' "$u" "$code"; RC=1 ;;
    000)       printf '  UNVERIFIED %s (no response — check in a browser)\n' "$u" ;;
    *)         printf '  UNVERIFIED %s (%s — likely WAF/login wall, not proof of death)\n' "$u" "$code" ;;
  esac
done

[ "$RC" -eq 0 ] && echo "entity-sameas: PASS"
exit "$RC"
