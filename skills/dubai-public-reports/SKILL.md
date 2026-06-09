---
name: dubai-public-reports
description: Discover and fetch published reports from Dubai government bodies that don't have an API — DHA (health statistics, household health survey, CSCP), DEWA (Annual Statistics, Sustainability Reports, **Investor Relations quarterly financials**), and DET (monthly Tourism Performance Reports). All free, no auth keys, but DEWA requires a Referer header and DHA filenames need URL encoding. Returns list of report URLs/metadata; pair with the project's pdf-reader plugin to actually read PDF contents.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Dubai Public Reports — DHA / DEWA / DET

Three Dubai government bodies publish report PDFs on their public sites. None offers an API. This skill provides discovery helpers (enumerate available reports) and a unified fetcher that handles each site's quirks:

- **DHA** (`dha.gov.ae/en/open-data`) — direct PDFs, URL-encode spaces
- **DEWA** (`dewa.gov.ae/-/media/Files/...`) — Sitecore `.ashx` media handlers; requires `Referer` header (anti-hotlink)
- **DET** (`dubaidet.gov.ae/en/research-and-insights/...`) — slug-based HTML pages; content JS-rendered (this skill returns the URLs; agent / pdf-reader plugin handles rendering)

For the highest-cadence DEWA data, use `list_dewa_ir_reports()` — DEWA PJSC is on DFM and files quarterly financials with ~45-day lag (much fresher than the biennial Annual Statistics booklet).

## Base helpers

```python
import json, os, re, time, urllib.parse, urllib.request, urllib.error

_CACHE_DIR = "/data/dubai-public-reports"

# Full browser fingerprint — required by Akamai-fronted DEWA + DET. Minimal headers get 403'd.
def _browser_headers(accept_type="document"):
    base = {
        "User-Agent":"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
        "Accept-Language":"en-US,en;q=0.9",
        "Accept-Encoding":"identity",
        "Sec-Ch-Ua":'"Google Chrome";v="130","Chromium";v="130"',
        "Sec-Ch-Ua-Mobile":"?0","Sec-Ch-Ua-Platform":'"macOS"',
        "Sec-Fetch-Mode":"navigate","Sec-Fetch-User":"?1",
        "Upgrade-Insecure-Requests":"1",
    }
    if accept_type == "pdf":
        base["Accept"] = "application/pdf,*/*"
        base["Sec-Fetch-Dest"] = "empty"
    else:
        base["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        base["Sec-Fetch-Dest"] = "document"
    return base

def _open_with_retry(req, *, max_retries: int = 3, base_delay: float = 1.0, timeout: int = 30):
    """urlopen with retry on 429, 5xx, and network timeouts."""
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 429 and attempt < max_retries:
                ra = e.headers.get("Retry-After") if e.headers else None
                try:
                    delay = float(ra) if ra else base_delay * (2 ** attempt)
                except ValueError:
                    delay = base_delay * (2 ** attempt)
                time.sleep(max(delay, 1.0)); continue
            if 500 <= e.code < 600 and attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt)); continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt)); continue
            raise
    raise last_err

def _fetch_html(url: str, referer: str | None = None) -> str:
    h = _browser_headers("document")
    if referer: h["Referer"] = referer; h["Sec-Fetch-Site"] = "same-origin"
    else: h["Sec-Fetch-Site"] = "none"
    req = urllib.request.Request(url, headers=h)
    return _open_with_retry(req).read().decode("utf-8", errors="replace")

def fetch_report(url: str, referer: str | None = None, *, max_bytes: int = 50_000_000) -> dict:
    """Unified report fetcher. Returns {bytes, content_type, size, is_pdf}.
    Set referer to a parent page on the same host — required for DEWA `.ashx` and recommended for all sites.
    Caches to /data/dubai-public-reports/<sanitized-filename>."""
    h = _browser_headers("pdf")
    if referer: h["Referer"] = referer; h["Sec-Fetch-Site"] = "same-origin"
    else: h["Sec-Fetch-Site"] = "none"
    req = urllib.request.Request(url, headers=h)
    resp = _open_with_retry(req)
    data = resp.read(max_bytes)
    return {
        "bytes": data, "content_type": resp.headers.get("Content-Type", ""),
        "size": len(data), "is_pdf": data[:4] == b"%PDF",
        "url": url,
    }

def cache_report(url: str, referer: str | None = None) -> str:
    """Download to /data/dubai-public-reports/ and return local path. Skips if already cached."""
    os.makedirs(_CACHE_DIR, exist_ok=True)
    fname = re.sub(r"[^A-Za-z0-9._-]+", "_", url.split("/")[-1].split("?")[0])[:120]
    if not fname.endswith(".pdf"): fname += ".pdf"
    path = f"{_CACHE_DIR}/{fname}"
    if os.path.exists(path) and os.path.getsize(path) > 1000:
        return path
    r = fetch_report(url, referer=referer)
    with open(path, "wb") as f: f.write(r["bytes"])
    return path
```

