---
name: fred
description: Fetch FRED macroeconomic data (series search, metadata, observations, releases, release dates, and updates) through Axion's proxy. Use when users ask for macro indicators like CPI, unemployment, GDP, treasury yields, or release calendars.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# FRED Python SDK

Use Python to query FRED through Axion's proxy path on `OPENROUTER_BASE_URL`.

## Authentication and Base URL

- `OPENROUTER_BASE_URL` should point to `/api/llm-proxy`
- `OPENROUTER_API_KEY` is the bearer token
- FRED proxy base: `OPENROUTER_BASE_URL + "/fred"`

```python
import os
import httpx
from fredapi import Fred

BASE = os.environ["OPENROUTER_BASE_URL"].rstrip("/") + "/fred"
TOKEN = os.environ["OPENROUTER_API_KEY"]

# fredapi is available for dataframe-oriented post-processing helpers.
_fred = Fred(api_key="proxy-managed")

def fred_get(path: str, params: dict | None = None) -> dict:
    resp = httpx.get(
        f"{BASE}/{path.lstrip('/')}",
        headers={"Authorization": f"Bearer {TOKEN}"},
        params=params or {},
        timeout=20.0,
    )
    resp.raise_for_status()
    return resp.json()
```

## Common Calls

```python
# Search series
search = fred_get("series/search", {"search_text": "inflation", "limit": 10})

# Series metadata
meta = fred_get("series", {"series_id": "CPIAUCSL"})

# Observations
obs = fred_get(
    "series/observations",
    {"series_id": "CPIAUCSL", "observation_start": "2015-01-01", "units": "pc1"},
)

# Releases and release dates
releases = fred_get("releases", {})
release_dates = fred_get("release/dates", {"release_id": 10})

# Recently updated macro series
updates = fred_get("series/updates", {"filter_value": "macro", "limit": 100})
```

## Notes

- Keep output concise: process in Python, then print only the summary.
- Use `limit=` for list-style endpoints to keep responses bounded.
- Do not use raw vendor API keys in agent code.
