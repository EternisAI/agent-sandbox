---
name: wam
description: Search and discover articles from WAM (Emirates News Agency, wam.ae) — the official UAE federal news wire. Surfaces (1) Cabinet decisions, federal decrees, emiri decrees, ministerial actions, ruler's-office directives — every legally-binding UAE government instrument; (2) **CBUAE monetary policy** — every Central Bank base-rate decision (maintain / raise / cut) and policy announcement (GDP projections, regulatory launches) is published as a dated WAM wire article; (3) UAE / regional news the global wires miss. Use when the agent needs primary-source government evidence for the Authoritative-disclosure override rule, or for UAE-specific news. Returns article URLs + titles + dates; call `fetch_article_body(url)` to read full rendered bodies (routed through the backend Firecrawl proxy — wam.ae article pages are SPA-rendered, plain urllib returns only the shell).
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# WAM (Emirates News Agency)

WAM is the official news wire of the United Arab Emirates and the canonical record of three classes of primary-source government evidence:

1. **Legally-binding government instruments** — Cabinet decisions, federal decrees, federal laws, emiri decrees, ministerial resolutions, ruler's-office decisions across all seven emirates.
2. **CBUAE monetary policy** — every Central Bank of the UAE base-rate decision (maintain / raise / cut), GDP projection update, and policy announcement is published as a dated WAM article within hours of the decision. Empirically: 10 CBUAE-tagged articles across 2024 alone, including the September 2024 first cut and every meeting after. **For UAE rate decisions and monetary policy announcements, WAM is the canonical source. You do not need a separate CBUAE skill for these.**
3. **UAE / regional news** that global wires (Reuters, SeekingAlpha) cover thinly or not at all.

The wire publishes ~50–70 articles per day across 19 languages, with a public archive going back to January 2016.

This skill exposes **discovery** — searching and listing articles by date, title, and category — through WAM's public sitemap feeds (direct urllib, no auth). For full article bodies, use `fetch_article_body(url)`, which routes through the backend Firecrawl proxy (`PROXY_BASE_URL` / `PROXY_API_KEY`) — direct urllib on `/en/article/<slug>` returns only the SPA shell.

## When to pick this skill

Reach for `wam` directly (do not pre-route through `exa_search` or `search_news`)
for any of:

- **UAE Cabinet decisions, Federal Decrees, Emiri decrees, federal laws,
  ministerial appointments, ruler's-office directives.** WAM is the primary
  wire; global wires re-paraphrase it with a lag.
- **CBUAE base-rate decisions and monetary policy announcements.** Every CBUAE
  meeting outcome publishes here as a wire article with the exact rate and
  direction. **This is the canonical source — use this method first instead
  of attempting to scrape `centralbank.ae` or relying on Finnhub macro series
  (which lag UAE CPI/GDP by years).**
- **Sovereign / GRE actions** — ICD, ADQ, Mubadala, DEWA, DP World, Emirates
  Group, Emaar large-deal announcements when sourced from official channels.
- **UAE/regional context** that global financial wires (Reuters, SeekingAlpha,
  Bloomberg) underreport.

For non-UAE topics, US-listed names, or commodity/equity price data, stay on
the existing tools (`exa_search`, `search_news`, Finnhub, Massive).

## Authentication

- **Sitemap discovery** (every `search_*` / `list_*` method): no auth. WAM sitemaps are public; direct urllib from the sandbox.
- **Article body fetch** (`fetch_article_body`): routed through the backend Firecrawl proxy (`PROXY_BASE_URL` / `PROXY_API_KEY` from the sandbox env). No vendor key in the sandbox.

## Helper

