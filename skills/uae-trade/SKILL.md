---
name: uae-trade
description: Fetch UAE international trade data from UN Comtrade — annual imports/exports by partner country and HS commodity code (HS2/HS4/HS6). Pre-scoped to reporterCode 784 (United Arab Emirates). Use when users ask about UAE trade flows, top trading partners, commodity composition (oil, gold, electronics), or year-over-year trade trends. No key required for default (public-v1) mode; reads optional COMTRADE_API_KEY env var for richer keyed-tier data.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# UAE Trade API (UN Comtrade)

UAE-scoped wrapper around UN Comtrade (`reporterCode=784`). Two modes:

- **Default (public-v1, no key):** annual imports/exports by partner and HS commodity. Descriptions stripped — skill ships lookup tables.
- **Keyed (with `COMTRADE_API_KEY` env var):** adds descriptions, reference endpoints, higher rate limits. Use when env var is set.

UAE reports **annually only** (verified via Comtrade data availability endpoint — no monthly data exists at any tier). Latest available year is typically 2 years behind current (e.g. 2023 in mid-2026).

For Dubai re-export analysis (`partner2Code`, mode of transport), a paid premium key is required — neither default tier exposes those fields. See `plans/dubai_gov_data.md`.

## Base URL and helpers

```python
import json, os, time, urllib.parse, urllib.request, urllib.error

REPORTER_UAE = 784  # United Arab Emirates ISO M49
_KEY = os.environ.get("COMTRADE_API_KEY")
_BASE_KEYED  = "https://comtradeapi.un.org/data/v1/get"
_BASE_PUBLIC = "https://comtradeapi.un.org/public/v1/preview"

def _get(path_after_get: str, params: dict, *, max_retries: int = 4, base_delay: float = 1.0) -> dict:
    """HTTP GET with retry on 429 (rate limit), 5xx, and timeouts. Public-v1 is ~1 call/sec —
    429 responses include a Retry-After header which we honour. Keyed tier is ~5/sec."""
    base = _BASE_KEYED if _KEY else _BASE_PUBLIC
    url = f"{base}/{path_after_get}?{urllib.parse.urlencode(params)}"
    headers = {"User-Agent": "uae-trade-skill/1.0"}
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
                time.sleep(max(delay, 1.0))
                continue
            if 500 <= e.code < 600 and attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt))
                continue
            raise
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_err = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt))
                continue
            raise
    raise last_err  # unreachable but keeps type-checkers happy
```

## Supported Tools

| Function | What it returns |
| --- | --- |
| `get_uae_trade` | Single query — UAE trade by year, partner, HS code, flow |
| `top_partners` | Top N trading partners for a year (all 219 partners ranked) |
| `top_commodities` | Top N HS chapters by trade value for a year |
| `partner_trade_history` | Multi-year UAE↔partner time series |
| `commodity_trade_history` | Multi-year UAE↔HS code time series |
| `lookup_partner` | Resolve partner ISO code → name (and reverse) |
| `lookup_hs` | Resolve HS chapter code → description |

## Functions

