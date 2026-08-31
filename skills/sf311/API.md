# SF311 DOGE Worker API Integration

> ⚠️ **DEPRECATED 2026-06-04.** The `sf311-doge` worker documented below was
> retired and deleted. SF311 submission moved to **improvebayarea.com**
> (official SF311 Android GraphQL backend). Use the **`iba` CLI** (`iba submit`,
> `iba categories`, `iba lookup`, `iba doctor`) → POST `https://improvebayarea.com/api/submit`
> with `{mode, city:"san-francisco", request_type_id, summary, description, lat, lng, address}`.
> The form_name-based contract below is historical and no longer live.

## Endpoint
Base URL: `https://improvebayarea.com` (was `sf311-doge.example.workers.dev`, retired)

## Authentication
Uses Clerk authentication. Get a session token from Clerk and pass as Bearer token.

## Endpoints

### POST /api/analyze
Analyzes a photo to detect 311 issues.

**Request:**
```
Content-Type: multipart/form-data
Authorization: Bearer <clerk_token>

Fields:
- photo: File (image)
- context: string (optional additional context)
```

**Response:**
```json
{
  "analysis": {
    "primary_category": "tree_maintenance",
    "severity": "medium",
    "issue_summary": "Young trees need restaking",
    "detailed_description": "...",
    "municipal_codes": ["SF Public Works Code Art. 16"],
    "escalation_tips": ["..."],
    "relevant_urls": [{"url": "...", "title": "..."}],
    "strategic_reframe": "..."
  }
}
```

### POST /api/submit
Submits a 311 report to SF.gov.

**Request:**
```json
{
  "form_name": "pw_tree_maintenance",
  "address": "1070 Bridgeview Way, San Francisco, CA 94158",
  "description": "Full description with AI analysis",
  "location_description": "Corner near parking garage",
  "lat": 37.7749,
  "lng": -122.3894,
  "anonymous": true,
  "category_data": {},
  "draft": false
}
```

**Response:**
```json
{
  "success": true,
  "reference": "101003507412"
}
```

## Form Names (FORM_MAP)
| Category | Form Name |
|----------|-----------|
| graffiti | pw_graffiti |
| street_cleaning | pw_street_cleaning |
| damaged_property | pw_damaged_property |
| tree_maintenance | pw_tree_maintenance |
| sidewalk_defect | pw_street_sidewalkdefect |
| abandoned_vehicle | mta_abandoned_vehicle |
| noise | cs_noise |
| sewer | puc_sewer |
| streetlights | puc_streetlights |
| litter | pw_litter_receptacles |
| blocked_sidewalk | cs_block_street_sidewalk |
| park | rpd_general |

## CLI Integration

### Using with curl (requires Clerk token)
```bash
# Analyze photo
curl -X POST https://sf311-doge.example.workers.dev/api/analyze \
  -H "Authorization: Bearer $CLERK_TOKEN" \
  -F "photo=@/path/to/photo.jpg" \
  -F "context=Trees need staking"

# Submit report
curl -X POST https://sf311-doge.example.workers.dev/api/submit \
  -H "Authorization: Bearer $CLERK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "form_name": "pw_tree_maintenance",
    "address": "1070 Bridgeview Way, San Francisco, CA 94158",
    "description": "Trees need restaking for wind protection",
    "location_description": "Corner by parking garage",
    "anonymous": true
  }'
```
