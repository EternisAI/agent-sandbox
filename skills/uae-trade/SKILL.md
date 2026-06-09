---
name: uae-trade
description: Fetch UAE international trade data. Default backend is FCSC's UAE.Stat SDMX API — monthly through Sept 2025, includes **re-exports by country** (the Dubai re-export economy view), monthly exports/imports by partner, HS section monthly. UN Comtrade is the fallback for HS6 commodity drill-down and multi-country comparison (Comtrade is multilateral; FCSC is UAE-reporter-only). FCSC requires `FIRECRAWL_API_KEY` env var (Cloudflare WAF on the SDMX host). Comtrade is free with no key; richer with optional `COMTRADE_API_KEY`. Pre-scoped to UAE (reporterCode 784 / REF_AREA AE).
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# UAE Trade

UAE-scoped trade data from two complementary sources. **FCSC is the default** — it's 24 months fresher than Comtrade and uniquely exposes re-exports by partner country (the Dubai re-export economy). **Comtrade is the fallback** for HS6 commodity drill-down and multi-country comparison.

## Source selection — pick the right backend

| Question | Backend | Why |
|---|---|---|
| Latest UAE monthly trade (totals, by partner, by HS section) | **FCSC** | Through Sept 2025; Comtrade has only 2023 annual |
| UAE re-exports by partner country | **FCSC** | `DF_TRADE_REXP_COUNTRY_MTH` monthly; Comtrade re-export tracking needs paid premium |
| UAE annual trade by partner | **FCSC** | 2024 annual published; Comtrade lags 2 years |
| UAE trade composition at HS4 / HS6 (specific commodities) | **Comtrade** | FCSC carries HS section/chapter only |
| UAE trade vs other countries' bilateral flows | **Comtrade** | Multilateral — FCSC is UAE-reporter only |
| Historical series before 2014 | **Comtrade** | FCSC dataflows mostly start 2014 |

## Auth model

- **FCSC** — `FIRECRAWL_API_KEY` env var required. The SDMX host (`releaseeuaestat.fcsc.gov.ae`) is Cloudflare-gated; direct urllib gets HTTP 403. Routed through Firecrawl.
- **Comtrade** — no key required for public-v1 tier. Set `COMTRADE_API_KEY` for human-readable descriptions, reference endpoints, and higher rate limits.

---

## Part 1 — FCSC (UAE.Stat SDMX), the default backend

### Base helpers

```python
import json, os, re, time, urllib.parse, urllib.request, urllib.error

_FIRECRAWL_BASE = "https://api.firecrawl.dev/v1/scrape"
_UAESTAT_API    = "https://releaseeuaestat.fcsc.gov.ae"  # SDMX REST host (Cloudflare-gated)

def _fc_key() -> str:
    k = os.environ.get("FIRECRAWL_API_KEY")
    if not k:
        raise RuntimeError("FIRECRAWL_API_KEY env var is required for FCSC. Set it before calling FCSC helpers.")
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
```

### Curated trade dataflows (versions verified 2026-06-09)

```python
TRADE_DATAFLOWS = {
    # Annual
    "DF_TRADE_TOT_YR":           {"version": "5.1.0", "freq": "A", "label": "UAE Foreign Trade — Annual"},
    "DF_TRADE_TOT_CHAP_YR":      {"version": "5.1.0", "freq": "A", "label": "Foreign Trade — HS Chapter, Annual"},
    "DF_TRADE_COUNTRY_YR":       {"version": "5.1.0", "freq": "A", "label": "Foreign Trade — by Country, Annual"},
    # Monthly (the freshness wins — through Sept 2025)
    "DF_TRADE_TOT_MTH":          {"version": "5.1.0", "freq": "M", "label": "Foreign Trade — Monthly"},
    "DF_TRADE_SECT_MTH":         {"version": "5.1.0", "freq": "M", "label": "Foreign Trade — HS Section, Monthly"},
    "DF_TRADE_TOT_COUNTRY_MTH":  {"version": "5.1.0", "freq": "M", "label": "Total Non-Oil Trade by Country, Monthly"},
    "DF_TRADE_EXP_COUNTRY_MTH":  {"version": "5.1.0", "freq": "M", "label": "Non-Oil Exports by Country, Monthly"},
    "DF_TRADE_IMP_COUNTRY_MTH":  {"version": "5.1.0", "freq": "M", "label": "Imports by Country, Monthly"},
    "DF_TRADE_REXP_COUNTRY_MTH": {"version": "5.1.0", "freq": "M", "label": "Re-Exports by Country, Monthly (Dubai re-export economy)"},
}
```

