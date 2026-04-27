---
name: fred
description: Fetch macroeconomic financial data (CPI, unemployment, GDP, rates, release calendars, and updates) through the backend FRED proxy. Use when users ask for macro series instead of prices/options microstructure.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Macroeconomics API (FRED Proxy)

Use direct HTTP requests through the backend FRED proxy. Do not use raw vendor API keys or the fredapi SDK.

## Authentication and Base URL Override

```python
import os
import urllib.parse
import urllib.request
import json

base = os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/fred-proxy")
token = os.environ["PROXY_API_KEY"]

def fred_proxy_get(path: str, params: dict | None = None) -> dict:
    query = urllib.parse.urlencode({"file_type": "json", **(params or {})})
    url = f"{base.rstrip('/')}/{path.lstrip('/')}?{query}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "opencode-fred-client/1.0"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())
```

## Supported Tools

Only use these functions/endpoints in this skill:

| Endpoint | Purpose | Refresh | Function |
| --- | --- | --- | --- |
| `fred/series/search` | Find any of 800K+ macro series by natural language | Continuous | `search_fred_series` |
| `fred/series/observations` | Pull the actual data (rates, levels, % changes) | Varies by series | `get_fred_series` |
| `fred/series` | Understand units and frequency before fetching | Rarely changes | `get_fred_series_info` |
| `(static list)` | Skip search for common series IDs (`CPIAUCSL`, `UNRATE`, `DGS10`) | Static | `get_popular_fred_series` |
| `fred/releases` | Resolve release names to IDs | Rarely changes | `get_fred_releases` |
| `fred/release/dates` | Fetch next/historical CPI, NFP, FOMC schedule dates | Per release calendar | `get_fred_release_dates` |
| `fred/series/updates` | Check which macro series just updated | Real-time | `get_fred_series_updates` |

## Examples

```python
def search_fred_series(query: str, limit: int = 10):
    return fred_proxy_get("series/search", {"search_text": query, "limit": limit, "order_by": "search_rank", "sort_order": "desc"})["seriess"]

def get_fred_series(series_id: str, observation_start: str | None = None, units: str | None = None):
    params = {"series_id": series_id}
    if observation_start:
        params["observation_start"] = observation_start
    if units:
        params["units"] = units
    return fred_proxy_get("series/observations", params)["observations"]

def get_fred_series_info(series_id: str):
    return fred_proxy_get("series", {"series_id": series_id})["seriess"][0]

def get_popular_fred_series():
    return ["CPIAUCSL", "UNRATE", "DGS10"]

def get_fred_releases():
    return fred_proxy_get("releases", {})["releases"]

def get_fred_release_dates(release_id: int):
    return fred_proxy_get("release/dates", {"release_id": release_id})["release_dates"]

def get_fred_series_updates(filter_value: str = "macro", limit: int = 100):
    return fred_proxy_get("series/updates", {"filter_value": filter_value, "limit": limit})["seriess"]

# quick usage
series_df = search_fred_series("inflation", limit=10)
meta = get_fred_series_info("CPIAUCSL")
obs = get_fred_series("CPIAUCSL", observation_start="2015-01-01", units="pc1")
popular = get_popular_fred_series()
releases = get_fred_releases()
dates = get_fred_release_dates(10)
updates = get_fred_series_updates()
```

## Notes

- Use `GET` only via `fred_proxy_get`; `file_type=json` is injected automatically.
- Keep results concise: process data in Python and print summarized outputs.
- Use `limit=` for list endpoints to avoid large responses.