## Discovery helpers

```python
# ---------- DHA ----------

_DHA_LISTING = "https://www.dha.gov.ae/en/open-data"

def list_dha_pdfs() -> list[dict]:
    """Scrape DHA open-data listing. Returns list of {url, filename, title_guess}.
    URL-encodes paths automatically (filenames contain spaces/double-spaces)."""
    html = _fetch_html(_DHA_LISTING)
    rels = sorted(set(re.findall(r'href="([^"]+\.pdf)"', html, re.I)))
    out = []
    for rel in rels:
        # absolute URL with proper encoding
        if not rel.startswith("http"):
            abs_url = "https://www.dha.gov.ae" + urllib.parse.quote(rel, safe="/")
        else:
            abs_url = rel
        fname = urllib.parse.unquote(rel.split("/")[-1])
        # crude title — strip extension + trailing upload-id digits
        title = re.sub(r"\d{6,}\.pdf$", "", fname).replace("_", " ").replace("-", " ").strip(" .")
        out.append({"url": abs_url, "filename": fname, "title": title or fname})
    return out

# ---------- DEWA ----------

_DEWA_AS_REF   = "https://www.dewa.gov.ae/en/about-us/strategy-excellence/annual-statistics"
_DEWA_IR_REF   = "https://www.dewa.gov.ae/en/investor-relations/reports"
_DEWA_SUST_REF = "https://www.dewa.gov.ae/en/consumer/sustainability/sustainability-reports"

_DEWA_AS_TEMPLATE = "https://www.dewa.gov.ae/-/media/Files/About-DEWA/Annual-Statistics/DEWA-statistics_booklet_{year}_EN.ashx"
_DEWA_SUST_TEMPLATE = "https://dewa.gov.ae/-/media/Files/Sustainability/DEWA_Sustainability_Report_{year}_English.ashx"

def list_dewa_annual_stats(start_year: int = 2018, end_year: int = 2026) -> list[dict]:
    """Probe DEWA Annual Statistics booklet URLs. Returns only verified PDFs.
    Note: DEWA publishes on a BIENNIAL cadence (odd years: 2019, 2021, 2023, expected 2025+)."""
    out = []
    for y in range(start_year, end_year + 1):
        url = _DEWA_AS_TEMPLATE.format(year=y)
        try:
            r = fetch_report(url, referer=_DEWA_AS_REF, max_bytes=8)  # just the signature
            if r["is_pdf"]:
                out.append({"url": url, "year": y, "kind": "annual_stats", "referer": _DEWA_AS_REF})
        except urllib.error.HTTPError:
            pass
        time.sleep(0.6)
    return out

def list_dewa_sustainability(start_year: int = 2018, end_year: int = 2026) -> list[dict]:
    """Probe DEWA Sustainability Report URLs. Returns only verified PDFs.
    As of 2026-06-09 only 2023 is published."""
    out = []
    for y in range(start_year, end_year + 1):
        url = _DEWA_SUST_TEMPLATE.format(year=y)
        try:
            r = fetch_report(url, referer=_DEWA_SUST_REF, max_bytes=8)
            if r["is_pdf"]:
                out.append({"url": url, "year": y, "kind": "sustainability", "referer": _DEWA_SUST_REF})
        except urllib.error.HTTPError:
            pass
        time.sleep(0.6)
    return out

def list_dewa_ir_reports() -> list[dict]:
    """DEWA Investor Relations — quarterly + annual financial statements, integrated reports.
    Fresher than Annual Statistics (45-day lag vs biennial). Scrapes the IR reports page,
    finds all `.ashx` media links under Investor-Relations-Files/."""
    html = _fetch_html(_DEWA_IR_REF)
    rels = sorted(set(re.findall(
        r'href="(/[-/]?media/Files/Investor-Relations-Files[^"]+\.(?:ashx|pdf))"', html, re.I)))
    out = []
    for rel in rels:
        url = "https://www.dewa.gov.ae" + rel
        fname = urllib.parse.unquote(rel.split("/")[-1])
        # Heuristic period/kind extraction
        kind = "other"
        if re.search(r"consolidated", fname, re.I) or re.search(r"\b(FY|annual|year)\b", fname, re.I):
            kind = "annual_financials"
        elif re.search(r"(1st|2nd|3rd|4th|Q[1-4])", fname, re.I):
            kind = "quarterly_financials"
        elif re.search(r"integrated", fname, re.I):
            kind = "integrated_report"
        elif re.search(r"agm|circular|meeting", fname, re.I):
            kind = "agm"
        # Year guess
        y = re.search(r"(20\d{2})", fname)
        out.append({"url": url, "filename": fname, "kind": kind,
                    "year": int(y.group(1)) if y else None,
                    "referer": _DEWA_IR_REF})
    return out

# ---------- DET ----------

_DET_REF = "https://www.dubaidet.gov.ae/en/research-and-insights"
_MONTHS_FULL = ["january","february","march","april","may","june",
                "july","august","september","october","november","december"]
_MONTHS_ABBR = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]

def list_det_tourism_reports(start_year: int = 2024, end_year: int = 2026) -> list[dict]:
    """Enumerate DET monthly Tourism Performance Report slugs. Returns verified (HTTP 200) URLs only.
    Probes both 'january' and 'jan' month forms — DET appears to have switched to full names ~2025.
    Note: report HTML pages are JS-rendered; this returns the URL for the agent to read separately
    (e.g. via the web-browser skill or a PDF viewer once the embedded PDF link is located)."""
    out = []
    for y in range(start_year, end_year + 1):
        for mf, ma in zip(_MONTHS_FULL, _MONTHS_ABBR):
            for slug in (f"tourism-performance-report-{mf}-{y}",
                         f"tourism-performance-report-{ma}-{y}"):
                url = f"{_DET_REF}/{slug}"
                try:
                    h = _browser_headers("document"); h["Referer"] = _DET_REF; h["Sec-Fetch-Site"] = "same-origin"
                    req = urllib.request.Request(url, headers=h, method="HEAD")
                    r = _open_with_retry(req, timeout=15)
                    if r.status == 200:
                        out.append({"url": url, "slug": slug, "year": y, "month": mf,
                                    "kind": "tourism_performance",
                                    "referer": _DET_REF,
                                    "render_required": True})
                        break  # don't try the abbr form if full worked
                except urllib.error.HTTPError as e:
                    if e.code != 404:
                        # 4xx other than 404 → assume the slug shape may still be valid, skip
                        pass
                time.sleep(0.4)
    return out

# ---------- Convenience aggregator ----------

def list_all_reports() -> dict:
    """Run every discovery helper and return a dict by source.
    Pacing built in (per-helper sleeps); takes ~30-60s for a fresh enumeration."""
    return {
        "dha": list_dha_pdfs(),
        "dewa_annual_stats": list_dewa_annual_stats(),
        "dewa_sustainability": list_dewa_sustainability(),
        "dewa_ir": list_dewa_ir_reports(),
        "det_tourism": list_det_tourism_reports(),
    }
```

