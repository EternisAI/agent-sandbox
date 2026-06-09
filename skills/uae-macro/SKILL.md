---
name: uae-macro
description: Fetch UAE macroeconomic data — CPI, GDP, population, unemployment, trade balance, fiscal indicators. Default backend is FCSC's UAE.Stat SDMX API for fresh series (monthly CPI through Dec 2025, quarterly GDP, PPI, sector GDP, govt revenues/expenditures). World Bank Indicators API is the fallback for long historical series (1960+) and indicators FCSC doesn't carry. IMF DataMapper provides forecasts through 2031. FCSC requires `FIRECRAWL_API_KEY` (Cloudflare WAF). World Bank + IMF are unauthenticated.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# UAE Macroeconomics

Three complementary public sources for UAE country-level macro data, with **FCSC as the freshness default** for CPI / GDP / national accounts.

## Source selection — pick the right backend

| Question | Backend | Why |
|---|---|---|
| Latest UAE CPI (monthly) | **FCSC** | Through Dec 2025; WB has only annual ~12-month lag |
| Latest UAE quarterly GDP | **FCSC** | No other free monthly/quarterly source |
| UAE GDP by economic sector (annual) | **FCSC** `DF_NA_ISIC_CUR` | Sector ISIC breakdown |
| UAE govt revenues + expenditures (annual) | **FCSC** `DF_NA_PFIN_CUR` | National accounts |
| UAE PPI | **FCSC** `DF_PPI_ALL` | Not in WB |
| Long historical series (pre-2014) | **World Bank** | FCSC dataflows mostly start 2014 |
| Population, unemployment, FDI, energy use | **World Bank** | Catalogue depth |
| GDP / inflation / debt **forecasts** | **IMF** | WEO projections through 2031 |
| Current account, govt debt as % of GDP | **IMF** | Standard WEO ratios |

## Auth model

- **FCSC** — `FIRECRAWL_API_KEY` env var required. SDMX host (`releaseeuaestat.fcsc.gov.ae`) is Cloudflare-gated; direct urllib gets HTTP 403.
- **World Bank** — no key, no auth. ISO `ARE`.
- **IMF DataMapper** — no key, no auth. ISO `ARE`.

---

## Part 1 — FCSC (UAE.Stat SDMX), the freshness default

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

### Curated macro dataflows (versions verified 2026-06-09)

```python
MACRO_DATAFLOWS = {
    # Prices
    "DF_CPI":         {"version": "3.2.0", "freq": "M", "label": "Consumer Price Index, Monthly (through Dec 2025)"},
    "DF_CPI_ANN":     {"version": "3.2.0", "freq": "A", "label": "CPI Annual"},
    "DF_PPI_ALL":     {"version": "2.3.0", "freq": "M", "label": "Producer Price Index"},
    # National accounts
    "DF_QGDP_CUR":    {"version": "1.8.0", "freq": "Q", "label": "GDP Quarterly — Current Prices"},
    "DF_QGDP_CON":    {"version": "1.8.0", "freq": "Q", "label": "GDP Quarterly — Constant Prices"},
    "DF_NA_ISIC_CUR": {"version": "3.4.0", "freq": "A", "label": "GDP — by Economic Sector (ISIC), Annual Current"},
    "DF_NA_PFIN_CUR": {"version": "3.4.0", "freq": "A", "label": "Govt Revenues & Expenditures, Annual"},
}
```

### FCSC tools

