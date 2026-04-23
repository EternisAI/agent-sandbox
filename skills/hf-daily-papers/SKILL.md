---
name: hf-daily-papers
description: Fetch and search AI research papers from Hugging Face — today's curated daily feed, full paper metadata, and semantic search across the HF corpus. Use when users ask about trending AI papers, specific arXiv papers, recent ML research, or want to search by topic.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Hugging Face Papers API

## Authentication

```python
import urllib.parse
import urllib.request
import json
import os

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/hf-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def hf_get(path: str, params: dict | None = None) -> dict | list:
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "User-Agent": "axion-hf-client/1.0",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())
```

## Supported Tools

| Tool | Endpoint | What it returns |
| --- | --- | --- |
| `get_daily_papers` | `GET /api/daily_papers` | Community-curated papers with upvotes for a given date |
| `get_paper_details` | `GET /api/papers/{paper_id}` | Full metadata for any HF-indexed paper by arXiv ID |
| `search_hf_papers` | `GET /api/papers/search` | Semantic search across all HF-indexed papers |

## Call Graph

```
1. get_daily_papers    date / sort       → paper list (github/project data included when present)
   search_hf_papers    query             → paper list across full HF corpus

2. get_paper_details   arxiv_id          → single paper deep-dive; use for direct arXiv ID lookups
```

## Triage Field Set

```
paper.id            → bare arXiv ID (e.g. 2307.09288)
paper.title         → paper title
paper.upvotes       → community upvote count
paper.publishedAt   → arXiv publication date
paper.ai_summary    → AI-generated summary (prefer over raw abstract)
paper.ai_keywords   → topic tags e.g. ["reasoning", "agents", "vision"]
paper.githubRepo    → linked GitHub repo URL (nullable)
paper.githubStars   → GitHub stars at submission time (nullable)
paper.projectPage   → demo/project URL — productization signal (nullable)
submittedBy.name    → curator name — credibility signal (daily feed only)
```

## Examples

### Today's Trending Papers

```python
import urllib.parse, urllib.request, json, os

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/hf-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def hf_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "axion-hf-client/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

papers = hf_get("/api/daily_papers", {"limit": 20, "sort": "trending"})
for item in papers:
    p = item["paper"]
    repo = f" | repo={p['githubRepo']}" if p.get("githubRepo") else ""
    stars = f" ⭐{p['githubStars']}" if p.get("githubStars") else ""
    print(f"[{p['upvotes']}↑] {p['title']}{repo}{stars}")
    if p.get("ai_summary"):
        print(f"  {p['ai_summary'][:120]}...")
```

### Paper Details by arXiv ID

```python
import urllib.parse, urllib.request, json, os

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/hf-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def hf_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "axion-hf-client/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

arxiv_id = "2307.09288"  # bare arXiv ID — no prefix, no URL
p = hf_get(f"/api/papers/{arxiv_id}")

print(f"{p['title']} ({p['publishedAt'][:10]})")
print(f"Upvotes: {p['upvotes']}")
print(f"Keywords: {', '.join(p.get('ai_keywords', []))}")
print(f"Summary: {p.get('ai_summary', 'N/A')}")
print(f"GitHub: {p.get('githubRepo', 'none')} ({p.get('githubStars', 0)} stars)")
print(f"Project: {p.get('projectPage', 'none')}")
authors = [a['name'] for a in p.get('authors', [])]
print(f"Authors: {', '.join(authors[:5])}")
```

### Search by Topic

```python
import urllib.parse, urllib.request, json, os

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/hf-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def hf_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "axion-hf-client/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

results = hf_get("/api/papers/search", {"q": "agentic reasoning tool use", "limit": 10})
for item in results:
    p = item["paper"]
    demo = " [has demo]" if p.get("projectPage") else ""
    code = " [has code]" if p.get("githubRepo") else ""
    print(f"[{p['upvotes']}↑] {p['title']}{demo}{code}")
    print(f"  {p.get('ai_summary', '')[:100]}...")
```

### Papers for a Specific Date

```python
import urllib.parse, urllib.request, json, os

base = os.environ["OPENROUTER_BASE_URL"].replace("/api/llm-proxy", "/api/hf-proxy")
token = os.environ["OPENROUTER_API_KEY"]

def hf_get(path, params=None):
    url = f"{base.rstrip('/')}/{path.lstrip('/')}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "axion-hf-client/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

papers = hf_get("/api/daily_papers", {"date": "2026-04-21", "limit": 50, "sort": "trending"})
if not papers:
    print("No papers — likely a weekend date")
else:
    for item in papers:
        p = item["paper"]
        print(f"[{p['upvotes']}↑] {p['id']} — {p['title']}")
```

## Gotchas

- **Weekdays only** — weekend dates return an empty list, not an error. Check the day before retrying.
- **`sort=trending` preferred** — ranks by upvote velocity, not raw count. Better signal than `publishedAt`.
- **`upvotes` is nested** — access as `item["paper"]["upvotes"]`, not `item["upvotes"]`.
- **Bare arXiv ID only** for `get_paper_details` — no `arxiv.org`, `abs/`, or `https://` prefix.
- **GitHub/project fields are conditional** — absent means genuinely not set; no endpoint will surface them if the paper has no linked repo.
- **`ai_summary` over `summary`** — AI summary is more useful than the raw abstract for downstream consumption.
- **`githubStars` is a snapshot** — cached at HF submission time, may be stale.
- **`projectPage` is a strong signal** — only papers with active demos fill this field. Rare = productization signal.
- **HF corpus only for search** — not all arXiv papers are indexed. Coverage is strong for ML/AI. For full academic coverage use Semantic Scholar.
- **Call `get_daily_papers` once per conversation** — returns up to 100 papers per call; no need to repeat.
- **HTTP 429 has no `Retry-After`** — use exponential backoff: `min(2^attempt, 60)` seconds.

## Usage Rules

- Use `get_daily_papers` for recency/trending; use `search_hf_papers` when the user has a topic.
- Always null-check `githubRepo`, `githubStars`, and `projectPage` before using.
- Use `ai_summary` and `ai_keywords` for triage — faster and cleaner than raw abstracts.
- For direct arXiv ID lookups or deep-dives, use `get_paper_details` — it covers the full HF corpus, not just the daily feed.
- Rate limit: 1,000 req / 5 min (authenticated free tier). Sufficient for all agentic use cases.
