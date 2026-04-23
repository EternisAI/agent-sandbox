---
name: semantic-scholar
description: Search and retrieve academic papers, authors, citations, and semantic recommendations from Semantic Scholar (220M+ papers). Use when users ask about research papers, academic citations, author credentials, scientific literature, technology emergence, or whitespace discovery.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Semantic Scholar API

Call the S2 API directly — no auth required for the unauthenticated tier (5,000 req/5min **shared globally across all anonymous users**).

> **⚠️ Rate limiting is a near-certainty in multi-step agent workflows.** The unauthenticated pool is shared worldwide and saturates unpredictably — well below the stated limit under load. Agents will fail silently without retry logic. Exponential backoff is a **policy requirement**, not a suggestion — S2 explicitly mandates it in their API release notes. The helpers below bake it in; always use them.

**Base URL:** `https://api.semanticscholar.org`

## Helper Functions

Retry and backoff are built in — HTTP 429 retries up to 5 times with `min(2^attempt, 60)` second waits.

```python
import time
import urllib.error
import urllib.parse
import urllib.request
import json

BASE = "https://api.semanticscholar.org"

def _do(req: urllib.request.Request, max_attempts: int = 5) -> dict:
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == max_attempts - 1:
                raise
            time.sleep(min(2 ** attempt, 60))
    raise RuntimeError("unreachable")

def s2_get(path: str, params: dict | None = None) -> dict:
    url = f"{BASE}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return _do(urllib.request.Request(url, headers={"User-Agent": "axion-s2-client/1.0"}))

def s2_post(path: str, body: dict, params: dict | None = None) -> dict:
    url = f"{BASE}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode()
    return _do(urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", "User-Agent": "axion-s2-client/1.0"}))
```

## Supported Tools

| Tool | Method | Endpoint | What it returns |
| --- | --- | --- | --- |
| `search_papers_bulk` | GET | `/graph/v1/paper/search/bulk` | Boolean search — no result cap, token pagination, sort by citationCount |
| `get_paper` | GET | `/graph/v1/paper/{id}` | Full paper: citation counts, influential citations, tldr, authors, venue |
| `get_papers_batch` | POST | `/graph/v1/paper/batch` | Up to 500 papers in one call — same fields as single paper |
| `get_paper_citations` | GET | `/graph/v1/paper/{id}/citations` | Incoming citations with intent labels and influence flag |
| `get_paper_references` | GET | `/graph/v1/paper/{id}/references` | Outgoing references — prior art and intellectual lineage |
| `search_authors` | GET | `/graph/v1/author/search` | Find authors by name — required first step before get_author |
| `get_author` | GET | `/graph/v1/author/{id}` | Author h-index, citation count, paper count, affiliations |
| `get_author_papers` | GET | `/graph/v1/author/{id}/papers` | Author's paper history and output trajectory |
| `get_authors_batch` | POST | `/graph/v1/author/batch` | Up to 1,000 authors in one call |
| `get_recommendations` | POST | `/recommendations/v1/papers/` | Multi-seed semantic similarity — finds papers keyword search misses |

## Call Graph

```
1. search_papers_bulk    query (boolean)      → paper list sorted by citationCount
   get_recommendations   [positive, negative] → semantically similar papers

2. get_paper             paperId / ArXiv ID   → full details incl. influential citations + tldr
   get_papers_batch      [paperIds]           → up to 500 papers in one call

3. get_paper_citations   paperId              → incoming citations with intent + influence
   get_paper_references  paperId              → outgoing references (prior art)

4. search_authors        name                 → authorId
   get_author            authorId             → h-index, citation count, affiliations
   get_author_papers     authorId             → paper history + trajectory
   get_authors_batch     [authorIds]          → up to 1,000 authors in one call
```

## Triage Field Set

```
paperId,title,year,publicationDate,citationCount,influentialCitationCount,
fieldsOfStudy,authors,venue,tldr,isOpenAccess
```

Use `tldr` for fast bulk triage. Filter by `influentialCitationCount` to cut noise. Sort bulk search by `citationCount DESC` + filter `year="2023-"` for momentum — `citationVelocity` is website-only and not available via API.

## Examples

### Bulk Paper Search

