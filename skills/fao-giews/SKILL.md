---
name: fao-giews
description: Fetch food prices from FAO GIEWS (Global Information and Early Warning System) — fresh sub-national retail prices for staple foods (wheat, rice, bread, beans, oils, sugar) across food-insecure and emerging-market countries. Weekly or monthly cadence, 2-4 week freshness lag. 3,772 domestic series across 70+ countries from 2000-present, plus 90 international reference price series. Use for regional food security in Yemen / Syria / Lebanon / Jordan / Egypt / Saudi (UAE itself is not GIEWS-monitored), source-country price shocks (wheat from Russia/Ukraine, rice from India/Thailand) before they hit Gulf shelves, and humanitarian / aid-corridor monitoring. Free, no auth.
allowed-tools: Bash(python3 -c *), Bash(python3 - *), Bash(python3 *)
---

# FAO GIEWS Food Prices (FPMA API)

GIEWS' Food Price Monitoring and Analysis (FPMA) tool publishes retail prices of staple foods at the **market level** (e.g. Kabul, Sana'a, Cairo wholesale) on a **weekly or monthly cadence** with a **2-4 week freshness lag**. Covers crisis-prone and food-insecure countries plus 90 international reference benchmarks (c.i.f. / f.o.b. wheat, rice, soybean, fertilizers, dairy).