### FCSC tools

```python
def list_uaestat_trade_dataflows(filter_text: str | None = None) -> list[dict]:
    """Scrape FCSC's SDMX dataflow registry, filtered to trade-related flows.
    Returns list of {id, version, name_en}. Use to discover any flow not in TRADE_DATAFLOWS."""
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
        needle = (filter_text or "trade").lower()
        if needle in name.lower() or needle in df_id.lower():
            out.append({"id": df_id, "version": version, "name_en": name})
    return out

def get_uaestat_data(df_id: str, version: str | None = None, *,
                     key: str = "all", start_period: str | None = None,
                     end_period: str | None = None,
                     dimension_at_observation: str = "AllDimensions",
                     ) -> str:
    """Fetch SDMX CSV (with labels) for one dataflow via Firecrawl.
    `key` is the dimension filter (e.g. 'A.AE..._T.TOTAL' for annual UAE total trade) — use 'all' to retrieve everything.
    `start_period` / `end_period`: SDMX period strings (e.g. '2020', '2024-01', '2024-Q3').
    Auto-resolves version from TRADE_DATAFLOWS if omitted.
    Returns raw CSV text — pipe through parse_sdmx_csv() to get dicts."""
    if not version:
        version = (TRADE_DATAFLOWS.get(df_id) or {}).get("version")
        if not version:
            raise ValueError(f"version required for non-curated dataflow {df_id} — call list_uaestat_trade_dataflows() to look up")
    params = {"format": "csvfilewithlabels", "dimensionAtObservation": dimension_at_observation}
    if start_period: params["startPeriod"] = start_period
    if end_period:   params["endPeriod"]   = end_period
    url = f"{_UAESTAT_API}/rest/data/FCSA,{df_id},{version}/{key}?{urllib.parse.urlencode(params)}"
    return _firecrawl_scrape(url, timeout_s=180)

def parse_sdmx_csv(csv_text: str) -> list[dict]:
    """Parse SDMX CSV (csvfilewithlabels format) into list of dicts.
    Strips structure header rows, keeps observation rows. Columns vary by dataflow."""
    import csv, io
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    return [r for r in rows if r.get("STRUCTURE") == "DATAFLOW"]

# Convenience wrappers — the highest-value flows

def get_uae_trade_monthly(start_month: str | None = "2024-01", end_month: str | None = None) -> list[dict]:
    """UAE monthly foreign trade — total exports/imports/re-exports.
    Latest available period: Sept 2025 (verified 2026-06-09). 24 months fresher than UN Comtrade."""
    return parse_sdmx_csv(get_uaestat_data("DF_TRADE_TOT_MTH",
                                           start_period=start_month, end_period=end_month))

def get_uae_reexports_by_country_monthly(start_month: str = "2025-01",
                                          end_month: str | None = None) -> list[dict]:
    """UAE re-exports by partner country, monthly. The Dubai re-export economy view —
    captures goods imported into UAE and re-exported through Dubai/Jebel Ali to a different country.
    NOTE: response is ~7MB for full history; always pass a tight period window."""
    return parse_sdmx_csv(get_uaestat_data("DF_TRADE_REXP_COUNTRY_MTH",
                                           start_period=start_month, end_period=end_month))

def get_uae_exports_by_country_monthly(start_month: str = "2025-01",
                                       end_month: str | None = None) -> list[dict]:
    return parse_sdmx_csv(get_uaestat_data("DF_TRADE_EXP_COUNTRY_MTH",
                                           start_period=start_month, end_period=end_month))

def get_uae_imports_by_country_monthly(start_month: str = "2025-01",
                                       end_month: str | None = None) -> list[dict]:
    return parse_sdmx_csv(get_uaestat_data("DF_TRADE_IMP_COUNTRY_MTH",
                                           start_period=start_month, end_period=end_month))

def get_uae_trade_by_hs_section_monthly(start_month: str = "2025-01",
                                         end_month: str | None = None) -> list[dict]:
    """UAE trade by HS section, monthly. HS section ≈ 22 broad groupings (e.g. machinery, mineral fuels).
    For HS4/HS6 commodity detail use the Comtrade backend (see Part 2)."""
    return parse_sdmx_csv(get_uaestat_data("DF_TRADE_SECT_MTH",
                                           start_period=start_month, end_period=end_month))
```

