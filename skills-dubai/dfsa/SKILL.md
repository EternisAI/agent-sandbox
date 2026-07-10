---
name: dfsa
description: Search Dubai Financial Services Authority (DFSA) news, enforcement actions, regulatory notices, and decision-notice PDFs — the regulator for firms licensed inside the DIFC free zone. Surfaces (1) the 3,389-URL DFSA sitemap as a dated discovery layer (lastmod through 2026-06, archive back to 2020-02); (2) enforcement decision notices as direct S3-hosted PDF downloads (fines, settlements, enforceable undertakings); (3) regulatory alerts, notices on legislation, and consultation papers. Use for any DIFC competitive-positioning question, DFSA-licensee enforcement risk analysis, or DFSA rulebook / regulatory-change tracking. Pairs with the wam skill (federal-level decisions) and the cbuae skill (UAE-wide monetary data) — DFSA's scope is DIFC-only.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# DFSA (Dubai Financial Services Authority)

DFSA is the financial-services regulator for the DIFC free zone. It licenses banks, asset managers, broker-dealers, insurers, and other financial-services firms operating from DIFC; supervises their conduct; runs the enforcement function; and publishes the DIFC rulebook. **Its scope is DIFC-only** — firms licensed outside DIFC (the rest of Dubai, Abu Dhabi's ADGM free zone, the wider UAE) fall under different regulators (CBUAE, SCA, FSRA).

## When to pick this skill

- **DIFC competitive-positioning questions** — when the agent needs to count licensed firms by category, track licence-grant velocity, or compare DIFC's regulatory perimeter against ADGM or other free zones.
- **DFSA enforcement risk** — when a question touches a named firm or executive and the agent needs to check whether DFSA has issued a decision notice, settlement, enforceable undertaking, or fine against them. The skill returns the actual S3-hosted PDF URL so the agent can `download_pdf(url)` and stream-extract the body.
- **DFSA rulebook and regulatory change** — when the agent needs to track DFSA consultation papers, notices on amendments to legislation, or new rule modules. The sitemap and `/news/` URL slugs surface these alongside enforcement.
- **DIFC entity background** — when the agent is doing diligence on a DIFC-domiciled name and wants to scan the full news + alerts record across the DFSA's six-year publication archive.

**Do NOT use this skill for:**

- **Banks regulated by CBUAE** (Emirates NBD, FAB, ADCB, Mashreq, etc. as commercial banks at federal level) — use the `cbuae` skill or WAM.
- **Securities listed on DFM or ADX** — the listings regulator there is the UAE Securities and Commodities Authority (SCA), not DFSA. (DFSA does regulate Nasdaq Dubai listings.)
- **ADGM-licensed firms** — ADGM's regulator is the FSRA (Financial Services Regulatory Authority). Different surface, different register.
- **Federal Cabinet decisions, UAE Federal Decrees** — those are in the `wam` skill.

## Authentication and gating model

Same two-tier pattern as the cbuae skill:

| Surface | Direct urllib | Notes |
|---|---|---|
| `www.dfsa.ae/sitemap.xml` and any HTML page | ❌ Cloudflare-gated (HTTP 403) | Routed through the backend Firecrawl proxy (`PROXY_BASE_URL` / `PROXY_API_KEY`). No vendor key in the sandbox. |
| `365343652932-web-server-storage.s3.eu-west-2.amazonaws.com/files/<path>/<name>.pdf` (enforcement decision notices) | ✅ Public (HTTP 200) | Direct urllib download, no auth |

**Format selection.** The skill's helpers pick the right format per surface:
- `fetch_sitemap()` and `fetch_enforcement_landing()` use `rawHtml` — the `markdown` serializer drops link targets on this site.
- `fetch_article_body(url)` uses `markdown` with `onlyMainContent=True` — best for LLM ingestion of news bodies.
- `fetch_register(name)` uses `markdown` with a `waitFor` for SPA hydration of the XHR-loaded register tables.

## Helper

```python
import json
import os
import urllib.request
import io
import re
from datetime import datetime, date

UA = "Mozilla/5.0 (compatible; AxionAgent/1.0)"


def _fetch_bytes(url: str) -> bytes:
    """Direct download. Works for S3-hosted enforcement PDFs."""
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def _clean(s: str) -> str:
    if not isinstance(s, str):
        return s
    return re.sub(r"\s+", " ", s).strip()


def _parse_lastmod(s: str) -> date | None:
    """Sitemap lastmod is ISO with timezone; trim to date."""
    if not s:
        return None
    try:
        return datetime.fromisoformat(s).date()
    except Exception:
        try:
            return datetime.strptime(s[:10], "%Y-%m-%d").date()
        except Exception:
            return None


def _firecrawl_proxy_base() -> str:
    return os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/firecrawl-proxy")


def _firecrawl_scrape(url: str, *, timeout_s: int = 120,
                      formats: list[str] | None = None,
                      only_main_content: bool | None = None,
                      wait_ms: int | None = None) -> str:
    """Scrape via the backend Firecrawl proxy. Returns the body as a string
    (rawHtml or markdown, depending on `formats`). All DFSA HTML surfaces are
    Cloudflare-gated; direct urllib returns 403."""
    body: dict = {
        "url": url,
        "formats": formats or ["rawHtml"],
        "timeout": (timeout_s - 10) * 1000,
    }
    if only_main_content is not None:
        body["onlyMainContent"] = only_main_content
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
    return data.get("rawHtml") or data.get("markdown") or ""
```

## Supported methods

| Method | Purpose | Cost |
| --- | --- | --- |
| `fetch_sitemap` | One-call discovery: scrape `sitemap.xml` via the backend Firecrawl proxy and parse to a list of `{url, lastmod, lang}` | 1 Firecrawl scrape |
| `parse_sitemap` | Pure parser — pass rawHtml of `sitemap.xml`; same return shape. Use only when you have cached rawHtml | 0 (in-memory) |
| `search_dfsa_news` | Filter sitemap entries to `/news/<slug>` URLs matching query/date window | 0 (in-memory) |
| `search_enforcement_actions` | Convenience filter for enforcement-related news (fines, decisions, settlements) | 0 (in-memory) |
| `search_regulatory_notices` | Convenience filter for legislation amendments, consultation papers, rule changes | 0 (in-memory) |
| `fetch_enforcement_landing` | One-call: scrape the enforcement landing page and return the list of S3 PDF URLs | 1 Firecrawl scrape |
| `extract_enforcement_pdfs` | Pure parser variant of the above, on rawHtml you already have | 0 (in-memory) |
| `fetch_article_body` | Render a single news/article URL through the proxy (`markdown`, main-content-only) | 1 Firecrawl scrape |
| `fetch_register` | Render a public-register page through the proxy with a `waitFor` for the XHR-loaded firm tables | 1 Firecrawl scrape |
| `download_pdf` | Direct fetch of an S3-hosted decision notice PDF | 1 HTTP request |
| `register_urls` | Return the 7 known public-register URLs (firms, individuals, funds) | 0 (in-memory constant) |

## Method signatures

```python
def fetch_sitemap() -> list[dict]:
    """One-call discovery: scrape https://www.dfsa.ae/sitemap.xml through the
    backend Firecrawl proxy and parse into a list of:
        {"url": str, "lastmod": "YYYY-MM-DD", "lang": "en"|"ar"}
    Sorted by lastmod descending (newest first). 3,389 entries as of 2026-06.
    Call this ONCE per session, then run as many `search_*` calls as needed
    against the returned list."""

def parse_sitemap(rawhtml: str) -> list[dict]:
    """Pure parser — pass rawHtml of https://www.dfsa.ae/sitemap.xml. Same
    return shape as fetch_sitemap(). Most callers should use fetch_sitemap()
    instead — this is only useful when you have rawHtml cached from a prior
    call."""

def search_dfsa_news(sitemap: list[dict], query: str | None = None,
                      date_after: str | None = None,
                      date_before: str | None = None,
                      language: str = "en",
                      limit: int = 100) -> list[dict]:
    """Filter sitemap entries to /news/<slug> URLs. `query` is a regex
    (case-insensitive) matched against the URL slug — for DFSA, the slug is
    derived from the article title, so matching the slug works well for
    most filtering. Date filtering uses sitemap lastmod."""

def search_enforcement_actions(sitemap: list[dict],
                                date_after: str | None = None,
                                date_before: str | None = None,
                                language: str = "en",
                                limit: int = 100) -> list[dict]:
    """All DFSA enforcement actions in window — fines, decision notices,
    settlements, enforceable undertakings, public censures, action against
    individuals. Uses a built-in slug pattern that empirically catches every
    enforcement article published on dfsa.ae."""

def search_regulatory_notices(sitemap: list[dict],
                               date_after: str | None = None,
                               date_before: str | None = None,
                               language: str = "en",
                               limit: int = 100) -> list[dict]:
    """Notices on legislation amendments, consultation paper releases,
    rulebook module updates, and other regulatory change announcements."""

def fetch_enforcement_landing() -> list[dict]:
    """One-call: scrape https://www.dfsa.ae/what-we-do/enforcement/regulatory-actions
    through the backend Firecrawl proxy and extract every S3-hosted
    decision-notice PDF link. Returns the same shape as extract_enforcement_pdfs()."""

def extract_enforcement_pdfs(rawhtml: str) -> list[dict]:
    """Pure parser — pass rawHtml of the enforcement landing page. Returns
    a list of {"url": "...pdf", "filename": "<name>.pdf"} for every S3-hosted
    decision-notice PDF linked on the page. The DFSA enforcement page surfaces
    the ~20 most recent decision notices this way. Most callers should use
    fetch_enforcement_landing() instead."""

def fetch_article_body(url: str, *, only_main_content: bool = True,
                       timeout_s: int = 90) -> str:
    """Render a single DFSA news/article page through the backend Firecrawl
    proxy. Returns markdown (main-content-only by default). Use after
    search_dfsa_news() / search_enforcement_actions() has surfaced a URL."""

def fetch_register(register_name: str, *, wait_ms: int = 5000,
                   timeout_s: int = 120) -> str:
    """Render a DFSA public-register page through the proxy with a `waitFor`
    long enough for the XHR-loaded firm/individual/fund tables to hydrate.
    `register_name` is a key from register_urls() (e.g. "firms",
    "individuals"). Returns markdown. Firecrawl bills per scrape with waitFor —
    use sparingly. Prefer search_dfsa_news() for recent licence events."""

def download_pdf(url: str) -> bytes:
    """Direct fetch of an S3-hosted decision notice PDF. Returns raw bytes;
    pass through pdftotext (in-sandbox) or feed the URL to fetch_article_body
    if you want Firecrawl's markdown rendering instead."""

def register_urls() -> dict[str, str]:
    """Return the 7 known DFSA public-register URLs. The register itself is
    SPA-rendered (XHR-loaded after page mount), so a plain Firecrawl scrape on
    these URLs returns navigation only. Use fetch_register(name) which adds
    the waitFor, or fall back to enumerating recent licence grants via
    search_dfsa_news()."""
```

## Return shape

```python
# parse_sitemap, search_*
[
  {"url": "https://www.dfsa.ae/news/dfsa-fines-company-usd-105000-unauthorised-activity",
   "lastmod": "2025-09-12",
   "lang": "en"},
  ...
]

# extract_enforcement_pdfs
[
  {"url": "https://365343652932-web-server-storage.s3.eu-west-2.amazonaws.com/files/2517/7857/2115/Wael_Mohsen_Decision_Notice_Signed_Redacted_2025.pdf",
   "filename": "Wael_Mohsen_Decision_Notice_Signed_Redacted_2025.pdf"},
  ...
]

# register_urls
{
  "firms": "https://www.dfsa.ae/public-register/firms",
  "individuals": "https://www.dfsa.ae/public-register/individuals",
  "funds": "https://www.dfsa.ae/public-register/funds",
  "funds_alt": "https://www.dfsa.ae/public-register/funds-1",
  "register_root": "https://www.dfsa.ae/public-register",
}
```

## Implementation

```python
import json
import os
import urllib.request
import io
import re
from datetime import datetime, date

UA = "Mozilla/5.0 (compatible; AxionAgent/1.0)"

_SITEMAP_URL = "https://www.dfsa.ae/sitemap.xml"
_ENFORCEMENT_LANDING = "https://www.dfsa.ae/what-we-do/enforcement/regulatory-actions"


def _firecrawl_proxy_base() -> str:
    return os.environ["PROXY_BASE_URL"].replace("/api/llm-proxy", "/api/firecrawl-proxy")


def _firecrawl_scrape(url: str, *, timeout_s: int = 120,
                      formats: list[str] | None = None,
                      only_main_content: bool | None = None,
                      wait_ms: int | None = None) -> str:
    body: dict = {
        "url": url,
        "formats": formats or ["rawHtml"],
        "timeout": (timeout_s - 10) * 1000,
    }
    if only_main_content is not None:
        body["onlyMainContent"] = only_main_content
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
    return data.get("rawHtml") or data.get("markdown") or ""


def _fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def _clean(s: str) -> str:
    if not isinstance(s, str):
        return s
    return re.sub(r"\s+", " ", s).strip()


def _parse_lastmod(s: str) -> str | None:
    """Trim 'YYYY-MM-DDTHH:MM:SS+04:00' to 'YYYY-MM-DD'."""
    if not s:
        return None
    return s[:10] if len(s) >= 10 and s[4] == "-" and s[7] == "-" else None


_URL_RE = re.compile(r"<url>(.*?)</url>", re.DOTALL)
_LOC_RE = re.compile(r"<loc>([^<]+)</loc>")
_LASTMOD_RE = re.compile(r"<lastmod>([^<]+)</lastmod>")


def parse_sitemap(rawhtml: str) -> list[dict]:
    """Extract every <url> entry from the DFSA sitemap. Returns list of
    {"url", "lastmod", "lang"} sorted by lastmod descending."""
    out: list[dict] = []
    for entry in _URL_RE.findall(rawhtml):
        loc_m = _LOC_RE.search(entry)
        if not loc_m:
            continue
        url = loc_m.group(1).strip()
        lastmod_m = _LASTMOD_RE.search(entry)
        lastmod = _parse_lastmod(lastmod_m.group(1)) if lastmod_m else None
        # Language: /ar/ prefix → Arabic, otherwise English
        lang = "ar" if "/ar/" in url or url.endswith("/ar") else "en"
        out.append({"url": url, "lastmod": lastmod, "lang": lang})
    # Sort newest first
    out.sort(key=lambda e: e["lastmod"] or "", reverse=True)
    return out


def fetch_sitemap() -> list[dict]:
    return parse_sitemap(_firecrawl_scrape(_SITEMAP_URL, formats=["rawHtml"]))


def _filter(sitemap: list[dict], *,
            url_pattern: re.Pattern,
            query: str | None,
            date_after: str | None,
            date_before: str | None,
            language: str,
            limit: int) -> list[dict]:
    qpat = re.compile(query, re.I) if query else None
    out: list[dict] = []
    for entry in sitemap:
        if entry["lang"] != language:
            continue
        if not url_pattern.search(entry["url"]):
            continue
        if qpat and not qpat.search(entry["url"]):
            continue
        if date_after and (entry["lastmod"] or "") < date_after:
            continue
        if date_before and (entry["lastmod"] or "9999-99-99") > date_before:
            continue
        out.append(entry)
        if len(out) >= limit:
            break
    return out


_NEWS_RE = re.compile(r"/news/[a-z0-9-]+")
# Enforcement matcher: scans the entire slug rather than anchoring to a prefix.
# Empirically catches DFSA fines, prohibitions, restrictions, suspensions,
# revocations, settlements, enforceable undertakings, and Financial Markets
# Tribunal / Regulatory Appeals Committee outcomes. Verified against the live
# 2025-2026 archive (12 enforcement slugs surfaced vs 3 with the older regex).
_ENFORCEMENT_SLUG_RE = re.compile(
    r"/news/[a-z0-9-]*"
    r"(?:dfsa-fines?|dfsa-takes-action|action-against|"
    r"dfsa-prohibits|dfsa-restricts|dfsa-bans|dfsa-revokes|dfsa-withdraws|"
    r"dfsa-suspends|dfsa-censures|dfsa-imposes|dfsa-sanctions|dfsa-accepts|"
    r"dfsa-wins|financial-markets-tribunal|regulatory-appeals-committee|"
    r"decision-notice|enforceable-undertaking|public-censure|"
    r"prohibition|impose-fine|impose-penalty)"
    r"[a-z0-9-]*",
    re.I,
)
_NOTICE_SLUG_RE = re.compile(
    r"/news/[a-z0-9-]*"
    r"(?:notice-amendments|consultation-paper|rulebook|amendments?-legislation|"
    r"regulatory-policy|new-rule|rule-module|policy-statement|finalised-rules?|"
    r"thematic-review|guidance-note|updated-rules|implementation-faqs?)"
    r"[a-z0-9-]*",
    re.I,
)


def search_dfsa_news(sitemap, query=None, date_after=None, date_before=None,
                      language="en", limit=100):
    return _filter(sitemap, url_pattern=_NEWS_RE, query=query,
                   date_after=date_after, date_before=date_before,
                   language=language, limit=limit)


def search_enforcement_actions(sitemap, date_after=None, date_before=None,
                                language="en", limit=100):
    return _filter(sitemap, url_pattern=_ENFORCEMENT_SLUG_RE, query=None,
                   date_after=date_after, date_before=date_before,
                   language=language, limit=limit)


def search_regulatory_notices(sitemap, date_after=None, date_before=None,
                               language="en", limit=100):
    return _filter(sitemap, url_pattern=_NOTICE_SLUG_RE, query=None,
                   date_after=date_after, date_before=date_before,
                   language=language, limit=limit)


_S3_PDF_RE = re.compile(
    r'href="(https://[^"]*?365343652932-web-server-storage\.s3\.[^"]*?\.pdf)"',
    re.I,
)


def extract_enforcement_pdfs(rawhtml: str) -> list[dict]:
    out: list[dict] = []
    seen = set()
    for url in _S3_PDF_RE.findall(rawhtml):
        if url in seen:
            continue
        seen.add(url)
        out.append({"url": url, "filename": url.rsplit("/", 1)[-1]})
    return out


def fetch_enforcement_landing() -> list[dict]:
    return extract_enforcement_pdfs(
        _firecrawl_scrape(_ENFORCEMENT_LANDING, formats=["rawHtml"])
    )


def fetch_article_body(url: str, *, only_main_content: bool = True,
                       timeout_s: int = 90) -> str:
    return _firecrawl_scrape(url, formats=["markdown"],
                             only_main_content=only_main_content,
                             timeout_s=timeout_s)


def fetch_register(register_name: str, *, wait_ms: int = 5000,
                   timeout_s: int = 120) -> str:
    urls = register_urls()
    if register_name not in urls:
        raise KeyError(f"Unknown register '{register_name}'. Known: {list(urls)}")
    return _firecrawl_scrape(urls[register_name], formats=["markdown"],
                             only_main_content=True, wait_ms=wait_ms,
                             timeout_s=timeout_s)


def download_pdf(url: str) -> bytes:
    return _fetch_bytes(url)


def register_urls() -> dict[str, str]:
    return {
        "firms": "https://www.dfsa.ae/public-register/firms",
        "individuals": "https://www.dfsa.ae/public-register/individuals",
        "funds": "https://www.dfsa.ae/public-register/funds",
        "funds_alt": "https://www.dfsa.ae/public-register/funds-1",
        "register_root": "https://www.dfsa.ae/public-register",
    }
```

## Examples

### Discovery — load the sitemap once

```python
# One Firecrawl-proxy call, parsed in place.
sitemap = fetch_sitemap()
print(f"Loaded {len(sitemap)} sitemap entries, newest = {sitemap[0]['lastmod']}")
# → Loaded 3389 sitemap entries, newest = 2026-06-03
```

### Search enforcement actions in a window

```python
# All DFSA enforcement actions in the last 12 months.
hits = search_enforcement_actions(sitemap,
                                    date_after="2025-06-01",
                                    date_before="2026-06-09",
                                    limit=30)
print(f"Found {len(hits)} enforcement actions")
for h in hits[:10]:
    slug = h["url"].rsplit("/", 1)[-1]
    print(f"  {h['lastmod']}  {slug}")
```

### Find a specific firm — has DFSA acted against them?

```python
# Free-text regex against URL slugs (the slug is the article title slugified).
hits = search_dfsa_news(sitemap, query=r"company-x|acme-capital|firm-y",
                         date_after="2020-01-01", limit=50)
for h in hits:
    print(f"  {h['lastmod']}  {h['url']}")

# For the body of any hit:
#   body = fetch_article_body(h["url"])
```

### Read a decision-notice PDF directly

```python
# Step 1: one Firecrawl-proxy call to the enforcement landing page;
# returns the current ~20 S3 PDF URLs already parsed.
pdfs = fetch_enforcement_landing()
print(f"Found {len(pdfs)} decision-notice PDFs on the landing page")
for p in pdfs[:5]:
    print(f"  {p['filename']}")
# Sample output (validated 2026-06-09):
#   Wael_Mohsen_Decision_Notice_Signed_Redacted_2025.pdf
#   ARK_Decision_Notice_Redacted.pdf
#   Ed_Broking_Decision_Notice_Signed_Redacted_20266.pdf
#   F007514_Xen_Capital_Asia_Pte_Ltd__-_Final_Decision_Notice.pdf
#   20240923_Enforceable_Undertaking_Baker_Tilly_MKM_Chartered_Accountants_Redacted

# Step 2: download the bytes (no auth, direct), then extract text.
pdf_bytes = download_pdf(pdfs[0]["url"])
with open("/tmp/notice.pdf", "wb") as f:
    f.write(pdf_bytes)
# Then in the same agent turn:
#   subprocess.run(["pdftotext", "-layout", "/tmp/notice.pdf", "-"], ...)
```

### Regulatory notices — track rulebook changes

```python
notices = search_regulatory_notices(sitemap,
                                     date_after="2025-01-01",
                                     limit=50)
print(f"Regulatory notices in window: {len(notices)}")
for n in notices[:15]:
    slug = n["url"].rsplit("/", 1)[-1]
    print(f"  {n['lastmod']}  {slug}")
```

### Public register — known SPA limitation

```python
# The DFSA public register is XHR-loaded after page mount. A plain Firecrawl
# scrape returns the navigation shell only — no firm rows. Two options:
#
#   (a) fetch_register(name) — calls the proxy with `waitFor=5000` so the XHR
#       has time to populate. Firecrawl bills more for waitFor than a plain
#       scrape, so use sparingly.
#         body = fetch_register("firms")        # markdown, ~5s wait
#
#   (b) Enumerate recent licence grants by sitemap walk — DFSA publishes a
#       /news/ article for material licence events (new firm authorisation,
#       licence variation, withdrawal). search_dfsa_news with a regex like
#       r"authorisation|licen[cs]e-grant|firm-X" surfaces these.
#
# Use option (b) by default. Reserve option (a) for cases where the agent
# explicitly needs the current full firm list.

urls = register_urls()
print(urls["firms"])
# → https://www.dfsa.ae/public-register/firms
```

## Coverage and archive

- **Sitemap depth.** 3,389 URL entries with `lastmod`, oldest dated 2020-02-10, newest within the last few days. Includes both English and Arabic (Arabic mirror at `/ar/*` paths).
- **News.** 855 URLs under `/news/*` — every DFSA press release, enforcement action, consultation paper, rule update, and notice goes here. This is the primary discovery surface.
- **Enforcement landing page** publishes the most recent ~20 decision-notice PDFs as direct S3 download links. Older decisions live deeper in the archive (their press-release URLs are in the sitemap, but the linked PDFs may not surface from the landing page).
- **Alerts (`/alerts/*`).** 276 URLs. Public warnings against unauthorised firms operating in or from the UAE — useful for fraud / mis-selling risk diligence.
- **Listed securities (`/official-listed-securities-and-delisted-securities/*`).** 386 URLs. Issuer disclosures for Nasdaq Dubai listings (where DFSA is the listing authority). Quarterly reports, prospectuses, voluntary disclosures.

## Usage rules

- **Single-fetch sitemap, then in-memory filter.** Call `fetch_sitemap()` ONCE per agent session, then run as many `search_*` calls as needed against the returned list. Re-fetching the sitemap on every search wastes Firecrawl proxy quota.
- **Format selection is handled by the skill.** `fetch_sitemap` / `fetch_enforcement_landing` use `rawHtml` (so `<a href>` targets survive); `fetch_article_body` / `fetch_register` use `markdown` with `onlyMainContent=true` (best for LLM ingestion). You should not need to override these.
- **S3 PDF downloads bypass Cloudflare** — use `download_pdf(url)` directly with stdlib urllib. No auth, no headers needed.
- **Sitemap lastmod IS the article date.** DFSA's sitemap lastmod tracks the article publish/update time precisely (timezone-aware, second precision). Date-filtering by lastmod works without scraping individual articles.
- **DIFC-scope only.** Do NOT report DFSA enforcement against a firm as evidence of UAE-wide regulatory action — it is specifically about DIFC-licensed activity. A firm fined by DFSA may operate unaffected outside DIFC (in mainland UAE, ADGM, or elsewhere).
- **Pair with WAM for federal-level context.** A DFSA action sometimes follows a Cabinet decision or federal-decree change. After surfacing an enforcement hit, check WAM (`search_uae_news` with the firm name) for the broader federal context if the question warrants it.
- **Cite the DFSA URL inline as `[N](url)`.** DFSA is the primary regulator-of-record for DIFC — its press release is tier-1 evidence for any DIFC-firm enforcement claim and can anchor the Authoritative-disclosure override.
