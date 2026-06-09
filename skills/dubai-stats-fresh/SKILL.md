---
name: dubai-stats-fresh
description: Fetch the freshest UAE statistics via FCSC's UAE.Stat SDMX API (monthly UAE foreign trade through Sept 2025, **re-exports by country** — the Dubai re-export economy view, monthly CPI through Dec 2025, quarterly GDP, ~291 total dataflows) and Dubai-specific PDFs from Dubai Statistics Center via Wayback Machine. Use for current-period UAE trade/inflation/GDP analysis and Dubai demographic data. Closes the ~24 month freshness gap vs UN Comtrade. Requires `FIRECRAWL_API_KEY` env var.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# Dubai Stats Fresh — UAE.Stat (FCSC) + DSC

Two sources, both reach-blocked from outside UAE (UAE.Stat: Cloudflare WAF; DSC: full geo-block), routed through Firecrawl + Wayback respectively. Both verified working 2026-06-09.

## What this unlocks vs existing skills

| Indicator | Best existing | This skill |
|---|---|---|
| UAE annual trade | UN Comtrade 2023 (in `uae-trade`) | UAE.Stat 2024 annual, monthly through Sept 2025 |
| UAE re-exports by country | Paid Comtrade premium only | ✅ `DF_TRADE_REXP_COUNTRY_MTH` monthly, free |
| UAE CPI | None (we had only WB annual) | Monthly through Dec 2025 |
| UAE quarterly GDP | None | `DF_QGDP_CUR` |
| Dubai-specific demographics | None | DSC Statistical Yearbook chapter PDFs via Wayback |

## Auth and base helpers

```python
import json, os, re, time, urllib.parse, urllib.request, urllib.error

_FIRECRAWL_BASE = "https://api.firecrawl.dev/v1/scrape"
_UAESTAT_API    = "https://releaseeuaestat.fcsc.gov.ae"  # SDMX REST host (Cloudflare-gated)
_DSC_HOST       = "https://www.dsc.gov.ae"
_WAYBACK        = "https://web.archive.org/web"
_CACHE_DIR      = "/data/dubai-stats-fresh"

def _fc_key() -> str:
    k = os.environ.get("FIRECRAWL_API_KEY")
    if not k:
        raise RuntimeError("FIRECRAWL_API_KEY env var is required. Set it before calling this skill.")
    return k

def _firecrawl_scrape(url: str, *, timeout_s: int = 120, formats: list[str] | None = None) -> str:
    """Scrape via Firecrawl. Returns raw HTML body (which for SDMX is XML/CSV text).
    `formats=["rawHtml"]` is the default — preserves SDMX XML / CSV exactly."""
    body = {
        "url": url,
        "formats": formats or ["rawHtml"],
        "timeout": (timeout_s - 10) * 1000,
    }
    req = urllib.request.Request(
        _FIRECRAWL_BASE,
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {_fc_key()}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as r:
        resp = json.loads(r.read().decode())
    if not resp.get("success"):
        raise RuntimeError(f"Firecrawl failed for {url}: {resp.get('error','no error msg')[:200]}")
    return (resp.get("data") or {}).get("rawHtml") or (resp.get("data") or {}).get("markdown") or ""

def _wayback_id(orig_url: str) -> tuple[str | None, str | None]:
    """Resolve the latest Wayback snapshot URL for an original URL.
    Returns (snapshot_url_with_id_, timestamp) or (None, None)."""
    api = f"https://archive.org/wayback/available?url={urllib.parse.quote(orig_url, safe=':/?=&%')}"
    with urllib.request.urlopen(api, timeout=15) as r:
        snap = json.load(r).get("archived_snapshots", {}).get("closest", {})
    if snap.get("available"):
        ts = snap["timestamp"]
        return (f"{_WAYBACK}/{ts}id_/{orig_url}", ts)
    return (None, None)

def _open_with_retry(req, *, max_retries: int = 3, base_delay: float = 1.0, timeout: int = 30):
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 429 and attempt < max_retries:
                ra = e.headers.get("Retry-After") if e.headers else None
                try: delay = float(ra) if ra else base_delay * (2 ** attempt)
                except ValueError: delay = base_delay * (2 ** attempt)
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
```

## Curated dataflows — Dubai-relevant subset