```python
import time, urllib.error, urllib.parse, urllib.request, json

BASE = "https://api.semanticscholar.org"

def _do(req, max_attempts=5):
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == max_attempts - 1: raise
            time.sleep(min(2 ** attempt, 60))

def s2_get(path, params=None):
    url = f"{BASE}/{path.lstrip('/')}"
    if params: url += "?" + urllib.parse.urlencode(params)
    return _do(urllib.request.Request(url, headers={"User-Agent": "axion-s2-client/1.0"}))

# Boolean query — no result cap, sorted by citation count
r = s2_get("/graph/v1/paper/search/bulk", {
    "query": '+"protein diffusion" +(generation | design)',
    "fields": "paperId,title,year,publicationDate,citationCount,influentialCitationCount,authors",
    "minCitationCount": 10,
    "year": "2022-",
    "sort": "citationCount:desc",
})
for p in r.get("data", []):
    print(f"[{p['citationCount']}c / {p['influentialCitationCount']}i] {p['title']} ({p['year']})")

# Paginate — pass token from response
next_token = r.get("token")
# if next_token: repeat with params["token"] = next_token
```

### Paper Details + Citations

```python
import time, urllib.error, urllib.parse, urllib.request, json

BASE = "https://api.semanticscholar.org"

def _do(req, max_attempts=5):
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == max_attempts - 1: raise
            time.sleep(min(2 ** attempt, 60))

def s2_get(path, params=None):
    url = f"{BASE}/{path.lstrip('/')}"
    if params: url += "?" + urllib.parse.urlencode(params)
    return _do(urllib.request.Request(url, headers={"User-Agent": "axion-s2-client/1.0"}))

paper_id = "ARXIV:1706.03762"

# Full details
p = s2_get(f"/graph/v1/paper/{paper_id}", {
    "fields": "title,year,citationCount,influentialCitationCount,tldr,publicationVenue,externalIds"
})
print(f"{p['title']} ({p['year']})")
print(f"Citations: {p['citationCount']} total / {p['influentialCitationCount']} influential")
print(f"tldr: {(p.get('tldr') or {}).get('text', 'N/A')}")

# Incoming citations with intent
cites = s2_get(f"/graph/v1/paper/{paper_id}/citations", {
    "fields": "intents,isInfluential,citingPaper.title,citingPaper.year",
    "limit": 50,
})
methodology = [c for c in cites.get("data", []) if "methodology" in c.get("intents", [])]
print(f"\nMethodology citations (operational adoption): {len(methodology)}")
for c in methodology[:5]:
    cp = c.get("citingPaper", {})
    print(f"  {cp.get('title', '')} ({cp.get('year', '')})")
```

### Author Diligence

```python
import time, urllib.error, urllib.parse, urllib.request, json

BASE = "https://api.semanticscholar.org"

def _do(req, max_attempts=5):
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == max_attempts - 1: raise
            time.sleep(min(2 ** attempt, 60))

def s2_get(path, params=None):
    url = f"{BASE}/{path.lstrip('/')}"
    if params: url += "?" + urllib.parse.urlencode(params)
    return _do(urllib.request.Request(url, headers={"User-Agent": "axion-s2-client/1.0"}))

# Step 1: resolve name -> authorId
candidates = s2_get("/graph/v1/author/search", {
    "query": "Andrej Karpathy",
    "fields": "name,hIndex,citationCount,affiliations",
    "limit": 3,
})
for a in candidates.get("data", []):
    print(f"[{a['authorId']}] {a['name']} | h={a['hIndex']} | {a.get('affiliations', [])}")

# Step 2: full profile
author_id = candidates["data"][0]["authorId"]
author = s2_get(f"/graph/v1/author/{author_id}", {
    "fields": "name,hIndex,citationCount,paperCount,affiliations"
})
print(f"\n{author['name']}: h-index={author['hIndex']}, citations={author['citationCount']}")

# Step 3: recent papers
papers = s2_get(f"/graph/v1/author/{author_id}/papers", {
    "fields": "title,year,citationCount,venue",
    "limit": 5,
})
for p in papers.get("data", []):
    print(f"  {p['year']} [{p['citationCount']}c] {p['title']}")
```

### Batch Lookups