---

## Part 2 — UN Comtrade (HS6 detail + multi-country fallback)

Use when FCSC's HS section granularity is too coarse, or when you need bilateral flows between non-UAE country pairs.

### Comtrade base helpers

```python
import json, os, time, urllib.parse, urllib.request, urllib.error

REPORTER_UAE = 784  # United Arab Emirates ISO M49
_KEY = os.environ.get("COMTRADE_API_KEY")
_BASE_KEYED  = "https://comtradeapi.un.org/data/v1/get"
_BASE_PUBLIC = "https://comtradeapi.un.org/public/v1/preview"

def _comtrade_get(path_after_get: str, params: dict, *, max_retries: int = 4, base_delay: float = 1.0) -> dict:
    """HTTP GET with retry on 429 (rate limit), 5xx, and timeouts. Public-v1 is ~1 call/sec —
    429 responses include a Retry-After header which we honour. Keyed tier is ~5/sec."""
    base = _BASE_KEYED if _KEY else _BASE_PUBLIC
    url = f"{base}/{path_after_get}?{urllib.parse.urlencode(params)}"
    headers = {"User-Agent": "Mozilla/5.0 (compatible; AxionAgent/1.0)"}
    if _KEY:
        headers["Ocp-Apim-Subscription-Key"] = _KEY
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=25) as r:
                return json.loads(r.read().decode())
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
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_err = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt)); continue
            raise
    raise last_err
```

### Comtrade tools