```python
# Subset of the ~291 UAE.Stat dataflows curated for Dubai gov analytical use.
# Full list discoverable via list_uaestat_dataflows(). Versions verified 2026-06-09.
CURATED_DATAFLOWS = {
    # Trade — annual
    "DF_TRADE_TOT_YR":           {"version": "5.1.0", "freq": "A",   "label": "UAE Foreign Trade — Annual"},
    "DF_TRADE_TOT_CHAP_YR":      {"version": "5.1.0", "freq": "A",   "label": "Foreign Trade — HS Chapter, Annual"},
    "DF_TRADE_COUNTRY_YR":       {"version": "5.1.0", "freq": "A",   "label": "Foreign Trade — by Country, Annual"},
    # Trade — monthly (the freshness wins)
    "DF_TRADE_TOT_MTH":          {"version": "5.1.0", "freq": "M",   "label": "Foreign Trade — Monthly (through Sept 2025)"},
    "DF_TRADE_SECT_MTH":         {"version": "5.1.0", "freq": "M",   "label": "Foreign Trade — HS Section, Monthly"},
    "DF_TRADE_TOT_COUNTRY_MTH":  {"version": "5.1.0", "freq": "M",   "label": "Total Non-Oil Trade by Country, Monthly"},
    "DF_TRADE_EXP_COUNTRY_MTH":  {"version": "5.1.0", "freq": "M",   "label": "Non-Oil Exports by Country, Monthly"},
    "DF_TRADE_IMP_COUNTRY_MTH":  {"version": "5.1.0", "freq": "M",   "label": "Imports by Country, Monthly"},
    "DF_TRADE_REXP_COUNTRY_MTH": {"version": "5.1.0", "freq": "M",   "label": "Re-Exports by Country, Monthly (Dubai re-export economy)"},
    # Prices
    "DF_CPI":                    {"version": "3.2.0", "freq": "M",   "label": "Consumer Price Index, Monthly (through Dec 2025)"},
    "DF_CPI_ANN":                {"version": "3.2.0", "freq": "A",   "label": "CPI Annual"},
    "DF_PPI_ALL":                {"version": "2.3.0", "freq": "M",   "label": "Producer Price Index"},
    # National accounts
    "DF_QGDP_CUR":               {"version": "1.8.0", "freq": "Q",   "label": "GDP Quarterly — Current Prices"},
    "DF_QGDP_CON":               {"version": "1.8.0", "freq": "Q",   "label": "GDP Quarterly — Constant Prices"},
    "DF_NA_ISIC_CUR":            {"version": "3.4.0", "freq": "A",   "label": "GDP — by Economic Sector, Annual Current"},
    "DF_NA_PFIN_CUR":            {"version": "3.4.0", "freq": "A",   "label": "Govt Revenues & Expenditures, Annual"},
}
```

## Tools — UAE.Stat (SDMX)

