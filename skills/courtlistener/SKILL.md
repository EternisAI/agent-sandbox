---
name: courtlistener
description: Search US federal court dockets and filings, and retrieve full case details via CourtListener. Use when users ask about litigation risk, active lawsuits, securities fraud complaints, bankruptcy filings, or legal exposure for companies or executives.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# CourtListener API (via proxy)

Use direct HTTP requests through the backend CourtListener proxy. Do not use raw vendor API keys.

## Authentication and Proxy Base

```python
import os
import urllib.parse
import urllib.request
import json

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/courtlistener-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def cl_get(path: str, params: dict | None = None) -> dict:
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())
```

## Supported Tools

| Tool | Endpoint | What it returns |
| --- | --- | --- |
| `search_court_dockets` | `GET /search/?type=d` | Federal case metadata — case name, court, dates, judge, nature of suit |
| `search_court_documents` | `GET /search/?type=rd` | PACER filing snippets with highlighted matches |
| `search_court_semantic` | `GET /search/?type=o&semantic=true` | Case law opinions via natural language — useful for precedent research |
| `get_docket` | `GET /dockets/{id}/` | Full structured docket record for a specific case |

## Examples

```python
def search_court_dockets(q: str, page_size: int = 10, order_by: str = "dateFiled desc") -> list:
    """Search federal dockets by company name, case type, or keywords."""
    r = cl_get("/search/", {"type": "d", "q": q, "page_size": page_size, "order_by": order_by})
    return r.get("results", [])

def search_court_documents(q: str, page_size: int = 10) -> list:
    """Full-text search across PACER filings — returns snippets with highlighted matches."""
    r = cl_get("/search/", {"type": "rd", "q": q, "page_size": page_size})
    return r.get("results", [])

def search_court_semantic(q: str, page_size: int = 10) -> list:
    """Natural language search across case law opinions. Use for precedent research."""
    r = cl_get("/search/", {"type": "o", "semantic": "true", "q": q, "page_size": page_size})
    return r.get("results", [])

def get_docket(docket_id: int) -> dict:
    """Get full structured record for a specific case by docket ID."""
    return cl_get(f"/dockets/{docket_id}/")
```

### Company Litigation Search

```python
import os, urllib.parse, urllib.request, json

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/courtlistener-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def cl_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

company = "Tesla Inc"
results = cl_get("/search/", {"type": "d", "q": company, "page_size": 10, "order_by": "dateFiled desc"})
for r in results.get("results", []):
    status = "ACTIVE" if not r.get("dateTerminated") else f"closed {r['dateTerminated']}"
    print(f"[{r['docket_id']}] {r['caseName']} | {r['dateFiled']} | {r.get('suitNature', '')} | {status}")
```

### Filing Text Search

```python
import os, urllib.parse, urllib.request, json

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/courtlistener-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def cl_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

results = cl_get("/search/", {"type": "rd", "q": "Tesla securities fraud", "page_size": 5})
for r in results.get("results", []):
    snippet = r.get("snippet", "").replace("<mark>", "**").replace("</mark>", "**")
    print(f"[docket {r['docket_id']}] {r['description'][:80]}")
    print(f"  Filed: {r['entry_date_filed']} | {snippet[:200]}")
    print()
```

### Get Case Detail

```python
import os, urllib.parse, urllib.request, json

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/courtlistener-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def cl_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "curl/7.88.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())

docket_id = 67687667  # from search results
d = cl_get(f"/dockets/{docket_id}/")
print(f"Case: {d['case_name']}")
print(f"Docket: {d['docket_number']} | Court: {d['court_id']}")
print(f"Filed: {d['date_filed']} | Terminated: {d.get('date_terminated', 'ACTIVE')}")
print(f"Cause: {d.get('cause', '')} | Nature: {d.get('nature_of_suit', '')}")
print(f"Judge: {d.get('assigned_to_str', 'N/A')} | Jury demand: {d.get('jury_demand', 'N/A')}")
```

## Notes

- `order_by` on search uses `"field direction"` format: `dateFiled desc`, `dateFiled asc`, `score desc`, `entry_date_filed desc`
- Search results are cached for **10 minutes** — not real-time
- `type=d` result counts have ±6% error above 2,000 results
- `search_court_semantic` searches **case law opinions only** — not dockets or filings
- Search field names are camelCase (`caseName`, `dateFiled`); docket API fields are snake_case (`case_name`, `date_filed`)
- Rate limit: 5,000 req/hour — HTTP 429 on breach
- US federal courts only — no state courts, no arbitration