```python
def get_uae_trade_comtrade(year: int, flow: str = "X", partner: int = 0, hs_code: str = "TOTAL") -> list[dict]:
    """Single Comtrade query. flow='X' export, 'M' import. partner=0 means 'World' (all partners
    aggregated). hs_code='TOTAL' for all commodities, '27' for HS2 mineral fuels, '270900' for HS6 crude oil.
    Returns list of trade records with primaryValue in USD."""
    params = {
        "reporterCode": REPORTER_UAE, "period": year,
        "partnerCode": partner, "flowCode": flow, "cmdCode": hs_code,
    }
    if _KEY:
        params["includeDesc"] = "true"
    return _comtrade_get("C/A/HS", params).get("data", []) or []

def top_partners_comtrade(year: int, flow: str = "X", top: int = 10) -> list[dict]:
    """Top N trading partners for UAE in given year (Comtrade source). For fresher data use FCSC."""
    params = {
        "reporterCode": REPORTER_UAE, "period": year,
        "flowCode": flow, "cmdCode": "TOTAL",
    }
    if _KEY:
        params["includeDesc"] = "true"
    data = _comtrade_get("C/A/HS", params).get("data", []) or []
    rows = [r for r in data if (r.get("partnerCode") or 0) > 0]
    rows.sort(key=lambda r: r.get("primaryValue") or 0, reverse=True)
    return rows[:top]

def top_commodities_comtrade(year: int, flow: str = "X", top: int = 10) -> list[dict]:
    """Top N HS2 chapters for UAE trade. Use HS6 codes (six digits) in get_uae_trade_comtrade for finer detail."""
    params = {
        "reporterCode": REPORTER_UAE, "period": year,
        "partnerCode": 0, "flowCode": flow,
    }
    if _KEY:
        params["includeDesc"] = "true"
    data = _comtrade_get("C/A/HS", params).get("data", []) or []
    rows = [r for r in data if r.get("cmdCode") not in (None, "TOTAL", "")]
    rows.sort(key=lambda r: r.get("primaryValue") or 0, reverse=True)
    return rows[:top]

def partner_trade_history_comtrade(partner_code: int, start: int, end: int, flow: str = "X") -> dict:
    """UAE ↔ partner total trade by year (multi-year). Returns {year: usd_value}."""
    periods = ",".join(str(y) for y in range(start, end + 1))
    params = {
        "reporterCode": REPORTER_UAE, "period": periods,
        "partnerCode": partner_code, "flowCode": flow, "cmdCode": "TOTAL",
    }
    data = _comtrade_get("C/A/HS", params).get("data", []) or []
    return {r["period"]: r.get("primaryValue") for r in data}

def commodity_trade_history_comtrade(hs_code: str, start: int, end: int, flow: str = "X") -> dict:
    """UAE world trade for an HS code over a year range. Returns {year: usd_value}.
    Pass HS6 ('270900' crude oil) for the granularity FCSC can't give you."""
    periods = ",".join(str(y) for y in range(start, end + 1))
    params = {
        "reporterCode": REPORTER_UAE, "period": periods,
        "partnerCode": 0, "flowCode": flow, "cmdCode": hs_code,
    }
    data = _comtrade_get("C/A/HS", params).get("data", []) or []
    return {r["period"]: r.get("primaryValue") for r in data}

# Hardcoded lookup tables — partner & HS chapter labels for the no-key mode where descs are null.
# Compiled from UN M49 + WCO HS 2022 reference. Extend as needed.
_PARTNER_LABELS = {
    0: "World", 156: "China", 699: "India", 682: "Saudi Arabia", 364: "Iran", 368: "Iraq",
    792: "Turkey", 344: "Hong Kong", 842: "USA", 826: "United Kingdom", 276: "Germany",
    392: "Japan", 410: "Korea, Rep.", 757: "Switzerland", 512: "Oman", 414: "Kuwait",
    634: "Qatar", 48: "Bahrain", 818: "Egypt", 36: "Australia", 124: "Canada",
    250: "France", 380: "Italy", 528: "Netherlands", 643: "Russia", 76: "Brazil",
    458: "Malaysia", 360: "Indonesia", 764: "Thailand", 704: "Vietnam", 608: "Philippines",
    710: "South Africa", 566: "Nigeria", 404: "Kenya", 231: "Ethiopia", 4: "Afghanistan",
    50: "Bangladesh", 144: "Sri Lanka", 586: "Pakistan", 899: "Other Asia, nes",
}
_HS_CHAPTER_LABELS = {
    "27": "Mineral fuels, oils (crude/refined)",
    "71": "Pearls, precious stones, gold",
    "84": "Machinery, mechanical appliances",
    "85": "Electrical machinery, electronics",
    "87": "Vehicles (excl. rail)",
    "39": "Plastics",
    "72": "Iron and steel",
    "73": "Articles of iron or steel",
    "76": "Aluminium",
    "30": "Pharmaceutical products",
    "29": "Organic chemicals",
    "62": "Apparel (not knitted)",
    "61": "Apparel (knitted)",
    "08": "Edible fruit, nuts",
    "10": "Cereals",
    "02": "Meat",
    "03": "Fish",
    "04": "Dairy, eggs",
}

def lookup_partner(code: int) -> str:
    return _PARTNER_LABELS.get(code, f"partner_{code}")

def lookup_hs(code: str) -> str:
    return _HS_CHAPTER_LABELS.get(code[:2], f"HS_{code}")
```

---

## Examples

### Latest UAE re-exports by partner country (FCSC, freshness path)

```python
# The Dubai re-export economy view — was previously paid Comtrade premium only.
rows = get_uae_reexports_by_country_monthly(start_month="2025-07", end_month="2025-09")
print(f"Got {len(rows)} re-export observations for Jul-Sep 2025")
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

### Latest UAE total monthly trade (FCSC)

```python
rows = get_uae_trade_monthly(start_month="2025-01", end_month="2025-09")
print(f"UAE monthly trade observations: {len(rows)}")
# Aggregate by period + measure
by_period = {}
for r in rows:
    period = r.get("TIME_PERIOD"); val = r.get("OBS_VALUE")
    if period and val:
        by_period.setdefault(period, []).append(float(val))
