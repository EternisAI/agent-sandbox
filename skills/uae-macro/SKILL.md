---
name: uae-macro
description: Fetch UAE macroeconomic data — GDP, inflation, population, unemployment, trade balance, fiscal indicators — from the World Bank Indicators API (historical) and IMF DataMapper API (forecasts to 2031). Use when users ask about UAE economic indicators, growth, prices, debt, current account, or any country-level macro context for Dubai. No auth required.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# UAE Macroeconomics API (World Bank + IMF)

Two complementary public sources for UAE country-level macro data. Both keyed by ISO code `ARE`. No API keys, no proxy.

- **World Bank Indicators API** — long historical series (1960+), development indicators
- **IMF DataMapper API** — forecasts via WEO (real GDP growth, inflation, debt, current account through 2031)

## Base URLs and helpers

```python
import json, time, urllib.parse, urllib.request, urllib.error

WB_BASE  = "https://api.worldbank.org/v2"
IMF_BASE = "https://www.imf.org/external/datamapper/api/v1"

def _get(url: str, *, max_retries: int = 3, base_delay: float = 1.0) -> dict:
    """HTTP GET with retry on 429, 5xx, and timeouts. Both World Bank and IMF are free
    public APIs that occasionally flake; default 3 retries with exponential backoff."""
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "uae-macro-skill/1.0"})
            with urllib.request.urlopen(req, timeout=20) as r:
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

## Supported Tools

| Function | Source | Returns |
| --- | --- | --- |
| `wb_indicator` | World Bank | Historical time series for any indicator (code → observations) |
| `wb_search_indicators` | World Bank | Search indicators by keyword (resolve "inflation" → `FP.CPI.TOTL.ZG`) |
| `imf_indicator` | IMF | Time series including forecasts for any IMF indicator |
| `imf_list_indicators` | IMF | All 132 IMF indicators with descriptions |
| `get_popular_uae_indicators` | Static | Curated dict of the most useful UAE indicators across both sources |

## Functions

```python
import json, urllib.parse, urllib.request

WB_BASE  = "https://api.worldbank.org/v2"
IMF_BASE = "https://www.imf.org/external/datamapper/api/v1"

def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "uae-macro-skill/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())

def wb_indicator(code: str, start: int = 2010, end: int = 2025) -> list[dict]:
    """Historical World Bank series for UAE. Returns list of {date, value} sorted ascending.
    Examples: 'NY.GDP.MKTP.CD' (GDP USD), 'FP.CPI.TOTL.ZG' (inflation %), 'SP.POP.TOTL' (population)."""
    url = f"{WB_BASE}/country/ARE/indicator/{code}?format=json&date={start}:{end}"
    r = _get(url)
    if not isinstance(r, list) or len(r) < 2 or not r[1]:
        return []
    obs = [{"date": x["date"], "value": x["value"]} for x in r[1] if x.get("value") is not None]
    return sorted(obs, key=lambda x: x["date"])

def wb_search_indicators(query: str, per_page: int = 20) -> list[dict]:
    """Search World Bank indicator catalogue by keyword."""
    url = f"{WB_BASE}/indicator?format=json&per_page={per_page}&search={urllib.parse.quote(query)}"
    r = _get(url)
    if not isinstance(r, list) or len(r) < 2:
        return []
    return [{"id": x["id"], "name": x["name"], "source": x.get("sourceOrganization", "")} for x in r[1]]

def imf_indicator(code: str) -> dict:
    """IMF DataMapper series for UAE (includes WEO forecasts to ~2031).
    Returns {year: value} dict. Common codes: 'NGDP_RPCH' (real GDP growth %),
    'PCPIPCH' (inflation %), 'GGXWDG_NGDP' (govt debt % GDP), 'BCA_NGDPD' (current account % GDP)."""
    r = _get(f"{IMF_BASE}/{code}/ARE")
    return r.get("values", {}).get(code, {}).get("ARE", {})

def imf_list_indicators() -> dict:
    """All 132 IMF indicators (id → metadata). Filter client-side."""
    return _get(f"{IMF_BASE}/indicators").get("indicators", {})

def get_popular_uae_indicators() -> dict:
    """Curated indicators by use case."""
    return {
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

## Examples

### UAE GDP trajectory (historical + forecast)

```python
hist = wb_indicator("NY.GDP.MKTP.CD", start=2015, end=2024)
fcst = imf_indicator("NGDPD")  # IMF gives forecasts past 2024
print("WB historical (USD):")
for o in hist[-5:]:
    print(f"  {o['date']}: ${o['value']:>15,.0f}")
print("IMF forecast (USD billions):")
for y in sorted(fcst.keys())[-5:]:
    print(f"  {y}: ${fcst[y]:>8.1f}B")
```

### Inflation comparison: WB actuals vs IMF forecast

```python
wb = {o["date"]: o["value"] for o in wb_indicator("FP.CPI.TOTL.ZG", 2018, 2024)}
imf = imf_indicator("PCPIPCH")
print(f"{'Year':<6}{'WB CPI %':<12}{'IMF CPI %':<12}")
for y in sorted(set(list(wb.keys()) + list(imf.keys()))):
    print(f"{y:<6}{wb.get(y,'-'):<12}{imf.get(y,'-'):<12}")
```

### Find a specific indicator

```python
hits = wb_search_indicators("oil rent", per_page=5)
for h in hits:
    print(f"  {h['id']:<25} {h['name']}")
```

### One-shot UAE snapshot

```python
popular = get_popular_uae_indicators()
for code, label in popular["wb_historical"].items():
    series = wb_indicator(code, 2022, 2024)
    if series:
        latest = series[-1]
        print(f"{label:<45} {latest['date']}: {latest['value']:,.2f}")
```

## Notes

- **No API key, no auth, no proxy** — both APIs are fully open.
- **ISO code:** UAE is `ARE` (3-letter) for both APIs. World Bank also accepts `AE` (2-letter).
- **Data lag:** World Bank annual indicators typically lag ~1 year (2024 published mid-2025). IMF includes forecasts so you get current-year + ~5-7 year forward projections.
- **Some indicators are sparse for UAE** — e.g. IMF `LUR` (unemployment) returns empty for UAE. Fall back to World Bank `SL.UEM.TOTL.ZS` (modeled ILO estimate, returns 2.16% for 2024).
- **World Bank pagination:** default per_page is 50. For deep series, append `&per_page=200`.
- **JSON format param required** — World Bank defaults to XML; always include `format=json`.
- **IMF DataMapper structure:** `{"values": {"<indicator>": {"<iso>": {"<year>": value}}}}`. The `imf_indicator` helper unwraps it.
- **Keep result sets concise** — process series in Python and print summarized output rather than full dumps.