## Examples

### Most recent DEWA financial filing

```python
reports = list_dewa_ir_reports()
# 2025 consolidated full-year (the freshest)
fy2025 = [r for r in reports if r["year"] == 2025 and r["kind"] == "annual_financials"]
for r in fy2025:
    print(f"  {r['filename']}  → {r['url']}")
    path = cache_report(r["url"], referer=r["referer"])
    print(f"    cached to {path} ({os.path.getsize(path):,} bytes)")
```

### Latest DET tourism perf report

```python
det = list_det_tourism_reports(start_year=2025, end_year=2026)
det_sorted = sorted(det, key=lambda r: (r["year"], _MONTHS_FULL.index(r["month"])))
latest = det_sorted[-1]
print(f"Latest DET tourism report: {latest['slug']}")
print(f"  URL: {latest['url']}")
print(f"  Render required: {latest['render_required']}  (use web-browser skill for content)")
```

### DHA most-recent health publication

```python
dha = list_dha_pdfs()
# Heuristic: find the highest year mentioned in filename
def y(r):
    m = re.search(r"(20\d{2})", r["filename"])
    return int(m.group(1)) if m else 0
latest = sorted(dha, key=y, reverse=True)[:5]
for r in latest:
    print(f"  {r['title'][:60]:<60} → {r['url']}")
```