```python
import json, os, time, urllib.parse, urllib.request, urllib.error

REPORTER_UAE = 784
_KEY = os.environ.get("COMTRADE_API_KEY")
_BASE_KEYED  = "https://comtradeapi.un.org/data/v1/get"
_BASE_PUBLIC = "https://comtradeapi.un.org/public/v1/preview"

def _get(path_after_get: str, params: dict, *, max_retries: int = 4, base_delay: float = 1.0) -> dict:
    base = _BASE_KEYED if _KEY else _BASE_PUBLIC
    url = f"{base}/{path_after_get}?{urllib.parse.urlencode(params)}"
    headers = {"User-Agent": "uae-trade-skill/1.0"}
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

def get_uae_trade(year: int, flow: str = "X", partner: int = 0, hs_code: str = "TOTAL") -> list[dict]:
    """Single Comtrade query. flow='X' export, 'M' import. partner=0 means 'World' (all partners
    aggregated). hs_code='TOTAL' for all commodities, '27' for HS2 mineral fuels, '270900' for HS6 crude oil.
    Returns list of trade records with primaryValue in USD."""
    params = {
        "reporterCode": REPORTER_UAE, "period": year,
        "partnerCode": partner, "flowCode": flow, "cmdCode": hs_code,
    }
    if _KEY:
        params["includeDesc"] = "true"
    return _get("C/A/HS", params).get("data", []) or []

def top_partners(year: int, flow: str = "X", top: int = 10) -> list[dict]:
    """Top N trading partners for UAE in given year. Omit partnerCode to get all 219 partners back."""
    params = {
        "reporterCode": REPORTER_UAE, "period": year,
        "flowCode": flow, "cmdCode": "TOTAL",
    }
    if _KEY:
        params["includeDesc"] = "true"
    data = _get("C/A/HS", params).get("data", []) or []
    rows = [r for r in data if (r.get("partnerCode") or 0) > 0]
    rows.sort(key=lambda r: r.get("primaryValue") or 0, reverse=True)
    return rows[:top]

def top_commodities(year: int, flow: str = "X", top: int = 10) -> list[dict]:
    """Top N HS2 chapters for UAE trade. Omit cmdCode to enumerate."""
    params = {
        "reporterCode": REPORTER_UAE, "period": year,
        "partnerCode": 0, "flowCode": flow,
    }
    if _KEY:
        params["includeDesc"] = "true"
    data = _get("C/A/HS", params).get("data", []) or []
    rows = [r for r in data if r.get("cmdCode") not in (None, "TOTAL", "")]
    rows.sort(key=lambda r: r.get("primaryValue") or 0, reverse=True)
    return rows[:top]

def partner_trade_history(partner_code: int, start: int, end: int, flow: str = "X") -> dict:
    """UAE ↔ partner total trade by year. Returns {year: usd_value}."""
    periods = ",".join(str(y) for y in range(start, end + 1))
    params = {
        "reporterCode": REPORTER_UAE, "period": periods,
        "partnerCode": partner_code, "flowCode": flow, "cmdCode": "TOTAL",
    }
    data = _get("C/A/HS", params).get("data", []) or []
    return {r["period"]: r.get("primaryValue") for r in data}

def commodity_trade_history(hs_code: str, start: int, end: int, flow: str = "X") -> dict:
    """UAE world trade for an HS code over a year range. Returns {year: usd_value}."""
    periods = ",".join(str(y) for y in range(start, end + 1))
    params = {
        "reporterCode": REPORTER_UAE, "period": periods,
        "partnerCode": 0, "flowCode": flow, "cmdCode": hs_code,
    }
    data = _get("C/A/HS", params).get("data", []) or []
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

## Examples

### Top 10 UAE export partners 2023

```python
rows = top_partners(2023, flow="X", top=10)
print(f"UAE top export partners 2023 (keyed mode={'yes' if os.environ.get('COMTRADE_API_KEY') else 'no'}):")
for r in rows:
    pc = r["partnerCode"]
    label = r.get("partnerDesc") or lookup_partner(pc)
    v = r.get("primaryValue") or 0
    print(f"  {label:<25} ${v:>15,.0f}")
```

### UAE crude oil exports over time

```python
series = commodity_trade_history("270900", start=2018, end=2023, flow="X")
print("UAE crude oil exports to World:")
for y in sorted(series.keys()):
    v = series[y] or 0
    print(f"  {y}: ${v:>15,.0f}")
```

### UAE–India bilateral trade

```python
exp = partner_trade_history(699, 2018, 2023, flow="X")
imp = partner_trade_history(699, 2018, 2023, flow="M")
print(f"{'Year':<6}{'UAE→India':<20}{'India→UAE':<20}{'Balance':<20}")
for y in sorted(exp.keys()):
    e, i = (exp.get(y) or 0), (imp.get(y) or 0)
    print(f"  {y:<6}${e:>15,.0f}    ${i:>15,.0f}    ${e-i:>15,.0f}")
```

### Top commodities exported 2023

```python
rows = top_commodities(2023, flow="X", top=10)
for r in rows:
    code = r["cmdCode"]
    label = r.get("cmdDesc") or lookup_hs(code)
    v = r.get("primaryValue") or 0
    print(f"  HS {code:<8} {label[:50]:<52} ${v:>15,.0f}")
```

## Notes

- **`COMTRADE_API_KEY` env var** — optional. When present, requests use the keyed endpoint and pass `includeDesc=true` for human-readable labels.
- **UAE reports annually only** — `freqCode=A`. Monthly queries return empty for any UAE period (verified 2026-06-09 against the data-availability endpoint). Do not attempt monthly.
- **Data lag** — most recent year typically available is *current year − 2*. UAE 2024 and 2025 data is not yet ingested by UN.
- **HS classification:** `cmdCode=TOTAL` for all goods, HS2 (`"27"`), HS4 (`"2709"`), or HS6 (`"270900"`).
- **Flow codes:** `X` export, `M` import, `RX` re-export, `RM` re-import. UAE reports X and M; re-export details require **paid premium**.
- **Partner code 0 = "World"** (aggregate across all partners). Omit `partnerCode` from the query to enumerate per-partner breakdowns.
- **Rate limit:** public-v1 ~1 call/sec, keyed free tier ~5/sec. Add `time.sleep(1)` between calls if iterating.
- **Re-export tracking** is the most Dubai-specific Comtrade angle but requires a **paid premium key** (`partner2Code` field). Not exposed at either default tier.
- **Lookup tables** are intentionally minimal — extend `_PARTNER_LABELS` / `_HS_CHAPTER_LABELS` as needed. Full UN M49 and HS 2022 references are at https://unstats.un.org/unsd/methodology/m49/ and https://www.wcoomd.org/en/topics/nomenclature/instrument-and-tools/hs-nomenclature-2022-edition.aspx.
- **Always summarize results** — don't dump raw response objects; the dataset is wide.
