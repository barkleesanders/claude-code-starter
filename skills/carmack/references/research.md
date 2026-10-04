# Research & Web Prompts

## Research & Prompts (last30days)

Research any topic from the last 30 days on Reddit, X, and the web. Surfaces what people are actually discussing, recommending, and debating right now.

**Use cases:**
- **Prompting**: "photorealistic people in Nano Banana Pro" -> learn techniques, get copy-paste prompts
- **Recommendations**: "best Claude Code skills", "top AI tools" -> list of specific things people mention
- **News**: "what's happening with OpenAI" -> current events and updates
- **General**: any topic -> understand what the community is saying

### Critical: Parse User Intent

Before doing anything, parse for:
1. **TOPIC**: What they want to learn about
2. **TARGET TOOL** (if specified): Where they'll use the prompts
3. **QUERY TYPE**: PROMPTING / RECOMMENDATIONS / NEWS / GENERAL

Common patterns:
- `[topic] for [tool]` -> "web mockups for Nano Banana Pro" -> TOOL IS SPECIFIED
- `best [topic]` or `top [topic]` -> QUERY_TYPE = RECOMMENDATIONS
- Just `[topic]` -> TOOL NOT SPECIFIED, run research first, ask AFTER

**Do NOT ask about target tool before research.**

### Setup

**Browser Mode** (no API keys required -- uses agent-browser):
```bash
npm i -g @anthropic/agent-browser  # Install if needed
# Skill auto-detects agent-browser and uses browser mode
```

**API Mode** (optional, for better engagement metrics):
```bash
mkdir -p ~/.config/last30days
cat > ~/.config/last30days/.env << 'ENVEOF'
OPENAI_API_KEY=    # For Reddit research
XAI_API_KEY=       # For X/Twitter research
ENVEOF
```

**Do NOT stop if no keys configured.** Fall back to WebSearch.

### Research Execution

**Step 1: Run the research script**
```bash
python3 ~/.claude/skills/last30days/scripts/last30days.py "$ARGUMENTS" --emit=compact 2>&1
```

The script auto-detects available API keys and signals mode:
- **"Mode: both"** or **"Mode: reddit-only"** or **"Mode: x-only"**: API mode
- **"Mode: browser"**: Browser automation mode
- **"Mode: web-only"**: No API keys or browser, use WebSearch only

**Step 2: Do WebSearch (for all modes)**

Choose search queries by QUERY_TYPE:

- **RECOMMENDATIONS**: `best {TOPIC} recommendations`, `{TOPIC} list examples`, `most popular {TOPIC}`
- **NEWS**: `{TOPIC} news 2026`, `{TOPIC} announcement update`
- **PROMPTING**: `{TOPIC} prompts examples 2026`, `{TOPIC} techniques tips`
- **GENERAL**: `{TOPIC} 2026`, `{TOPIC} discussion`

For ALL types: **USE USER'S EXACT TERMINOLOGY** -- don't substitute tech names based on your knowledge. Exclude reddit.com, x.com (covered by script).

**Depth options**: `--quick` (8-12 sources), default (20-30), `--deep` (50-70 Reddit, 40-60 X)

### Judge Agent: Synthesize All Sources

After all searches complete:
1. Weight Reddit/X sources HIGHER (engagement signals: upvotes, likes)
2. Weight WebSearch sources LOWER (no engagement data)
3. Identify patterns that appear across ALL three sources (strongest signals)
4. Note contradictions between sources
5. Extract top 3-5 actionable insights

**CRITICAL: Ground synthesis in ACTUAL research content, not pre-existing knowledge.**

### For RECOMMENDATIONS Query Type

Extract SPECIFIC NAMES, not generic patterns:
- Count how many times each product/tool/skill is mentioned
- Note which sources recommend each
- List by popularity/mention count

```
Most mentioned:
1. [Specific name] - mentioned {n}x (r/sub, @handle, blog.com)
2. [Specific name] - mentioned {n}x (sources)
3. [Specific name] - mentioned {n}x (sources)
```

### For PROMPTING/NEWS/GENERAL

```
What I learned:
[2-4 sentences synthesizing key insights FROM THE ACTUAL RESEARCH OUTPUT]

KEY PATTERNS I'll use:
1. [Pattern from research]
2. [Pattern from research]
```

### Stats Display

For full/partial mode:
```
All agents reported back!
-- Reddit: {n} threads | {sum} upvotes | {sum} comments
-- X: {n} posts | {sum} likes | {sum} reposts
-- Web: {n} pages | {domains}
-- Top voices: r/{sub1}, r/{sub2} | @{handle1}, @{handle2}
```

### Wait for User's Vision

After showing stats, stop and wait for user to say what they want to create. Then write ONE perfect prompt.

**CRITICAL: Match the FORMAT the research recommends.** If research says JSON prompts -> write JSON. If natural language -> use prose.

```
Here's your prompt for {TARGET_TOOL}:

---

[The actual prompt IN THE FORMAT THE RESEARCH RECOMMENDS]

---

This uses [brief 1-line explanation of research insight applied].
```

After delivering, offer: "Want another prompt? Just tell me what you're creating next."

**Context Memory:** After research is complete, you are now an EXPERT on this topic. Do NOT run new WebSearches for follow-up questions -- answer from what you learned.