```python
import json
import os
import urllib.request
import xml.etree.ElementTree as ET
import re
from datetime import datetime, timezone, timedelta

UA = "Mozilla/5.0 (compatible; AxionAgent/1.0)"

NS = {
    "sm": "http://www.sitemaps.org/schemas/sitemap/0.9",
    "image": "http://www.google.com/schemas/sitemap-image/1.1",
    "news": "http://www.google.com/schemas/sitemap-news/0.9",
}

def _fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def _firecrawl_proxy_base() -> str:
    return os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/firecrawl-proxy")


def _firecrawl_scrape(url: str, *, timeout_s: int = 90,
                      formats: list[str] | None = None,
                      only_main_content: bool = True,
                      wait_ms: int | None = None) -> str:
    """Scrape via the backend Firecrawl proxy. Returns the rendered body as a
    string (markdown by default). Used by fetch_article_body() — WAM article
    pages are SPA-rendered behind a cookie consent banner.

    `wait_ms` adds a Firecrawl `waitFor` after page load before serialization.
    WAM hydrates client-side; without a wait, Firecrawl returns either the SPA
    shell (`formats=["rawHtml"]`) or fails with SCRAPE_ALL_ENGINES_FAILED
    (`formats=["markdown"]`). fetch_article_body defaults to wait_ms=5000."""
    body: dict = {
        "url": url,
        "formats": formats or ["markdown"],
        "onlyMainContent": only_main_content,
        "timeout": (timeout_s - 10) * 1000,
    }
    if wait_ms:
        body["waitFor"] = wait_ms
    req = urllib.request.Request(
        _firecrawl_proxy_base().rstrip("/") + "/v1/scrape",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['PROXY_API_KEY']}",
            "Content-Type": "application/json",
            "User-Agent": UA,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as r:
        resp = json.loads(r.read().decode())
    if not resp.get("success"):
        raise RuntimeError(f"Firecrawl failed for {url}: {resp.get('error','no error msg')[:200]}")
    data = resp.get("data") or {}
    return data.get("markdown") or data.get("rawHtml") or ""
```

## Supported methods

| Method | Purpose | Cost |
| --- | --- | --- |
| `list_recent_news` | Pull the rolling ~48-hour daily news index | 1 sitemap fetch (~86KB) |
| `search_news` | Walk monthly sitemaps over a date window, filter by title regex | 1 fetch per month covered (~500KB–1MB each) |
| `search_news_with_filter` | Same, but takes a callable predicate instead of a regex (for composite filters) | same as `search_news` |
| `search_cabinet_decisions` | UAE government actions: Cabinet, decrees, laws, ministerial, ruler's office | same as `search_news` |
| **`search_cbuae_policy`** | **CBUAE monetary policy: base-rate decisions, GDP projections, regulatory announcements** | **same as `search_news`** |
| `list_categories` | List the WAM category taxonomy (from menu sitemap) | 1 fetch (~5KB) |
| `fetch_article_body` | Render the body of one article URL through the backend Firecrawl proxy | 1 Firecrawl scrape |

## Method signatures

```python
def list_recent_news(language: str = "en", query: str | None = None, limit: int = 50) -> list[dict]:
    """Rolling ~48-hour feed. language ∈ {en, ar, zh, de, es, fa, fr, hi, it, ru, pt, tr, ...}."""

def search_news(
    date_after: str,                  # "YYYY-MM-DD"
    date_before: str,                 # "YYYY-MM-DD"
    query: str | None = None,         # case-insensitive regex on title
    language: str = "en",
    limit: int = 100,
) -> list[dict]:
    """Walks monthly sitemaps from date_after through date_before, applies optional title regex."""

def search_cabinet_decisions(
    date_after: str,
    date_before: str,
    language: str = "en",
    limit: int = 100,
) -> list[dict]:
    """Convenience wrapper for search_news with a built-in Cabinet/decree regex."""

def search_cbuae_policy(
    date_after: str,
    date_before: str,
    language: str = "en",
    limit: int = 100,
) -> list[dict]:
    """Convenience wrapper: every CBUAE base-rate decision, GDP projection,
    and policy announcement in the window. Use this for UAE monetary policy
    questions — WAM publishes CBUAE rate decisions within hours of the meeting,
    making this the canonical source for the Authoritative-disclosure override
    on UAE rates and central bank policy."""

def list_categories(language: str = "en") -> list[str]:
    """Returns the WAM category slugs (business, markets, real-estate, oil-and-energy, ai, emirates-news, ...)."""

def fetch_article_body(url: str, *, only_main_content: bool = True,
                       wait_ms: int = 5000, timeout_s: int = 90) -> str:
    """Render the body of a single WAM article URL through the backend Firecrawl
    proxy. Returns the rendered markdown (`onlyMainContent=True` strips nav,
    header, footer, and the cookie banner). Use this AFTER any discovery method
    has surfaced a URL — direct urllib on `/en/article/<slug>` returns only the
    SPA shell, not the body.

    `wait_ms` (default 5000) is the Firecrawl `waitFor` delay between page load
    and serialization. WAM hydrates client-side; without this wait Firecrawl
    either returns the SPA shell or fails with SCRAPE_ALL_ENGINES_FAILED.
    Lower it only if you have measured 5s as too generous on a specific URL."""
```