```python
import time, urllib.error, urllib.parse, urllib.request, json

BASE = "https://api.semanticscholar.org"

def _do(req, max_attempts=5):
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == max_attempts - 1: raise
            time.sleep(min(2 ** attempt, 60))

def s2_post(path, body, params=None):
    url = f"{BASE}/{path.lstrip('/')}"
    if params: url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode()
    return _do(urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", "User-Agent": "axion-s2-client/1.0"}))

# Up to 500 papers — fields as query param, ids in body
papers = s2_post(
    "/graph/v1/paper/batch",
    body={"ids": ["ARXIV:1706.03762", "ARXIV:2005.14165"]},
    params={"fields": "title,year,citationCount,influentialCitationCount,tldr"},
)
for p in papers:
    print(f"[{p['paperId']}] {p['title']} ({p['year']}) [{p['citationCount']}c]")

# Up to 1,000 authors — same pattern
authors = s2_post(
    "/graph/v1/author/batch",
    body={"ids": ["1741101", "1701686"]},
    params={"fields": "name,hIndex,citationCount,affiliations"},
)
for a in authors:
    print(f"{a['name']} h={a['hIndex']} cites={a['citationCount']}")
```

### Semantic Recommendations

```python
import time, urllib.error, urllib.parse, urllib.request, json

BASE = "https://api.semanticscholar.org"

def _do(req, max_attempts=5):
    for attempt in range(max_attempts):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == max_attempts - 1: raise
            time.sleep(min(2 ** attempt, 60))

def s2_post(path, body, params=None):
    url = f"{BASE}/{path.lstrip('/')}"
    if params: url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode()
    return _do(urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", "User-Agent": "axion-s2-client/1.0"}))

# positivePaperIds/negativePaperIds must be S2 SHA IDs — ARXIV: prefix not accepted here
# fields and limit go in query params, not the body
r = s2_post(
    "/recommendations/v1/papers/",
    body={
        "positivePaperIds": ["204e3073870fae3d05bcbc2f6a8e263d9b72e776"],
        "negativePaperIds": ["90abbc2cf38462b954ae1b772fac9532e2ccd8b0"],
    },
    params={"fields": "title,year,citationCount,influentialCitationCount", "limit": 20},
)
for p in r.get("recommendedPapers", []):
    print(f"[{p['citationCount']}c] {p['title']} ({p['year']})")
```

## Gotchas

- Default response returns only `paperId` and `title` — always specify `fields`.
- `tldr` is **not supported on bulk search or recommendations** — returns an error. Fetch `tldr` via `/paper/{id}` or batch after narrowing.
- `citationVelocity` is **not in the API** — website-only field. Compute from `citationCount` + `publicationDate`.
- `corpusId` (integer) is the stable ID for persistent storage — prefer over `paperId` (SHA).
- `abstract` may be null — Springer journals block abstract delivery.
- Bulk search uses token pagination only — pass `token` from response back as query param. `null` token = end of results.
- `search_papers_bulk` is the heaviest endpoint — it saturates the shared pool more than any other call. Always add a delay (≥10s) before the next request after a bulk search to avoid exhausting all retry attempts.
- **Batch and recommendations POST endpoints:** `fields` and `limit` must be query params, not in the request body. Body takes only `ids` / `positivePaperIds` / `negativePaperIds`.
- **Recommendations:** only accepts S2 SHA IDs — `ARXIV:` and other prefixes return 400.
- Author `affiliations` is self-reported — may be stale.
- Author `hIndex` and `citationCount` may undercount if early-career papers predate S2 corpus coverage.
- Recommendations `from` param: `recent` (default) or `all-cs` — `all-cs` limits to CS corpus only. Max 500 results.
- Max 1,000 citations/references per call — use offset pagination for high-citation papers.
- HTTP 429 has no `Retry-After` header and no gradual degradation — the pool cuts off hard. The helpers above retry with `min(2^attempt, 60)` second backoff; always use them rather than calling `urlopen` directly.

## Key Signals

| Signal | Calculation | Meaning |
| --- | --- | --- |
| **Momentum** | `citationCount` + `publicationDate` | Sort bulk by `citationCount DESC`, filter `year="2023-"` for fast-rising recent papers |
| **Influence density** | `influentialCitationCount / citationCount` | Quality filter — foundational vs frequently-mentioned |
| **Operational adoption** | `methodology` intent citations | Paper being used as a method, not just cited |
| **Team credibility** | Author `hIndex` + `citationCount` | Research track record for founding team diligence |
| **Field emergence** | Bulk search sorted by `citationCount`, filtered `year="2023-"` | Fast-rising new subfields |

## Usage Rules

- Always specify `fields` — default responses return only `paperId` and `title`.
- Use `search_papers_bulk` for systematic sweeps; use `get_recommendations` for whitespace discovery after seed papers are identified.
- Resolve author names via `search_authors` before fetching profiles — author IDs are not derivable from names.
- Always use the `_do`-based helpers — never call `urlopen` directly. The shared unauthenticated pool saturates unpredictably; agents will fail silently without built-in retry.