for p in sorted(by_period):
    print(f"  {p}  AED {sum(by_period[p]):>15,.0f}")
```

### UAE crude oil exports over time, HS6 (Comtrade — FCSC doesn't have HS6)

```python
series = commodity_trade_history_comtrade("270900", start=2018, end=2023, flow="X")
print("UAE crude oil (HS 270900) exports to World:")
for y in sorted(series.keys()):
    v = series[y] or 0
    print(f"  {y}: ${v:>15,.0f}")
```

### Top 10 UAE export partners 2023 (Comtrade — historical reference)

```python
rows = top_partners_comtrade(2023, flow="X", top=10)
for r in rows:
    pc = r["partnerCode"]
    label = r.get("partnerDesc") or lookup_partner(pc)
    v = r.get("primaryValue") or 0
    print(f"  {label:<25} ${v:>15,.0f}")
```

### UAE–India bilateral trade history (Comtrade)

```python
exp = partner_trade_history_comtrade(699, 2018, 2023, flow="X")
imp = partner_trade_history_comtrade(699, 2018, 2023, flow="M")
print(f"{'Year':<6}{'UAE→India':<20}{'India→UAE':<20}{'Balance':<20}")
for y in sorted(exp.keys()):
    e, i = (exp.get(y) or 0), (imp.get(y) or 0)
    print(f"  {y:<6}${e:>15,.0f}    ${i:>15,.0f}    ${e-i:>15,.0f}")
```

## Notes

### FCSC
- **`FIRECRAWL_API_KEY` required** — SDMX host is Cloudflare-WAF-gated; direct urllib returns 403. Helpers raise a clear error if missing.
- **Period syntax (SDMX):** annual `YYYY` (e.g. `"2024"`); monthly `YYYY-MM` (e.g. `"2025-09"`); quarterly `YYYY-Q{1-4}`. `startPeriod`/`endPeriod` work for all.
- **Re-export endpoint is heavy** — `DF_TRADE_REXP_COUNTRY_MTH` full history is ~7MB CSV. Always pass `start_period` / `end_period` to scope.
- **CSV columns vary by dataflow** — always inspect `csv.DictReader` field names from a small sample first, then write column-specific extraction. Common keys: `TIME_PERIOD`, `OBS_VALUE`, `REF_AREA`, `Counterpart area`, `MEASURE`, `UNIT_MEASURE`.
- **Granularity ceiling:** FCSC carries HS section / chapter (annual). For HS4/HS6, go to Comtrade.
- **Firecrawl is rate-limited** — serialize requests; insert `time.sleep(1)` between probes if iterating.

### Comtrade
- **`COMTRADE_API_KEY` env var** — optional. When present, requests use the keyed endpoint and pass `includeDesc=true` for human-readable labels.
- **UAE reports annually only** — `freqCode=A`. Monthly queries return empty for any UAE period (verified 2026-06-09 against the data-availability endpoint). Use FCSC for monthly.
- **Data lag** — most recent year typically available is *current year − 2*. UAE 2024 and 2025 data is not yet ingested by UN. Use FCSC for current-year data.
- **HS classification:** `cmdCode=TOTAL` for all goods, HS2 (`"27"`), HS4 (`"2709"`), or HS6 (`"270900"`).
- **Flow codes:** `X` export, `M` import, `RX` re-export, `RM` re-import. Re-export details require **paid premium** in Comtrade; use FCSC `DF_TRADE_REXP_COUNTRY_MTH` instead.
- **Partner code 0 = "World"**. Omit `partnerCode` to enumerate per-partner breakdowns.
- **Rate limit:** public-v1 ~1 call/sec, keyed free tier ~5/sec.
- **Lookup tables** are intentionally minimal — extend `_PARTNER_LABELS` / `_HS_CHAPTER_LABELS` as needed.

### General
- **Always summarize results** — don't dump raw response objects; both datasets are wide.