## Return shape

Every method (except `list_categories`) returns a list of dicts:

```python
{
    "url": "https://www.wam.ae/en/article/<slug>",
    "title": "Article title verbatim from the sitemap",
    "published_date": "2026-06-09T15:32:40+04:00",   # ISO 8601 with timezone
    "image_url": "https://assets.wam.ae/resource/<id>.jpg",
    "language": "en",
}
```

The `published_date` field is always present from monthly sitemaps (`<lastmod>`) and from news sitemap (`<news:publication_date>`).

## Implementation

```python
def list_recent_news(language: str = "en", query: str | None = None, limit: int = 50):
    url = f"https://www.wam.ae/{language}/sitemap/news.xml"
    root = ET.fromstring(_fetch(url))
    pattern = re.compile(query, re.I) if query else None
    out = []
    for u in root.findall("sm:url", NS):
        title_el = u.find("news:news/news:title", NS) or u.find("image:image/image:title", NS)
        title = (title_el.text or "").strip() if title_el is not None else ""
        # Some sitemap entries ship without news:title AND image:title — skip
        # them. Otherwise they leak into results as empty-title rows and any
        # downstream regex/predicate either misclassifies them or excludes them
        # noisily.
        if not title:
            continue
        if pattern and not pattern.search(title):
            continue
        date_el = u.find("news:news/news:publication_date", NS)
        loc_el = u.find("sm:loc", NS)
        img_el = u.find("image:image/image:loc", NS)
        out.append({
            "url": loc_el.text if loc_el is not None else "",
            "title": title,
            "published_date": date_el.text if date_el is not None else "",
            "image_url": img_el.text if img_el is not None else "",
            "language": language,
        })
        if len(out) >= limit:
            break
    return out


def search_news(date_after: str, date_before: str, query: str | None = None,
                language: str = "en", limit: int = 100):
    d_after = datetime.strptime(date_after, "%Y-%m-%d").date()
    d_before = datetime.strptime(date_before, "%Y-%m-%d").date()
    pattern = re.compile(query, re.I) if query else None
    out = []

    # Walk one monthly sitemap per (year, month) in the window.
    cur = d_after.replace(day=1)
    while cur <= d_before:
        year, month = cur.year, cur.month
        url = f"https://www.wam.ae/{language}/sitemap/articles/{year}/{month}.xml"
        try:
            root = ET.fromstring(_fetch(url))
        except Exception:
            # Months before 2026 live under /archive/<year>.xml — try that index next.
            cur = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
            continue
        for u in root.findall("sm:url", NS):
            img_title_el = u.find("image:image/image:title", NS)
            title = img_title_el.text if img_title_el is not None and img_title_el.text else ""
            if not title:
                continue
            lastmod_el = u.find("sm:lastmod", NS)
            date_str = lastmod_el.text if lastmod_el is not None else ""
            try:
                article_date = datetime.fromisoformat(date_str.replace("Z", "+00:00")).date()
            except Exception:
                continue
            if not (d_after <= article_date <= d_before):
                continue
            if pattern and not pattern.search(title):
                continue
            loc_el = u.find("sm:loc", NS)
            img_el = u.find("image:image/image:loc", NS)
            out.append({
                "url": loc_el.text if loc_el is not None else "",
                "title": title,
                "published_date": date_str,
                "image_url": img_el.text if img_el is not None else "",
                "language": language,
            })
            if len(out) >= limit:
                return out
        cur = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
    return out


# Composite UAE-government predicate. Requires BOTH a UAE entity anchor
# (country, emirate, federal body, named leader) AND an action verb. Empirically
# tested on May 2026 (1,834 articles): same hit count as a single-regex action
# match (37), but with 16 false positives ("Belgian parliament approves...",
# "EU Council adopts...", foreign-government Minister meetings) dropped and 16
# real UAE actions previously missed (Sharjah Ruler laws, Mansour bin Zayed
# resolutions, UAE President policy directives) added.
_UAE_ENTITY = re.compile(
    r"\bUAE\b|\bEmirati(?:s)?\b|"
    r"\bDubai\b|\bAbu Dhabi\b|\bSharjah\b|\bAjman\b|\bRas Al Khaimah\b|"
    r"\bFujairah\b|\bUmm Al Quwain\b|\bRAK\b|\bUAQ\b|"
    r"\bFederal Decree\b|\bFederal Law\b|\bFederal Authority\b|\bFederal National Council\b|\bFNC\b|"
    r"\bCBUAE\b|"
    r"\bMohammed bin Rashid\b|\bMohamed bin Zayed\b|\bMBR\b|\bMBZ\b|"
    r"\bHamdan bin Mohammed\b|\bHamdan bin Zayed\b|\bMansour bin Zayed\b|"
    r"\bAbdullah bin Zayed\b|\bSaif bin Zayed\b|\bTahnoun bin Zayed\b|"
    r"\bKhaled bin Mohamed\b|\bSultan bin Mohammed\b|\bMaktoum bin Mohammed\b|"
    r"\bTheyab bin Mohamed\b|"
    r"\bCrown Prince of Abu Dhabi\b|"
    r"\bRuler of (?:Dubai|Sharjah|Ajman|Fujairah|Umm Al Quwain|Ras Al Khaimah)\b",
    re.I,
)
_UAE_ACTION = re.compile(
    r"\bCabinet\b|\bdecree\b|\bapproves\b|\badopts\b|\bratifies\b|\bissues\b|"
    r"\bdirects\b|\bministerial\b|\bMinister of\b|\bFederal Law\b|\bFederal Decree\b|"
    r"\bdecision\b|\bresolution\b|\bappoints\b|\bappointment\b",
    re.I,
)

def is_uae_gov_action(title: str) -> bool:
    """True iff the title names a UAE entity AND a government action verb.
    Use this as a custom filter argument when calling search_news_with_filter."""
    return bool(_UAE_ENTITY.search(title)) and bool(_UAE_ACTION.search(title))


def search_cabinet_decisions(date_after: str, date_before: str,
                              language: str = "en", limit: int = 100):
    """All UAE government actions in window: Cabinet decisions, Federal Decrees,
    Emiri Decrees, ministerial resolutions, ruler's-office directives. Uses the
    composite predicate above."""
    return search_news_with_filter(date_after, date_before,
                                    title_filter=is_uae_gov_action,
                                    language=language, limit=limit)


# CBUAE policy predicate. Any article that names the Central Bank of the UAE
# in the title is in scope — base-rate decisions, policy statements, GDP
# projection updates, regulatory announcements. Empirically validated across
# 2024 (10 hits including the full rate-cut sequence Sep/Nov/Dec 2024).
def is_cbuae_policy(title: str) -> bool:
    """True if the title names CBUAE (the Central Bank of the UAE).
    Catches every WAM-published CBUAE action including base-rate decisions,
    policy statements, projections, and regulatory launches."""
    return bool(re.search(r"\bCBUAE\b|\bCentral Bank of the UAE\b", title, re.I))


def search_cbuae_policy(date_after: str, date_before: str,
                         language: str = "en", limit: int = 100):
    """CBUAE monetary policy events in window: every base-rate decision
    (maintain / raise / cut), GDP projection update, and major policy
    announcement. WAM is the canonical wire for these — published within
    hours of each CBUAE meeting. Use this directly for UAE rate-decision
    questions instead of trying to scrape the CBUAE website."""
    return search_news_with_filter(date_after, date_before,
                                    title_filter=is_cbuae_policy,
                                    language=language, limit=limit)


def search_news_with_filter(date_after: str, date_before: str,
                             title_filter, language: str = "en", limit: int = 100):
    """Like search_news but takes a callable `title_filter(title) -> bool`
    instead of a regex. Use for composite predicates like is_uae_gov_action."""
    d_after = datetime.strptime(date_after, "%Y-%m-%d").date()
    d_before = datetime.strptime(date_before, "%Y-%m-%d").date()
    out = []
    cur = d_after.replace(day=1)
    while cur <= d_before:
        year, month = cur.year, cur.month
        url = f"https://www.wam.ae/{language}/sitemap/articles/{year}/{month}.xml"
        try:
            root = ET.fromstring(_fetch(url))
        except Exception:
            cur = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
            continue
        for u in root.findall("sm:url", NS):
            img_title_el = u.find("image:image/image:title", NS)
            title = img_title_el.text if img_title_el is not None and img_title_el.text else ""
            if not title:
                continue
            lastmod_el = u.find("sm:lastmod", NS)
            date_str = lastmod_el.text if lastmod_el is not None else ""
            try:
                article_date = datetime.fromisoformat(date_str.replace("Z", "+00:00")).date()
            except Exception:
                continue
            if not (d_after <= article_date <= d_before):
                continue
            if not title_filter(title):
                continue
            loc_el = u.find("sm:loc", NS)
            img_el = u.find("image:image/image:loc", NS)
            out.append({
                "url": loc_el.text if loc_el is not None else "",
                "title": title,
                "published_date": date_str,
                "image_url": img_el.text if img_el is not None else "",
                "language": language,
            })
            if len(out) >= limit:
                return out
        cur = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
    return out


def list_categories(language: str = "en"):
    url = f"https://www.wam.ae/{language}/sitemap/menu.xml"
    root = ET.fromstring(_fetch(url))
    cats = []
    for u in root.findall("sm:url", NS):
        loc = u.find("sm:loc", NS)
        if loc is None or loc.text is None:
            continue
        m = re.search(rf"/{language}/category/([a-z0-9-]+)$", loc.text)
        if m:
            cats.append(m.group(1))
    return sorted(set(cats))


def fetch_article_body(url: str, *, only_main_content: bool = True,
                       wait_ms: int = 5000, timeout_s: int = 90) -> str:
    return _firecrawl_scrape(url, formats=["markdown"],
                             only_main_content=only_main_content,
                             wait_ms=wait_ms, timeout_s=timeout_s)
```