```python
def list_uaestat_macro_dataflows(filter_text: str | None = None) -> list[dict]:
    """Scrape FCSC's SDMX dataflow registry, optionally filtered by substring.
    Returns list of {id, version, name_en}. Use to find macro flows not in MACRO_DATAFLOWS
    (e.g. labour, population, vital stats — FCSC ships ~291 flows total)."""
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
                     end_period: str | None = None,
                     dimension_at_observation: str = "AllDimensions",
                     ) -> str:
    """Fetch SDMX CSV (with labels) for one dataflow via Firecrawl.
    Auto-resolves version from MACRO_DATAFLOWS if omitted.
    `start_period` / `end_period`: SDMX period strings (`YYYY`, `YYYY-MM`, `YYYY-Q{1-4}`).
    Returns raw CSV — pipe through parse_sdmx_csv() to get dicts."""
    if not version:
        version = (MACRO_DATAFLOWS.get(df_id) or {}).get("version")
        if not version:
            raise ValueError(f"version required for non-curated dataflow {df_id} — call list_uaestat_macro_dataflows() to look up")
    params = {"format": "csvfilewithlabels", "dimensionAtObservation": dimension_at_observation}
    if start_period: params["startPeriod"] = start_period
    if end_period:   params["endPeriod"]   = end_period
    url = f"{_UAESTAT_API}/rest/data/FCSA,{df_id},{version}/{key}?{urllib.parse.urlencode(params)}"
    return _firecrawl_scrape(url, timeout_s=180)

def parse_sdmx_csv(csv_text: str) -> list[dict]:
    """Parse SDMX CSV (csvfilewithlabels format) into list of dicts.
    Strips structure header rows, keeps observation rows. Columns vary by dataflow.
    Common keys: TIME_PERIOD, OBS_VALUE, REF_AREA, MEASURE, UNIT_MEASURE."""
    import csv, io
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    return [r for r in rows if r.get("STRUCTURE") == "DATAFLOW"]

# Convenience wrappers — highest-value flows

def get_uae_cpi_monthly(start_month: str = "2024-01", end_month: str | None = None) -> list[dict]:
    """UAE Consumer Price Index, monthly. Latest period: Dec 2025 (verified 2026-06-09)."""
    return parse_sdmx_csv(get_uaestat_data("DF_CPI",
                                           start_period=start_month, end_period=end_month))

def get_uae_cpi_annual(start_year: str = "2010", end_year: str | None = None) -> list[dict]:
    """UAE CPI annual."""
    return parse_sdmx_csv(get_uaestat_data("DF_CPI_ANN",
                                           start_period=start_year, end_period=end_year))

def get_uae_ppi_monthly(start_month: str = "2024-01", end_month: str | None = None) -> list[dict]:
    """UAE Producer Price Index, monthly."""
    return parse_sdmx_csv(get_uaestat_data("DF_PPI_ALL",
                                           start_period=start_month, end_period=end_month))

def get_uae_quarterly_gdp(start_quarter: str = "2022-Q1", end_quarter: str | None = None,
                          constant_prices: bool = False) -> list[dict]:
    """UAE quarterly GDP. Default current prices; set constant_prices=True for real GDP."""
    df_id = "DF_QGDP_CON" if constant_prices else "DF_QGDP_CUR"
    return parse_sdmx_csv(get_uaestat_data(df_id,
                                           start_period=start_quarter, end_period=end_quarter))

def get_uae_gdp_by_sector_annual(start_year: str = "2018", end_year: str | None = None) -> list[dict]:
    """UAE GDP by economic sector (ISIC), annual, current prices."""
    return parse_sdmx_csv(get_uaestat_data("DF_NA_ISIC_CUR",
                                           start_period=start_year, end_period=end_year))

def get_uae_govt_revenues_expenditures(start_year: str = "2018", end_year: str | None = None) -> list[dict]:
    """UAE government revenues and expenditures, annual."""
    return parse_sdmx_csv(get_uaestat_data("DF_NA_PFIN_CUR",
                                           start_period=start_year, end_period=end_year))
```

---

## Part 2 — World Bank Indicators (historical fallback)