```python
def list_uaestat_dataflows(filter_text: str | None = None) -> list[dict]:
    """Scrape the full SDMX dataflow registry via Firecrawl. ~291 dataflows.
    Filter by case-insensitive substring against the English name (e.g. 'trade', 'cpi', 'labour').
    Returns list of {id, version, name_en}."""
    xml = _firecrawl_scrape(
        f"{_UAESTAT_API}/rest/dataflow/FCSA?detail=allstubs",
        timeout_s=180,
    )
    out = []
    for m in re.finditer(
        r'<structure:Dataflow\s+id="(DF_[^"]+)"\s+agencyID="FCSA"\s+version="([^"]+)"',
        xml,
    ):
        df_id, version = m.group(1), m.group(2)
        seg = xml[m.end():m.end() + 1500]
        nm = re.search(r'<common:Name xml:lang="en">([^<]+)</common:Name>', seg)
        name = nm.group(1) if nm else "(no en name)"
        if not filter_text or filter_text.lower() in name.lower() or filter_text.lower() in df_id.lower():
            out.append({"id": df_id, "version": version, "name_en": name})
    return out

def get_uaestat_data(df_id: str, version: str | None = None, *,
                     key: str = "all", start_period: str | None = None,
                     end_period: str | None = None, dimension_at_observation: str = "AllDimensions",
                     ) -> str:
    """Fetch SDMX CSV (with labels) for one dataflow via Firecrawl.
    `key` is the dimension filter (e.g. 'A.AE..._T.TOTAL' for annual UAE total trade) — use 'all' to retrieve everything.
    `start_period` / `end_period`: SDMX period strings (e.g. '2020', '2024-01', '2024-Q3').
    Returns raw CSV text. Use parse_sdmx_csv() to convert to dicts.
    Auto-resolves version from CURATED_DATAFLOWS if omitted."""
    if not version:
        version = (CURATED_DATAFLOWS.get(df_id) or {}).get("version")
        if not version:
            raise ValueError(f"version required for non-curated dataflow {df_id} — call list_uaestat_dataflows() to look up")
    params = {"format": "csvfilewithlabels", "dimensionAtObservation": dimension_at_observation}
    if start_period: params["startPeriod"] = start_period
    if end_period:   params["endPeriod"]   = end_period
    url = f"{_UAESTAT_API}/rest/data/FCSA,{df_id},{version}/{key}?{urllib.parse.urlencode(params)}"
    return _firecrawl_scrape(url, timeout_s=180)

def parse_sdmx_csv(csv_text: str) -> list[dict]:
    """Parse SDMX CSV (csvfilewithlabels format) into list of dicts.
    Strips the structure header rows and keeps observation rows. Columns vary by dataflow."""
    import csv, io
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    # SDMX csvfilewithlabels: each row IS an observation; the STRUCTURE column equals 'DATAFLOW'.
    return [r for r in rows if r.get("STRUCTURE") == "DATAFLOW"]

# Convenience wrappers for the highest-value dataflows
def get_uae_trade_monthly(start_month: str | None = "2024-01", end_month: str | None = None) -> list[dict]:
    """UAE monthly foreign trade — total exports/imports/re-exports.
    Latest available period: Sept 2025 (verified 2026-06-09). 24 months fresher than UN Comtrade."""
    csv = get_uaestat_data("DF_TRADE_TOT_MTH", start_period=start_month, end_period=end_month)
    return parse_sdmx_csv(csv)

def get_uae_reexports_by_country_monthly(start_month: str = "2025-01",
                                          end_month: str | None = None) -> list[dict]:
    """UAE re-exports by partner country, monthly. The Dubai re-export economy view —
    captures goods imported into UAE and re-exported through Dubai/Jebel Ali to a different country.
    NOTE: response is ~7MB for full history; always pass a tight period window."""
    csv = get_uaestat_data("DF_TRADE_REXP_COUNTRY_MTH", start_period=start_month, end_period=end_month)
    return parse_sdmx_csv(csv)

def get_uae_exports_by_country_monthly(start_month: str = "2025-01",
                                       end_month: str | None = None) -> list[dict]:
    csv = get_uaestat_data("DF_TRADE_EXP_COUNTRY_MTH", start_period=start_month, end_period=end_month)
    return parse_sdmx_csv(csv)

def get_uae_cpi_monthly(start_month: str = "2024-01", end_month: str | None = None) -> list[dict]:
    """UAE Consumer Price Index, monthly. Latest period: Dec 2025 (~6 months old, verified 2026-06-09)."""
    csv = get_uaestat_data("DF_CPI", start_period=start_month, end_period=end_month)
    return parse_sdmx_csv(csv)

def get_uae_quarterly_gdp(start_quarter: str = "2022-Q1", end_quarter: str | None = None) -> list[dict]:
    """UAE quarterly GDP at current prices."""
    csv = get_uaestat_data("DF_QGDP_CUR", start_period=start_quarter, end_period=end_quarter)
    return parse_sdmx_csv(csv)
```

## Tools — DSC (Dubai Statistics Center) via Wayback