## Examples

### Latest Cabinet decisions in the last 48 hours

```python
recent = list_recent_news(language="en", query=r"Cabinet|decree|approves|adopts", limit=20)
for r in recent:
    print(f"{r['published_date'][:10]}  {r['title']}")
    print(f"    {r['url']}")
```

### All UAE government actions in May–June 2026

`search_cabinet_decisions` uses the composite `is_uae_gov_action` predicate
(UAE entity anchor AND action verb), so foreign-government actions like
"Belgian parliament approves..." are excluded automatically.

```python
hits = search_cabinet_decisions(date_after="2026-05-01", date_before="2026-06-09", language="en", limit=50)
print(f"Found {len(hits)} UAE-government actions in window")
for h in hits[:10]:
    print(f"  {h['published_date'][:10]}  {h['title']}")
```

### CBUAE monetary policy across a full year (rate decisions, projections)

WAM publishes every CBUAE base-rate decision as a wire article within hours
of the meeting — including the precise rate level and direction. Across 2024
this surfaces the complete rate trajectory: hold sequence, the September 2024
first cut, and the subsequent November and December cuts. Use this **directly**
for any UAE monetary policy question. Do NOT try to scrape the CBUAE website
when the wire already has the dated decision text.

```python
hits = search_cbuae_policy(date_after="2024-01-01", date_before="2024-12-31",
                            language="en", limit=100)
for h in hits:
    print(f"  {h['published_date'][:10]}  {h['title']}")
```

