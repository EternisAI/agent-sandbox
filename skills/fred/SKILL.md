---
name: fred
description: Fetch macroeconomic financial data (CPI, unemployment, GDP, rates, release calendars, and updates) through the backend FRED proxy. Use when users ask for macro series instead of prices/options microstructure.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Macroeconomics API (FRED Proxy)

Use the `fredapi` Python package through the backend proxy. Do not use raw vendor API keys.

## Authentication and Base URL Override

```python
import os
import urllib.parse
import urllib.request
import json
from fredapi import Fred

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/fred-proxy")
token = os.environ["OPENROUTER_API_KEY"]

fred = Fred(api_key=token)
fred.root_url = base.rstrip("/")

def fred_proxy_get(path: str, params: dict | None = None) -> dict:
    query = urllib.parse.urlencode(params or {})
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if query:
        url += f"?{query}"
    # fredapi-compatible auth: send proxy token in api_key query param
    sep = "&" if "?" in url else "?"
    url += f"{sep}api_key={urllib.parse.quote(token)}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())
```

## Function Mapping

- `search_macro_series(query, limit)` -> `fred.search(...)`
- `get_macro_series(series_id, observation_start, units)` -> `fred.get_series(...)`
- `get_macro_series_info(series_id)` -> `fred.get_series_info(...)`
- `get_macro_releases()` -> `releases`
- `get_macro_release_dates(release_id)` -> `release/dates`
- `get_macro_series_updates(filter_value, limit)` -> `series/updates`

## Examples

```python
series_df = fred.search(
    "inflation",
    limit=10,
    order_by="search_rank",
    sort_order="desc",
)
meta = fred.get_series_info("CPIAUCSL")
obs = fred.get_series("CPIAUCSL", observation_start="2015-01-01", units="pc1")

# Endpoints not wrapped by fredapi: use direct proxy helper
releases = fred_proxy_get("releases", {})["releases"]
dates = fred_proxy_get("release/dates", {"release_id": 10})["release_dates"]
updates = fred_proxy_get("series/updates", {"filter_value": "macro", "limit": 100})["seriess"]
```

## Notes

- Use `GET` only.
- Keep `fred.root_url` overridden to the proxy base from `OPENROUTER_BASE_URL`.
- Keep results concise: process data in Python and print summarized outputs.
- Use `limit=` for list endpoints to avoid large responses.