```python
import json, urllib.parse, urllib.request, urllib.error, time

WB_BASE = "https://api.worldbank.org/v2"

def _wb_get(url: str, *, max_retries: int = 3, base_delay: float = 1.0) -> dict:
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; AxionAgent/1.0)"})
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode())
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
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_err = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt)); continue
            raise
    raise last_err

def wb_indicator(code: str, start: int = 2010, end: int = 2025) -> list[dict]:
    """Historical World Bank series for UAE. Returns list of {date, value} sorted ascending.
    Examples: 'NY.GDP.MKTP.CD' (GDP USD), 'FP.CPI.TOTL.ZG' (inflation %), 'SP.POP.TOTL' (population).
    For fresh monthly CPI / quarterly GDP, use the FCSC helpers above instead."""
    url = f"{WB_BASE}/country/ARE/indicator/{code}?format=json&date={start}:{end}&per_page=200"
    r = _wb_get(url)
    if not isinstance(r, list) or len(r) < 2 or not r[1]:
        return []
    obs = [{"date": x["date"], "value": x["value"]} for x in r[1] if x.get("value") is not None]
    return sorted(obs, key=lambda x: x["date"])

def wb_search_indicators(query: str, per_page: int = 20) -> list[dict]:
    """Search World Bank indicator catalogue by keyword."""
    url = f"{WB_BASE}/indicator?format=json&per_page={per_page}&search={urllib.parse.quote(query)}"
    r = _wb_get(url)
    if not isinstance(r, list) or len(r) < 2:
        return []
    return [{"id": x["id"], "name": x["name"], "source": x.get("sourceOrganization", "")} for x in r[1]]
```

---

## Part 3 — IMF DataMapper (forecasts to 2031)

```python
IMF_BASE = "https://www.imf.org/external/datamapper/api/v1"

def imf_indicator(code: str) -> dict:
    """IMF DataMapper series for UAE (includes WEO forecasts to ~2031).
    Returns {year: value} dict. Common codes: 'NGDP_RPCH' (real GDP growth %),
    'PCPIPCH' (inflation %), 'GGXWDG_NGDP' (govt debt % GDP), 'BCA_NGDPD' (current account % GDP)."""
    r = _wb_get(f"{IMF_BASE}/{code}/ARE")  # reuses retry helper
    return r.get("values", {}).get(code, {}).get("ARE", {})

def imf_list_indicators() -> dict:
    """All 132 IMF indicators (id → metadata). Filter client-side."""
    return _wb_get(f"{IMF_BASE}/indicators").get("indicators", {})
```

---

## Curated indicators (cross-source)

```python
def get_popular_uae_indicators() -> dict:
    """Curated indicators by use case."""
    return {
        "fcsc_fresh": {
            "DF_CPI":         "Consumer Price Index, monthly (latest Dec 2025)",
            "DF_QGDP_CUR":    "GDP quarterly, current prices",
            "DF_QGDP_CON":    "GDP quarterly, constant prices (real GDP)",
            "DF_PPI_ALL":     "Producer Price Index, monthly",
            "DF_NA_ISIC_CUR": "GDP by economic sector, annual",
            "DF_NA_PFIN_CUR": "Govt revenues & expenditures, annual",
        },
        "wb_historical": {
            "NY.GDP.MKTP.CD":    "GDP (current US$)",
            "NY.GDP.PCAP.CD":    "GDP per capita (current US$)",
            "FP.CPI.TOTL.ZG":    "Inflation, consumer prices (annual %)",
            "SP.POP.TOTL":       "Population, total",
            "SL.UEM.TOTL.ZS":    "Unemployment, total (% labor force, ILO model)",
            "NE.EXP.GNFS.CD":    "Exports of goods and services (current US$)",
            "NE.IMP.GNFS.CD":    "Imports of goods and services (current US$)",
            "BX.KLT.DINV.CD.WD": "Foreign direct investment, net inflows (BoP, US$)",
            "EG.USE.PCAP.KG.OE": "Energy use per capita (kg oil equiv)",
        },
        "imf_forecasts": {
            "NGDP_RPCH":   "Real GDP growth (%) — annual + forecasts",
            "PCPIPCH":     "Inflation, avg consumer prices (%) — incl. forecasts",
            "GGXWDG_NGDP": "General government debt (% of GDP)",
            "BCA_NGDPD":   "Current account balance (% of GDP)",
            "GGR_NGDP":    "Govt revenue (% of GDP)",
            "GGX_NGDP":    "Govt expenditure (% of GDP)",
            "NGDPD":       "GDP (current US$, billions)",
            "PPPGDP":      "GDP based on PPP",
        },
    }
```

---