This single call surfaces **82 CBUAE-tagged articles for 2024 alone**
(empirically validated 2026-06-09). Coverage spans seven distinct categories
that an agent answering UAE macro / banking questions needs:

1. **Rate decisions** — every meeting, with the exact rate level in the title.
   2024 trajectory: Jan/May/Jun/Jul hold at 5.40%, Sept –50bp, Nov –25bp,
   Dec –25bp. 2025 maintains at 4.40% (Jan, Mar). Jan 2026 maintains at 3.65%.
2. **Monetary & banking statistical bulletin** — recurring announcement of
   each monthly update ("CBUAE issues monetary and banking developments -
   December 2023" etc.). The title-with-month tells the agent when the
   official bulletin published.
3. **Balance sheet and banking sector aggregates** — published with the
   actual numbers in the title:
   - "CBUAE's balance sheet hits AED750 billion, surges 32.5% annually"
   - "Gross banks' assets exceed AED4.4 trillion by end of September: CBUAE"
   - "Bank investments in monetary bills, Islamic CD hit AED226.9 billion"
4. **Insurance sector data** — "Gross written premiums increased by 18.5%
   Y-o-Y in Q1 2024 to AED21.1 billion: CBUAE", quarterly cadence.
5. **GDP projections** — "CBUAE revises upwards its GDP growth projection
   for 2024 to 4%; 6% for 2025" and the periodic re-affirmations.
6. **Gold reserves** — "CBUAE's gold reserves up 7% YoY", "CBUAE's gold
   reserves surpass AED23 billion by end of Q3/24".
7. **Regulatory enforcement, fintech policy, bilateral MoUs** —
   sanctions, licence revocations, mBridge/Aperta/sandbox launches, AI
   guidance notes, currency-swap agreements with HKMA, Bank of Finland,
   Tajikistan central bank, Hong Kong Monetary Authority.

**Implication for the agent:** for most UAE central-bank questions the title
text alone carries the load-bearing datum (rate, growth %, sector aggregate
in AED billion). Body extraction via `fetch_article_body(url)` is only needed
when the agent wants the full vote language, the regulatory statement text,
or detailed methodology — not for the headline number, which is in the
title.

### Strict-binding-decisions only (custom predicate)

If you want only legally-binding instruments (federal decrees, federal laws,
Cabinet decisions, emiri decrees) and not softer actions like diplomatic
statements or ministerial appointments, pass a custom predicate:

```python
def is_binding_instrument(title: str) -> bool:
    if not _UAE_ENTITY.search(title):
        return False
    return bool(re.search(
        r"\bFederal Decree\b|\bFederal Law\b|\bissues decree\b|"
        r"\bissues law\b|\bCabinet (?:approves|adopts|decides)\b|"
        r"\bEmiri Decree\b|\bratifies\b",
        title, re.I))

binding = search_news_with_filter("2026-01-01", "2026-06-09",
                                    title_filter=is_binding_instrument,
                                    language="en", limit=30)
for h in binding:
    print(f"  {h['published_date'][:10]}  {h['title']}")
```

### Topical search — "Agentic AI" framework adoption by UAE government

```python
hits = search_news(date_after="2026-01-01", date_before="2026-06-09",
                   query=r"AI|artificial intelligence|agentic", language="en", limit=30)
for h in hits:
    print(f"  {h['published_date'][:10]}  {h['title']}")
```

### Read the body of a Cabinet decision

Discovery (`search_*` / `list_*`) returns URLs only. Body extraction is
`fetch_article_body(url)`, which routes through the backend Firecrawl proxy
to handle cookie consent + SPA hydration that direct urllib cannot satisfy.

```python
# Step 1: discovery — get the URL and title
hits = search_cabinet_decisions(date_after="2026-05-01", date_before="2026-05-31")
cabinet_ai = next((h for h in hits if "Agentic AI" in h["title"]), None)

# Step 2: render the body (one Firecrawl proxy call). Returns markdown.
body = fetch_article_body(cabinet_ai["url"])
print(body[:500])
```

### List available categories

```python
print(list_categories(language="en"))
# ['ai', 'business', 'culture', 'cyber-security', 'emirates-news', 'football',
#  'international', 'investment', 'markets', 'oil-and-energy', 'real-estate',
#  'science-and-technology', 'space', 'sport', 'tolerance', 'tourism', ...]
```

## Coverage notes

- **Languages.** Sitemap is published in 19 languages: `en, ar, bn, zh, de, es, fa, fr, he, hi, id, it, ml, ps, pt, ru, si, tr, ur`. Default to `en`. Pass `language="ar"` only when the agent specifically needs the Arabic original for legal-canon citation; Arabic article slugs are Arabic strings, not transliterated, so cross-language slug matching is not trivial.
- **Archive depth.** The monthly URL pattern `/<lang>/sitemap/articles/<year>/<month>.xml` works back to **January 2016**, verified live across 2016, 2017, 2020, 2022, 2024, 2025, 2026. The `search_news` and `search_news_with_filter` walkers above already handle any year in that range without modification. WAM also publishes an alternative yearly-rollup index at `/<lang>/sitemap/articles/archive/<year>.xml` (one XML per year, indexed via `/<lang>/sitemap/articles/archive.xml`) — use this only when fetching an entire year in one call is cheaper than walking 12 months individually.
- **Daily volume.** 50–70 articles per day in 2026; ~30/day in 2020. A single monthly sitemap can be 500KB–1MB and 1,500–2,000 entries — parse it once and filter, do not refetch per query.
- **Cabinet-decision quality.** Title filter alone catches all Cabinet meetings (the wire publishes a dedicated "UAE Cabinet, chaired by Mohammed bin Rashid, approves …" article for every meeting), Federal Decrees by the President, Emiri Decrees by the rulers of the seven emirates, ministerial appointments, and named economic-package approvals. Empirically validated on May 2026 sitemap data.

## Usage rules

- **No auth on sitemaps.** Discovery methods (`list_recent_news`, `search_*`, `list_categories`) fetch public sitemaps with direct urllib — do not add `Authorization` or `X-API-Key` headers.
- **Always pass a date window** to `search_news` / `search_cabinet_decisions`. Walking many months unfiltered will pull megabytes for no reason. For "recent" use `list_recent_news` (one fetch, last ~48 hours).
- **Title filtering is regex, case-insensitive.** Combine alternatives with `|`. The skill does not have full-text body search — only title. If the agent needs to search inside article text, call `fetch_article_body(url)` on the candidates and grep locally.
- **Always use `fetch_article_body(url)` for body extraction.** Direct urllib fetch of `/en/article/<slug>` returns only the SPA shell; the body is JS-rendered behind a cookie consent banner. `fetch_article_body` routes the URL through the backend Firecrawl proxy (no vendor key in the sandbox; requires `PROXY_BASE_URL` + `PROXY_API_KEY` env vars, which are always present in agent sessions).
- **Cite the WAM URL inline as `[N](url)`.** WAM is a primary government wire (Tier-1 source per the coordinator's "Authoritative-disclosure override" rule), so cabinet-decision and federal-decree articles can anchor load-bearing claims directly — no need to cross-verify with secondary press for the existence of the act.
- **Quote the timestamp.** WAM publish times are precise to the second with timezone (e.g. `2026-06-09T15:32:40+04:00`). Always include the date in the synthesis next to any claim sourced here; the override rule depends on the disclosure bracketing the resolution window.
- **Rate limits.** None observed against the sitemap endpoints. The polite default is one request per second; if you are walking 6+ months in one call, add `time.sleep(0.5)` between fetches.
