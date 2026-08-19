# Magazine — Invocation Examples

How to invoke the skill for different content types. Each example shows the user request, the curation/treatment plan, and the output filename pattern.

---

## Example 1 — Daily HN digest (the original Morning Edition)

**User says:** "Build me a daily Morning Edition magazine from Hacker News, my taste."

**Flow:**
1. `curl https://hacker-news.firebaseio.com/v0/topstories.json` → top 30–40 IDs
2. Fetch each item's metadata (title, URL, score, comments) in parallel
3. Score against taste profile (love list / skip list)
4. Pick top 10
5. Fetch a 1–2 sentence summary for each via WebFetch
6. Pick spread treatment per item:
   - #1 cover story → Treatment 1 (Hero)
   - Security / supply chain → Treatment 3 (Dark midnight)
   - Backups / breakage / outage → Treatment 2 (Rose alert stamp)
   - Creative software → Treatment 4 (Magazine cover)
   - Dev tool / CLI → Treatment 5 (Terminal)
   - Civic / activism → Treatment 6 (Poster)
   - Cultural / archives → Treatment 7 (Vinyl vintage)
   - Web standards / longform → Treatment 8 (Academic drop-cap)
   - Stat / number-led → Treatment 9 (Big-stat)
   - Research / paper → Treatment 10 (Scientific)
7. Save to `~/Downloads/morning-edition-YYYY-MM-DD.html`
8. Add `★ APPLIES TO YOU` badge for any story directly relevant to user's active projects (use what you know from their context)

---

## Example 2 — Meeting minutes as editorial field notes

**User says:** "Magazine the April 14 SFPUC meeting minutes."

**Flow:**
1. Read the minutes source document (Drive or local)
2. Identify 6–10 distinct items worth their own spread:
   - The headline decision / motion
   - Each major presentation (with presenter name)
   - Each contentious discussion thread
   - Each action item or follow-up
   - Future agenda items
3. Pick treatments with **field-notes bias** since the source is a civic body:
   - Cover → Treatment 11 (Field notes newsprint) for the dateline cover
   - Each agenda item → vary across 11, 8 (Academic drop-cap for policy detail), 1 (Hero for the headline decision)
   - Questions raised → Treatment 9 (Big-stat) if a number anchors them, else 11 with pull-quote
   - Action items → Treatment 6 (Poster) for the call-to-action energy
   - Follow-up / future items → Treatment 8 (Academic) for the "to be continued" feel
4. Use real attributee quotes as pull-quotes wherever possible
5. Save to `~/Downloads/minutes-magazine-<body>-YYYY-MM-DD.html`

**Key difference from HN:** Don't curate against a taste filter — every agenda item matters. Instead, curate by *importance to the body's mission*. The cover spread is whichever item drives the most consequential vote or commitment.

---

## Example 3 — Research summary as longform editorial

**User says:** "Magazine the §99.5 exposure analysis."

**Flow:**
1. Read the source analysis doc
2. Each numbered risk = its own spread
3. Each records request target = its own spread (with mailing address as the source line)
4. Treatments lean academic / scientific / dark midnight (it's a serious policy doc):
   - Hero (1) — the thesis
   - Dark midnight (3) — corruption / Kelly precedent
   - Big-stat (9) — exposure counts, dollar figures, dates
   - Academic (8) — the legal analysis sections
   - Field notes (11) — the records request blocks
   - Big-stat finish (9) — closing call to action
5. Save to `~/Downloads/exposure-magazine-<topic>-YYYY-MM-DD.html`

---

## Example 4 — Project status report as investor letter

**User says:** "Render this week's project update as a magazine for the team."

**Flow:**
1. Parse the update (markdown, doc, or chat message)
2. One spread per major project / workstream
3. Treatments balance:
   - Cover (1) — top-line "this is what shipped"
   - Big-stat (9) — KPIs
   - Terminal (5) — anything dev-infrastructure
   - Field notes (11) — narrative paragraphs
   - Poster (6) — the asks / blockers / decisions needed
4. Always end with a colophon spread that includes the action items for next week

---

## Example 5 — Curated link roundup

**User says:** "Magazine these 8 links I sent."

**Flow:**
1. WebFetch each URL for title + 1–2 sentence summary
2. Group by tone (security, creative, civic, etc.)
3. Assign treatments by tone
4. No "applies to you" badges unless explicitly flagged by user
5. Save to `~/Downloads/roundup-<topic>-YYYY-MM-DD.html`

---

## Output naming conventions

| Source | Filename pattern |
|---|---|
| HN daily | `morning-edition-YYYY-MM-DD.html` |
| Meeting minutes | `minutes-magazine-<body-slug>-YYYY-MM-DD.html` |
| Research / analysis | `<topic-slug>-magazine-YYYY-MM-DD.html` |
| Project status | `status-<project-slug>-YYYY-MM-DD.html` |
| Link roundup | `roundup-<topic-slug>-YYYY-MM-DD.html` |

---

## Testing your output before reporting back

After saving, sanity-check:

1. Open the file (`open path`) so the user can see it immediately.
2. Validate visually: at least 3 distinct background colors visible across the document, no `<small>` tags, no font-size below 22px in body text.
3. Validate structurally: masthead present, colophon present, every spread has a numeral + h2 + source line.

If any check fails, fix before reporting "done."

---

## When the user wants this on a recurring schedule

Three options to offer (in order of difficulty):

1. **Claude Code Routine** — a saved cloud routine that fires daily and posts the magazine to Slack / saves to Drive. Best for the HN morning edition use case.
2. **`/loop` skill** — recurring task runner inside an active session. Good for "every 30 minutes regenerate the project status magazine."
3. **macOS launchd / cron** — wrap the fetch + Claude call into a shell script and schedule locally. Most reliable.

Don't set this up unless the user asks. Just offer it as a follow-up after the first run.