```python
# Known DSC publication URL patterns (verified 2026-06-09 via Wayback)
DSC_STAT_YEARBOOK_TEMPLATE = "https://www.dsc.gov.ae/Report/DSC_SYB_{year}_{section:02d}_{chapter:02d}.pdf"
DSC_PUBLICATION_TEMPLATE   = "https://www.dsc.gov.ae/Publication/{title}.pdf"

# Curated DSC publication landing pages (use these as Wayback discovery seeds)
DSC_LANDING_PAGES = {
    "publications_catalog":   "https://www.dsc.gov.ae/en-us/EServices/Pages/Display-or-Download-Statistical-Reports-and-Indicators.aspx",
    "publication_details_8":  "https://www.dsc.gov.ae/en-us/Publications/Pages/publication-details.aspx?PublicationId=8",
    "international_trade":    "https://www.dsc.gov.ae/en-us/Themes/Pages/International-Trade.aspx?Theme=26",
    "population":             "https://www.dsc.gov.ae/en-us/Themes/Pages/Population.aspx",
}

def fetch_dsc_pdf_via_wayback(original_url: str, *, max_bytes: int = 50_000_000) -> dict:
    """Fetch a DSC PDF through the latest Wayback snapshot. Bypasses the UAE geo-block.
    Returns {bytes, is_pdf, snapshot_timestamp, snapshot_url, original_url}."""
    wb, ts = _wayback_id(original_url)
    if not wb:
        raise RuntimeError(f"No Wayback snapshot for {original_url}")
    req = urllib.request.Request(wb, headers={"User-Agent": "Mozilla/5.0 dubai-stats-fresh/1.0"})
    resp = _open_with_retry(req, timeout=45)
    data = resp.read(max_bytes)
    return {
        "bytes": data, "is_pdf": data[:4] == b"%PDF",
        "snapshot_timestamp": ts, "snapshot_url": wb,
        "original_url": original_url, "size": len(data),
    }

def cache_dsc_pdf(original_url: str) -> str:
    """Download a DSC PDF via Wayback to /data/dubai-stats-fresh/. Returns local path."""
    os.makedirs(_CACHE_DIR, exist_ok=True)
    fname = re.sub(r"[^A-Za-z0-9._-]+", "_", original_url.split("/")[-1])[:120]
    if not fname.endswith(".pdf"): fname += ".pdf"
    path = f"{_CACHE_DIR}/{fname}"
    if os.path.exists(path) and os.path.getsize(path) > 1000:
        return path
    r = fetch_dsc_pdf_via_wayback(original_url)
    if not r["is_pdf"]:
        raise RuntimeError(f"Wayback returned non-PDF for {original_url} (size {r['size']})")
    with open(path, "wb") as f: f.write(r["bytes"])
    return path

def discover_dsc_pdfs_via_wayback(landing_page_key: str = "publications_catalog") -> list[str]:
    """Scrape a DSC landing page snapshot from Wayback and extract PDF URLs.
    Uses Firecrawl on the wayback URL since wayback pages can be heavy."""
    orig = DSC_LANDING_PAGES.get(landing_page_key, landing_page_key)  # accept raw URL too
    wb, ts = _wayback_id(orig)
    if not wb:
        return []
    html = _firecrawl_scrape(wb, timeout_s=120, formats=["rawHtml"])
    pdfs = sorted(set(re.findall(r'(?:dsc\.gov\.ae)?(/Report/[^"\'<>]+\.pdf|/Publication/[^"\'<>]+\.pdf)', html)))
    return [f"{_DSC_HOST}{p}" if p.startswith("/") else p for p in pdfs]

def list_dsc_yearbook_chapters(year: int = 2024, max_section: int = 20, max_chapter: int = 20) -> list[str]:
    """Enumerate Dubai Statistical Yearbook PDF URLs by template.
    Naming: DSC_SYB_{YEAR}_{section:02}_{chapter:02}.pdf. Sections cover Population, Vital Stats,
    Education, Health, Labour, Economy, Trade, etc. (1 per major theme); chapters are sub-tables."""
    out = []
    for sec in range(1, max_section + 1):
        for ch in range(1, max_chapter + 1):
            out.append(DSC_STAT_YEARBOOK_TEMPLATE.format(year=year, section=sec, chapter=ch))
    return out
```

## Examples

### Latest UAE re-exports by country (monthly)

```python
# Dubai re-export economy view — was previously paid Comtrade premium only
rows = get_uae_reexports_by_country_monthly(start_month="2025-07", end_month="2025-09")
print(f"Got {len(rows)} re-export observations for Jul-Sep 2025")
# Aggregate by partner country
from collections import defaultdict
by_country = defaultdict(float)
for r in rows:
    cc = r.get("Counterpart area") or r.get("REF_AREA_2") or r.get("PARTNER")
    val = float(r.get("OBS_VALUE", 0) or 0)
    by_country[cc] += val
top = sorted(by_country.items(), key=lambda x: x[1], reverse=True)[:10]
for c, v in top:
    print(f"  {c[:30]:<32}  AED {v:>15,.0f}")
```

### UAE inflation vs World Bank annual (sanity check)