### Full survey of what's available right now

```python
all_reports = list_all_reports()
for source, items in all_reports.items():
    print(f"{source}: {len(items)} reports")
    for r in items[:3]:
        fname = r.get("filename") or r.get("slug") or r["url"].split("/")[-1]
        print(f"  {r.get('year','?'):<6} {fname[:80]}")
```

## Notes

- **Three different bot-detection regimes:**
  - DHA: lenient — any sensible UA works.
  - DEWA: Akamai with `Referer` check on media handlers. Full browser fingerprint headers required. `Referer` must point to a DEWA page or you get 403.
  - DET: Akamai with stricter checks. Static slug HTML pages load with full browser fingerprint, but content is JS-rendered (Highcharts/SPA). This skill returns slug URLs; rendering is out-of-scope.
- **DEWA cadence is biennial, not annual** — Annual Statistics booklets exist for 2019, 2021, 2023. 2025 booklet expected late 2025/early 2026 but not yet at the verified URL pattern. The *real* fresh DEWA data lives in `list_dewa_ir_reports()` — quarterly + annual financials.
- **DEWA URL year is the publication year**, sometimes shifted by one from the data year. The 2023 booklet may contain 2022 data, etc. Check the cover page / first paragraph of each PDF.
- **DET tourism reports' content is JS-rendered** — the static HTML returned by `_fetch_html()` is mostly the SPA shell + nav. To read actual visitor numbers, hand the URL to the `web-browser` skill (Playwright) or to a human/browser.
- **Filename → year extraction is heuristic** — relies on a `20\d{2}` regex match. Some filenames omit the year; consult the cover page for definitive data year.
- **Caching:** `cache_report()` writes to `/data/dubai-public-reports/` keyed by sanitized filename. PDFs are large (5–10 MB common); be selective about what you cache in a single session.
- **Rate-limit pacing:** `list_*` helpers include short `time.sleep()` between probes to avoid tripping Akamai rate limits. Don't remove them.
- **Retry-on-429/5xx** is built into `_open_with_retry`. Doesn't retry 401/403 — those are caller errors (wrong Referer, blocked UA).
- **Pair with `plugins/pdf-reader.js`** to actually read PDF content. This skill returns URLs and bytes; PDF-to-text extraction lives in the pdf-reader plugin.