## Examples

### Fresh UAE inflation (FCSC monthly)

```python
rows = get_uae_cpi_monthly(start_month="2025-01", end_month="2025-12")
by_month = {}
for r in rows:
    period = r.get("TIME_PERIOD"); val = r.get("OBS_VALUE")
    if period and val:
        by_month[period] = float(val)
for m in sorted(by_month):
    print(f"  {m}  CPI index = {by_month[m]:.2f}")
```

### Fresh UAE quarterly GDP (FCSC)

```python
rows = get_uae_quarterly_gdp(start_quarter="2024-Q1")
by_q = {}
for r in rows:
    p, v = r.get("TIME_PERIOD"), r.get("OBS_VALUE")
    if p and v: by_q.setdefault(p, []).append(float(v))
for q in sorted(by_q):
    print(f"  {q}  AED {sum(by_q[q]):>15,.0f}")
```

### UAE GDP trajectory — historical + forecast

```python
hist = wb_indicator("NY.GDP.MKTP.CD", start=2010, end=2024)
fcst = imf_indicator("NGDPD")  # IMF forecasts past 2024
print("WB historical (USD):")
for o in hist[-5:]:
    print(f"  {o['date']}: ${o['value']:>15,.0f}")
print("IMF forecast (USD billions):")
for y in sorted(fcst.keys())[-5:]:
    print(f"  {y}: ${fcst[y]:>8.1f}B")
```

### Inflation: FCSC monthly vs WB annual vs IMF forecast

```python
# Aggregate FCSC monthly → annual for sanity check
fcsc_2025 = get_uae_cpi_monthly(start_month="2025-01", end_month="2025-12")
fcsc_avg_2025 = sum(float(r["OBS_VALUE"]) for r in fcsc_2025 if r.get("OBS_VALUE")) / max(1, len(fcsc_2025))
wb = {o["date"]: o["value"] for o in wb_indicator("FP.CPI.TOTL.ZG", 2018, 2024)}
imf = imf_indicator("PCPIPCH")
print(f"FCSC 2025 mean CPI index = {fcsc_avg_2025:.2f}")
print(f"{'Year':<6}{'WB %':<10}{'IMF %':<10}")
for y in sorted(set(list(wb.keys()) + list(imf.keys()))):
    print(f"{y:<6}{wb.get(y,'-'):<10}{imf.get(y,'-'):<10}")
```

### Find a WB indicator

```python
hits = wb_search_indicators("oil rent", per_page=5)
for h in hits:
    print(f"  {h['id']:<25} {h['name']}")
```

## Notes

### FCSC
- **`FIRECRAWL_API_KEY` required.** Helpers raise clearly if missing.
- **Period syntax:** annual `YYYY`, monthly `YYYY-MM`, quarterly `YYYY-Q{1-4}`.
- **Quarterly CPI `DF_CPI_Q` returns empty** — use `DF_CPI` (monthly) and aggregate, or `DF_CPI_ANN`.
- **Quarterly GDP version pin:** `DF_QGDP_CUR` requires `version="1.8.0"` — pinned in `MACRO_DATAFLOWS`. Front-end URLs may show higher numbers; the structure registry has the authoritative version.
- **CSV columns vary** — inspect with `csv.DictReader` first.
- **Firecrawl is rate-limited** — serialize; `time.sleep(1)` between probes if iterating.

### World Bank
- **No API key, no auth.** ISO `ARE`.
- **Data lag:** annual indicators ~1 year (2024 published mid-2025).
- **JSON format param required** — defaults to XML; always include `format=json`.

### IMF DataMapper
- **No API key, no auth.** ISO `ARE`.
- **Forecast horizon:** typically current year + 5-7 years forward (through ~2031).
- **Sparse for UAE:** `LUR` (unemployment) returns empty — fall back to WB `SL.UEM.TOTL.ZS`.
- **Structure:** `{"values": {"<indicator>": {"<iso>": {"<year>": value}}}}` — `imf_indicator` unwraps it.

### General
- **Keep result sets concise** — process in Python and print summarized output rather than full dumps.