```python
rows = get_uae_cpi_monthly(start_month="2025-01", end_month="2025-12")
# Group by month
by_month = {}
for r in rows:
    period = r.get("TIME_PERIOD")
    val = r.get("OBS_VALUE")
    if period and val:
        by_month[period] = float(val)
for m in sorted(by_month):
    print(f"  {m}  CPI index = {by_month[m]:.2f}")
```

### Discover Dubai Statistical Yearbook chapters

```python
# Probe known yearbook chapter URLs against Wayback to see which are indexed
candidates = list_dsc_yearbook_chapters(year=2024, max_section=10, max_chapter=10)
found = []
for url in candidates[:30]:  # cap probe to avoid Wayback rate limits
    wb, ts = _wayback_id(url)
    if wb:
        found.append({"url": url, "wayback_ts": ts})
        time.sleep(0.3)
print(f"Found {len(found)} indexed yearbook chapters")
for f in found[:10]:
    fname = f["url"].split("/")[-1]
    print(f"  {f['wayback_ts']}  {fname}")
```

### Read a DSC PDF

```python
# Combine with the pdf-reader plugin: download via Wayback, then extract text
path = cache_dsc_pdf("https://www.dsc.gov.ae/Report/DSC_SYB_2024_01_01.pdf")
print(f"Cached at {path}")
# Agent step: pass `path` to pdf-reader.js plugin to extract text
```

### Enumerate all trade-related dataflows

```python
flows = list_uaestat_dataflows(filter_text="trade")
for f in flows:
    print(f"  {f['id']:30}  v{f['version']:8}  {f['name_en'][:80]}")
```

## Notes

- **`FIRECRAWL_API_KEY` is required** for UAE.Stat queries. Without it the SDMX endpoints return 403 (Cloudflare WAF). The key is read from env; helpers raise a clear error if missing.
- **DSC requires no key** — Wayback Machine is reached directly. Geo-block bypassed via archive.org's snapshot infrastructure.
- **SDMX CSV columns vary by dataflow** — every dataflow has its own dimension set. Always check `csv.DictReader` field names from a small sample first, then write column-specific extraction. Common keys: `TIME_PERIOD`, `OBS_VALUE`, `REF_AREA`, `Counterpart area`, `MEASURE`, `UNIT_MEASURE`.
- **Period syntax (SDMX):** annual `YYYY` (e.g. `"2024"`); monthly `YYYY-MM` (e.g. `"2025-09"`); quarterly `YYYY-Q{1-4}` (e.g. `"2024-Q3"`). `startPeriod`/`endPeriod` work for all.
- **Re-export endpoint is heavy** — `DF_TRADE_REXP_COUNTRY_MTH` full history is ~7MB CSV. Always pass `start_period` / `end_period` to scope.
- **Quarterly CPI (`DF_CPI_Q`) returns empty** for current versions — use `DF_CPI` (monthly) and aggregate, or use `DF_CPI_ANN`.
- **Quarterly GDP `DF_QGDP_CUR` requires `version="1.8.0"`** — pinned in `CURATED_DATAFLOWS`. Front-end shows higher version numbers in URLs; the structure registry has the authoritative version.
- **Wayback freshness:** snapshots are 2–8 weeks old depending on URL. For real-time Dubai data, this is sufficient since DSC publishes monthly/quarterly anyway (publication lag dominates Wayback lag).
- **DSC URL patterns:** `Report/DSC_SYB_{year}_{section:02d}_{chapter:02d}.pdf` for the Statistical Yearbook chapter PDFs. `Publication/{title}.pdf` for standalone reports (titles contain spaces — URL-encode).
- **Firecrawl is rate-limited** — concurrent calls can stall. Serialize requests; insert `time.sleep(1)` between probes if iterating.
- **Skipped from this skill:** FCSC main site (Firecrawl-detected and blocked even via WAF bypass), SCAD (geo-blocked, Wayback returns Akamai error pages, Abu Dhabi-specific anyway). UAE.Stat (FCSC's actual data portal) covers FCSC's data with much better access.
- **Pair with `pdf-reader.js` plugin** for DSC PDF content extraction — `cache_dsc_pdf()` returns a local path the plugin can read.
- **Retry/backoff** is built into `_open_with_retry` for Wayback fetches. Firecrawl handles its own retries internally per request.
