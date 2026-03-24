---
name: taddy
description: Query the Taddy podcast database (4M+ podcasts, 200M+ episodes) -- search, details, episodes, transcripts, top charts. Use when the user asks about podcasts, wants to find shows/episodes, get transcripts, or browse top charts.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/taddy.sh *)
---

# Taddy Podcast API

Query the Taddy podcast database using the bundled script. Requires env vars `TADDY_USER_ID` and `TADDY_API_KEY`.

## Commands

```bash
# Search for podcasts by keyword
${CLAUDE_SKILL_DIR}/scripts/taddy.sh search "artificial intelligence" 10

# Search for episodes
${CLAUDE_SKILL_DIR}/scripts/taddy.sh search-episodes "machine learning" 5

# Get podcast details (by name or UUID)
${CLAUDE_SKILL_DIR}/scripts/taddy.sh podcast "This American Life"
${CLAUDE_SKILL_DIR}/scripts/taddy.sh podcast "cb8d858a-3ef4-4645-8942-67e55c0927f2"

# Get episode details
${CLAUDE_SKILL_DIR}/scripts/taddy.sh episode "<episode-uuid>"

# Get latest episodes for a podcast
${CLAUDE_SKILL_DIR}/scripts/taddy.sh episodes "<podcast-uuid>" 10

# Get episode transcript
${CLAUDE_SKILL_DIR}/scripts/taddy.sh transcript "<episode-uuid>"

# Top charts (default: US, max 25)
${CLAUDE_SKILL_DIR}/scripts/taddy.sh top-charts UNITED_STATES_OF_AMERICA 25

# Top by genre
${CLAUDE_SKILL_DIR}/scripts/taddy.sh top-genre PODCASTSERIES_TECHNOLOGY 25

# Get multiple podcasts at once (max 25)
${CLAUDE_SKILL_DIR}/scripts/taddy.sh multi "uuid1,uuid2,uuid3"
```

## Direct GraphQL

For custom queries beyond what the script supports, use curl:

```bash
curl -s -X POST https://api.taddy.org/graphql \
  -H "Content-Type: application/json" \
  -H "X-USER-ID: $TADDY_USER_ID" \
  -H "X-API-KEY: $TADDY_API_KEY" \
  -d '{"query": "{ getPodcastSeries(name:\"Lex Fridman Podcast\") { uuid name totalEpisodesCount } }"}'
```

## Reference

For complete API type and field reference, see [reference.md](reference.md).