**Why this matters for Dubai**: UAE itself is **not** GIEWS-monitored (it's high-income, food-secure), but the regional adjacency is strong — Yemen (122 series), Syria (60), Jordan (55), Lebanon (42), Saudi Arabia (25), Egypt (13). Use this skill for: (a) **regional food-security monitoring** when Dubai is weighing humanitarian-aid or stability questions; (b) **upstream price-shock tracking** in source countries Gulf imports come from (Russia/Ukraine wheat, Thailand/India rice, US soybean, Indonesia/Malaysia palm oil); (c) confirming the international reference prices that drive UAE retail food CPI before the CBUAE CPI release.

For UAE's own retail food prices, use `cbuae` or `wam` (UAE inflation announcements). For long-run global commodity benchmarks, use `world-bank-commodities`. For agricultural production volumes, use `faostat`. GIEWS is uniquely the **fresh, market-level retail** layer.

## Sandbox Environment

- **Python 3.12** stdlib only — `urllib`, `json`, `time`. No external packages required.
- Free public endpoint — no API key, no quota observed.
- Two distinct hosts:
  - `https://fpma.fao.org/giews/v4/global/` — the **data API** (use this)
  - `https://fpma.apps.fao.org/giews/food-prices/tool/public/` — the SPA UI (do NOT fetch; returns Angular shell)
- **Behind Cloudflare** (`server: cloudflare`, `cf-ray` headers present). A minimal UA passes today, but Cloudflare adapts — use the full browser fingerprint below so the skill stays durable when the WAF tightens. Same pattern as `dubai-public-reports` (Akamai).
- Optional cache: `/data/giews-cache/` (per-thread persistent) if you make repeated calls in one session.

## Quick start

```python
import json
import time
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://fpma.fao.org/giews/v4/global"
PRICE_MODULE = f"{API_BASE}/price_module/api/v1"
SPA_ORIGIN = "https://fpma.apps.fao.org"  # the SPA that legitimately calls the API; must match the Origin/Referer Cloudflare expects


def _browser_headers() -> dict:
    """Full Chrome 130 / macOS fingerprint. Cloudflare's bot scoring lets these
    through; bare `User-Agent: Mozilla/5.0` works today but is fragile."""
    return {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "identity",
        "Sec-Ch-Ua": '"Google Chrome";v="130","Chromium";v="130"',
        "Sec-Ch-Ua-Mobile": "?0",
        "Sec-Ch-Ua-Platform": '"macOS"',
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-site",
        "Sec-Fetch-Dest": "empty",
        "Referer": f"{SPA_ORIGIN}/",
        "Origin": SPA_ORIGIN,
    }


def _open_with_retry(req, *, max_retries: int = 3, base_delay: float = 1.0, timeout: int = 30):
    """urlopen with retry on 429, 5xx, and network timeouts. Honors Retry-After."""
    last_err: Exception | None = None
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
                time.sleep(max(delay, 1.0))
                continue
            if 500 <= e.code < 600 and attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt))
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            if attempt < max_retries:
                time.sleep(base_delay * (2 ** attempt))
                continue
            raise
    assert last_err is not None
    raise last_err


def _get(path: str, params: dict | None = None) -> dict:
    """Issue a GET against the FPMA API and return parsed JSON."""
    url = f"{PRICE_MODULE}{path}"
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers=_browser_headers())
    with _open_with_retry(req) as r:
        return json.loads(r.read())
```

## Tool 1: `list_domestic_series()` — catalog of country × market × commodity

The domestic catalog has **3,772 series** spanning 70+ countries. Each entry tells you the series `uuid` (used to fetch prices), the market, commodity, periodicity (weekly / monthly), and date range.

```python
def list_domestic_series(
    iso3: str | None = None,
    commodity_contains: str | None = None,
    newer_than: str = "11 months ago",
) -> list[dict]:
    """Discover available price series, optionally filtered.

    Args:
        iso3: 3-letter country code, e.g. "EGY", "YEM", "SAU", "JOR", "LBN", "SYR".
              UAE ("ARE") is not covered. None returns all countries.
        commodity_contains: case-insensitive substring filter on commodity_name,
                            e.g. "wheat", "rice", "bread".
        newer_than: server-side staleness filter. Default "11 months ago" trims
                    the full 3MB catalog to actively-reporting series only.
                    Pass "" to disable.

    Returns: list of {uuid, country_name, iso3_country_code, market_name,
                      commodity_name, periodicity, market_type}.
    """
    params: dict = {}
    if newer_than:
        params["newerThan"] = newer_than
    if iso3:
        params["iso3_country_code"] = iso3
    data = _get("/FpmaSerieDomestic/", params)
    rows = [
        {
            "uuid": r["uuid"],
            "country_name": r["country_name"],
            "iso3_country_code": r["iso3_country_code"],
            "market_name": r["market_name"],
            "commodity_name": r["commodity_name"],
            "periodicity": [p["period"] for p in r.get("periodicity", [])],
            "market_type": r["market_type"],
        }
        for r in data["results"]
    ]
    if commodity_contains:
        needle = commodity_contains.lower()
        rows = [r for r in rows if needle in r["commodity_name"].lower()]
    return rows
```

## Tool 2: `list_international_series()` — global reference prices

90 international reference price series (c.i.f. / f.o.b. wheat, rice, soybeans, dairy, fertilizers, palm oil). These are the upstream benchmarks driving Gulf-region food import costs.

```python
def list_international_series(
    commodity_contains: str | None = None,
) -> list[dict]:
    """List international (cross-border) reference price series."""
    data = _get("/FpmaSerieInternational/")
    rows = [
        {
            "uuid": r["uuid"],
            "commodity_name": r["commodity_name"],
            "market_name": r["market_name"],
            "market_type": r["market_type"],
            "periodicity": [p["period"] for p in r.get("periodicity", [])],
        }
        for r in data["results"]
    ]
    if commodity_contains:
        needle = commodity_contains.lower()
        rows = [r for r in rows if needle in r["commodity_name"].lower()]
    return rows
```

## Tool 3: `get_prices()` — fetch time series by UUID

Pass one or more series UUIDs and a periodicity. Returns the full datapoint history (typically 2000-present for monthly, fewer years for weekly).

Each datapoint exposes:
- `date` (ISO `YYYY-MM-DD`)
- `price_value` — price in local currency
- `price_value_dollar` — USD-converted price (computed using FAO's official monthly rate)
- `conversion_factor` — local-currency-unit per kg (use to back out the original quoted unit if needed)
- `periodicity` — `weekly` or `monthly`

```python
def get_prices(
    uuids: str | list[str],
    periodicity: str = "monthly",
) -> dict[str, list[dict]]:
    """Fetch price datapoints for one or many series UUIDs.

    Args:
        uuids: a single uuid or a list. Batch fetch is preferred — one HTTP
               round-trip returns all series.
        periodicity: "monthly" (default) or "weekly". The catalog entry's
                     `periodicity` field tells you which is available.

    Returns: {uuid: [datapoint, ...]} with newest first.
    """
    if isinstance(uuids, str):
        uuids = [uuids]
    data = _get(
        "/FpmaSeriePrice/",
        {"uuid__in": ",".join(uuids), "periodicity": periodicity},
    )
    return {r["uuid"]: r["datapoints"] for r in data["results"]}
```

## Worked example — Egyptian wheat prices

End-to-end: find Egypt's wheat series, fetch its prices, summarize.

```python
egypt = list_domestic_series(iso3="EGY")
wheat = [s for s in egypt if "wheat" in s["commodity_name"].lower()]
print(f"Egypt wheat series: {len(wheat)}")
for s in wheat:
    print(f"  {s['uuid'][:8]}  {s['market_name']:30s}  {s['commodity_name']:30s}  {s['periodicity']}")

if wheat:
    series = get_prices(wheat[0]["uuid"], periodicity="monthly")
    pts = next(iter(series.values()))
    print(f"\n{wheat[0]['market_name']} / {wheat[0]['commodity_name']}: {len(pts)} datapoints")
    print(f"latest 5 (EGP / USD):")
    for p in pts[:5]:
        print(f"  {p['date']}  EGP {p['price_value']:>8}  USD {p['price_value_dollar']}")
```

## Worked example — Saudi Arabia wheat flour, monthly

```python
saudi = list_domestic_series(iso3="SAU", commodity_contains="wheat")
print(f"Saudi wheat-related series: {len(saudi)}")
for s in saudi[:5]:
    print(f"  {s['market_name']:30s}  {s['commodity_name']}")
```

## Worked example — Yemen + Syria batch fetch

When monitoring regional crises, batch-fetch multiple series in one request to keep latency low.

```python
yemen = list_domestic_series(iso3="YEM", commodity_contains="wheat")[:3]
syria = list_domestic_series(iso3="SYR", commodity_contains="bread")[:3]
both_uuids = [s["uuid"] for s in yemen + syria]
batch = get_prices(both_uuids, periodicity="monthly")
print(f"fetched {len(batch)} series in one round-trip")
for uuid, pts in batch.items():
    if pts:
        latest = pts[0]
        print(f"  {uuid[:8]}  latest: {latest['date']}  USD {latest['price_value_dollar']}")
```

## Caveats

1. **UAE, Qatar, Kuwait, Bahrain, Oman are NOT covered.** GIEWS monitors food-insecure countries; the Gulf states are high-income and food-secure. For UAE-specific retail food CPI use `cbuae` or `wam`. GIEWS is for **regional context** around UAE, not UAE itself.
2. **Two hosts, easy to confuse.** API host is `fpma.fao.org`. The SPA host `fpma.apps.fao.org` returns an Angular shell for every path — never curl it.
3. **`newerThan` cuts the response from ~3MB to ~600KB.** Default `"11 months ago"` matches the FPMA UI. Pass `""` if you specifically need stale/discontinued series.
4. **Trailing slash matters.** All paths in this skill include the trailing slash (`/FpmaSerieDomestic/`). Without it, the server occasionally 301-redirects.
5. **Weekly periodicity not always available.** The catalog entry's `periodicity` array tells you which periodicities the series supports; passing `periodicity=weekly` for a monthly-only series returns `{"count":0}`.
6. **USD values use the FAO monthly exchange rate**, not spot. For cross-country comparison this is fine; for hedging-relevant FX, source separately.
7. **Server-side commodity filter is silently broken.** The API accepts `commodity_name__icontains=wheat` but ignores it and returns all series. `list_*_series(commodity_contains=...)` therefore filters client-side. Do not assume the API itself can narrow by commodity — fetch the catalog (or a country slice) and filter in Python.
8. **Cloudflare in front of the API.** `_browser_headers()` sends a full Chrome/macOS fingerprint plus `Origin`/`Referer` pointing at the SPA host (`fpma.apps.fao.org`). A bare `User-Agent: Mozilla/5.0` passes today but is fragile — when Cloudflare tightens its bot rules the minimal header set is the first thing that breaks. Use the helper. If you must build a request yourself, copy every field from `_browser_headers()`, not just the UA.
9. **Retry / rate limits.** `_open_with_retry()` retries on `429` (honoring `Retry-After`) and `5xx` with exponential backoff. Don't strip it — Cloudflare occasionally returns 429 during catalog-wide scans even from authorized clients.
